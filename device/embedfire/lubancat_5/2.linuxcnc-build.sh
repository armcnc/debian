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
sudo apt update && sudo apt install git build-essential dpkg-dev fakeroot

# Clone the LinuxCNC repository from GitHub and check out the v2.9.10 branch
git clone --branch v2.9.10 https://github.com/LinuxCNC/linuxcnc.git linuxcnc
# OR
git clone --branch v2.9.10 https://gh-proxy.com/https://github.com/LinuxCNC/linuxcnc.git linuxcnc
# OR
git clone --branch v2.9.10 https://ghclone.com/https://github.com/LinuxCNC/linuxcnc.git linuxcnc

# In the linuxcnc directory
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

# In the src directory of the linuxcnc repository
cd src

# Run the autogen.sh script to generate the configure script and prepare the build environment
./autogen.sh

# Configure the build environment for LinuxCNC with real-time support in user space
./configure --with-realtime=uspace

# Build LinuxCNC using 4 parallel jobs to speed up the compilation process
make -j6

# Set the setuid bit on the LinuxCNC binary to allow it to run with elevated privileges
sudo make setuid

# In the linuxcnc directory
cd ~/linuxcnc

# Source the rip-environment script to set up the environment variables for building the Debian package
source scripts/rip-environment

# CPU frequency scaling: Set the CPU governor to "performance" for CPUs 6 and 7 to ensure consistent performance during real-time operations
for cpu in 6 7; do
    echo performance | sudo tee /sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor
done

# Run the latency-histogram tool to measure and display the system's real-time latency characteristics
latency-histogram --base 125000 --servo 125000 --show --verbose

# Build the LinuxCNC Debian package for user space with no documentation
cd ~/linuxcnc/src

# Clean the build directory to remove any previous build artifacts
make clean

# In the linuxcnc directory
cd ~/linuxcnc

# Configure the Debian package build environment for LinuxCNC with user space and no documentation
./debian/configure uspace no-docs

# Check for build dependencies required for building the Debian package
dpkg-checkbuilddeps

# Build the LinuxCNC Debian package for user space with no documentation, using 6 parallel jobs to speed up the process
dpkg-buildpackage -b -us -uc -j6

# Divert the io binary to avoid conflicts with the io.rktoolkit binary provided by linuxcnc-uspace
sudo dpkg-divert --package linuxcnc-uspace \
  --add --rename \
  --divert /usr/bin/io.rktoolkit \
  /usr/bin/io

# Install the built LinuxCNC Debian packages for user space and development files
sudo apt install ./linuxcnc-uspace_2.9.10_arm64.deb ./linuxcnc-uspace-dev_2.9.10_arm64.deb