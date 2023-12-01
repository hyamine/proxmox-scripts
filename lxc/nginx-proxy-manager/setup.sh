#!/usr/bin/env sh

set -eux
#set -o pipefail

SUPPORTED_OS="debian ubuntu alpine"
CURRENT_SHELL=""
INSTALL_SCRIPT=""
OS_VERSION_CODENAME=""
#LAST_COMMAND="$_"  # IMPORTANT: This must be the first line in the script after the shebang otherwise it will not work
#echo LAST_COMMAND=$LAST_COMMAND
#temp="$(ps -o pid,comm | grep -Fw $$)"; for word in $temp; do CURRENT_SHELL=$word; done; unset temp word
#if test -n "$BASH_SOURCE"; then SCRIPT="${BASH_SOURCE[0]}"; elif test "$0" != "$CURRENT_SHELL" && test "$0" != "-$CURRENT_SHELL"; then SCRIPT="$0"; elif test -n "$LAST_COMMAND"; then SCRIPT="$LAST_COMMAND"; else echo "Error"; fi; unset LAST_COMMAND
##SCRIPT=$(realpath "$SCRIPT" 2>&-) || echo "Error"
#SCRIPT_DIR=$(dirname "$SCRIPT")

#ps -o args= -p "$$"
#CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
#CURRENT_SHELL=$(pstree  -p $$  | tr ' ()' '\012\012\012' | grep -i "sh$" | grep -v "$0" | tr '`' '-' | tail -1 | sed 's/[|-]//g')

get_cur_shell() {
  __temp_pid="$(ps -o pid,comm | grep -Fw $$)"
  for __tmp_word in $__temp_pid; do
    CURRENT_SHELL=$__tmp_word;
  done
  unset __temp_pid __temp_pid
}

prepare_temp_dir() {
  TEMPDIR=$(mktemp -d)
  TEMPLOG="$TEMPDIR/tmplog"
  TEMPERR="$TEMPDIR/tmperr"
  mkdir -p $TEMPDIR/install && touch "$TEMPLOG"
}
exit_with_msg() {
  echo "ERROR: $2" 1>&2
  exit $1
}
check_support() {
  [ -f /etc/os-release ] || exit_with_msg 100 "OS Not Supported"
  #source <(cat /etc/os-release | tr -s '\n' | sed 's/ubuntu/debian/' | awk '{print "OS_"$0}')
  source <(cat /etc/os-release | tr -s '\n' | awk '{print "OS_"$0}')
  #CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
  for the_os in $SUPPORTED_OS; do
    [ "$the_os" = "$OS_ID" ] && IS_SUPPORTED=true && break
  done
  [ ! $IS_SUPPORTED ] && exit_with_msg 101 "OS Not Supported"
  if [ -n "$(grep 'kthreadd' /proc/2/status 2>/dev/null)" ]; then
    exit_with_msg 102 "Only Supported In Container"
  fi

}
prepare_dep_alpine() {
  sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
  apk update
  apk add -U wget bash
  touch ~/.bashrc
  chmod 0644 ~/.bashrc
}
prepare_dep_debian() {
    apt update
    apt install -y apt-transport-https ca-certificates wget
  if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
      sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
      sed -i 's|security.debian.org|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list.d/debian.sources
      sed -i 's/http:/https:/g' /etc/apt/sources.list.d/debian.sources
    else
      sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
      sed -i 's|security.debian.org|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list
      sed -i 's/http:/https:/g' /etc/apt/sources.list
      #sed -i 's/security.debian.org/mirrors.cloud.tencent.com/g' /etc/apt/sources.list
    fi
    apt update
}
prepare_dep_ubuntu() {
  todo...
}
get_install_script() {
  [ $# -gt 0 ] && INSTALL_SCRIPT="$1"
  #[ $# -gt 0 ] && echo "$INSTALL_SCRIPT" | grep -v '^/' && INSTALL_SCRIPT="$INSTALL_SCRIPT"
  if [ ! -f "$INSTALL_SCRIPT" ] && [ -n "${BASH_SOURCE+set}" ]; then
    INSTALL_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/install/${OS_ID}.sh"
  fi
  if [ ! -f "$INSTALL_SCRIPT" ]; then
    INSTALL_SCRIPT="$(readlink -f -- "$0")" && INSTALL_SCRIPT="$(dirname "$INSTALL_SCRIPT")/install/${OS_ID}.sh"
  fi
  if [ ! -f "$INSTALL_SCRIPT" ]; then
    INSTALL_SCRIPT="$TEMPDIR/install/${OS_ID}.sh"
    wget -O "${INSTALL_SCRIPT}" https://fastly.jsdelivr.net/gh/hyamine/proxmox-scripts@main/lxc/nginx-proxy-manager/install/$OS_ID.sh
  fi
  if [ ! -f "$INSTALL_SCRIPT" ]; then
    exit_with_msg 103 "OS Not Supported or Download install file failed"
  fi
}

check_support
#get_cur_shell
prepare_temp_dir
prepare_dep_${OS_ID}
get_install_script "$@"
SET_UP_SCRIPT="$TEMPDIR/_setup_on_${OS_ID}.sh"
echo TEMPDIR=$TEMPDIR
echo echo SET_UP_SCRIPT=$SET_UP_SCRIPT

cat > $SET_UP_SCRIPT <<EOF
#!/usr/bin/env bash

set -eux
set -o pipefail

TEMPDIR=$TEMPDIR
TEMPLOG=$TEMPLOG
TEMPERR="$TEMPERR"
OS_ID=$OS_ID
OS_VERSION_ID=$OS_VERSION_ID
OS_VERSION_CODENAME=$OS_VERSION_CODENAME

LASTCMD=""
INSTALL_SCRIPT=""
NPMURL="https://github.com/NginxProxyManager/nginx-proxy-manager"
INSTALL_SCRIPT="$INSTALL_SCRIPT"
SCRIPT_SHELL=bash
EOF

cat <<'EOF' >> $SET_UP_SCRIPT
log() {
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  #clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
  printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}

echo load "$INSTALL_SCRIPT"
. "$INSTALL_SCRIPT"

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
  rm -rf /root/.cache
  if [ "$(type -t trapexit_clean)" != "" ]; then
    trapexit_clean
  fi
 }

