#!/usr/bin/env sh

set -eux
set -o pipefail

SUPPORTED_OS="debian alpine"
CURRENT_SHELL=""
INSTALL_SCRIPT=""
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
  source <(cat /etc/os-release | tr -s '\n' | sed 's/ubuntu/debian/' | awk '{print "OS_"$0}')
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
  echo todo...
}
get_install_script() {
  [ $# -gt 0 ] && INSTALL_SCRIPT="$1"
  #[ $# -gt 0 ] && echo "$INSTALL_SCRIPT" | grep -v '^/' && INSTALL_SCRIPT="$INSTALL_SCRIPT"
  if [ ! -f "$INSTALL_SCRIPT" ] && [ -n "${BASH_SOURCE+set}" ]; then
    INSTALL_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/install/${OS_ID}.sh"
  fi
  [ -f "$INSTALL_SCRIPT" ] || INSTALL_SCRIPT="$(readlink -f -- "$0")" && INSTALL_SCRIPT="$(dirname "$INSTALL_SCRIPT")/install/${OS_ID}.sh"
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
echo INSTALL_SCRIPT=$INSTALL_SCRIPT ......

SET_UP_SCRIPT="$TEMPDIR/_setup_on_${OS_ID}.sh"
echo TEMPDIR=$TEMPDIR
echo echo SET_UP_SCRIPT=$SET_UP_SCRIPT

cat > $SET_UP_SCRIPT <<EOF
#!/usr/bin/env bash
TEMPDIR=$TEMPDIR
TEMPLOG=$TEMPLOG
TEMPERR="$TEMPERR"
OS_ID=$OS_ID
OS_VERSION_ID=$OS_VERSION_ID
set -eux
set -o pipefail
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

#trap trapexit_${OS_ID} EXIT SIGTERM

cd $TEMPDIR

pre_install
install_depend
install_nvm_nodejs
install_openresty
install_python3
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