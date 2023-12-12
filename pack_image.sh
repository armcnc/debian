#!/bin/bash

set -e

USER="$(whoami)"
if [ "${USER}" != "root" ]; then
    echo "ERROR: This script requires root privilege"
    exit 1
fi

# shellcheck disable=SC2155
export HR_LOCAL_DIR=$(pwd)
IMAGE_DEPLOY_DIR=${HR_LOCAL_DIR}/build
# shellcheck disable=SC2236
[ ! -z "${IMAGE_DEPLOY_DIR}" ] && [ ! -d "$IMAGE_DEPLOY_DIR" ] && mkdir "$IMAGE_DEPLOY_DIR"
# shellcheck disable=SC2034
IMG_FILE="${IMAGE_DEPLOY_DIR}/armcnc-debian-bookworm-arm64.img"
# shellcheck disable=SC2034
ROOTFS_BUILD_DIR=${IMAGE_DEPLOY_DIR}/rootfs
rm -rf "${ROOTFS_BUILD_DIR}"
[ ! -d "$ROOTFS_BUILD_DIR" ] && mkdir "${ROOTFS_BUILD_DIR}"
CONSOLE_CHAR="UTF-8"
ARMCNC_USERNAME="armcnc"
ARMCNC_PASSWORD="armcnc"

function install_packages(){
    local dst_dir=$1
    if [ ! -d "${dst_dir}" ]; then
        echo "dst_dir is not exist!" "${dst_dir}"
        # shellcheck disable=SC2242
        exit -1
    fi

    cd "${dst_dir}/app/hobot_debs"
    deb_list=$(ls)
    # shellcheck disable=SC2068
    for deb_name in ${deb_list[@]}
    do
        install_deb_chroot "${deb_name}" "${dst_dir}"
    done

    chroot "${dst_dir}" /bin/bash -c "apt clean"
    echo "Install hobot packages is finished"
}

function install_deb_chroot(){
    local package=$1
    local dst_dir=$2

    cd "${dst_dir}/app/hobot_debs"

    echo "###### Installing" "${package} ######"
    depends=$(dpkg-deb -f "${package}" Depends | sed 's/([^()]*)//g')
    if [ -f "${package}" ];then
        chroot "${dst_dir}" /bin/bash -c "dpkg --ignore-depends=${depends// /} -i /app/hobot_debs/${package}"
    fi
    echo "###### Installed" "${package} ######"
}

function unmount(){
    if [ -z "$1" ]; then
        DIR=$PWD
    else
        DIR=$1
    fi

    while mount | grep -q "$DIR"; do
        local LOCS
        LOCS=$(mount | grep "$DIR" | cut -f 3 -d ' ' | sort -r)
        for loc in $LOCS; do
            umount "$loc"
        done
    done
}

function unmount_image(){
    sync
    sleep 2
    LOOP_DEVICE=$(losetup --list | grep "$1" | cut -f1 -d' ')
    if [ -n "$LOOP_DEVICE" ]; then
        for part in "$LOOP_DEVICE"p*; do
            if DIR=$(findmnt -n -o target -S "$part"); then
                unmount "$DIR"
            fi
            sleep 5
        done
    fi
}