install_nvm_nodejs() {
  # Install nodejs
  log "Installing nodejs"
  # shellcheck disable=SC1101
  wget -qO-  https://fastly.jsdelivr.net/gh/nvm-sh/nvm@master/install.sh | \
    sed 's|raw.githubusercontent.com/${NVM_GITHUB_REPO}/${NVM_VERSION}|fastly.jsdelivr.net/gh/${NVM_GITHUB_REPO}@${NVM_VERSION}|g' | \
    sed 's|NVM_SOURCE_URL="https://github.com|NVM_SOURCE_URL="https://g.osspub.cn/https://github.com|g' > $TEMPDIR/nvm_install.sh

  $SCRIPT_SHELL $TEMPDIR/nvm_install.sh
  if [ "$(command -v nvm)" = "" ]; then
    [ -f ~/.bashrc ] && source ~/.bashrc
    [ -f ~/.profile ] && source ~/.profile
  fi
  nvm install 16
  npm config set registry https://registry.npmmirror.com
  npm install --force --global yarn

  ln -sf $(command -v node) /usr/bin/node
  ln -sf $(command -v yarn) /usr/bin/yarn
  ln -sf $(command -v npm) /usr/bin/npm

  yarn config set registry https://registry.npmmirror.com -g
  yarn config set disturl https://npmmirror.com/dist -g
  yarn config set electron_mirror https://npmmirror.com/mirrors/electron/ -g
  yarn config set sass_binary_site https://npmmirror.com/mirrors/node-sass/ -g
  yarn config set phantomjs_cdnurl https://npmmirror.com/mirrors/phantomjs/ -g
  yarn config set chromedriver_cdnurl https://cdn.npmmirror.com/dist/chromedriver -g
  yarn config set operadriver_cdnurl https://cdn.npmmirror.com/dist/operadriver -g
  yarn config set fse_binary_host_mirror https://npmmirror.com/mirrors/fsevents -g
}

download_NPM() {
  # Get latest version information for nginx-proxy-manager
  log "Checking for latest NPM release"
  URL_INFO_API_1="https://g.osspub.cn/https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest"
  URL_INFO_API_2="https://api.upup.cool/repo/NginxProxyManager/nginx-proxy-manager/info"
  PROXY_MANAGER_INFO="$(wget -qO - $URL_INFO_API_1 || wget -qO - URL_INFO_API_2)"
  _latest_version=$(echo $PROXY_MANAGER_INFO | jq -r 'if .version then .version else .tag_name end')
  PROXY_MANAGER_URL_1="https://g.osspub.cn/${NPMURL}/archive/refs/tags/${_latest_version}.tar.gz"
  PROXY_MANAGER_URL_2="https://api.upup.cool/repo/NginxProxyManager/nginx-proxy-manager/source"
  PROXY_MANAGER_URL_3="${NPMURL}/archive/refs/tags/${_latest_version}.tar.gz"
  PROXY_DOWN_FILE="${_latest_version}.tar.gz"
  wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_1} || wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_2} || wget -O ${PROXY_DOWN_FILE} ${PROXY_MANAGER_URL_3}
  tar xzf ${PROXY_DOWN_FILE}
  cd nginx-proxy-manager-*
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

init_NPM_backend() {
  # Initialize backend
  log "Initializing backend"
  rm -rf /app/config/default.json &>/dev/null
  if [ ! -f /app/config/production.json ]; then
  cat << 'EEOOFF' > /app/config/production.json
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
EEOOFF
  fi
  cd /app
  export NODE_ENV=development
  yarn install --network-timeout=30000
}

trap trapexit EXIT SIGTERM

cd $TEMPDIR

pre_install
install_depend
install_nvm_nodejs
install_python3
install_openresty
download_NPM
set_up_NPM_env
build_NPM_frontend
init_NPM_backend
create_NPM_service
start_now
EOF

bash $SET_UP_SCRIPT


#echo "registry=https://registry.npmmirror.com" > ~/.npmrc
#chmod 0600 ~/.npmrc
#mkdir -p ~/.config/pip/
#chmod 0755 ~/.config/pip/
#echo "[global]" > ~/.config/pip/pip.conf
#echo "index-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> ~/.config/pip/pip.conf
#echo 'registry "https://registry.npmmirror.com"' > /usr/local/share/.yarnrc
#echo 'registry "https://registry.npmmirror.com"' > ~/.yarnrc
#chmod 0644 ~/.yarnrc /usr/local/share/.yarnrc ~/.config/pip/pip.conf
#if typeset -p BASH_SOURCE 2> /dev/null | grep -q '^'; then
#  echo '$BASH_SOURCE exists'
#fi