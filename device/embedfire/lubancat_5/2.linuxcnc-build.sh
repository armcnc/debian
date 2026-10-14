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

# Update the package list and install necessary packages
sudo apt update && sudo apt install git build-essential dpkg-dev

# Clone the LinuxCNC repository from GitHub and check out the v2.9.10 branch
git clone --branch v2.9.10 https://github.com/LinuxCNC/linuxcnc.git linuxcnc
# OR
git clone --branch v2.9.10 https://gh-proxy.com/https://github.com/LinuxCNC/linuxcnc.git linuxcnc
# OR
git clone --branch v2.9.10 https://ghclone.com/https://github.com/LinuxCNC/linuxcnc.git linuxcnc

# Build LinuxCNC from source
cd linuxcnc

# Backup the current commit hash to a file for reference
git rev-parse HEAD | tee ../source-commit.txt

# Configure the build environment for LinuxCNC
./debian/configure uspace

# Unhold the xserver-common package to allow installation of xvfb and xserver-common
sudo apt-mark unhold xserver-common
sudo apt-get install xvfb xserver-common
sudo apt-mark hold xserver-common

# Install build dependencies for LinuxCNC
sudo apt-get build-dep .