function make_ubuntu_image(){

    echo "tar -xzf ${HR_LOCAL_DIR}/debian_rootfs.tar.gz -C ${ROOTFS_BUILD_DIR}"
    tar --same-owner --numeric-owner -xzpf "${HR_LOCAL_DIR}"/debian_rootfs.tar.gz -C "${ROOTFS_BUILD_DIR}"
    mkdir -p "${ROOTFS_BUILD_DIR}"/{home,home/root,mnt,root,usr/lib,var,media,tftpboot,var/lib,var/volatile,dev,proc,tmp,run,sys,userdata,app,boot/hobot,boot/config}
    echo "1.0.0" >"${ROOTFS_BUILD_DIR}"/etc/version

    echo "Custom Special Modifications"

    echo "${ARMCNC_USERNAME}" > "${ROOTFS_BUILD_DIR}/etc/hostname"

    echo "kernel.printk = 4 4 1 7" > "${ROOTFS_BUILD_DIR}/etc/sysctl.conf"

    echo -e "\n[device]\nwifi.scan-rand-mac-address=no" >> "${ROOTFS_BUILD_DIR}/etc/NetworkManager/NetworkManager.conf"

    sed -i "1i127.0.0.1   ${ARMCNC_USERNAME}" "${ROOTFS_BUILD_DIR}/etc/hosts"
    echo "Asia/Shanghai" > "${ROOTFS_BUILD_DIR}/etc/timezone"

    sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' "${ROOTFS_BUILD_DIR}"/etc/ssh/sshd_config
    sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "${ROOTFS_BUILD_DIR}"/etc/ssh/sshd_config
    sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i "${ROOTFS_BUILD_DIR}"/etc/default/console-setup

    sed -i 's/^#autologin-user=$/autologin-user='"$ARMCNC_USERNAME"'/' "${ROOTFS_BUILD_DIR}"/etc/lightdm/lightdm.conf
    sed -i 's/^#autologin-user-timeout=0$/autologin-user-timeout=0/' "${ROOTFS_BUILD_DIR}"/etc/lightdm/lightdm.conf

    echo "HRNGDEVICE=/dev/urandom" >> "${ROOTFS_BUILD_DIR}"/etc/default/rng-tools
    echo "HRNGDEVICE=/dev/urandom" >> "${ROOTFS_BUILD_DIR}"/etc/default/rng-tools-debian

    sed "s/managed=\(.*\)/managed=true/g" -i "${ROOTFS_BUILD_DIR}"/etc/NetworkManager/NetworkManager.conf

    sed "/dns/d" -i "${ROOTFS_BUILD_DIR}"/etc/NetworkManager/NetworkManager.conf
    sed "s/\[main\]/\[main\]\ndns=default\nrc-manager=file/g" -i "${ROOTFS_BUILD_DIR}"/etc/NetworkManager/NetworkManager.conf
    if [[ -n $NM_IGNORE_DEVICES ]]; then
        mkdir -p "${ROOTFS_BUILD_DIR}"/etc/NetworkManager/conf.d/
        cat <<-EOF > "${ROOTFS_BUILD_DIR}"/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
[keyfile]
unmanaged-devices=$NM_IGNORE_DEVICES
EOF
    fi

    cat <<-EOF >> "${ROOTFS_BUILD_DIR}"/etc/skel/.bashrc
case \$(tty 2>/dev/null) in
        /dev/tty[A-z]*) [ -x /usr/bin/resize_tty ] && /usr/bin/resize_tty >/dev/null;;
