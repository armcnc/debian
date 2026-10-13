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

cat <<'BANNER'
     _      ____    __  __    ____   _   _    ____
    / \    |  _ \  |  \/  |  / ___| | \ | |  / ___|
   / _ \   | |_) | | |\/| | | |     |  \| | | |
  / ___ \  |  _ <  | |  | | | |___  | |\  | | |___
 /_/   \_\ |_| \_\ |_|  |_|  \____| |_| \_|  \____|

BANNER

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