### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=by dyatz685 @ github
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=topaz
device.name2=tapas
device.name3=sapphiren
device.name4=sapphire
device.name5=xun
device.name6=creek
supported.versions=13-17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching
. tools/ak3-core.sh

### Pengaturan & deteksi lingkungan
# Pilihan bawaan bila tidak ada input (aplikasi Android / timeout di recovery)
DEFAULT_KERNEL_TYPE="gki"    # gki | clo
DEFAULT_KSU_TYPE="ksu"        # ksu | noksu
INPUT_WAIT=30                # total detik menunggu tombol volume

# Berjalan dari aplikasi Android (bukan recovery)?
is_android_app() {
  [ "$BOOTMODE" = "true" ] && return 0
  [ "$(getprop init.svc.zygote 2>/dev/null)" = "running" ] && return 0
  return 1
}

# Tombol aktif di recovery DAN aplikasi Android (selama tool tersedia)
can_use_keys() {
  command -v getevent >/dev/null 2>&1 || return 1
  command -v timeout >/dev/null 2>&1 || return 1
  return 0
}

# Baca nilai dari cryo.conf (format: kernel=gki / ksu=noksu)
read_conf() {
  for f in "$AKHOME/cryo.conf" /data/local/tmp/cryo.conf /sdcard/cryo.conf /data/media/0/cryo.conf; do
    [ -f "$f" ] || continue
    v=$(sed -n "s/^$1=//p" "$f" 2>/dev/null | head -n 1 | tr -d ' \r' | tr 'A-Z' 'a-z')
    if [ -n "$v" ]; then echo "$v"; return 0; fi
  done
  return 1
}

# Pilihan otomatis tanpa interaksi.
# Prioritas: variabel env (CRYO_KERNEL / CRYO_KSU) > nama zip > cryo.conf
pre_kernel=""
pre_ksu=""
zipname=$(basename "${ZIPFILE:-}" 2>/dev/null | tr 'A-Z' 'a-z')

v="$(echo "$CRYO_KERNEL" | tr 'A-Z' 'a-z')"
if [ -z "$v" ]; then
  case "$zipname" in
    *[-_.]clo[-_.]*) v="clo" ;;
    *[-_.]gki[-_.]*) v="gki" ;;
  esac
fi
[ -z "$v" ] && v="$(read_conf kernel)"
case "$v" in gki|clo) pre_kernel="$v" ;; esac

v="$(echo "$CRYO_KSU" | tr 'A-Z' 'a-z')"
if [ -z "$v" ]; then
  case "$zipname" in
    *[-_.]noksu[-_.]*|*[-_.]vanilla[-_.]*) v="noksu" ;;
    *[-_.]ksu[-_.]*) v="ksu" ;;
  esac
fi
[ -z "$v" ] && v="$(read_conf ksu)"
case "$v" in ksu|noksu) pre_ksu="$v" ;; esac

# Clear input buffer function
clear_input() {
  # Kill any existing getevent processes
  pkill getevent 2>/dev/null
  # Wait a moment and clear any buffered input
  sleep 0.5
  # Flush input buffer
  timeout 0.1 getevent -qlc 1 >/dev/null 2>&1 || true
}

# [OPTIMASI] Satu pembaca tombol untuk semua menu.
# Return: 1 = Vol+, 2 = Vol-, 4 = Power, 3 = timeout (pakai default)
# Hanya event tekan (DOWN) yang dihitung; event lepas (UP) diabaikan
# sehingga pelepasan tombol tidak "bocor" ke menu berikutnya.
read_key() {
  end=$(( $(date +%s) + INPUT_WAIT ))
  while [ "$(date +%s)" -lt "$end" ]; do
    input=$(timeout 10 getevent -qlc 1 2>/dev/null \
      | grep -E "KEY_(VOLUMEUP|VOLUMEDOWN|POWER)" \
      | grep -v -E "[[:space:]]UP[[:space:]]*$")
    case "$input" in
      *KEY_VOLUMEUP*)   return 1 ;;
      *KEY_VOLUMEDOWN*) return 2 ;;
      *KEY_POWER*)      return 4 ;;
    esac
    sleep 0.1 2>/dev/null || sleep 1
  done
  return 3
}

# Kernel type selection
choose_kernel_type() {
  clear_input
  ui_print " "
  ui_print "Cryo Variant:"
  ui_print "  Volume + : GKI"
  ui_print "  Volume - : CLO"
  ui_print "  Power    : Batal / keluar"
  ui_print "  (${INPUT_WAIT} detik tanpa input = default: $DEFAULT_KERNEL_TYPE)"
  ui_print " "
  read_key
  rc=$?
  clear_input
  return $rc
}

# KSU selection
choose_ksu() {
  clear_input
  ui_print " "
  ui_print "KernelSU Support:"
  ui_print "  Volume + : With KSU"
  ui_print "  Volume - : Vanilla"
  ui_print "  Power    : Batal / keluar"
  ui_print "  (${INPUT_WAIT} detik tanpa input = default: $DEFAULT_KSU_TYPE)"
  ui_print " "
  read_key
  rc=$?
  clear_input
  return $rc
}

# Info lingkungan
if is_android_app; then ui_print "Environment: Android app"; else ui_print "Environment: Recovery"; fi

# Handle selection
if [ -n "$pre_kernel" ]; then
  kernel_type="$pre_kernel"
  ui_print "Selected (preset): $kernel_type"
elif can_use_keys; then
  choose_kernel_type
  case $? in
    1) kernel_type="gki"; ui_print "Selected: GKI" ;;
    2) kernel_type="clo"; ui_print "Selected: CLO" ;;
    4) abort "Dibatalkan oleh user (tombol Power)." ;;
    *) kernel_type="$DEFAULT_KERNEL_TYPE"; ui_print "No input, default: $kernel_type" ;;
  esac
else
  kernel_type="$DEFAULT_KERNEL_TYPE"
  ui_print "Non-interactive mode, default: $kernel_type"
fi

# Add a brief pause between selections
sleep 1

if [ -n "$pre_ksu" ]; then
  ksu_type="$pre_ksu"
  ui_print "Selected (preset): $ksu_type"
elif can_use_keys; then
  choose_ksu
  case $? in
    1) ksu_type="ksu"; ui_print "Selected: With KSU" ;;
    2) ksu_type="noksu"; ui_print "Selected: Vanilla" ;;
    4) abort "Dibatalkan oleh user (tombol Power)." ;;
    *) ksu_type="$DEFAULT_KSU_TYPE"; ui_print "No input, default: $ksu_type" ;;
  esac
else
  ksu_type="$DEFAULT_KSU_TYPE"
  ui_print "Non-interactive mode, default: $ksu_type"
fi

# Move selected kernel
selected_kernel="Image.${kernel_type}.${ksu_type}"
if [ -f "$AKHOME/$selected_kernel" ]; then
  ui_print "Flashing: $selected_kernel"
  mv "$AKHOME/$selected_kernel" "$AKHOME/Image"
else
  abort "Kernel file not found: $selected_kernel"
fi

# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" -o -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot
    flash_boot
else
    dump_boot
    write_boot
fi
## end boot install