esac
EOF

    if [ -h "${ROOTFS_BUILD_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service" ]; then
        rm "${ROOTFS_BUILD_DIR}/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"
    fi

    if [ -h "${ROOTFS_BUILD_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service" ]; then
        rm -f "${ROOTFS_BUILD_DIR}/etc/systemd/system/multi-user.target.wants/ondemand.service"
    fi

    date '+%Y-%m-%d %H:%M:%S' > "${ROOTFS_BUILD_DIR}"/etc/fake-hwclock.data

    if [ -e "${ROOTFS_BUILD_DIR}/etc/apt/apt.conf.d/20auto-upgrades" ]; then
        sed -i "s/Unattended-Upgrade \"1\"/Unattended-Upgrade \"0\"/" "${ROOTFS_BUILD_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
    fi

    if [ -e "${ROOTFS_BUILD_DIR}/etc/update-motd.d/91-release-upgrade" ]; then
        rm -f "${ROOTFS_BUILD_DIR}/etc/update-motd.d/91-release-upgrade"
    fi
    if [ -e "${ROOTFS_BUILD_DIR}/etc/update-manager/release-upgrades" ]; then
        sed -i "s/Prompt=lts/Prompt=never/" "${ROOTFS_BUILD_DIR}/etc/update-manager/release-upgrades"
    fi

    groups_list="audio gpio i2c video misc vps ipu jpu graphics weston-launch lightdm gdm render vpu kmem dialout disk"
    extra_groups="EXTRA_GROUPS=\"${groups_list}\""
    sed -i "/\<EXTRA_GROUPS\>=/ s/^.*/${extra_groups}/" "${ROOTFS_BUILD_DIR}/etc/adduser.conf"
    sed -i "/\<ADD_EXTRA_GROUPS\>=/ s/^.*/ADD_EXTRA_GROUPS=1/" "${ROOTFS_BUILD_DIR}/etc/adduser.conf"
    for group_name in ${groups_list}
    do
        chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "groupadd -rf ${group_name} || true"
    done

    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "(echo $ARMCNC_PASSWORD;echo $ARMCNC_PASSWORD;) | passwd root"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "useradd -U -m -d /home/${ARMCNC_USERNAME} -k /etc/skel/ -s /bin/bash -G sudo,${groups_list//' '/','} ${ARMCNC_USERNAME}"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "(echo ${ARMCNC_PASSWORD};echo ${ARMCNC_PASSWORD};) | passwd ${ARMCNC_USERNAME}"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "cp -aRf /etc/skel/. /root/"

    echo "Install hobot debs in /app/hobot_debs"
    mkdir -p "${ROOTFS_BUILD_DIR}"/app/hobot_debs
    [ -d "${HR_LOCAL_DIR}/deb_packages" ] && find "${HR_LOCAL_DIR}/deb_packages" -maxdepth 1 -type f -name '*.deb' -exec cp -f {} "${ROOTFS_BUILD_DIR}/app/hobot_debs" \;

    install_packages "${ROOTFS_BUILD_DIR}"
    rm -rf "${ROOTFS_BUILD_DIR}"/app/hobot_debs/
    rm -rf "${ROOTFS_BUILD_DIR}"/lib/aarch64-linux-gnu/dri/

    cat <<'EOF' > "${ROOTFS_BUILD_DIR}"/boot/boot.cmd
# Print boot source
echo "Boot script loaded from devtype:${devtype} devnum:${devnum} devplist:${devplist}"
imagefile="Image"
setenv bootargs "$bootargs root=/dev/mmcblk${devnum}p${devplist} rw rootwait ubi.mtd=2,2048 mtdparts=hr_nand.0:6291456@0x0(miniboot),2097152@0x600000(env),0x400000@0x800000(boot),0x400000@0xC00000(system) isolcpus=2,3"
echo bootargs = $bootargs
echo Loading fdt file: ${prefix}hobot/${fdtfile}
ext4load ${devtype} ${devnum}:${devplist} ${fdt_addr_r} ${prefix}hobot/${fdtfile}
echo Loading kernel: ${prefix}${imagefile}
ext4load ${devtype} ${devnum}:${devplist} ${kernel_addr_r} ${prefix}${imagefile}
booti ${kernel_addr_r} - ${fdt_addr_r}
# Recompile with:
# mkimage -C none -A arm -T script -d boot.cmd boot.scr
EOF
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "cd /boot && mkimage -C none -A arm -T script -d boot.cmd boot.scr"

    cat <<'EOF' > "${ROOTFS_BUILD_DIR}"/etc/set_mac_address.sh
#!/bin/bash
mac_file=/etc/network/mac_address

if [ -s ${mac_file} ] && [ -f ${mac_file} ]; then
    ifconfig eth0 down
    ifconfig eth0 hw ether $(cat ${mac_file})
    ifconfig eth0 up
else
    openssl rand -rand /dev/urandom:/sys/class/socinfo/soc_uid -hex 6 | sed -e 's/../&:/g;s/:$//' -e 's/^\(.\)[13579bdf]/\10/' > $mac_file
    ifconfig eth0 down
    ifconfig eth0 hw ether $(cat ${mac_file})
    ifconfig eth0 up
fi

if [ -e /etc/ethercat.conf ]; then
    systemctl restart ethercat.service
