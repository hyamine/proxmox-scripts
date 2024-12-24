#!/usr/bin/env bash

#set -Eeux
set -u
#set -o pipefail

function info {
  echo -e "\e[32m[Info] $*\e[39m"
}
function warn {
  echo -e "\e[33m[Warn] $*\e[39m"
}
function error() {
  echo -e "\e[33m[Error] $*\e[39m" >&2
}

if [ -n "${BASH_SOURCE+set}" ]; then
  CURRENT_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
  CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
else
  CURRENT_SCRIPT_NAME=""
  CURRENT_SCRIPT_DIR="/tmp/_DIR_NOT_EXISTS"
fi
#CURRENT_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Parse command line parameters
while [[ $# -gt 0 ]]; do
  arg="$1"

  case $arg in
  --host-shell)
    [ "$2" = "false" ] && _host_shell=false
    shift
    ;;
  --os)
    _os_type=$2
    shift
    ;;
  --osversion)
    _os_version=$2
    shift
    ;;
  --id)
    _ctid=$2
    shift
    ;;
  --bridge)
    _bridge=$2
    shift
    ;;
  --cores)
    _cpu_cores=$2
    shift
    ;;
  --disksize)
    _disk_size=$2
    shift
    ;;
  --hostname)
    _host_name=$2
    shift
    ;;
  --memory)
    _memory=$2
    shift
    ;;
  --storage)
    _storage=$2
    shift
    ;;
  --templates)
    _storage_template=$2
    shift
    ;;
  --swap)
    _swap=$2
    shift
    ;;
  --cn-mirrors)
    [ "$2" = "false" ] && _cn_mirrors=false
    shift
    ;;
  *)
    error "Unrecognized option $1"
    ;;
  esac
  shift
done

# Base raw github URL
#_raw_base="https://fastly.jsdelivr.net/gh/hyamine/proxmox-scripts@main/lxc/nginx-proxy-manager"
_raw_base="https://g.osspub.cn/https://raw.githubusercontent.com/hyamine/proxmox-scripts/master/lxc/nginx-proxy-manager"

# Check user settings or set defaults
_cpu_cores=${_cpu_cores:-1}
_disk_size=${_disk_size:-2G}
_host_name=${_host_name:-nginx-proxy-manager}
_bridge=${_bridge:-vmbr0}
_memory=${_memory:-512}
_swap=${_swap:-0}
_storage=${_storage:-local-lvm}
_storage_template=${_storage_template:-local}
# Operating system
_os_version=${_os_version:-debian}
_os_type=${_os_type:-12}
_host_shell=${_host_shell:-true}
_cn_mirrors=${_cn_mirrors:-true}
_template=""
_disk=""
_rootfs=""
_ctid=""

let PRE_INSTALL_STEP=0
let CURRENT_INSTALL_STEP=0
USER_HOME=${HOME} || ~
LXC_INSTALL_STEP_FILE="${USER_HOME}/.${_os_type}__${_os_version}_INSTALL_STEP"

if [ -f "${LXC_INSTALL_STEP_FILE}" ]; then
  PRE_LXC_ID=$(cat "${LXC_INSTALL_STEP_FILE}" | grep "_ctid" | awk -F "=" '{print $2}')
  tmp_os_type=$(cat "${LXC_INSTALL_STEP_FILE}" | grep "_os_type" | awk -F "=" '{print $2}')
  tmp_os_version=$(cat "${LXC_INSTALL_STEP_FILE}" | grep "_os_version" | awk -F "=" '{print $2}')
  pct status $PRE_LXC_ID >/dev/null 2>&1
  if [ "$?" = "0" ] && [ "$_os_version" = "$tmp_os_version" ] && [ "$_os_type" = "$tmp_os_type" ]; then
    # shellcheck source=${USER_HOME}/.${_os_type}__${_os_version}_INSTALL_STEP
    #pct status $PRE_LXC_ID >/dev/null 2>&1 &&
    . "${LXC_INSTALL_STEP_FILE}"
    let PRE_INSTALL_STEP=$INSTALL_STEP
  else
    rm -f "${LXC_INSTALL_STEP_FILE}"
  fi

fi

