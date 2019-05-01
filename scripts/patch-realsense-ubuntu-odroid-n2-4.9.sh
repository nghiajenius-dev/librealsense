#!/bin/bash
#This script is used to apply kernel patch for Odroid N2 (bionic, kernel 4.9)

#Break execution on any error received
set -e

#Locally suppress stderr to avoid raising not relevant messages
exec 3>&2
exec 2> /dev/null
con_dev=$(ls /dev/video* | wc -l)
exec 2>&3

if [ $con_dev -ne 0 ];
then
	echo -e "\e[32m"
	read -p "Remove all RealSense cameras attached. Hit any key when ready"
	echo -e "\e[0m"
fi

#Include usability functions
source ./scripts/patch-utils.sh

# Get the required tools and headers to build the kernel
sudo apt-get install build-essential git

#Packages to build the patched modules
require_package libusb-1.0-0-dev
require_package libssl-dev
require_package libelf-dev
require_package elfutils

LINUX_BRANCH=$(uname -r)
PLATFORM=$(uname -n)

ubuntu_codename="bionic"
kernel_name="odroidn2_bionic"
kernel_branch="odroidn2-4.9.y"

# Get the hardkernel linux kernel
[ ! -d ${kernel_name} ] && git clone --depth 1 https://github.com/hardkernel/linux -b ${kernel_branch} ./${kernel_name}
cd ${kernel_name}

# Patching kernel source code
echo -e "\e[32mApplying realsense-uvc patch\e[0m"
patch -p1 < ../scripts/realsense-camera-formats_odroidn2-4.9.patch
echo -e "\e[32mApplying realsense-hid patch\e[0m"
patch -p1 < ../scripts/realsense-hid_odroidn2-4.9.patch
echo -e "\e[32mApplying realsense-metadata patch\e[0m"
patch -p1 < ../scripts/realsense-metadata_odroidn2-4.9.patch
echo -e "\e[32mApplying realsense-powerlinefrequency-fix patch\e[0m"
patch -p1 < ../scripts/realsense-powerlinefrequency-control_odroidn2-4.9.patch

# Copy stock kernel configuration to ${kernel_name}
sudo cp /lib/modules/$(uname -r)/build/.config .
sudo cp /lib/modules/$(uname -r)/build/Module.symvers .

# Patch config for IIO support
echo -e "\e[32mPatch kernel modules configuration\e[0m"
bash ./scripts/config --file .config \
	--set-str LOCALVERSION $LINUX_BRANCH \
        --module HID_SENSOR_IIO_COMMON \
        --module HID_SENSOR_ACCEL_3D \
	--module HID_SENSOR_GYRO_3D

# Use .config file
sudo make silentoldconfig modules_prepare

# Build the uvc, accel and gyro modules
KBASE=`pwd` # same as ${kernel_name}, KBASE: patched kernel base
cd drivers/media/usb/uvc
sudo cp $KBASE/Module.symvers .

echo -e "\e[32mCompiling uvc module\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/media/usb/uvc/ modules
echo -e "\e[32mCompiling accelerometer and gyro modules\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/iio/accel modules
sudo make -j -C $KBASE M=$KBASE/drivers/iio/gyro modules
echo -e "\e[32mCompiling v4l2-core modules\e[0m"
sudo make -j -C $KBASE M=$KBASE/drivers/media/v4l2-core modules

# Copy and load the patched modules
if [ -f $KBASE/drivers/media/usb/uvc/uvcvideo.ko ]; then
	echo "Copying uvcvideo.ko"
	sudo cp $KBASE/drivers/media/usb/uvc/uvcvideo.ko ~/$LINUX_BRANCH-uvcvideo.ko
	try_module_insert uvcvideo ~/$LINUX_BRANCH-uvcvideo.ko /lib/modules/`uname -r`/kernel/drivers/media/usb/uvc/uvcvideo.ko
fi

if [ -f $KBASE/drivers/iio/accel/hid-sensor-accel-3d.ko ]; then
	echo "Copying hid-sensor-accel-3d.ko" 
	sudo cp $KBASE/drivers/iio/accel/hid-sensor-accel-3d.ko ~/$LINUX_BRANCH-hid-sensor-accel-3d.ko
	try_module_insert hid_sensor_accel_3d ~/$LINUX_BRANCH-hid-sensor-accel-3d.ko /lib/modules/#`uname -r`/kernel/drivers/iio/accel/hid-sensor-accel-3d.ko
fi

if [ -f $KBASE/drivers/iio/gyro/hid-sensor-gyro-3d.ko ]; then
	echo "Copying hid-sensor-gyro-3d.ko"
	sudo cp $KBASE/drivers/iio/gyro/hid-sensor-gyro-3d.ko ~/$LINUX_BRANCH-hid-sensor-gyro-3d.ko
	try_module_insert hid_sensor_gyro_3d ~/$LINUX_BRANCH-hid-sensor-gyro-3d.ko /lib/modules/`uname -#r`/kernel/drivers/iio/gyro/hid-sensor-gyro-3d.ko
fi

if [ -f $KBASE/drivers/media/v4l2-core/videobuf-core.ko ]; then
	echo "Copying video drivers"
	sudo cp $KBASE/drivers/media/v4l2-core/videobuf-core.ko ~/$LINUX_BRANCH-videobuf-core.ko
	try_module_insert videobuf-core ~/$LINUX_BRANCH-videobuf-core.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/videobuf-core.ko

	sudo cp $KBASE/drivers/media/v4l2-core/videobuf-vmalloc.ko ~/$LINUX_BRANCH-videobuf-vmalloc.ko
	try_module_insert videobuf-vmalloc ~/$LINUX_BRANCH-videobuf-vmalloc.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/videobuf-vmalloc.ko

	sudo cp $KBASE/drivers/media/v4l2-core/videobuf-dvb.ko ~/$LINUX_BRANCH-videobuf-dvb.ko
	try_module_insert videobuf-dvb ~/$LINUX_BRANCH-videobuf-dvb.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/videobuf-dvb.ko

	sudo cp $KBASE/drivers/media/v4l2-core/videobuf2-vmalloc.ko ~/$LINUX_BRANCH-videobuf2-vmalloc.ko
	try_module_insert videobuf2-vmalloc ~/$LINUX_BRANCH-videobuf2-vmalloc.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/videobuf2-vmalloc.ko

	sudo cp $KBASE/drivers/media/v4l2-core/v4l2-fwnode.ko ~/$LINUX_BRANCH-v4l2-fwnode.ko
	try_module_insert v4l2-fwnode ~/$LINUX_BRANCH-v4l2-fwnode.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/v4l2-fwnode.ko

	sudo cp $KBASE/drivers/media/v4l2-core/tuner.ko ~/$LINUX_BRANCH-tuner.ko
	try_module_insert tuner ~/$LINUX_BRANCH-tuner.ko /lib/modules/`uname -r`/kernel/drivers/media/v4l2-core/tuner.ko
fi
echo -e "\e[32mPatched kernels modules were created successfully\n\e[0m"

echo -e "\e[92m\n\e[1mScript has completed. Please consult the installation guide for further instruction.\n\e[0m"
