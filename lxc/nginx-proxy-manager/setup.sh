#!/usr/bin/env sh

exit_with_msg() {
  echo "ERROR: $2" 1>&2
  exit $1
}

TEMPDIR=$(mktemp -d)
cd $TEMPDIR && mkdir -p install

[ -f /etc/os-release ] || exit_with_msg 100 "OS Not Supported"
source <(cat /etc/os-release | tr -s '\n' | sed 's/ubuntu/debian/' | awk '{print "OS_"$0}')
#CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
[ -z "${OS_ID}" ] && exit_with_msg 101 "OS Not Supported"
[ -n "$(grep 'kthreadd' /proc/2/status 2>/dev/null)" ] && exit_with_msg 102 "Only Supported In Container"

if [ "$1" != "" ] && [ -f "$1" ]; then
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

if [ "$(command -v bash)" ]; then
  $(command -v sudo) bash "$INSTALL_SCRIPT"
else
  sh "$INSTALL_SCRIPT"
fi


