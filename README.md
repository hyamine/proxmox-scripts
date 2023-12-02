# Proxmox scripts

Some useful proxmox scripts...

Proxmox ve (pve) 一键脚本，
当前已完成一键安装Nginx Proxy Manager(支持Debian、Alpine)

在Debian 12 、 Alpine 3.18上测试通过
主要针对中国大陆地区安装加速进行优化，安装示例：
```bash
wget --no-cache -qO - https://g.osspub.cn/https://raw.githubusercontent.com/hyamine/proxmox-scripts/main/lxc/nginx-proxy-manager/create.sh  \
| bash -s -- \
--cores 4 --disksize 20G --memory 4096 --id 202 --hostname debian-nginx \
--os debian --osversion 12
###或者
curl -fsSL https://g.osspub.cn/https://raw.githubusercontent.com/hyamine/proxmox-scripts/main/lxc/nginx-proxy-manager/create.sh  \
| bash -s -- \
--cores 4 --disksize 15G --memory 4096 --id 203 --hostname alpine-nginx \
--os alpine --osversion 3.18
```

## Scripts
### 1. Nginx Proxy Manager
[Nginx Proxy Manager](https://github.com/hyamine/proxmox-scripts/tree/main/lxc/nginx-proxy-manager) 

thanks to [ej52/proxmox-scripts](https://github.com/ej52/proxmox-scripts)