function save_step() {
  if [ "$1" != "" ] && [ $1 -gt $PRE_INSTALL_STEP ]; then
    if [ "$1" = "1" ]; then
      cat >$LXC_INSTALL_STEP_FILE <<-EOF
_os_type=$_os_type
_os_version=$_os_version
_ctid=${_ctid}
_cpu_cores=${_cpu_cores}
_disk_size=${_disk_size}
_host_name=${_host_name}
_bridge=${_bridge}
_memory=${_memory}
_swap=${_swap}
_storage=${_storage}
_storage_template=${_storage_template}
_template=${_template}
INSTALL_STEP=$1
EOF
    else
      sed -i "s|INSTALL_STEP=.*|INSTALL_STEP=$1|" $LXC_INSTALL_STEP_FILE
    fi
  fi
}

function exit_with_error() {
  echo -e "\033[31m Error: $* \033[0m" >&2
  exit $CURRENT_INSTALL_STEP
}

_retries=5
__step_info=""
__step_error=""

function retry {
  let CURRENT_INSTALL_STEP++
  info "retry $CURRENT_INSTALL_STEP run: $*"
  if [ $CURRENT_INSTALL_STEP -gt $PRE_INSTALL_STEP ]; then
    info "retry run step:  $CURRENT_INSTALL_STEP"
    [ -n "$__step_info" ] && info "$__step_info"
    local count=0
    until "$@"; do
      exit=$?
      wait=$((2 ** $count))
      count=$(($count + 1))
      if [ $count -lt $_retries ]; then
        echo "Retry $count/$_retries exited $exit, retrying in $wait seconds..."
        sleep $wait
      else
        echo "Retry $count/$_retries exited $exit, no more retries left."
        [ -n "$__step_error" ] && info "$__step_error"
        exit $exit
      fi
    done
    save_step $CURRENT_INSTALL_STEP
  fi
  __step_info=""
  __step_error=""
  return 0
}

function run_step() {
  let CURRENT_INSTALL_STEP++
  info "step $CURRENT_INSTALL_STEP run: $*"
  if [ $CURRENT_INSTALL_STEP -gt $PRE_INSTALL_STEP ]; then
    info "step run step:  $CURRENT_INSTALL_STEP"
    [ -n "$__step_info" ] && info "$__step_info"
    [ -z "$__step_error" ] && __step_error="Execute error: $*"
    "$@" || exit_with_error "$__step_error"
    save_step $CURRENT_INSTALL_STEP
  fi
  __step_info=""
  __step_error=""
  return 0
}

