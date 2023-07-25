# Build a Fedora Rawhide image for the TI SK-AM62

## Download a Fedora Rawhide image

```bash
$ FEDORA_VER=$(curl -s -o - https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/COMPOSE_ID | sed 's/Fedora-Rawhide/Fedora-Minimal-Rawhide/')
$ curl -O https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Spins/aarch64/images/${FEDORA_VER}.aarch64.raw.xz
```

## Flash that image using arm-image-installer

```bash
$ sudo arm-image-installer \
	--image=${FEDORA_VER}.aarch64.raw.xz \
	--media=${SDCARD_DEVICE} \
	--target=none \
	--addconsole \
	--resizefs
```

## Reformat the bootloader partition

```bash
$ PARTITION=${SDCARD_DEVICE}1
$ udisksctl mount --block-device ${PARTITION}
$ MOUNT_POINT=$(udisksctl info -b ${PARTITION} | grep MountPoints | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')
$ UUID=$(udisksctl info -b /dev/sde1 | grep IdUUID | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//' | sed 's/-//')
$ TMP_DIR=$(mktemp -d)
$ cp -a ${MOUNT_POINT}/EFI ${TMP_DIR}/
$ udisksctl unmount --block-device ${PARTITION}
$ (
	echo t
	echo 1
	echo c
	echo w
  ) | sudo fdisk ${SDCARD_DEVICE}
$ sudo mkfs.vfat -i ${UUID} -F 32 ${PARTITION}
$ udisksctl mount --block-device ${PARTITION}
$ cp -a ${TMP_DIR}/EFI ${MOUNT_POINT}/
```

## Compile Upstream U-Boot

```bash
git clone https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git/
git clone https://github.com/OP-TEE/optee_os.git
git clone https://github.com/mripard/u-boot.git -b v2023.07-sk-am62
git clone git://git.ti.com/processor-firmware/ti-linux-firmware.git

./build-uboot-new.sh .
cp u-boot/build/r5/tiboot3-am62x-gp-evm.bin ${MOUNT_POINT}/tiboot3.bin
cp u-boot/build/a53/tispl.bin u-boot/build/a53/u-boot.img ${MOUNT_POINT}/
```

You can now boot the board.

## Install development kernel

Once the board has booted and you created the user, you can add the
current dev kernel on the board:

```
$ sudo dnf copr enable eballetbo/automotive fedora-rawhide-aarch64
$ sudo dnf install kernel-6.5.0-0.rc2.20230720gitbfa3037d8280.319.fc39
```
