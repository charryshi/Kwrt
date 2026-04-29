#!/bin/bash

shopt -s extglob
SHELL_FOLDER=$(dirname $(readlink -f "$0"))

#bash $SHELL_FOLDER/../common/kernel_6.6.sh

sed -i -E -e 's/ ?root=\/dev\/fit0 rootwait//' -e "/rootdisk =/d" -e '/bootargs.* = ""/d' target/linux/mediatek/dts/*{qihoo-360t7,netcore-n60,h3c-magic-nx30-pro,jdcloud-re-cp-03,cmcc-rax3000m,jcg-q30-pro,tplink-tl-xdr*}.dts

find target/linux/mediatek/filogic/base-files/ -type f -exec sed -i "s/-stock//g" {} \;
find target/linux/mediatek/base-files/ -type f -exec sed -i "s/-stock//g" {} \;

sed -i "s/-stock//g" package/boot/uboot-envtools/files/mediatek_filogic

sed -i "s/openwrt-mediatek-filogic/kwrt-mediatek-filogic/g" target/linux/mediatek/image/filogic.mk
sed -i "s/ fitblk / /g" target/linux/mediatek/image/filogic.mk


# XR30 256M NAND layout (generated in diy.sh to avoid brittle patch hunks)
python3 - <<'PY2'
from pathlib import Path
import re
mk = Path('target/linux/mediatek/image/filogic.mk')
text = mk.read_text()
block = """TARGET_DEVICES += cmcc_rax3000m

define Device/cmcc_xr30
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 NAND
  DEVICE_DTS := mt7981b-cmcc-xr30
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += cmcc,xr30
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \
	e2fsprogs f2fsck mkf2fs
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 250000k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30
"""
if 'define Device/cmcc_xr30' in text:
    text = re.sub(r'TARGET_DEVICES \+= cmcc_rax3000m

define Device/cmcc_xr30
(?:.*
)*?TARGET_DEVICES \+= cmcc_xr30
', block, text, count=1)
else:
    text = text.replace('TARGET_DEVICES += cmcc_rax3000m
', block, 1)
mk.write_text(text)

dts = Path('target/linux/mediatek/dts/mt7981b-cmcc-xr30.dts')
if dts.exists():
    dt = dts.read_text()
    dt = dt.replace('reg = <0x580000 0x7200000>;', 'reg = <0x580000 0xfa80000>;')
    dts.write_text(dt)
PY2
