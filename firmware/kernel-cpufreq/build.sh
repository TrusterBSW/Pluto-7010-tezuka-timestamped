#!/bin/bash
# Noyau Tezuka fishball v0.3.24 (ADI linux bf1d49f + patchs Tezuka, config de la carte) + cpufreq.
# Produit : uImage (LZMA, comme Tezuka) + modules (dont maia-sdr.ko 0.12.0 patché Tezuka).
#
# Prérequis (Ubuntu 22.04) : build-essential bc bison flex libssl-dev u-boot-tools lzma kmod git wget
# Entrée : board.config = /proc/config.gz de la carte (zcat), à côté de ce script.
set -euo pipefail
cd "$(dirname "$0")"
W=$PWD/work; mkdir -p "$W"; cd "$W"

TC_NAME=armv7-eabihf--glibc--bleeding-edge-2025.08-1      # gcc 15.1, identique à Tezuka
[ -d $TC_NAME ] || { wget -q https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/$TC_NAME.tar.xz; tar xJf $TC_NAME.tar.xz; rm $TC_NAME.tar.xz; }
X="ARCH=arm CROSS_COMPILE=$W/$TC_NAME/bin/arm-linux-"

[ -d tezuka_fw ] || { git clone -q https://github.com/F5OEO/tezuka_fw.git; git -C tezuka_fw checkout -q v0.3.24; }

if [ ! -d linux ]; then
  wget -q -O adi.tar.gz https://github.com/analogdevicesinc/linux/archive/bf1d49f17fa9e15bc40be2615ef67cdf023f660a.tar.gz
  tar xzf adi.tar.gz && mv linux-bf1d49f* linux && rm adi.tar.gz
  for p in $(LC_ALL=C ls tezuka_fw/board/tezuka/common/patches/linux/adi-6.12.y/*.patch); do
    patch -d linux -p1 -N -s < "$p"; done
fi

cd linux
cp ../../board.config .config
while read -r l; do scripts/config --set-val "${l%%=*}" "${l#*=}"; done < <(grep '^CONFIG_' ../../cpufreq.config | sed 's/^CONFIG_//')
make $X olddefconfig >/dev/null
echo "kernelrelease : $(make -s $X kernelrelease)   (doit être 6.12.77)"
make -j"$(nproc)" $X Image modules
rm -rf ../mod && make $X INSTALL_MOD_PATH=../mod modules_install >/dev/null
lzma -9 -k -c arch/arm/boot/Image > ../Image.lzma
mkimage -A arm -O linux -T kernel -C lzma -a 0x8000 -e 0x8000 -n "Linux kernel" -d ../Image.lzma ../uImage >/dev/null
cd ..

# Module Maia (dépend du noyau : CONFIG_MODVERSIONS)
[ -f maia-sdr-0.12.0.tar.gz ] || wget -q -O maia-sdr-0.12.0.tar.gz https://github.com/maia-sdr/maia-sdr/archive/refs/tags/v0.12.0.tar.gz
rm -rf maia-sdr-0.12.0 && tar xzf maia-sdr-0.12.0.tar.gz
for p in $(LC_ALL=C ls tezuka_fw/package/maia-kmod/*.patch); do patch -d maia-sdr-0.12.0 -p1 -s < "$p"; done
make -C linux $X M="$W/maia-sdr-0.12.0/maia-kmod" modules >/dev/null
mkdir -p mod/lib/modules/6.12.77/updates && cp maia-sdr-0.12.0/maia-kmod/maia-sdr.ko mod/lib/modules/6.12.77/updates/
/sbin/depmod -b mod 6.12.77
rm -f mod/lib/modules/6.12.77/build mod/lib/modules/6.12.77/source
ls -l uImage mod/lib/modules/6.12.77/updates/maia-sdr.ko
echo "Fini : work/uImage + work/mod/lib/modules/6.12.77 (à ajouter au ramdisk, voir README.md)"
