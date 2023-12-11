# 🛠️ ARMCNC Debian

⚡ Building the Debian system required for ARMCNC operation. ⚡

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ⬇️ Setting up the compilation environment

```
https://zhuanlan.zhihu.com/p/141033713
```

```shell
sudo apt -y update && sudo apt -y upgrade
sudo apt -y install git vim curl wget
sudo passwd root
```

## ⬇️ Download

```shell
su
cd ~
git clone --depth=1 git@github.com:armcnc/debian.git
cd debian
```

## ⬇️ Building a Minimal File System for Debian12

```shell
sudo ./pack_rootfs.sh
```

## ⬇️ Customizing a Debian 12 System Image

```shell
sudo ./pack_image.sh
```

## ⚠️ Account information

```
Account：armcnc Password: armcnc
Account：root Password: armcnc
```

## 🌞 Development Team

> https://www.armcnc.net