if [ "$_host_shell" = "true" ]; then
  if [ "$_ctid" = "" ]; then
    _ctid=${_ctid:-$(pvesh get /cluster/nextid)}
  fi

  # System architecture
  _arch="$(dpkg --print-architecture)"
  set -o pipefail
  function pct_run() {
    pct exec $_ctid -- $EXEC_SHELL -c "$*"
  }

  #trap _error ERR
  #trap 'popd >/dev/null; echo $_temp_dir | grep "/tmp" && rm -rf $_temp_dir;' EXIT

  function _error {
    trap - ERR

    if [ -z "${1-}" ]; then
      echo -e "\e[31m[error] $(caller): ${BASH_COMMAND}\e[39m"
    else
      echo -e "\e[31m[error] $1\e[39m"
    fi

    if [[ -n ${_ctid-} ]]; then
      if pct status $_ctid &>/dev/null; then
        if [ "$(pct status $_ctid 2>/dev/null | awk '{print $2}')" == "running" ]; then
          pct stop $_ctid &>/dev/null
        fi
        pct destroy $_ctid &>/dev/null
      elif [ "$(pvesm list $_storage --vmid $_ctid 2>/dev/null | awk 'FNR == 2 {print $2}')" != "" ]; then
        pvesm free $_rootfs &>/dev/null
      fi
    fi

    exit 1
  }
  function echo_config() {
    echo ""
    warn "Container will be created using the following settings."
    warn ""
    warn "os:        $_os_type"
    warn "osversion: $_os_version"
    warn "ctid:      $_ctid"
    warn "hostname:  $_host_name"
    warn "cores:     $_cpu_cores"
    warn "memory:    $_memory"
    warn "swap:      $_swap"
    warn "disksize:  $_disk_size"
    warn "bridge:    $_bridge"
    warn "storage:   $_storage"
    warn "templates: $_storage_template"
    warn "template:  $_template"
    warn "disk:      $_disk"
    warn "rootfs:    $_rootfs"
    warn ""
    warn "If you want to abort, hit ctrl+c within 5 seconds..."
    echo ""
    sleep 5
  }
  $_host_shell && echo_config
  function get_template_name() {
    if [ "$_template" == "" ]; then
      __step_info="check LXC template name..."
      __step_error="No LXC template found for $_os_type-$_os_version"
      pveam update &>/dev/null || return 1
      mapfile -t _templates < <(pveam available -section system | sed -n "s/.*\($_os_type-$_os_version.*\)/\1/p" | sort -t - -k 2 -V)
      [ ${#_templates[@]} -eq 0 ] && return 1
      _template="${_templates[-1]}"
    fi
    return 0
  }

  retry get_template_name
  [ -z "${_template}" ] && rm -f "${LXC_INSTALL_STEP_FILE}" && get_template_name

  __step_info="Downloading LXC template..."
  __step_error="A problem occured while downloading the LXC template."
  echo retry pveam download $_storage_template $_template
  retry pveam download $_storage_template $_template

  # Create variables for container disk
  function prepare_disk_params() {
    _storage_type=$(pvesm status -storage $_storage 2>/dev/null | awk 'NR>1 {print $2}')
    case $_storage_type in
    btrfs | dir | nfs)
      _disk_ext=".raw"
      _disk_ref="$_ctid/"
      ;;
    zfspool)
      _disk_prefix="subvol"
      _disk_format="subvol"
      ;;
    esac
    _disk=${_disk_prefix:-vm}-${_ctid}-disk-0${_disk_ext-}
    _rootfs=${_storage}:${_disk_ref-}${_disk}
    echo "_disk=$_disk" >>$LXC_INSTALL_STEP_FILE
    echo "_rootfs=$_rootfs" >>$LXC_INSTALL_STEP_FILE
  }

  run_step prepare_disk_params

  # Create LXC
  __step_info="Allocating storage for LXC container..."
  __step_error="A problem occured while allocating storage."
  run_step pvesm alloc $_storage $_ctid $_disk $_disk_size --format ${_disk_format:-raw}

  function format_rootfs() {
    if [ "$_storage_type" = "zfspool" ]; then
      warn "Some containers may not work properly due to ZFS not supporting 'fallocate'."
    else
      mkfs.ext4 "$(pvesm path $_rootfs)"
    fi
  }
  run_step format_rootfs

  #_pct_options=(
  set -- \
    "-arch" "$_arch" \
    "-cmode" "shell" \
    "-hostname" "$_host_name" \
    "-cores" "$_cpu_cores" \
    "-memory" "$_memory" \
    "-net0" "name=eth0,bridge=$_bridge,ip=dhcp" \
    "-onboot" "1" \
    "-ostype" "$_os_type" \
    "-rootfs" "$_rootfs,size=$_disk_size" \
    "-storage" "$_storage" \
    "-swap" "$_swap" \
    "-tags" "npm" \
    "-timezone" "host"
  #)

  # Test if ID is in use
  #    if pct status $_ctid &>/dev/null; then
  #      warn "ID '$_ctid' is already in use."
  #      unset _ctid
  #      error "Cannot use ID that is already in use."
  #    fi
  __step_info="Creating LXC container..."
  __step_error="A problem occured while creating LXC container."
  run_step pct create $_ctid "$_storage_template:vztmpl/$_template" "$@"

  function setup_timezone() {
    # Set container timezone to match host
    cat <<'EOF' >>/etc/pve/lxc/${_ctid}.conf
lxc.hook.mount: sh -c 'ln -fs $(readlink /etc/localtime) ${LXC_ROOTFS_MOUNT}/etc/localtime'
EOF
    return $?
  }
  run_step setup_timezone

  # Setup container
  info "Setting up LXC container..."
  lxc_status="$(pct status $_ctid 2>/dev/null | awk '{print $2}')"
  if [ "$lxc_status" = "" ]; then
    exit_with_error "LXC container $_ctid not found"
  elif [ "$lxc_status" = "stopped" ]; then
    pct start $_ctid
    sleep 5
  fi

  DISTRO=$(pct exec $_ctid -- sh -c "cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '\"'")
  EXEC_SHELL=$(pct exec $_ctid -- sh -c "[ -f /bin/bash ] && echo bash") || EXEC_SHELL="sh"

  function prepare_dep_alpine() {
    $_cn_mirrors && pct_run "sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories"
    pct_run "apk update && apk add -U wget bash" || return $CURRENT_INSTALL_STEP
    #pct_run "touch ~/.bashrc && chmod 0644 ~/.bashrc"
    #EXEC_SHELL=$(pct exec $_ctid -- sh -c "[ -f /bin/bash ] && echo bash") || EXEC_SHELL="sh"
    return 0
  }
  function prepare_dep_debian() {
    if [ "$_cn_mirrors" = "true" ]; then
      _no_trusted="$(pct_run [ -f '/etc/apt/sources.list.d/debian.sources' ] && echo true)"
      if [ "$_no_trusted" = "false" ]; then
        pct_run 'apt update && apt install -y apt-transport-https ca-certificates'
        pct_run 'sed -i "s/deb.debian.org/mirrors.ustc.edu.cn/g" /etc/apt/sources.list.d/debian.sources'
        pct_run 'sed -i "s|security.debian.org|mirrors.ustc.edu.cn/debian-security|g" /etc/apt/sources.list.d/debian.sources'
        pct_run 'sed -i "s/http:/https:/g" /etc/apt/sources.list.d/debian.sources'
      else
        pct_run 'sed -i "s|deb https\?://deb.debian.org|deb [trusted=yes] https://mirrors.ustc.edu.cn|g" /etc/apt/sources.list'
        pct_run 'sed -i "s|deb https\?://security.debian.org|deb [trusted=yes] https://mirrors.ustc.edu.cn/debian-security|g" /etc/apt/sources.list'
        #sed -i 's/http:/https:/g' /etc/apt/sources.list
        #sed -i 's/security.debian.org/mirrors.cloud.tencent.com/g' /etc/apt/sources.list
        pct_run 'apt update && apt install -y apt-transport-https ca-certificates'
      fi
    fi
    pct_run 'apt update && apt install -y wget' || return $CURRENT_INSTALL_STEP
    return 0
  }

  #retry prepare_dep_${_os_type}
  LXC_SETUP_FILE="/tmp/___npm_setup.sh"
  function push_install_file() {
    #[ "$EXEC_SHELL" != "bash" ] && exit_with_error "Bash not found, the script needs to be run in a bash environment!"
    if [ "$(echo $CURRENT_SCRIPT_NAME | grep -o '\.sh')" = ".sh" ] && [ -f "${CURRENT_SCRIPT_DIR}/$CURRENT_SCRIPT_NAME" ]; then
      pct push $_ctid "${CURRENT_SCRIPT_DIR}/$CURRENT_SCRIPT_NAME" "$LXC_SETUP_FILE" || return $CURRENT_INSTALL_STEP
    else
      #pct exec $_ctid -- $EXEC_SHELL -c "wget --no-cache -qO $LXC_SETUP_FILE $_raw_base/create.sh" || return $CURRENT_INSTALL_STEP
      wget --no-cache -qO "$LXC_SETUP_FILE" || return $CURRENT_INSTALL_STEP
      pct push $_ctid "$LXC_SETUP_FILE" "$LXC_SETUP_FILE" || return $CURRENT_INSTALL_STEP
    fi
  }

  retry push_install_file

  function exec_lxc_setup() {
    set -- \
      "--host-shell" "false" \
      "--cn-mirrors" "$_cn_mirrors" \
      "--os" "$_os_type"
    _cmd_line="pct exec $_ctid -- $EXEC_SHELL -c \"$EXEC_SHELL -- $LXC_SETUP_FILE $*\""
    echo "$_cmd_line"
    #$_cmd_line
    pct exec $_ctid -- $EXEC_SHELL -c "$EXEC_SHELL -- $LXC_SETUP_FILE $*"
  }
  retry exec_lxc_setup