fi
EOF

    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "rm -rf /etc/apt/sources.list.d/*"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "apt install --reinstall tree libgl1-mesa-glx libgl1-mesa-dri xserver-xorg-core"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "apt update -y"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "apt upgrade -y"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "apt autoremove -y"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "apt clean"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "truncate -s 0 /var/log/*.log"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "rm -rf /tmp/*"
    chroot "${ROOTFS_BUILD_DIR}" /bin/bash -c "history -c && history -w"

    unmount_image "${IMG_FILE}"
    rm -f "${IMG_FILE}"

    ROOTFS_DIR=${IMAGE_DEPLOY_DIR}/rootfs_mount
    rm -rf "${ROOTFS_DIR}"
    mkdir -p "${ROOTFS_DIR}"

    CONFIG_SIZE="$((256 * 1024 * 1024))"
    ROOT_SIZE=$(du --apparent-size -s "${ROOTFS_BUILD_DIR}" --exclude var/cache/apt/archives --exclude boot/config --block-size=1 | cut -f 1)
    ALIGN="$((4 * 1024 * 1024))"
    ROOT_MARGIN="$(echo "($ROOT_SIZE * 0.2 + 200 * 1024 * 1024) / 1" | bc)"

    CONFIG_PART_START=$((ALIGN))
    CONFIG_PART_SIZE=$(((CONFIG_SIZE + ALIGN - 1) / ALIGN * ALIGN))
    ROOT_PART_START=$((CONFIG_PART_START + CONFIG_PART_SIZE))
    ROOT_PART_SIZE=$(((ROOT_SIZE + ROOT_MARGIN + ALIGN  - 1) / ALIGN * ALIGN))
    IMG_SIZE=$((CONFIG_PART_START + CONFIG_PART_SIZE + ROOT_PART_SIZE))

    truncate -s "${IMG_SIZE}" "${IMG_FILE}"

    cd "${HR_LOCAL_DIR}"
    parted --script "${IMG_FILE}" mklabel msdos
    parted --script "${IMG_FILE}" unit B mkpart primary fat32 "${CONFIG_PART_START}" "$((CONFIG_PART_START + CONFIG_PART_SIZE - 1))"
    parted --script "${IMG_FILE}" unit B mkpart primary ext4 "${ROOT_PART_START}" "$((ROOT_PART_START + ROOT_PART_SIZE - 1))"
    # 设置为启动分区
    parted "${IMG_FILE}" set 2 boot on

    echo "Creating loop device..."
    cnt=0
    until LOOP_DEV="$(losetup --show --find --partscan "$IMG_FILE")"; do
        if [ $cnt -lt 5 ]; then
            cnt=$((cnt + 1))
            echo "Error in losetup.  Retrying..."
            sleep 5
        else
            echo "ERROR: losetup failed; exiting"
            exit 1
        fi
    done

    CONFIG_DEV="${LOOP_DEV}p1"
    ROOT_DEV="${LOOP_DEV}p2"

    ROOT_FEATURES="^huge_file"
    for FEATURE in 64bit; do
        if grep -q "$FEATURE" /etc/mke2fs.conf; then
            ROOT_FEATURES="^$FEATURE,$ROOT_FEATURES"
        fi
    done

    mkdosfs -n CONFIG -F 32 -s 4 -v "$CONFIG_DEV" > /dev/null
    mkfs.ext4 -L rootfs -O "$ROOT_FEATURES" "$ROOT_DEV" > /dev/null

    mount -v "$ROOT_DEV" "${ROOTFS_DIR}" -t ext4
    mkdir -p "${ROOTFS_DIR}/boot/config"
    mount -v "$CONFIG_DEV" "${ROOTFS_DIR}/boot/config" -t vfat

    cd "${HR_LOCAL_DIR}"
    rsync -aHAXx --exclude /var/cache/apt/archives --exclude /boot/config "${ROOTFS_BUILD_DIR}/" "${ROOTFS_DIR}/"
    rsync -rtx "${HR_LOCAL_DIR}/config/" "${ROOTFS_DIR}/boot/config"
    sync
    unmount_image "${IMG_FILE}"
    rm -rf "${ROOTFS_DIR}"

    md5sum "${IMG_FILE}" > "${IMG_FILE}".md5sum

    echo "Make Debian Image successfully"
    echo "Image File: build/armcnc-debian-bookworm-arm64.img"
    echo "Packaging Image: xz ./build/armcnc-debian-bookworm-arm64.img"
    echo "Account：armcnc Password: armcnc"
    echo "Account：root Password: armcnc"
    exit 0
}

make_ubuntu_image