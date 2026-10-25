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

########################################################################
# [1] PENGATURAN
########################################################################
DEFAULT_KERNEL_TYPE="gki"    # gki | clo
DEFAULT_KSU_TYPE="ksu"       # ksu | noksu
INPUT_WAIT=30                # total detik menunggu tombol
DEBOUNCE=0.4                 # detik "hening" setelah memilih (anti tekan ganda)
# Jika busybox/toybox tidak mendukung timeout pecahan, pakai 1 detik utuh
if command -v timeout >/dev/null 2>&1 && ! timeout 0.1 true 2>/dev/null; then
  DEBOUNCE=1
fi

########################################################################
# [2] TAMPILAN (gaya kotak, senada dengan banner Cryo)
########################################################################
BOX_LINE="-----------------------------------------------------"

box_top() { ui_print "+${BOX_LINE}+"; }
box_mid() { ui_print "+${BOX_LINE}+"; }
box_bot() { ui_print "+${BOX_LINE}+"; }
box_row() { ui_print "$(printf '| %-51s |' "$1")"; }   # teks: ASCII saja

# Label tampilan untuk nilai pilihan
label_of() {
  case "$1" in
    gki) echo "GKI" ;;
    clo) echo "CLO" ;;
    ksu) echo "With KSU" ;;
    noksu) echo "Vanilla" ;;
    *) echo "$1" ;;
  esac
}

########################################################################
# [3] DETEKSI LINGKUNGAN & PILIHAN OTOMATIS
########################################################################
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

# Pilihan tanpa interaksi.
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

########################################################################
# [4] INPUT TOMBOL
########################################################################
# Clear input buffer + anti tekan ganda (debounce adaptif).
# Menunggu sampai tidak ada event input selama $DEBOUNCE detik. Tekan ganda,
# pelepasan tombol, dan key-repeat ikut tertelan di sini. Jika user tidak
# menyentuh apa pun, jedanya hanya sekitar $DEBOUNCE detik (bukan 2 detik).
clear_input() {
  ci=0
  while [ "$ci" -lt 8 ]; do
    ev=$(timeout "$DEBOUNCE" getevent -qlc 1 2>/dev/null)
    [ -z "$ev" ] && return 0     # hening -> aman lanjut
    ci=$((ci + 1))
  done
  sleep 0.3 2>/dev/null || sleep 1   # input terus mengalir (perangkat "berisik")
}

# Pembaca tombol terpadu.
# Return: 1 = Vol+, 2 = Vol-, 4 = Power, 3 = timeout (pakai default)
# Satu aliran getevent dipakai selama seluruh waktu tunggu (tidak ada celah
# antar-pembacaan, jadi tekanan tombol tidak terlewat). Hanya event DOWN yang
# dihitung; UP dan REPEAT (tahan tombol) tidak cocok dengan pola.
read_key() {
  input=$(timeout "$INPUT_WAIT" getevent -l 2>/dev/null \
    | grep -m 1 -E "KEY_(VOLUMEUP|VOLUMEDOWN|POWER)[[:space:]]+DOWN")
  case "$input" in
    *KEY_VOLUMEUP*)   return 1 ;;
    *KEY_VOLUMEDOWN*) return 2 ;;
    *KEY_POWER*)      return 4 ;;
  esac
  return 3
}

# Menu pilihan generik. Hasil di $sel_result.
#   $1 judul   $2/$3 teks & nilai Vol+   $4/$5 teks & nilai Vol-
#   $6 default $7 preset (opsional, melewati menu)
select_option() {
  s_title="$1"; s_up_txt="$2"; s_up_val="$3"
  s_dn_txt="$4"; s_dn_val="$5"; s_def="$6"; s_pre="$7"

  if [ -n "$s_pre" ]; then
    sel_result="$s_pre"; sel_how="preset"
    return 0
  fi

  if ! can_use_keys; then
    sel_result="$s_def"; sel_how="default (tanpa input)"
    return 0
  fi

  mark_up=""; mark_dn=""
  [ "$s_def" = "$s_up_val" ] && mark_up="  (default)"
  [ "$s_def" = "$s_dn_val" ] && mark_dn="  (default)"

  ui_print " "
  box_top
  box_row "$s_title"
  box_mid
  box_row "[Vol +]  ${s_up_txt}${mark_up}"
  box_row "[Vol -]  ${s_dn_txt}${mark_dn}"
  box_row "[Power]  Batal / keluar"
  box_row ""
  box_row "Tanpa input ${INPUT_WAIT} detik = pilih default"
  box_bot
  read_key
  rc=$?
  clear_input

  case $rc in
    1) sel_result="$s_up_val"; sel_how="tombol" ;;
    2) sel_result="$s_dn_val"; sel_how="tombol" ;;
    4) abort "Dibatalkan oleh user (tombol Power)." ;;
    *) sel_result="$s_def";    sel_how="default (timeout)" ;;
  esac
  ui_print "  > Dipilih: $(label_of "$sel_result")"
}

# Pemilihan jenis kernel
choose_kernel_type() {
  select_option "Pilih Varian Cryo" "GKI" "gki" "CLO" "clo" \
    "$DEFAULT_KERNEL_TYPE" "$pre_kernel"
}

# Pemilihan dukungan KSU
choose_ksu() {
  select_option "Pilih Dukungan KernelSU" "With KSU" "ksu" "Vanilla" "noksu" \
    "$DEFAULT_KSU_TYPE" "$pre_ksu"
}

########################################################################
# [5] PROSES PEMILIHAN
########################################################################
ui_print " "
if is_android_app; then env_name="Aplikasi Android"; else env_name="Recovery"; fi
ui_print "Environment : $env_name"

clear_input   # buang sisa input sebelum menu pertama

choose_kernel_type
kernel_type="$sel_result"; kernel_how="$sel_how"

# Jeda antar menu kini ditangani debounce di clear_input (di akhir select_option)

choose_ksu
ksu_type="$sel_result"; ksu_how="$sel_how"

# Move selected kernel
selected_kernel="Image.${kernel_type}.${ksu_type}"

ui_print " "
box_top
box_row "Ringkasan Pilihan"
box_mid
box_row "Varian    : $(label_of "$kernel_type")  [$kernel_how]"
box_row "KernelSU  : $(label_of "$ksu_type")  [$ksu_how]"
box_row "Image     : $selected_kernel"
box_bot
ui_print " "

if [ -f "$AKHOME/$selected_kernel" ]; then
  ui_print "Flashing: $selected_kernel"
  mv "$AKHOME/$selected_kernel" "$AKHOME/Image"
else
  abort "Kernel file not found: $selected_kernel"
fi

########################################################################
# [6] BOOT INSTALL
########################################################################
# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" -o -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot
    flash_boot
else
    dump_boot
    write_boot
fi
## end boot install
