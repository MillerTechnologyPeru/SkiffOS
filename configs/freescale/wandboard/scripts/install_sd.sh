#!/bin/bash

if [ $EUID != 0 ]; then
  echo "This script requires sudo, so it might not work."
fi

set -e
if [ -z "$WANDBOARD_SD" ]; then
  echo "Please set WANDBOARD_SD and try again."
  exit 1
fi

if [ ! -b "$WANDBOARD_SD" ]; then
  echo "$WANDBOARD_SD is not a block device or doesn't exist."
  exit 1
fi

WANDBOARD_SD_SFX=$WANDBOARD_SD
if [ -b ${WANDBOARD_SD}p1 ]; then
  WANDBOARD_SD_SFX=${WANDBOARD_SD}p
fi

IMAGES_DIR=${BUILDROOT_DIR}/images

if [ ! -f "$IMAGES_DIR/zImage" ]; then
  echo "zImage not found, make sure Buildroot is done compiling."
  exit 1
fi

mounts=()
outp_path="${BUILDROOT_DIR}/output"
MOUNTS_DIR=${outp_path}/mounts
mkdir -p ${MOUNTS_DIR}
WORK_DIR=`mktemp -d -p "${MOUNTS_DIR}"`

# deletes the temp directory
function cleanup {
sync || true
for mount in "${mounts[@]}"; do
  echo "Unmounting ${mount}..."
  sudo umount $mount || true
done
mounts=()
if [ -d "$WORK_DIR" ]; then
  rm -rf "$WORK_DIR" || true
fi
}
trap cleanup EXIT

mount_persist_dir="${WORK_DIR}/persist"
BOOT_DIR=${mount_persist_dir}/boot
ROOTFS_DIR=${mount_persist_dir}/rootfs
PERSIST_DIR=${mount_persist_dir}/

echo "Mounting ${WANDBOARD_SD_SFX}1 to $mount_persist_dir..."
mkdir -p $mount_persist_dir
mounts+=("$mount_persist_dir")
sudo mount ${WANDBOARD_SD_SFX}1 $mount_persist_dir

echo "Copying files..."

cd ${IMAGES_DIR}
mkdir -p ${BOOT_DIR}/skiff-init ${ROOTFS_DIR}/
if [ -d ${IMAGES_DIR}/rootfs_part/ ]; then
    rsync -rav ${IMAGES_DIR}/rootfs_part/ ${ROOTFS_DIR}/
fi
if [ -d ${IMAGES_DIR}/persist_part/ ]; then
    rsync -rav ${IMAGES_DIR}/persist_part/ ${PERSIST_DIR}/
fi
rsync -rv ./skiff-init/ ${BOOT_DIR}/skiff-init/
rsync -rv \
      ./*.dtb ./zImage \
      ./skiff-release ./rootfs.squashfs \
      ${BOOT_DIR}/

if [ -z "$DISABLE_CREATE_SWAPFILE" ]; then
    PERSIST_SWAP=${PERSIST_DIR}/primary.swap
    if [ ! -f ${PERSIST_SWAP} ]; then
        echo "Pre-allocating 2GB swapfile with zeros (ignoring errors)..."
        dd if=/dev/zero of=${PERSIST_SWAP} bs=1M count=2000 || true
    else
        echo "Swapfile already exists, skipping allocation step."
    fi
fi

mkdir -p ${BOOT_DIR}/extlinux
cp ${SKIFF_CURRENT_CONF_DIR}/resources/boot-scripts/extlinux.conf ${BOOT_DIR}/extlinux/extlinux.conf
cd -
