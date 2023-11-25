#!/usr/bin/env sh

if [ "$(uname)" != "Linux" ]; then
  echo "OS NOT SUPPORTED"
  exit 1
fi

if [ "$1" != "" ] && [ -f "$1" ]; then
  INSTALL_SCRIPT="$1"
else
  DISTRO=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
  if [ "$DISTRO" != "alpine" ] && [ "$DISTRO" != "ubuntu" ] && [ "$DISTRO" != "debian" ]; then
    echo "DISTRO NOT SUPPORTED"
    exit 1
  fi
  if [ "$DISTRO" = "ubuntu" ]; then
    INSTALL_SCRIPT="debian"
  fi
  INSTALL_SCRIPT="/tmp/${DISTRO}_npm_install.sh"
  wget -O ${INSTALL_SCRIPT} https://fastly.jsdelivr.net/gh/hyamine/proxmox-scripts@main/lxc/nginx-proxy-manager/install/$DISTRO.sh
fi
if [ "$DISTRO" != "alpine" ]; then
  sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
else
  sudo sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
fi

echo "registry=https://registry.npmmirror.com" > ~/.npmrc
chmod 0600 ~/.npmrc
mkdir -p ~/.config/pip/
chmod 0755 ~/.config/pip/
echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" > ~/.config/pip/pip.conf

echo 'registry "https://registry.npmmirror.com"' > /usr/local/share/.yarnrc
echo 'registry "https://registry.npmmirror.com"' > ~/.yarnrc
chmod 0644 ~/.yarnrc /usr/local/share/.yarnrc ~/.config/pip/pip.conf

if [ "$(command -v bash)" ]; then
  $(command -v sudo) bash "$INSTALL_SCRIPT"
else
  sh "$INSTALL_SCRIPT"
fi


