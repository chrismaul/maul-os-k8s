#!/bin/bash -ex

source /output/os-release

if egrep -q "BUILD_ID=[\"]?$BUILD_ID[\"]?" /host/usr/lib/os-release
then
  exit 0
fi

VG_NAME=${VG_NAME:-root}
HOST_ROOT=/host

SRC=/output/root.squashfs
SRC_VERITY=/output/root.verity
KERNEL=/output/kernel.efi

if ! [ -e /dev/root/maul-os-$BUILD_ID ]
then

  FILESIZE=$(stat --printf="%s" $SRC)
  HASH_SIZE=$(stat --printf="%s" $SRC_VERITY)

  lvcreate -Wy -y -n maul-os-$BUILD_ID -L ${FILESIZE}B $VG_NAME

  lvcreate -Wy -y -n maul-os-$BUILD_ID-verity -L ${HASH_SIZE}B $VG_NAME

  echo "Install version $BUILD_ID"

  dd if=$SRC of=/dev/$VG_NAME/maul-os-$BUILD_ID bs=4M

  dd if=$SRC_VERITY of=/dev/$VG_NAME/maul-os-$BUILD_ID-verity bs=4M

fi

if ! [ -e "$HOST_ROOT/boot/EFI" ]
then
  mkdir -p $HOST_ROOT/boot
  mount LABEL=BOOT $HOST_ROOT/boot
fi

cp -v $KERNEL $HOST_ROOT/boot/efi/Linux/maul-os-$BUILD_ID.efi

for MOD_LOC in /output/modules_*_squashfs
do
  MOD_VERS=$(echo $MOD_LOC | cut -d _ -f 2)
  if ! [ -e "/dev/root/modules-${BUILD_ID}-$MOD_VERS" ]
  then
    MOD_SIZE=$(stat --printf="%s" $MOD_LOC)
    MOD_HASH_SIZE=$(stat --printf="%s" /output/modules_${MOD_VERS}_verity)
    lvcreate -Wy -y -n modules-${BUILD_ID}-$MOD_VERS -L ${MOD_SIZE}B $VG_NAME
    lvcreate -Wy -y -n modules-${BUILD_ID}-${MOD_VERS}-verity -L ${MOD_HASH_SIZE}B $VG_NAME

    dd if=$MOD_LOC of=/dev/$VG_NAME/modules-${BUILD_ID}-$MOD_VERS bs=4M
    dd if=/output/modules_${MOD_VERS}_verity of=/dev/$VG_NAME/modules-${BUILD_ID}-${MOD_VERS}-verity bs=1M
  fi
done

if [ "$ACTIVATE" = "yes" ]
then
  if ! egrep -q "BUILD_ID=[\"]?$BUILD_ID[\"]?" /host/usr/lib/os-release
  then
    TMP_ROOT=$HOST_ROOT/tmp/activate
    if ! [ -e "/dev/mapper/root-$BUILD_ID" ]
    then
      echo "Verify Device"
      veritysetup open \
        /dev/$VG_NAME/maul-os-$BUILD_ID \
        root-$BUILD_ID \
        /dev/$VG_NAME/maul-os-$BUILD_ID-verity \
        $(cat /output/root.verity-info.txt | grep "Root hash:" | cut -f 2)
    fi
    mkdir -p $TMP_ROOT/{new,old}
    if grep -q " $TMP_ROOT/new " /proc/mounts
    then
      echo "Something already mounting exiting"
      exit 8
    fi
    mount /dev/mapper/root-$BUILD_ID $TMP_ROOT/new -o ro

    test -e $TMP_ROOT/new/usr

    mount -N /proc/1/ns/mnt --make-private /
    mount -N /proc/1/ns/mnt --move /usr /tmp/activate/old
    mount -N /proc/1/ns/mnt --bind /tmp/activate/new/usr /usr
    kill -SIGTERM 1
    sleep 10
    fuser -mvk -TERM /host/usr
    sleep 10
    while grep -q " /tmp/activate/old " /proc/1/mounts
    do
      umount -N /proc/1/ns/mnt /tmp/activate/old || true
      sleep 1
    done
    while grep -q " $TMP_ROOT/new " /proc/mounts
    do
      umount $TMP_ROOT/new || true
      sleep 1
    done
    umount /host/usr
    while [ -n "$(dmsetup table | grep "^root.* verity " | \
      cut -d ':' -f 1 | grep -v root-$BUILD_ID)" ] ;
    do
      dmsetup table | grep "^root.* verity " | \
        cut -d ':' -f 1 | grep -v root-$BUILD_ID | \
      xargs -n 1 veritysetup close || sleep 1
    done
    mount -N /proc/1/ns/mnt --make-shared /
  fi
fi
