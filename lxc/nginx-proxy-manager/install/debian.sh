#!/usr/bin/env bash

set -eux
set -o pipefail
#trap trapexit EXIT SIGTERM
echo $PATH | grep /usr/local/bin >/dev/null 2>&1 || export PATH=$PATH:/usr/local/bin

alias sget='wget -qO -'
DISTRO_ID=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
DISTRO_CODENAME=$(cat /etc/*-release | grep -w VERSION_CODENAME | cut -d= -f2 | tr -d '"')

TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
LASTCMD=""
WGETOPT="-t 1 -T 15 -q"
DEVDEPS="git build-essential libffi-dev libssl-dev python3-dev"
NPMURL="https://github.com/NginxProxyManager/nginx-proxy-manager"

cd $TEMPDIR
touch $TEMPLOG

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
  apt remove --purge -y $DEVDEPS -qq &>/dev/null
  apt autoremove -y -qq &>/dev/null
  apt clean
  rm -rf $TEMPDIR
  rm -rf /root/.cache
}

# Check for previous install
if [ -f /lib/systemd/system/npm.service ]; then
  log "Stopping services"
  systemctl stop openresty
  systemctl stop npm
  
  # Cleanup for new install
  log "Cleaning old files"
  rm -rf /app \
  /var/www/html \
  /etc/nginx \
  /var/log/nginx \
  /var/lib/nginx \
  /var/cache/nginx &>/dev/null
fi

# Install dependencies
log "Installing dependencies"
apt update
export DEBIAN_FRONTEND=noninteractive
apt install -y --no-install-recommends $DEVDEPS gnupg openssl ca-certificates apache2-utils logrotate jq

# Install Python
log "Installing python"
apt install -y -q --no-install-recommends python3 python3-distutils python3-venv python3-pip
python3 -m venv /opt/certbot/
export PATH=/opt/certbot/bin:$PATH
source /opt/certbot/bin/activate
#grep -qo "/opt/certbot" /etc/environment || echo "PATH=$PATH" >> /etc/environment
grep -qo "/opt/certbot" /etc/profile || echo "source /opt/certbot/bin/activate" >> /etc/profile
# Install certbot and python dependancies
#wget -qO - https://bootstrap.pypa.io/get-pip.py | python -
if [ "$(getconf LONG_BIT)" = "32" ]; then
pip install --no-cache-dir -U cryptography==3.3.2
fi
pip install --no-cache-dir cffi certbot

# Install openresty
log "Installing openresty"
wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
_distro_release=$(wget $WGETOPT "http://openresty.org/package/$DISTRO_ID/dists/" -O - | grep -o "$DISTRO_CODENAME" | head -n1 || true)
if [ $DISTRO_ID = "ubuntu" ]; then
  echo "deb [trusted=yes] http://openresty.org/package/$DISTRO_ID ${_distro_release:-focal} main" | tee /etc/apt/sources.list.d/openresty.list
else
  echo "deb [trusted=yes] http://openresty.org/package/$DISTRO_ID ${_distro_release:-bullseye} openresty" | tee /etc/apt/sources.list.d/openresty.list
fi
apt install -y -q --no-install-recommends openresty

# Install nodejs
log "Installing nodejs"
wget -qO - https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
wget -qO - https://deb.nodesource.com/setup_16.x | bash -
apt install -y -q --no-install-recommends nodejs npm gcc g++ make
npm install --global yarn

# Get latest version information for nginx-proxy-manager
log "Checking for latest NPM release"
URL_INFO_API_1="https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest"
URL_INFO_API_2="https://api.upup.cool/repo/NginxProxyManager/nginx-proxy-manager/info"
PROXY_MANAGER_INFO="$(sget $URL_INFO_API_1 || sget URL_INFO_API_2)"
_latest_version=$(echo $PROXY_MANAGER_INFO | jq -r 'if .version then .version else .tag_name end')

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
ln -sf /opt/certbot/bin/pip /usr/bin/pip
ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
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
yarn install --network-timeout=30000
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
yarn install --network-timeout=30000

# Create NPM service
log "Creating NPM service"
cat << 'EOF' > /lib/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target
Wants=openresty.service

[Service]
Type=simple
Environment=NODE_ENV=production
ExecStartPre=-/bin/mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge
ExecStart=/usr/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250
WorkingDirectory=/app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable npm

# Start services
log "Starting services"
systemctl start openresty
systemctl start npm

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete

\e[0mNginx Proxy Manager should be reachable at the following URL.

      http://${IP}:81
"
