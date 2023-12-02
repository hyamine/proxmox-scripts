#!/usr/bin/env bash

set -Eeux
set -o pipefail

RUN_LOCAL_SCRIPT=""
if [ -n "${BASH_SOURCE+set}" ]; then
  CURRENT_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
  CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
else
  CURRENT_SCRIPT_NAME=""
  CURRENT_SCRIPT_DIR="/tmp/_DIR_NOT_EXISTS"
fi
#CURRENT_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"


trap error ERR
trap 'popd >/dev/null; echo $_temp_dir | grep "/tmp" && rm -rf $_temp_dir;' EXIT

function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn { echo -e "\e[33m[warn] $*\e[39m"; }
function error { 
  trap - ERR

  if [ -z "${1-}" ]; then
    echo -e "\e[31m[error] $(caller): ${BASH_COMMAND}\e[39m"
  else
    echo -e "\e[31m[error] $1\e[39m"
  fi

  if [ ! -z ${_ctid-} ]; then
    if $(pct status $_ctid &>/dev/null); then
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

# Base raw github URL
#_raw_base="https://fastly.jsdelivr.net/gh/hyamine/proxmox-scripts@main/lxc/nginx-proxy-manager"
_raw_base="https://g.osspub.cn/https://raw.githubusercontent.com/hyamine/proxmox-scripts/master/lxc/nginx-proxy-manager"
# Operating system
_os_type=debian
_os_version=12
# System architecture
_arch=$(dpkg --print-architecture)

# Create temp working directory
_temp_dir=$(mktemp -d)
pushd $_temp_dir >/dev/null

# Parse command line parameters
while [[ $# -gt 0 ]]; do
  arg="$1"

  case $arg in
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
    *)
      error "Unrecognized option $1"
      ;;
  esac
  shift
done

# Check user settings or set defaults
_ctid=${_ctid:-`pvesh get /cluster/nextid`}
_cpu_cores=${_cpu_cores:-1}
_disk_size=${_disk_size:-2G}
_host_name=${_host_name:-nginx-proxy-manager}
_bridge=${_bridge:-vmbr0}
_memory=${_memory:-512}
_swap=${_swap:-0}
_storage=${_storage:-local-lvm}
_storage_template=${_storage_template:-local}

# Test if ID is in use
if pct status $_ctid &>/dev/null; then
  warn "ID '$_ctid' is already in use."
  unset _ctid
  error "Cannot use ID that is already in use."
fi

echo ""
warn "Container will be created using the following settings."
warn ""
warn "ctid:     $_ctid"
warn "hostname: $_host_name"
warn "cores:    $_cpu_cores"
warn "memory:   $_memory"
warn "swap:     $_swap"
warn "disksize: $_disk_size"
warn "bridge:   $_bridge"
warn "storage:  $_storage"
warn "templates:  $_storage_template"
warn ""
warn "If you want to abort, hit ctrl+c within 5 seconds..."
echo ""

sleep 5

# Download latest Alpine LXC template
info "Updating LXC template list..."
pveam update &>/dev/null

info "Downloading LXC template..."
mapfile -t _templates < <(pveam available -section system | sed -n "s/.*\($_os_type-$_os_version.*\)/\1/p" | sort -t - -k 2 -V)
[ ${#_templates[@]} -eq 0 ] \
  && error "No LXC template found for $_os_type-$_os_version"

_template="${_templates[-1]}"
pveam download $_storage_template $_template &>/dev/null \
  || error "A problem occured while downloading the LXC template."

# Create variables for container disk
_storage_type=$(pvesm status -storage $_storage 2>/dev/null | awk 'NR>1 {print $2}')
case $_storage_type in
  btrfs|dir|nfs)
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

# Create LXC
info "Allocating storage for LXC container..."
pvesm alloc $_storage $_ctid $_disk $_disk_size --format ${_disk_format:-raw} &>/dev/null \
  || error "A problem occured while allocating storage."

if [ "$_storage_type" = "zfspool" ]; then
  warn "Some containers may not work properly due to ZFS not supporting 'fallocate'."
else
  mkfs.ext4 $(pvesm path $_rootfs) &>/dev/null
fi

info "Creating LXC container..."
_pct_options=(
  -arch $_arch
  -cmode shell
  -hostname $_host_name
  -cores $_cpu_cores
  -memory $_memory
  -net0 name=eth0,bridge=$_bridge,ip=dhcp
  -onboot 1
  -ostype $_os_type
  -rootfs $_rootfs,size=$_disk_size
  -storage $_storage
  -swap $_swap
  -tags npm
  -timezone host
)
pct create $_ctid "$_storage_template:vztmpl/$_template" ${_pct_options[@]} &>/dev/null \
  || error "A problem occured while creating LXC container."

# Set container timezone to match host
cat << 'EOF' >> /etc/pve/lxc/${_ctid}.conf
lxc.hook.mount: sh -c 'ln -fs $(readlink /etc/localtime) ${LXC_ROOTFS_MOUNT}/etc/localtime'
EOF

# Setup container
info "Setting up LXC container..."
pct start $_ctid
sleep 5

echo "_rootfs=$_rootfs ; _storage=$_storage ; _ctid=$_ctid"

DISTRO=$(pct exec $_ctid -- sh -c "cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '\"'")
EXEC_SHELL=$(pct exec $_ctid -- sh -c "[ -f /bin/bash ] && echo bash") || EXEC_SHELL=sh

[ "$(echo $CURRENT_SCRIPT_NAME | grep -o '\.sh')" = ".sh" ] &&
[ -f "${CURRENT_SCRIPT_DIR}/setup.sh" ] && \
pct push $_ctid ${CURRENT_SCRIPT_DIR}/setup.sh /tmp/npm_setup.sh && \
[ -f "${CURRENT_SCRIPT_DIR}/install/${DISTRO}.sh" ] && \
pct push $_ctid "${CURRENT_SCRIPT_DIR}/install/${DISTRO}.sh" /tmp/${DISTRO}_npm_install.sh && \
RUN_LOCAL_SCRIPT="true" && \
pct exec $_ctid -- $EXEC_SHELL /tmp/npm_setup.sh /tmp/${DISTRO}_npm_install.sh

[ "$RUN_LOCAL_SCRIPT" != "true" ] && pct exec $_ctid -- $EXEC_SHELL -c "wget --no-cache -qO - $_raw_base/setup.sh | $EXEC_SHELL"
