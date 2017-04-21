#!/bin/bash

set -e

readonly EXTENSIONS=(bash dialog gnupg)

readonly MIRROR_URL=http://tinycorelinux.net/8.x/x86
readonly DIST=./dist
readonly BUILD=./build
readonly DOWNLOADS=./downloads
readonly ISOFILE=Core-current.iso

main() {
  prepare
  explode_iso
  download_extensions
  unpack_extensions
  customize
  repack_core
  remaster_iso
  calculate_checksum
}

prepare() {
  rm -rf $DIST
  rm -rf $BUILD
  mkdir -p $DIST
  mkdir -p $BUILD

  [[ ! -d "$DOWNLOADS" ]] && mkdir -p $DOWNLOADS

  return 0
}

download() {
  local url=$1
  local file=$DOWNLOADS/${url##*/}

  if [[ ! -f "$file" ]]; then
    echo "Downloading $url"
    wget -q -P $DOWNLOADS $url
  fi
}

download_tcz() {
  local tcz=$1
  local baseurl="$MIRROR_URL/tcz"
  local extension="$baseurl/$tcz"

  download "$extension"
  download "$extension.dep" || true

  if [[ -f "$DOWNLOADS/$tcz.dep" ]]; then
    for dep in $(cat $DOWNLOADS/$tcz.dep)
    do
      download_tcz $dep
    done
  fi
  echo "Finished downloading"
}

explode_iso() {
  local url=$MIRROR_URL/release/$ISOFILE
  local iso=$DOWNLOADS/${url##*/}
  local source=tmp

  download $url

  [[ ! -d "$source" ]] && mkdir -p $source

  mount $iso $source -o loop,ro
  cp -a $source/boot $DIST
  zcat $DIST/boot/core.gz | (cd $BUILD && cpio -i -H newc -d)
  umount $source
}

download_extensions() {
  for extension in "${EXTENSIONS[@]}"
  do
    download_tcz "$extension.tcz"
  done
}

unpack_extensions() {
  for extension in $DOWNLOADS/*.tcz
  do
    echo "Unpacking $extension"
    unsquashfs -f -d $BUILD $extension
  done
}

repack_core() {
  ldconfig -r $BUILD
  (cd $BUILD && find | cpio -o -H newc | gzip -2 > ../core.gz)
  advdef -z4 core.gz
}

remaster_iso() {
  mv core.gz $DIST/boot
  mkisofs -l -J -R -V TC-custom -no-emul-boot -boot-load-size 4 \
    -boot-info-table -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat -o tinycore-packer.iso $DIST
}

calculate_checksum() {
  local md5=($(md5sum tinycore-packer.iso))

  echo "Remastering done. The md5 checksum of the new iso is: ${md5}"
}

customize() {
  echo "adding gpgtools"
  cp gpg-tools.sh ${BUILD}/usr/local/bin/
  echo "eval \$(gpg-agent --daemon)" >> ${BUILD}/etc/profile
  #  echo "gpg-tools.sh &" >> $BUILD/opt/bootlocal.sh
}

main
