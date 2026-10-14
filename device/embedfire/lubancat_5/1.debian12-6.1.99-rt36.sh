#!/bin/bash

# Copyright 2026 ARMCNC, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit immediately if a command exits with a non-zero status.
set -e && lsb_release -a

# Get the system's architecture
architecture=$(dpkg --print-architecture)

# Get the system's code name
code_name=$(lsb_release -c -s)

# Switch to the home directory
cd ~

# Get the current directory of the script
current_dir=$(cd "$(dirname "$0")" && pwd)

# Install necessary packages for adding repositories and keys
sudo apt install curl gnupg ca-certificates
curl -fsSL https://Embedfire.github.io/keyfile -o /tmp/embedfire-keyfile
sudo install -d -m 0755 /etc/apt/keyrings
sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/embedfire.gpg /tmp/embedfire-keyfile
sudo chmod 0644 /etc/apt/keyrings/embedfire.gpg

# Update the package list and install necessary packages
sudo apt -y update && sudo apt -y upgrade

# Configure the system locale to en_US.UTF-8
sudo sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
sudo update-locale --reset LANG=en_US.UTF-8 LANGUAGE=en_US:en

# Reboot the system to apply changes
sudo reboot

# Add a new user 'tempadmin' and add it to the sudo group
sudo adduser tempadmin
sudo usermod -aG sudo tempadmin

# Reboot the system to apply changes and use the new user login
sudo reboot

# Backup critical system files before renaming the user 'cat' to 'debian'
sudo mkdir -p /root/cat-rename-backup
sudo cp -a /etc/passwd /etc/shadow /etc/group /etc/gshadow /etc/gdm3/daemon.conf /root/cat-rename-backup/

# Stop the GDM3 service and terminate the user session for 'cat'
sudo systemctl stop gdm3
sudo loginctl terminate-user cat

# Check if the user 'cat' is still running any processes
pgrep -a -u 1000

# Check if the user 'debian' already exists
getent passwd debian
getent group debian
ls -ld /home/debian

# Rename the user 'cat' to 'debian' and update the home directory and comment
sudo usermod -l debian cat
sudo groupmod -n debian cat
sudo usermod -d /home/debian -m debian
sudo usermod -c debian debian

# Update the GDM3 configuration to set the automatic login user to 'debian'
sudo sed -i -E 's/^([[:space:]]*AutomaticLogin[[:space:]]*=[[:space:]]*)cat[[:space:]]*$/\1debian/' /etc/gdm3/daemon.conf

# Update the hostname from 'lubancat' to 'armcnc'
sudo sed -i 's/^lubancat$/armcnc/' /etc/hostname

# Update the /etc/hosts file to reflect the new hostname
sudo sed -i "s/\blubancat\b/armcnc/g" /etc/hosts

# Update the SSH configuration to set ClientAliveInterval and ClientAliveCountMax
sudo sed -i -e 's/^[[:space:]#]*ClientAliveInterval[[:space:]].*/ClientAliveInterval 60/' -e 's/^[[:space:]#]*ClientAliveCountMax[[:space:]].*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl reload ssh

# Change the password for the 'debian' user to 'debian'
echo "debian:debian" | sudo chpasswd

# Remove the temporary admin user 'tempadmin
sudo deluser --remove-home tempadmin

# Clean up the backup directory after confirming the changes
sudo ls -la /root/cat-rename-backup
sudo rm -r -- /root/cat-rename-backup

# Reboot the system to apply changes and use the debian user login
sudo reboot

# Update the message of the day (MOTD) to display a custom welcome message
sudo tee /etc/update-motd.d/00-header > /dev/null <<'EOF'
#!/bin/sh

[ -r /etc/lsb-release ] && . /etc/lsb-release