else
  ### run on lxc container

  # Create temp working directory
  #_temp_dir=$(mktemp -d)
  #pushd "$_temp_dir" >/dev/null || exit
  WGETOPT="-t 1 -T 15 -q"
  TEMPDIR=""
  NPMURL="https://github.com/NginxProxyManager/nginx-proxy-manager"
  echo $PATH | grep /usr/local/bin >/dev/null 2>&1 || export PATH=$PATH:/usr/local/bin
  export DEBIAN_FRONTEND=noninteractive
  _shell_profile="${HOME}/.profile"
  EXEC_SHELL=$([ -f /bin/bash ] && echo bash) || EXEC_SHELL="sh"
  [ "$EXEC_SHELL" = "bash" ] && _shell_profile="${HOME}/.bashrc"

  function check_support() {
    [ -f /etc/os-release ] || exit_with_msg 100 "OS Not Supported"
    #source <(cat /etc/os-release | tr -s '\n' | sed 's/ubuntu/debian/' | awk '{print "OS_"$0}')
    source <(cat /etc/os-release | tr -s '\n' | awk '{print "OS_"$0}')
    #CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    if [ "$_os_type" != "$OS_ID" ]; then
      exit_with_msg 101 "OS Not Supported"
    fi
    if [ -n "$(grep 'kthreadd' /proc/2/status 2>/dev/null)" ]; then
      exit_with_msg 102 "Only Supported In Container"
    fi
  }
  function prepare_temp_dir() {
    TEMPDIR=$(mktemp -d)
    TEMPLOG="$TEMPDIR/tmplog"
    TEMPERR="$TEMPDIR/tmperr"
    mkdir -p $TEMPDIR/install && touch "$TEMPLOG"
  }

  function replace_debian_pkg_source() {
    if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
      apt update
      apt install -y apt-transport-https ca-certificates
      sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
      sed -i 's|security.debian.org|mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list.d/debian.sources
      sed -i 's/http:/https:/g' /etc/apt/sources.list.d/debian.sources
      apt update
    else
      sed -i 's|deb https\?://deb.debian.org|deb [trusted=yes] https://mirrors.ustc.edu.cn|g' /etc/apt/sources.list
      sed -i 's|deb https\?://security.debian.org|deb [trusted=yes] https://mirrors.ustc.edu.cn/debian-security|g' /etc/apt/sources.list
      #sed -i 's/http:/https:/g' /etc/apt/sources.list
      #sed -i 's/security.debian.org/mirrors.cloud.tencent.com/g' /etc/apt/sources.list
      apt update
    fi
  }

  function log() {
    logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g")
    #clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
    printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG
  }

  function replace_alpine_pkg_source() {
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
    apk update
    #apk update && apk add -U wget bash || return $CURRENT_INSTALL_STEP
    #pct_run "touch ~/.bashrc && chmod 0644 ~/.bashrc"
    #EXEC_SHELL=$(pct exec $_ctid -- sh -c "[ -f /bin/bash ] && echo bash") || EXEC_SHELL="sh"
  }

  # Check for previous install
  pre_install() {
    log "Updating container OS"
    echo "fs.file-max = 65535" >/etc/sysctl.conf
    #sed -i 's|root:/root:/bin/ash|root:/root:/bin/bash|' /etc/passwd
    [ -f "${_shell_profile}" ] || touch "${_shell_profile}" && chmod 0644 "${_shell_profile}"
    if [ "${_os_type}" = "alpine" ] && [ -f /etc/init.d/npm ]; then
      log "Stopping services"
      rc-service npm stop >/dev/null
      rc-service openresty stop >/dev/null
      echo ". ${_shell_profile}" >>/etc/profile
    elif [ "${_os_type}" = "debian" ] && [ -f /lib/systemd/system/npm.service ]; then
      log "Stopping services"
      systemctl stop openresty
      systemctl stop npm
    fi
    sleep 2
    # Cleanup for new install
    log "Cleaning old files"
    rm -rf /app \
      /var/www/html \
      /etc/nginx \
      /var/log/nginx \
      /var/lib/nginx \
      /var/cache/nginx >/dev/null 2>&1
  }
  install_alpine_depend() {
    log "Installing dependencies"
    # Install dependancies
    DEVDEPS="npm g++ make gcc libgcc linux-headers git musl-dev libffi-dev openssl openssl-dev jq binutils findutils wget"
    echo id -u npm
    id -u npm >/dev/null 2>&1 || adduser npm --shell=/bin/false --no-create-home -D
    apk upgrade
    apk add apache2-utils logrotate $DEVDEPS
    apk add -U curl bash ca-certificates ncurses coreutils grep util-linux gcompat
  }
  install_debian_depend() {
    # Install dependencies
    log "Installing dependencies"
    DEVDEPS="git build-essential libffi-dev libssl-dev python3-dev wget"
    apt upgrade -y
    #apt install  gnupg -y
    apt install -y --no-install-recommends $DEVDEPS gnupg openssl ca-certificates apache2-utils logrotate jq
  }
  install_alpine_python3() {
    apk add python3 py3-pip python3-dev
    #python3 -m ensurepip --upgrade
    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
    pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
    pip3 config list
    # Setup python env and PIP
    log "Setting up python"
    python3 -m venv /opt/certbot/
    grep -qo "/opt/certbot" "${_shell_profile}" || echo "source /opt/certbot/bin/activate" >> "${_shell_profile}"
    source /opt/certbot/bin/activate
    ln -sf /opt/certbot/bin/activate /etc/profile.d/pyenv_activate.sh
    # Install certbot and python dependancies
    #pip3 install --no-cache-dir -U cryptography==3.3.2
    #pip3 install --no-cache-dir -U cryptography
    pip3 install --upgrade pip
    pip3 install --no-cache-dir cffi certbot
  }
  install_debian_python3() {
    # Install Python
    log "Installing python"
    #apt install -y -q --no-install-recommends python3 python3-distutils python3-venv python3-pip
    apt install -y -q --no-install-recommends python3 python3-setuptools python3-venv python3-pip
    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple/
    pip3 config set install.trusted-host pypi.tuna.tsinghua.edu.cn
    pip3 config list
    python3 -m venv /opt/certbot/
    #export PATH=/opt/certbot/bin:$PATH
    source /opt/certbot/bin/activate
    grep -qo "/opt/certbot" "${_shell_profile}" || echo "source /opt/certbot/bin/activate" >> "${_shell_profile}"
    ln -sf /opt/certbot/bin/activate /etc/profile.d/pyenv_activate.sh
    pip3 install --upgrade pip
  }
  install_nvm_nodejs() {
    # Install nodejs
    log "Installing nodejs"
    _API_INFO="$(wget -qO - 'https://g.osspub.cn/repos/nvm-sh/nvm/releases/latest' || wget -qO - 'https://api.upup.cool/repo/nvm-sh/nvm/info')"
    _latest_version=$(echo $_API_INFO | jq -r 'if .version then .version else .tag_name end')
    # shellcheck disable=SC1101
    wget -qO- https://fastly.jsdelivr.net/gh/nvm-sh/nvm@${_latest_version}/install.sh |
      sed 's|raw.githubusercontent.com/${NVM_GITHUB_REPO}/${NVM_VERSION}|fastly.jsdelivr.net/gh/${NVM_GITHUB_REPO}@${NVM_VERSION}|g' |
      sed 's|NVM_SOURCE_URL="https://github.com|NVM_SOURCE_URL="https://g.osspub.cn/https://github.com|g' >$TEMPDIR/nvm_install.sh

    bash $TEMPDIR/nvm_install.sh
    # shellcheck source=${_shell_profile}
    . "${_shell_profile}"
    [ -f /etc/alpine-release ] && mv /etc/alpine-release /etc/alpine-release.bak
    nvm install 16
    [ -f /etc/alpine-release.bak ] && mv /etc/alpine-release.bak /etc/alpine-release
    npm config set registry https://registry.npmmirror.com
    npm install --force --global yarn

    ln -sf "$(command -v node)" /usr/bin/node
    ln -sf "$(command -v yarn)" /usr/bin/yarn
    ln -sf "$(command -v npm)" /usr/bin/npm

    yarn config set registry https://registry.npmmirror.com -g
    yarn config set disturl https://npmmirror.com/dist -g
    yarn config set electron_mirror https://npmmirror.com/mirrors/electron/ -g
    yarn config set sass_binary_site https://npmmirror.com/mirrors/node-sass/ -g
    yarn config set phantomjs_cdnurl https://npmmirror.com/mirrors/phantomjs/ -g
    yarn config set chromedriver_cdnurl https://cdn.npmmirror.com/dist/chromedriver -g
    yarn config set operadriver_cdnurl https://cdn.npmmirror.com/dist/operadriver -g
    yarn config set fse_binary_host_mirror https://npmmirror.com/mirrors/fsevents -g
  }

  info "Installing services in container:"
  echo "mirrors: $_cn_mirrors, host: $_host_shell"
  echo "$*"
  run_step prepare_temp_dir
  check_support
  $_cn_mirrors && run_step replace_${_os_type}_pkg_source
  run_step pre_install
  run_step install_${_os_type}_depend
  run_step install_${_os_type}_python3

fi
