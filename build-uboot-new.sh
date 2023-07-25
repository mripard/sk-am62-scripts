#!/bin/bash

AARCH32_CROSS_COMPILE=arm-linux-gnu-
AARCH64_CROSS_COMPILE=aarch64-linux-gnu-

ATF_RELEASE="v2.9.0"
FIRMWARE_RELEASE="09.00.00.005"
OPTEE_RELEASE="3.22.0"
UBOOT_RELEASE="v2023.07-rc6"

DFU=$(which dfu-util)
if [ -z ${DFU} ]; then
	echo "dfu-util not found"
	exit 1
fi

BASE_DIR=$(realpath $1)
if [ ! -d ${BASE_DIR} ]; then
	echo "Base Directory doesn't exist"
	exit 1
fi

ATF_DIR=${BASE_DIR}/trusted-firmware-a
if [ ! -d ${ATF_DIR} ]; then
	echo "ATF Directory doesn't exist"
	exit 1
fi

git -C ${ATF_DIR} checkout ${ATF_RELEASE}

OPTEE_DIR=${BASE_DIR}/optee_os
if [ ! -d ${OPTEE_DIR} ]; then
	echo "Optee Directory doesn't exist"
	exit 1
fi

git -C ${OPTEE_DIR} checkout ${OPTEE_RELEASE}

UBOOT_DIR=${BASE_DIR}/u-boot
if [ ! -d ${UBOOT_DIR} ]; then
	echo "U-Boot Directory doesn't exist"
	exit 1
fi

# git -C ${UBOOT_DIR} checkout ${UBOOT_RELEASE}

FIRMWARE_DIR=${BASE_DIR}/ti-linux-firmware
if [ ! -d ${FIRMWARE_DIR} ]; then
	echo "Firmware Directory doesn't exist"
	exit 1
fi

git -C ${FIRMWARE_DIR} checkout ${FIRMWARE_RELEASE}

cd ${ATF_DIR}

make \
    CROSS_COMPILE=${AARCH64_CROSS_COMPILE} \
    ARCH=aarch64 \
    PLAT=k3 \
    TARGET_BOARD=lite \
    SPD=opteed \
    -j $(nproc)

cd ${OPTEE_DIR}

make \
    PLATFORM=k3 \
    CFG_ARM64_core=y \
    CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
    CROSS_COMPILE64=${AARCH64_CROSS_COMPILE} \
    -j $(nproc)

cd ${UBOOT_DIR}

BUILD_DIR_R5=${UBOOT_DIR}/build/r5
BUILD_DIR_A53=${UBOOT_DIR}/build/a53

rm -rf ${UBOOT_DIR}/build

make \
    ARCH=arm \
    CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
    O=${BUILD_DIR_R5} \
    am62x_evm_r5_defconfig

make \
    ARCH=arm \
    CROSS_COMPILE=${AARCH32_CROSS_COMPILE} \
    BINMAN_INDIRS=${FIRMWARE_DIR} \
    O=${BUILD_DIR_R5} \
    -j $(nproc)

make \
    ARCH=arm \
    CROSS_COMPILE=${AARCH64_CROSS_COMPILE} \
    O=${BUILD_DIR_A53} \
    am62x_evm_a53_defconfig

make \
    ARCH=arm \
    CROSS_COMPILE=${AARCH64_CROSS_COMPILE} \
    BINMAN_INDIRS=${FIRMWARE_DIR} \
    BL31=${ATF_DIR}/build/k3/lite/release/bl31.bin \
    TEE=${OPTEE_DIR}/out/arm-plat-k3/core/tee-raw.bin \
    O=${BUILD_DIR_A53} \
    -j $(nproc)

TIBOOT3_BIN=${BUILD_DIR_R5}/tiboot3.bin
if [ ! -f ${TIBOOT3_BIN} ]; then
	echo "tiboot3.bin Binary doesn't exist"
	exit 1
fi

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

# sudo ${DFU} -R -a bootloader -D ${TIBOOT3_BIN}
# sudo ${DFU} -w -R -a tispl.bin -D ${TISPL_BIN}
# sudo ${DFU} -w -R -a u-boot.img -D ${UBOOT_BIN}
