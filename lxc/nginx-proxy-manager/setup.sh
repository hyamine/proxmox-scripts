#!/usr/bin/env sh

set -eux
set -o pipefail

SUPPORTED_OS="debian alpine"

TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
NPMURL="https://github.com/NginxProxyManager/nginx-proxy-manager"
cd $TEMPDIR && mkdir -p install && touch "$TEMPLOG"
LASTCMD=""


exit_with_msg() {
  echo "ERROR: $2" 1>&2
  exit $1
}

log() {
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  #clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
  printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}

prepare_dep_debian() {
  echo todo...
}
prepare_dep_alpine() {
  sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
  WGETOPT="-t 2 -T 15 -q"
  apk update
  apk add wget
}

[ -f /etc/os-release ] || exit_with_msg 100 "OS Not Supported"
source <(cat /etc/os-release | tr -s '\n' | sed 's/ubuntu/debian/' | awk '{print "OS_"$0}')
#CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
for the_os in $SUPPORTED_OS; do
  [ "$the_os" = "$OS_ID" ] && IS_SUPPORTED=true && break
done
[ ! $IS_SUPPORTED ] && exit_with_msg 101 "OS Not Supported"
[ -n "$(grep 'kthreadd' /proc/2/status 2>/dev/null)" ] && exit_with_msg 102 "Only Supported In Container"

prepare_dep_${OS_ID}

if [ -f "$1" ]; then
  INSTALL_SCRIPT="$1"
else
  NSTALL_SCRIPT="$TEMPDIR/install/${OS_ID}.sh"
  wget -O ${INSTALL_SCRIPT} https://fastly.jsdelivr.net/gh/hyamine/proxmox-scripts@main/lxc/nginx-proxy-manager/install/$OS_ID.sh
fi
[ ! -f "$NSTALL_SCRIPT" ] && exit_with_msg 103 "OS Not Supported or Download install file failed"

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
export LC_ALL=en_US.UTF-8
export TZ=Asia/Shanghai
echo "LC_ALL=en_US.UTF-8" >> /etc/environment
echo "TZ=Asia/Shanghai" >> /etc/environment

#echo "registry=https://registry.npmmirror.com" > ~/.npmrc
#chmod 0600 ~/.npmrc
#mkdir -p ~/.config/pip/
#chmod 0755 ~/.config/pip/
#echo "[global]" > ~/.config/pip/pip.conf
#echo "index-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> ~/.config/pip/pip.conf
#echo 'registry "https://registry.npmmirror.com"' > /usr/local/share/.yarnrc
#echo 'registry "https://registry.npmmirror.com"' > ~/.yarnrc
#chmod 0644 ~/.yarnrc /usr/local/share/.yarnrc ~/.config/pip/pip.conf

#if [ "$(command -v bash)" ]; then
#  $(command -v sudo) bash "$INSTALL_SCRIPT" "$TEMPDIR"
#else
#  sh "$INSTALL_SCRIPT" "$TEMPDIR"
#fi

. "$NSTALL_SCRIPT"

trap trapexit_${OS_ID} EXIT SIGTERM

pre_install
install_depend
install_nodejs
install_openresty
install_python3
download_NPM
set_up_NPM_env
build_NPM_frontend
init_NPM_backend
create_NPM_service
start_now