printf '\n\033[90m'
cat <<'BANNER'
     _      ____    __  __    ____   _   _    ____
    / \    |  _ \  |  \/  |  / ___| | \ | |  / ___|
   / _ \   | |_) | | |\/| | | |     |  \| | | |
  / ___ \  |  _ <  | |  | | | |___  | |\  | | |___
 /_/   \_\ |_| \_\ |_|  |_|  \____| |_| \_|  \____|

BANNER
printf '\033[0m\n'

if [ -z "$DISTRIB_DESCRIPTION" ] && [ -x /usr/bin/lsb_release ]; then
    DISTRIB_DESCRIPTION=$(lsb_release -s -d)
fi

printf 'Welcome to %s (%s %s %s)\n\n' \
    "${DISTRIB_DESCRIPTION:-Debian GNU/Linux}" \
    "$(uname -o)" "$(uname -r)" "$(uname -m)"
EOF

# Update the message of the day (MOTD) to display help text with documentation and management links
sudo tee /etc/update-motd.d/10-help-text > /dev/null <<'EOF'
#!/bin/bash
#
#    10-help-text - print the help text associated with the distro

#printf "\n"
printf " * Documentation:  http://doc.armcnc.org\n"
printf " * Management:     http://www.armcnc.org\n"

if [ -e /boot/boot_init ];then
    source /etc/init.d/boot_init.sh > /dev/null 2>&1
    #echo " * Board Name:     "$BOARD_NAME
    #echo " * Device-tree:    "$BOARD_DTB
fi

#if [ -e /etc/build-release ];then
#    cat /etc/build-release
#fi
printf "\n"
EOF

# Reboot the system to apply changes and use the debian user login
sudo reboot

# Remove the custom kernel packages installed earlier
sudo apt remove linux-headers-6.1.99-rk3588 linux-image-6.1.99-rk3588

# Install the new real-time kernel packages
sudo dpkg -i linux-image-6.1.99-rt36-rk3588_6.1.99-rt36-rk3588-9_arm64.deb linux-headers-6.1.99-rt36-rk3588_6.1.99-rt36-rk3588-9_arm64.deb

# Create the directory ~/.armcnc if it does not exist
sudo mkdir -p ~/.armcnc

# Save the MAC addresses of all network interfaces to ~/.armcnc/mac-addresses
ifconfig -a | awk '
/^[^[:space:]]/ { iface=$1; sub(/:$/, "", iface) }
$1 == "ether" { print iface, $2 }
' | sudo tee ~/.armcnc/mac-addresses

# Extract the MAC address of the eth0 interface from ~/.armcnc/mac-addresses and store it in the variable mac_addresses
mac_addresses=$(awk '$1 == "eth0" { print $2; exit }' ~/.armcnc/mac-addresses)
echo "$mac_addresses"

# Update the kernel boot parameters in /boot/uEnv/uEnvLubanCat5-V2.txt to isolate CPU cores 6 and 7 for real-time tasks
sudo sed -i -e 's/isolcpus=7\b/isolcpus=6,7/g' -e 's/nohz_full=7\b/nohz_full=6,7/g' -e 's/rcu_nocbs=7\b/rcu_nocbs=6,7/g' /boot/uEnv/uEnvLubanCat5-V2.txt
grep '^cmdline=' /boot/uEnv/uEnvLubanCat5-V2.txt

# Reboot the system to apply changes and use the debian user login
sudo reboot

