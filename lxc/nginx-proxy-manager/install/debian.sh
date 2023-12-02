#!/usr/bin/env bash

echo $PATH | grep /usr/local/bin >/dev/null 2>&1 || export PATH=$PATH:/usr/local/bin
WGETOPT="-t 1 -T 15 -q"
DEVDEPS="git build-essential libffi-dev libssl-dev python3-dev"
export DEBIAN_FRONTEND=noninteractive

# Helpers
log() { 
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  #clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
  printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}

trapexit_clean() {
  apt remove --purge -y $DEVDEPS -qq &>/dev/null
  apt autoremove -y -qq &>/dev/null
  apt clean
}
pre_install() {
  [ -f ~/.bashrc ] || touch ~/.bashrc && chmod 0644 ~/.bashrc
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
}
install_depend() {
  # Install dependencies
  log "Installing dependencies"
  apt upgrade -y
  #apt install  gnupg -y
  apt install -y --no-install-recommends $DEVDEPS gnupg openssl ca-certificates apache2-utils logrotate jq
}

install_python3() {
  # Install Python
  log "Installing python"
  apt install -y -q --no-install-recommends python3 python3-distutils python3-venv python3-pip
  pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
  pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
  pip3 config list
  python3 -m venv /opt/certbot/
  #export PATH=/opt/certbot/bin:$PATH
  source /opt/certbot/bin/activate
  grep -qo "/opt/certbot" ~/.bashrc || echo "source /opt/certbot/bin/activate" >> ~/.bashrc
  ln -sf /opt/certbot/bin/activate /etc/profile.d/pyenv_activate.sh
  pip3 install --upgrade pip
}

install_openresty() {
  OPENRESTY_REP_PREFIX="https://mirrors.ustc.edu.cn/openresty"
  if [ "$(getconf LONG_BIT)" = "32" ]; then
  pip install --no-cache-dir -U cryptography==3.3.2
  fi
  pip install --no-cache-dir cffi certbot

  # Install openresty
  log "Installing openresty"
  OS_ARCH_PATH=""
  uname -m | sed 's/aarch64/arm64/' | grep 'arm64' && OS_ARCH_PATH="/arm64"
  wget -O - $OPENRESTY_REP_PREFIX/pubkey.gpg | apt-key add -
  _distro_release=$(wget $WGETOPT "$OPENRESTY_REP_PREFIX/$OS_ID/dists/" -O - | grep -o "$OS_VERSION_CODENAME" | head -n1 || true)
  if [ $OS_ID = "ubuntu" ]; then
    echo "deb [trusted=yes] ${OPENRESTY_REP_PREFIX}${OS_ARCH_PATH}/$OS_ID ${_distro_release:-focal} main" | tee /etc/apt/sources.list.d/openresty.list
  else
    echo "deb [trusted=yes] ${OPENRESTY_REP_PREFIX}${OS_ARCH_PATH}/$OS_ID ${_distro_release:-bullseye} openresty" | tee /etc/apt/sources.list.d/openresty.list
  fi
  apt update
  apt install -y -q --no-install-recommends openresty
}

build_NPM_frontend() {
  # Build the frontend
  log "Building frontend"
  cd ./frontend
  export NODE_ENV=development
  yarn install --network-timeout=30000
  yarn build
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images
}

create_NPM_service() {
  [ -f /usr/lib/systemd/system/openresty.service ] \
    && sed -i 's|/usr/local/openresty/nginx/logs/nginx.pid|/run/nginx/nginx.pid|g' \
    /usr/lib/systemd/system/openresty.service
  mkdir -p /run/nginx && chmod 0755 /run/nginx

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
  adduser npm --shell=/bin/false --no-create-home
  systemctl daemon-reload
  systemctl enable npm
}

start_now() {
  # Start services
  log "Starting services"
  systemctl start openresty
  sleep 1
  systemctl start npm

  IP=$(hostname -I | cut -f1 -d ' ')
  log "Installation complete

  \e[0mNginx Proxy Manager should be reachable at the following URL.

        http://${IP}:81
  "
}