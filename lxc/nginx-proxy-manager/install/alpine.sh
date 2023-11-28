#!/usr/bin/env sh

set -eux
set -o pipefail

trap trapexit EXIT SIGTERM

TEMPDIR="$1"
[ -d "${TEMPDIR}" ] || TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
LASTCMD=""
WGETOPT="-t 2 -T 15 -q"
DEVDEPS="npm g++ make gcc git python3-dev musl-dev libffi-dev openssl-dev jq"
NPMURL="https://github.com/NginxProxyManager/nginx-proxy-manager"
source <(cat /etc/os-release | tr -s '\n' | awk '{print "OS_"$0}')
cd $TEMPDIR
touch "$TEMPLOG"

# Helpers
log() {
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  #clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
  printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}

trapexit() {
  status=$?

  if [[ $status -eq 0 ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g")
    clear && printf "\033c\e[3J$logs\n";
  elif [[ -s $TEMPERR ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/31/g" | sed -e "s/info/error/g")
    err=$(cat $TEMPERR | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | rev | cut -d':' -f1 | rev | cut -d' ' -f2-)
    clear && printf "\033c\e[3J$logs\e[33m\n$0: line $LASTCMD\n\e[33;2;3m$err\e[0m\n"
  else
    printf "\e[33muncaught error occurred\n\e[0m"
  fi
  # Cleanup
  rm -rf $TEMPDIR
  apk del $DEVDEPS &>/dev/null
}

sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
# Update container OS
log "Updating container OS"
echo "fs.file-max = 65535" > /etc/sysctl.conf
apk update
apk upgrade
adduser npm --shell=/bin/false --no-create-home -D

# Check for previous install
if [ -f /etc/init.d/npm ]; then
  log "Stopping services"
  rc-service npm stop &>/dev/null
  rc-service openresty stop &>/dev/null
  sleep 2

  log "Cleaning old files"
  # Cleanup for new install
  rm -rf /app \
  /var/www/html \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx &>/dev/null

  log "Removing old dependencies"
  apk del certbot $DEVDEPS &>/dev/null
fi

OPENRESTY_REP_PREFIX="https://mirrors.ustc.edu.cn/openresty"
log "Checking for latest openresty repository"
ALPINE_MAJOR_VER=$(echo $OS_VERSION_ID | sed 's/\.[0-9]\+$//')
# add openresty public key
if [ ! -f /etc/apk/keys/admin@openresty.com-5ea678a6.rsa.pub ]; then
  wget $WGETOPT -P /etc/apk/keys/ $OPENRESTY_REP_PREFIX/admin@openresty.com-5ea678a6.rsa.pub
fi
# Update/Insert openresty repository
sed -i '/openresty/d' /etc/apk/repositories
echo "$OPENRESTY_REP_PREFIX/alpine/v$ALPINE_MAJOR_VER/main" \
    | tee -a /etc/apk/repositories
apk update

# Install dependancies
log "Installing dependencies"
apk add python3 py3-pip openresty nodejs yarn openssl apache2-utils logrotate $DEVDEPS
#python3 -m ensurepip --upgrade
pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
pip3 config list
pip3 install --upgrade pip
# Setup python env and PIP
log "Setting up python"
python3 -m venv /opt/certbot/
[ -f ~/.profile ] || touch ~/.profile && chmod 0644 ~/.profile
echo "source /opt/certbot/bin/activate" >> ~/.profile
source ~/.profile

# Install certbot and python dependancies
pip3 install --no-cache-dir -U cryptography==3.3.2
pip3 install --no-cache-dir cffi certbot

log "Checking for latest NPM release"
# Get latest version information for nginx-proxy-manager
URL_INFO_API_1="https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest"
URL_INFO_API_2="https://api.upup.cool/repo/NginxProxyManager/nginx-proxy-manager/info"
PROXY_MANAGER_INFO="$(wget -qO - $URL_INFO_API_1 || wget -qO - URL_INFO_API_2)"
_latest_version=$(echo $PROXY_MANAGER_INFO | jq -r 'if .version then .version else .tag_name end')

# Download nginx-proxy-manager source
PROXY_MANAGER_URL_1="https://mirror.ghproxy.com/${NPMURL}/archive/refs/tags/${_latest_version}.tar.gz"
PROXY_MANAGER_URL_2="https://api.upup.cool/repo/NginxProxyManager/nginx-proxy-manager/source"
PROXY_MANAGER_URL_3="${NPMURL}/archive/refs/tags/${_latest_version}.tar.gz"
PROXY_DOWN_FILE="${_latest_version}.tar.gz"
wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_1} || wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_2} || wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_3}
tar xzf ${PROXY_DOWN_FILE}
cd nginx-proxy-manager-*

log "Setting up enviroment"
# Crate required symbolic links
ln -sf /usr/bin/python3 /usr/bin/python
ln -sf /usr/bin/pip3 /usr/bin/pip
ln -sf /usr/bin/certbot /opt/certbot/bin/certbot
ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
ln -sf /usr/local/openresty/nginx/ /etc/nginx

# Update NPM version in package.json files
sed -i "s+0.0.0+$_latest_version+g" backend/package.json
sed -i "s+0.0.0+$_latest_version+g" frontend/package.json

# Fix nginx config files for use with openresty defaults
sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
for NGINX_CONF in $NGINX_CONFS; do
  sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done

# Copy runtime files
mkdir -p /var/www/html /etc/nginx/logs
cp -r docker/rootfs/var/www/html/* /var/www/html/
cp -r docker/rootfs/etc/nginx/* /etc/nginx/
cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf

# Create required folders
mkdir -p /tmp/nginx/body \
/run/nginx \
/data/nginx \
/data/custom_ssl \
/data/logs \
/data/access \
/data/nginx/default_host \
/data/nginx/default_www \
/data/nginx/proxy_host \
/data/nginx/redirection_host \
/data/nginx/stream \
/data/nginx/dead_host \
/data/nginx/temp \
/var/lib/nginx/cache/public \
/var/lib/nginx/cache/private \
/var/cache/nginx/proxy_temp

chmod -R 777 /var/cache/nginx
chown root /tmp/nginx

# Dynamically generate resolvers file, if resolver is IPv6, enclose in `[]`
# thanks @tfmm
echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" > /etc/nginx/conf.d/include/resolvers.conf

# Generate dummy self-signed certificate.
if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
  log "Generating dummy SSL certificate"
  openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem
fi

# Copy app files
mkdir -p /app/global /app/frontend/images
cp -r backend/* /app
cp -r global/* /app/global

# Build the frontend
log "Building frontend"
cd ./frontend
export NODE_ENV=development
yarn install
yarn build
cp -r dist/* /app/frontend
cp -r app-images/* /app/frontend/images

# Initialize backend
log "Initializing backend"
rm -rf /app/config/default.json &>/dev/null
if [ ! -f /app/config/production.json ]; then
cat << 'EOF' > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
fi
cd /app
export NODE_ENV=development
yarn install

# Create NPM service
log "Creating NPM service"
cat << 'EOF' > /etc/init.d/npm
#!/sbin/openrc-run
description="Nginx Proxy Manager"

command="/usr/bin/node"
command_args="index.js --abort_on_uncaught_exception --max_old_space_size=250"
command_background="yes"
directory="/app"

pidfile="/var/run/npm.pid"
output_log="/var/log/npm.log"
error_log="/var/log/npm.err"

depends () {
  before openresty
}

start_pre() {
  mkdir -p /tmp/nginx/body \
  /data/letsencrypt-acme-challenge

  export NODE_ENV=production
}

stop() {
  pkill -9 -f node
  return 0
}

restart() {
  $0 stop
  $0 start
}
EOF
chmod a+x /etc/init.d/npm
rc-update add npm boot &>/dev/null
rc-update add openresty boot &>/dev/null
rc-service openresty stop &>/dev/null

# Start services
log "Starting services"
rc-service openresty start
rc-service npm start

IP=$(ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
log "Installation complete

\e[0mNginx Proxy Manager should be reachable at the following URL.

      http://${IP}:81
"
