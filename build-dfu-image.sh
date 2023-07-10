#!/bin/bash

DEVICE="am62x"
TI_SYSFW_NAME="ti-fs-firmware-am62x-gp.bin"

SYSFW_RELEASE="09.00.00.001"
UBOOT_RELEASE="08.06.00.007"

UBOOT_R5_DEFCONFIG="${DEVICE}_evm_r5_usbdfu_defconfig"
UBOOT_A53_DEFCONFIG="${DEVICE}_evm_a53_defconfig"

DFU=$(which dfu-util)
if [ -z ${DFU} ]; then
	echo "dfu-util not found"
	exit 1
fi

SDK_DIR=$(realpath $1)
if [ ! -d ${SDK_DIR} ]; then
	echo "SDK Directory doesn't exist"
	exit 1
fi

export PATH=${PATH}:${SDK_DIR}/linux-devkit/sysroots/x86_64-arago-linux/usr/bin

AARCH32_CROSS_COMPILE=arm-none-linux-gnueabihf-
AARCH64_CROSS_COMPILE=aarch64-none-linux-gnu-

PREBUILT_DIR=${SDK_DIR}/board-support/prebuilt-images
if [ ! -d ${PREBUILT_DIR} ]; then
	echo "Prebuilt images Directory doesn't exist"
	exit 1
fi

ATF_BIN=${PREBUILT_DIR}/bl31.bin
if [ ! -f ${ATF_BIN} ]; then
	echo "Prebuilt ATF image missing"
	exit 1
fi

TEE_BIN=${PREBUILT_DIR}/bl32.bin
if [ ! -f ${TEE_BIN} ]; then
	echo "Prebuilt TEE image missing"
	exit 1
fi

DM_BIN=${PREBUILT_DIR}/ipc_echo_testb_mcu1_0_release_strip.xer5f
if [ ! -f ${DM_BIN} ]; then
	echo "Prebuilt DM image missing"
	exit 1
fi

TI_SYSFW_BIN=${PREBUILT_DIR}/${TI_SYSFW_NAME}
if [ ! -f ${TI_SYSFW_BIN} ]; then
	echo "Prebuilt sysfw image missing"
	exit 1
fi

UBOOT_DIR=$(ls -d ${SDK_DIR}/board-support/u-boot-*)
if [ ! -d ${UBOOT_DIR} ]; then
	echo "U-Boot Directory doesn't exist"
	exit 1
fi

git -C ${UBOOT_DIR} checkout ${UBOOT_RELEASE}

# This patch is needed for DFU to work
# See https://software-dl.ti.com/processor-sdk-linux/esd/AM62X/08_06_00_42/exports/docs/devices/AM62X/linux/Release_Specific_Workarounds.html#usb-device-firmware-upgrade-dfu-boot-fix
git -C ${UBOOT_DIR} cherry-pick	28c75c2713


SYSFW_DIR=$(ls -d ${SDK_DIR}/board-support/k3-image-gen-*)
if [ ! -d ${SYSFW_DIR} ]; then
	echo "K3 image gen directory doesn't exist"
	exit 1
fi

git -C ${SYSFW_DIR} checkout ${SYSFW_RELEASE}

cd ${UBOOT_DIR}

BUILD_DIR_R5=${UBOOT_DIR}/build/r5

echo "Compiling U-Boot"

rm -rf ${BUILD_DIR_R5}

make \
	ARCH=arm \
	CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
	O=${BUILD_DIR_R5} \
	${UBOOT_R5_DEFCONFIG} > /dev/null

make \
	ARCH=arm \
	CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
	O=${BUILD_DIR_R5} \
	-j $(nproc) > /dev/null

cd ${SYSFW_DIR}

echo "Compiling tiboot3.bin"

make \
	ARCH=arm \
	CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
	SOC=${DEVICE} \
	SBL=${BUILD_DIR_R5}/spl/u-boot-spl.bin \
	-j $(nproc) > /dev/null

TIBOOT3_BIN="${SYSFW_DIR}/tiboot3.bin"
if [ ! -f ${TIBOOT3_BIN} ]; then
	echo "tiboot3.bin Binary doesn't exist"
	exit 1
fi

cd ${UBOOT_DIR}

BUILD_DIR_A53=${UBOOT_DIR}/build/a53

export ARCH=arm
export CROSS_COMPILE=aarch64-none-linux-gnu-

rm -rf ${BUILD_DIR_A53}

make \
	ARCH=arm \
	CROSS_COMPILE=${AARCH64_CROSS_COMPILE} \
	O=${BUILD_DIR_A53} \
	${UBOOT_A53_DEFCONFIG} > /dev/null

make \
    ARCH=arm \
    CROSS_COMPILE=${AARCH64_CROSS_COMPILE} \
    ATF=${ATF_BIN} \
    TEE=${TEE_BIN} \
    DM=${DM_BIN} \
    O=${BUILD_DIR_A53} \
	-j $(nproc) > /dev/null

TISPL_BIN=${BUILD_DIR_A53}/tispl.bin
if [ ! -f ${TISPL_BIN} ]; then
	echo "SPL Binary doesn't exist"
	exit 1
fi

UBOOT_BIN=${BUILD_DIR_A53}/u-boot.img
if [ ! -f ${UBOOT_BIN} ]; then
	echo "U-Boot Binary doesn't exist"
	exit 1
fi

echo "Built tiboot3.bin: ${TIBOOT3_BIN}"
echo "Built tispl.bin: ${TISPL_BIN}"
echo "Built u-boot.img: ${UBOOT_BIN}"

sudo ${DFU} -R -a bootloader -D ${TIBOOT3_BIN}
sudo ${DFU} -w -R -a tispl.bin -D ${TISPL_BIN}
sudo ${DFU} -w -R -a u-boot.img -D ${UBOOT_BIN}
