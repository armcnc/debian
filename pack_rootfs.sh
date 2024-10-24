#!/bin/bash

set -e

USER="$(whoami)"
if [ "${USER}" != "root" ]; then
    echo "ERROR: This script requires root privilege"
    exit 1
fi

sudo apt update
sudo apt install -y qemu-user-static qemu-system-arm debootstrap binfmt-support

# shellcheck disable=SC2155
export LOCAL_DIR=$(pwd)
# shellcheck disable=SC2034
ROOTFS_DIR="${LOCAL_DIR}/debian_rootfs"
# shellcheck disable=SC2034
TAR_FILE=${LOCAL_DIR}/debian_rootfs.tar.gz
# shellcheck disable=SC2034
DEST_LANG="en_US.UTF-8"
# shellcheck disable=SC2034
DEST_LANG_CN="zh_CN.UTF-8"

# shellcheck disable=SC2034
DEBOOTSTRAP_LIST="systemd sudo locales apt-utils init dbus kmod udev bash-completion ntp libjsoncpp-dev libjson-c-dev rapidjson-dev libgpiod2 libgpiod-dev libdrm-dev libevent-dev kcapi-tools libkcapi-dev libminizip-dev can-utils"

get_package_list()
{
    package_list_file="${LOCAL_DIR}/package/debian-${1}-arm64-packages"
    if [ ! -f "${package_list_file}" ]; then
        echo "ERROR: package list file - ${package_list_file} not found" > /dev/stderr
        exit 1
    fi
    PACKAGE_LIST=$(sed ':a;N;$!ba;s/\n/ /g' < "${package_list_file}")
    echo "${PACKAGE_LIST}"
}

# shellcheck disable=SC2034
ADD_PACKAGE_LIST="${DEBOOTSTRAP_LIST} $(get_package_list "base") $(get_package_list "server") $(get_package_list "desktop") "

make_base_root() {
    if [ ! -d debian_rootfs ]; then
        # 生成基础文件系统
        mkdir debian_rootfs
        debootstrap --arch=arm64 --foreign bookworm "${ROOTFS_DIR}" http://mirrors.ustc.edu.cn/debian/
        # 使用qemu-user-static启动aarch64的二进制文件
        cp /usr/bin/qemu-aarch64-static "${ROOTFS_DIR}/usr/bin/"
        # 构建基础文件系统
        chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage
    fi

    # 挂载文件系统和设备节点
    mount -t proc chproc "${ROOTFS_DIR}"/proc
    mount -t sysfs chsys "${ROOTFS_DIR}"/sys
    mount -t devtmpfs chdev "${ROOTFS_DIR}"/dev || mount --bind /dev "${ROOTFS_DIR}"/dev
    mount -t devpts chpts "${ROOTFS_DIR}"/dev/pts

    chroot "${ROOTFS_DIR}" /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

    cat <<-EOF > "${ROOTFS_DIR}"/etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
EOF

    eval 'LC_ALL=C LANG=C chroot ${ROOTFS_DIR} /bin/bash -c "apt -q -y update"'
    eval 'LC_ALL=C LANG=C chroot ${ROOTFS_DIR} /bin/bash -c "apt -q -y upgrade"'
    eval 'LC_ALL=C LANG=C chroot ${ROOTFS_DIR} /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt -y -q install $ADD_PACKAGE_LIST"'

    chroot "${ROOTFS_DIR}" /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > "${TAR_FILE}".info

    chroot "${ROOTFS_DIR}" /bin/bash -c "pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple"
    chroot "${ROOTFS_DIR}" /bin/bash -c "pip3 config set install.trusted-host https://pypi.tuna.tsinghua.edu.cn"

    if [ -f "${ROOTFS_DIR}"/etc/locale.gen ];then
        sed -i "s/^# $DEST_LANG/$DEST_LANG/" "${ROOTFS_DIR}"/etc/locale.gen
        sed -i "s/^# $DEST_LANG_CN/$DEST_LANG_CN/" "${ROOTFS_DIR}"/etc/locale.gen
    fi

    eval 'LC_ALL=C LANG=C chroot $ROOTFS_DIR /bin/bash -c "locale-gen $DEST_LANG"'
    eval 'LC_ALL=C LANG=C chroot $ROOTFS_DIR /bin/bash -c "locale-gen $DEST_LANG_CN"'
    eval 'LC_ALL=C LANG=C chroot $ROOTFS_DIR /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG"'

    chroot "${ROOTFS_DIR}" /bin/bash -c "systemctl disable hostapd dnsmasq NetworkManager-wait-online.service"
    chroot "${ROOTFS_DIR}" /bin/bash -c "systemctl enable lightdm"
}

compress_base_root() {
    tar --numeric-owner -czpf "${TAR_FILE}" -C "${ROOTFS_DIR}"/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' --exclude='./sys/*' --exclude='./usr/lib/aarch64-linux-gnu/dri/*' .
}

make_base_root