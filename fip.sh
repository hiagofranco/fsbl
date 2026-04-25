#!/usr/bin/env sh

fail() {
	echo "$1"
	exit 1
}

[ "$CHIP_ARCH" ] || fail "\$CHIP_ARCH isn't specified"
[ "$OPENSBI" ] || fail "\$OPENSBI isn't specified"
[ "$NEXTLOADER" ] || fail "\$NEXTLOADER isn't specified"
FIP_COMPRESS="${FIP_COMPRESS:-lzma}"
NEXTLOADER_BASE="${NEXTLOADER_BASE:-0x80200000}"

BUILDDIR="build/$CHIP_ARCH/"
PYTHON3="${PYTHON3:-python3}"
FIPTOOL="plat/$CHIP_ARCH/fiptool.py"
[ "$FDT" ] && FDT_ARG="--FDT $FDT"

export BLCP_IMG_RUNADDR=0x05200200
export BLCP_PARAM_LOADADDR=0
export NAND_INFO=00000000
export NOR_INFO="$(printf '%72s' | tr ' ' 'FF')"

get_memmap_conf() {
	key="$1"
	value=""

	awk -e '{ print($2 " " $3) }' "plat/$CHIP_ARCH/include/cvi_board_memmap.h" |
	while read line; do
		if echo "$line" | grep -q "$key"; then
			value="$(echo "$line" | cut -f 2 -d ' ')"
			echo "$value"
			return
		fi
	done
}

MONITOR_RUNADDR="$(get_memmap_conf "CVIMMAP_MONITOR_ADDR")"

# Prepend the 32-byte BL2 header the BootROM expects (4-byte `jal zero, +32`
# followed by 28 bytes of metadata slots) to u-boot-spl.bin so that the
# BootROM reaches U-Boot SPL's _start.
SPL_IN="../u-boot/spl/u-boot-spl.bin"
SPL_WRAPPED="$BUILDDIR/u-boot-spl-bl2.bin"
mkdir -p "$BUILDDIR"
"$PYTHON3" -c "import sys; sys.stdout.buffer.write(bytes.fromhex('6f00000200000000000000000000000000000000000000000000000000000000'))" > "$SPL_WRAPPED"
cat "$SPL_IN" >> "$SPL_WRAPPED"

"$PYTHON3" "$FIPTOOL" -v genfip \
	fip.bin					\
	--MONITOR_RUNADDR="$MONITOR_RUNADDR"	\
	--CHIP_CONF="$BUILDDIR/chip_conf.bin"	\
	--BL2="$SPL_WRAPPED"			\
	--MONITOR="$OPENSBI"			\
	--LOADER_2ND="$NEXTLOADER"		\
	--LOADER_2ND_BASE="$NEXTLOADER_BASE"	\
	--compress="$FIP_COMPRESS"		\
	--NOR_INFO="$NOR_INFO"			\
	--NAND_INFO="$NAND_INFO"		\
	$FDT_ARG
