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
DEBOOTSTRAP_LIST="systemd sudo git vim curl wget lsb-release locales apt-utils openssh-server ssh dbus init \
strace kmod init udev bash-completion netbase network-manager \
ifupdown ethtool net-tools iputils-ping hostapd lightdm dnsmasq ntp chromium "
BASE_PACKAGE_LIST="file openssh-server ssh bsdmainutils whiptail device-tree-compiler \
bzip2 htop rsyslog parted python3 python3-pip console-setup fake-hwclock \
ncurses-term gcc g++ toilet sysfsutils rsyslog tzdata u-boot-tools \
libcjson1 libcjson-dev db-util diffutils e2fsprogs libc6 xterm \
libcrypt1 libdevmapper1.02.1 libedit2 libgcc-s1-arm64-cross libgcrypt20 libgpg-error0 \
libkcapi1 libmenu-cache3 libnss-db libpcap0.8 libpcre3 \
libvorbis0a libzmq5 lvm2 makedev mtd-utils ncurses-term ncurses-base nettle-bin \
nfs-common openssl perl-base perl tftpd-hpa tftp-hpa tzdata watchdog \
wpasupplicant alsa-utils base-files cryptsetup diffutils dosfstools \
dropbear e2fsprogs ethtool ffmpeg i2c-tools iperf3 \
libaio1 libasound2 libattr1 \
libblkid1 libc6 libc6-dev libcap2 libcom-err2 libcrypt-dev libdbus-1-3 libexpat1 libext2fs2 \
libgcc1 libgdbm-compat4 libgdbm-dev libgdbm6 libgmp10 libgnutls30 libidn2-0 libkmod2 \
liblzo2-2 libmount1 libncurses5 libncursesw5 libnl-3-200 libnl-genl-3-200 libogg0 libpopt0 \
libreadline8 libsamplerate0 libsndfile1 libss2 libstdc++6 \
libtinfo5 libtirpc3 libudev1 libunistring2 libusb-1.0-0 libuuid1 libwrap0 libx11-6 \
libxau6 libxcb1 libxdmcp6 libxext6 libxv1 libz-dev libz1 lrzsz lvm2 mtd-utils net-tools \
netbase openssh-sftp-server openssl rpcbind screen sysstat tcpdump libgl1-mesa-glx libgl1-mesa-dri xserver-xorg-core \
thin-provisioning-tools trace-cmd tzdata usbutils watchdog libturbojpeg0-dev \
base-passwd libasound2-dev libavcodec-dev libavformat-dev libavutil-dev libcrypto++-dev \
libjsoncpp-dev libssl-dev libswresample-dev libzmq3-dev perl sed \
symlinks libunwind8 libperl-dev ifmetric v4l-utils python3-dev \
build-essential libbullet-dev libasio-dev libtinyxml2-dev iotop htop iw wireless-tools \
bluetooth bluez blueman sqlite3 libsqlite3-dev libeigen3-dev liblog4cxx-dev libcurl4-openssl-dev \
libboost-dev libboost-date-time-dev libboost-thread-dev \
distro-info python3-click python3-colorama "
DESKTOP_PACKAGE_LIST="xfce4 xfce4-goodies xserver-xorg-video-fbdev policykit-1-gnome notification-daemon \
tightvncserver network-manager-gnome xfce4-terminal tightvncserver \
smplayer pavucontrol pulseaudio \
libvulkan1 mesa-vulkan-drivers libtinyxml-dev fonts-wqy-zenhei "
# shellcheck disable=SC2034
ADD_PACKAGE_LIST="${DEBOOTSTRAP_LIST} ${BASE_PACKAGE_LIST} ${DESKTOP_PACKAGE_LIST} "

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

    cat <<-EOF > "${ROOTFS_DIR}"/etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian/ sid main contrib non-free non-free-firmware
EOF

    chroot "${ROOTFS_DIR}" /bin/bash -c "apt update -y"
    chroot "${ROOTFS_DIR}" /bin/bash -c "apt -t sid install -y python3.11"

    cat <<-EOF > "${ROOTFS_DIR}"/etc/apt/sources.list
deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
EOF

    chroot "${ROOTFS_DIR}" /bin/bash -c "apt update -y"

    chroot "${ROOTFS_DIR}" /bin/bash -c "wget https://cdn.geekros.com/armcnc/libs/openssl-1.1.1w.tar.gz"
    chroot "${ROOTFS_DIR}" /bin/bash -c "tar xvf openssl-1.1.1w.tar.gz"
    chroot "${ROOTFS_DIR}" /bin/bash -c "cd openssl-1.1.1w && ./config && make && make install && cd ../ && rm -rf openssl-1.1.1*"

    chroot "${ROOTFS_DIR}" /bin/bash -c "rm -rf /var/lib/apt/lists/mirrors*"
    chroot "${ROOTFS_DIR}" /bin/bash -c "apt update -y"
    chroot "${ROOTFS_DIR}" /bin/bash -c "apt upgrade -y"
    chroot "${ROOTFS_DIR}" /bin/bash -c "apt autoremove -y"
    chroot "${ROOTFS_DIR}" /bin/bash -c "apt clean"
    chroot "${ROOTFS_DIR}" /bin/bash -c "truncate -s 0 /var/log/*.log"
    chroot "${ROOTFS_DIR}" /bin/bash -c "rm -rf /tmp/*"
    chroot "${ROOTFS_DIR}" /bin/bash -c "history -c && history -w"

    # 卸载文件系统和设备节点
    umount "${ROOTFS_DIR}/dev/pts"
    umount "${ROOTFS_DIR}/dev"
    umount "${ROOTFS_DIR}/proc"
    umount "${ROOTFS_DIR}/sys"

    # shellcheck disable=SC2155
    # shellcheck disable=SC2006
    local du_size=`du -sh "${ROOTFS_DIR}" 2> /dev/null |awk '{print $1}'`
    echo "DIR_DU_SIZE ${du_size%%M}" >> "${TAR_FILE}".info

    compress_base_root

    echo "Make Debian rootfs successfully"
}

compress_base_root() {
    tar --numeric-owner -czpf "${TAR_FILE}" -C "${ROOTFS_DIR}"/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' --exclude='./sys/*' --exclude='./usr/lib/aarch64-linux-gnu/dri/*' .
}

make_base_root