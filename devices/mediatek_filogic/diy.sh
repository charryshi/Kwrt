#!/bin/bash

set -e
shopt -s extglob
SHELL_FOLDER=$(dirname $(readlink -f "$0"))

# ===== 安全修改 DTS（避免文件不存在报错） =====
for f in target/linux/mediatek/dts/*{qihoo-360t7,netcore-n60,h3c-magic-nx30-pro,jdcloud-re-cp-03,cmcc-rax3000m,jcg-q30-pro,tplink-tl-xdr*}.dts; do
    [ -f "$f" ] && sed -i -E \
        -e 's/ ?root=\/dev\/fit0 rootwait//' \
        -e "/rootdisk =/d" \
        -e '/bootargs.* = ""/d' "$f"
done

# ===== 去掉 -stock 标识 =====
find target/linux/mediatek/filogic/base-files/ -type f -exec sed -i "s/-stock//g" {} \; 2>/dev/null || true
find target/linux/mediatek/base-files/ -type f -exec sed -i "s/-stock//g" {} \; 2>/dev/null || true
sed -i "s/-stock//g" package/boot/uboot-envtools/files/mediatek_filogic 2>/dev/null || true

# ===== 修改固件名称 =====
sed -i "s/openwrt-mediatek-filogic/kwrt-mediatek-filogic/g" target/linux/mediatek/image/filogic.mk
sed -i "s/ fitblk / /g" target/linux/mediatek/image/filogic.mk

# ===== 尝试切换 firewall3（注意：后面 defconfig 可能覆盖）=====
if [ -f .config ]; then
    sed -i 's/CONFIG_PACKAGE_firewall4=y/CONFIG_PACKAGE_firewall4=n/g' .config
    sed -i 's/CONFIG_PACKAGE_fw4=y/CONFIG_PACKAGE_fw4=n/g' .config
    sed -i 's/CONFIG_PACKAGE_nftables=y/CONFIG_PACKAGE_nftables=n/g' .config

    grep -q "CONFIG_PACKAGE_firewall3" .config || echo "CONFIG_PACKAGE_firewall3=y" >> .config
    grep -q "CONFIG_PACKAGE_iptables" .config || echo "CONFIG_PACKAGE_iptables=y" >> .config

    for pkg in kmod-ipt-core kmod-ipt-nat kmod-ipt-conntrack kmod-nf-reject kmod-nf-ipt kmod-nf-log; do
        grep -q "CONFIG_PACKAGE_$pkg" .config || echo "CONFIG_PACKAGE_$pkg=y" >> .config
    done

    # 避免 LuCI 拉回 fw4
    echo "CONFIG_PACKAGE_luci-compat=y" >> .config
fi

# ===== XR30 NAND layout patch（修复 Python 报错 + 提高稳定性）=====
python3 - <<'PY2'
from pathlib import Path
import re

mk = Path('target/linux/mediatek/image/filogic.mk')
if not mk.exists():
    exit(0)

text = mk.read_text()

block = """TARGET_DEVICES += cmcc_rax3000m

define Device/cmcc_xr30
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 NAND
  DEVICE_DTS := mt7981b-cmcc-xr30
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += cmcc,xr30
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \\
\te2fsprogs f2fsck mkf2fs
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
    pattern = r'''TARGET_DEVICES \+= cmcc_rax3000m

define Device/cmcc_xr30
(?:.|\n)*?TARGET_DEVICES \+= cmcc_xr30
'''
    text = re.sub(pattern, block, text, count=1, flags=re.S)
else:
    text = text.replace('TARGET_DEVICES += cmcc_rax3000m\n', block, 1)

mk.write_text(text)

# ===== 修改 DTS 分区 =====
dts = Path('target/linux/mediatek/dts/mt7981b-cmcc-xr30.dts')
if dts.exists():
    dt = dts.read_text()
    dt = dt.replace('reg = <0x580000 0x7200000>;', 'reg = <0x580000 0xfa80000>;')
    dts.write_text(dt)
PY2