# Save the MAC addresses of all network interfaces to ~/.armcnc/mac-addresses, including EtherCAT interfaces if present
{
    for dev in /sys/class/net/*; do
        [ -r "$dev/type" ] || continue
        [ "$(cat "$dev/type")" = "1" ] || continue
        printf '%s %s\n' "${dev##*/}" "$(cat "$dev/address")"
    done

    if command -v ethercat >/dev/null 2>&1; then
        sudo ethercat master 2>/dev/null | awk '
            $1 == "Main:" || $1 == "Backup:" {
                if ($2 ~ /^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$/)
                    print "ethercat", tolower($2)
            }
        '
    fi

    for node in /proc/device-tree/ethernet@*; do
        [ -r "$node/compatible" ] || continue
        tr '\0' '\n' < "$node/compatible" | grep -q ethercat || continue

        for prop in mac-address local-mac-address; do
            [ -r "$node/$prop" ] || continue

            mac=$(od -An -v -tx1 "$node/$prop" | awk '
                {
                    for (i = 1; i <= NF; i++) bytes[++n] = $i
                }
                END {
                    if (n == 6)
                        printf "%s:%s:%s:%s:%s:%s",
                            bytes[1], bytes[2], bytes[3],
                            bytes[4], bytes[5], bytes[6]
                }
            ')

            case "$mac" in
                ""|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff) continue ;;
            esac

            printf 'ethercat %s\n' "$mac"
            break
        done
    done
} | awk '!seen[tolower($2)]++' | sudo tee ~/.armcnc/mac-addresses

# Extract the MAC address of the EtherCAT interface from ~/.armcnc/mac-addresses and store it in the variable ethercat_mac_addresses
ethercat_mac_addresses=$(awk '$1 == "ethercat" { print $2; exit }' ~/.armcnc/mac-addresses)
echo "$ethercat_mac_addresses"

# Get the process ID of the gnome-shell process for the current user and store it in the variable shell_pid
shell_pid=$(pgrep -u "$(id -u)" -x gnome-shell | head -n 1)

# Get the DBUS_SESSION_BUS_ADDRESS environment variable for the current shell process and store it in the variable desktop_bus
desktop_bus=$(sudo cat "/proc/$shell_pid/environ" \
    | tr '\0' '\n' \
    | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')

# Export the DBUS_SESSION_BUS_ADDRESS environment variable for the current shell process to ensure that GUI applications can communicate with the D-Bus session bus
export DBUS_SESSION_BUS_ADDRESS="$desktop_bus"

# Create the directory ~/.local/share/gnome-shell/extensions/no-overview@armcnc if it does not exist
mkdir -p ~/.local/share/gnome-shell/extensions/no-overview@armcnc

# Create the metadata.json file for the no-overview@armcnc GNOME Shell extension to disable the overview at login
cat > ~/.local/share/gnome-shell/extensions/no-overview@armcnc/metadata.json <<'EOF'
{
  "uuid": "no-overview@armcnc",
  "name": "Start on Desktop",
  "description": "Disable the overview at login",
  "shell-version": ["43"],
  "version": 1
}
EOF

# Create the extension.js file for the no-overview@armcnc GNOME Shell extension to implement the functionality of disabling the overview at login
cat > ~/.local/share/gnome-shell/extensions/no-overview@armcnc/extension.js <<'EOF'
const Main = imports.ui.main;
const GLib = imports.gi.GLib;

let startupId = 0;
let timeoutId = 0;
let previousValue;

function init() {}

function hideOverview() {
    timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
        Main.overview.hide();
        timeoutId = 0;
        return GLib.SOURCE_REMOVE;
    });
}

function enable() {
    previousValue = Main.layoutManager.startInOverview;
    Main.layoutManager.startInOverview = false;

    if (Main.layoutManager._startingUp) {
        startupId = Main.layoutManager.connect('startup-complete', () => {
            Main.layoutManager.disconnect(startupId);
            startupId = 0;
            hideOverview();
        });
    } else {
        hideOverview();
    }
}

function disable() {
    if (startupId) {
        Main.layoutManager.disconnect(startupId);
        startupId = 0;
    }
    if (timeoutId) {
        GLib.source_remove(timeoutId);
        timeoutId = 0;
    }
    Main.layoutManager.startInOverview = previousValue;
}
EOF

# Enable the no-overview@armcnc GNOME Shell extension to disable the overview at login
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['no-overview@armcnc']"

# Clear the command history and remove the .bash_history file for security purposes, then exit the script
history -c && history -w && rm -rf .bash_history && exit
# OR
history -c && history -w && rm -rf .bash_history && sudo reboot