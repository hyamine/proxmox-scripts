#!/usr/bin/env sh

WGETOPT="-t 2 -T 15 -q"

trapexit_clean() {
  # Cleanup
  rm -rf $TEMPDIR
  apk del $DEVDEPS &>/dev/null
}

# Check for previous install
pre_install() {
  log "Updating container OS"
  echo "fs.file-max = 65535" > /etc/sysctl.conf
  [ -f ~/.profile ] || touch ~/.profile && chmod 0644 ~/.profile
  #[ -f ~/.bashrc ] || touch ~/.bashrc && chmod 0644 ~/.bashrc
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
}

install_depend() {
    log "Installing dependencies"
    # Install dependancies
    DEVDEPS="npm g++ make gcc libgcc linux-headers git musl-dev libffi-dev openssl openssl-dev jq binutils findutils"
    echo id -u npm
    id -u npm > /dev/null 2>&1 || adduser npm --shell=/bin/false --no-create-home -D;
    apk upgrade
    apk add openssl apache2-utils logrotate $DEVDEPS
    apk add -U curl bash ca-certificates ncurses coreutils grep util-linux gcompat
}


install_nodejs() {
  apk add nodejs
}

install_openresty() {
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
  apk add openresty
}

install_python3() {
  apk add python3 py3-pip python3-dev
  #python3 -m ensurepip --upgrade
  pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
  pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
  pip3 config list
  pip3 install --upgrade pip
  # Setup python env and PIP
  log "Setting up python"
  python3 -m venv /opt/certbot/
  grep -qo "/opt/certbot" ~/.bashrc || echo "source /opt/certbot/bin/activate" >> ~/.profile
  source /opt/certbot/bin/activate
  ln -sf /opt/certbot/bin/activate /etc/profile.d/pyenv_activate.sh
  # Install certbot and python dependancies
  pip3 install --no-cache-dir -U cryptography==3.3.2
  pip3 install --no-cache-dir cffi certbot
}

set_up_NPM_env() {
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
  sed -i 's|https://github.com/tabler|https://mirror.ghproxy.com/https://github.com/tabler|g' frontend/package.json

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
}

build_NPM_frontend() {
  # Build the frontend
  log "Building frontend"
  cd ./frontend
  export NODE_ENV=development
  yarn install || \
  sed -i 's|open(build_file_path, "rU").read()|open(build_file_path, "r").read()|g' $(find / -iname 'input.py') && \
  yarn install
  yarn build
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images
}

init_NPM_backend() {
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
}

create_NPM_service() {
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
}

start_now() {
  # Start services
  log "Starting services"
  rc-service openresty start
  rc-service npm start
  IP=$(ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')
  log "Installation complete

  \e[0mNginx Proxy Manager should be reachable at the following URL.

        http://${IP}:81
  "
}