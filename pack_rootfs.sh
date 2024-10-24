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
ARCH=arm64

# shellcheck disable=SC2034
DEBOOTSTRAP_LIST="systemd sudo locales apt-utils init dbus kmod udev bash-completion ntp libjsoncpp-dev libjson-c-dev rapidjson-dev libgpiod2 libgpiod-dev libdrm-dev libevent-dev kcapi-tools libkcapi-dev libminizip-dev can-utils"

get_package_list()
{
    package_list_file="${LOCAL_DIR}/package/debian-${1}-${ARCH}-packages"
    if [ ! -f "${package_list_file}" ]; then
        echo "ERROR: package list file - ${package_list_file} not found" > /dev/stderr
        exit 1
    fi
    PACKAGE_LIST=$(sed ':a;N;$!ba;s/\n/ /g' < "${package_list_file}")
    echo "${PACKAGE_LIST}"
}

# shellcheck disable=SC2034
ADD_PACKAGE_LIST="$(get_package_list "base") $(get_package_list "server") $(get_package_list "desktop") "