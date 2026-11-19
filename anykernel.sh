#!/sbin/sh
# shellcheck disable=SC2034
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
# shellcheck disable=SC2289
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
# shellcheck source=/dev/null
. tools/ak3-core.sh

########################################################################
# [1] PENGATURAN
########################################################################
DEFAULT_KERNEL_TYPE="gki"    # gki | clo
DEFAULT_KSU_TYPE="ksu"       # ksu | noksu

INPUT_WAIT="${CRYO_WAIT:-30}"
DEBOUNCE="${CRYO_DEBOUNCE:-0.4}"

# Validasi INPUT_WAIT: harus integer > 0
case "$INPUT_WAIT" in ''|*[!0-9]*) INPUT_WAIT=30 ;; esac
[ "$INPUT_WAIT" -gt 0 ] 2>/dev/null || INPUT_WAIT=30

# Validasi DEBOUNCE: harus float sederhana
case "$DEBOUNCE" in ''|.|*[!0-9.]*|*.*.*) DEBOUNCE=0.4 ;; esac

# Fallback jika timeout tidak mendukung pecahan
if command -v timeout >/dev/null 2>&1 && ! timeout 0.1 true 2>/dev/null; then
  DEBOUNCE=1
fi

########################################################################
# [2] TAMPILAN
########################################################################
BOX_LINE="-----------------------------------------------------"
BOX_BORDER="+${BOX_LINE}+"

box_line() { ui_print "$BOX_BORDER"; }
box_row()  { ui_print "$(printf '| %-51.51s |' "$1")"; }

label_of() {
  case "$1" in
    gki) echo "GKI" ;; clo) echo "CLO" ;;
    ksu) echo "With KSU" ;; noksu) echo "Vanilla" ;;
    *) echo "$1" ;;
  esac
}

lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }

########################################################################
# [3] DETEKSI LINGKUNGAN & PILIHAN OTOMATIS
########################################################################
detect_env() {
  # Android (flashing via Magisk, KernelSU, APatch, MMRL atau live Android OS)
  if [ "${BOOTMODE:-}" = "true" ] \
    || [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] \
    || [ "$(getprop init.svc.zygote 2>/dev/null)" = "running" ] \
    || [ "$(getprop init.svc.zygote_secondary 2>/dev/null)" = "running" ] \
    || (ps -A 2>/dev/null || ps 2>/dev/null) | grep -qE '[z]ygote|[s]ystem_server'; then
    echo "Android"
    return 0
  fi

  # Recovery (TWRP, OrangeFox, PBRP, AOSP/Lineage Recovery)
  if [ -d /twres ] || [ -d /fox ] \
    || [ -f /sbin/recovery ] || [ -f /system/bin/recovery ] \
    || [ -f /init.recovery.rc ] || [ -f /tmp/recovery.log ] \
    || [ "$(getprop ro.boot.bootmode 2>/dev/null)" = "recovery" ] \
    || [ "$(getprop ro.bootmode 2>/dev/null)" = "recovery" ] \
    || [ "$(getprop init.svc.recovery 2>/dev/null)" = "running" ] \
    || (ps -A 2>/dev/null || ps 2>/dev/null) | grep -q '[r]ecovery'; then
    echo "Recovery"
    return 0
  fi

  echo "Unknown"
}

is_android_app() {
  [ "$(detect_env)" = "Android" ]
}

can_use_keys() {
  command -v getevent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1
}

# Baca nilai dari cryo.conf
CR=$(printf '\r')
read_conf() {
  for rc_f in "$AKHOME/cryo.conf" /data/local/tmp/cryo.conf /sdcard/cryo.conf /data/media/0/cryo.conf; do
    [ -f "$rc_f" ] || continue
    while IFS= read -r rc_l || [ -n "$rc_l" ]; do
      rc_l="${rc_l%%#*}"; rc_l="${rc_l%"$CR"}"
      IFS="=	 " read -r rc_k rc_v _ <<EOF_CONF
$rc_l
EOF_CONF
      [ "$rc_k" = "$1" ] && [ -n "$rc_v" ] && { lower "$rc_v"; echo; return 0; }
    done < "$rc_f"
  done
  return 1
}

# Resolusi preset: env > nama zip > cryo.conf
resolve_preset() {
  rp_env="$1" rp_dim="$2"
  v=$(lower "$rp_env")
  if [ -z "$v" ]; then
    case "$rp_dim" in
      kernel) case "$zipname" in *[-_.]clo|*[-_.]clo[-_.]*) v=clo ;; *[-_.]gki|*[-_.]gki[-_.]*) v=gki ;; esac ;;
      ksu)    case "$zipname" in *[-_.]noksu|*[-_.]noksu[-_.]*|*[-_.]vanilla|*[-_.]vanilla[-_.]*) v=noksu ;; *[-_.]ksu|*[-_.]ksu[-_.]*) v=ksu ;; esac ;;
    esac
  fi
  [ -z "$v" ] && v=$(read_conf "$rp_dim")
  echo "$v"
}

zipname=$(lower "${ZIPFILE##*/}")
pre_kernel=$(resolve_preset "${CRYO_KERNEL:-}" kernel)
pre_ksu=$(resolve_preset "${CRYO_KSU:-}" ksu)
# Sanitasi
case "$pre_kernel" in gki|clo) ;; *) pre_kernel="" ;; esac
case "$pre_ksu" in ksu|noksu) ;; *) pre_ksu="" ;; esac

# Enumerasi image yang tersedia
AVAIL=""
for k in gki clo; do
  for s in ksu noksu; do
    [ -s "$AKHOME/Image.$k.$s" ] && AVAIL="$AVAIL $k.$s"
  done
done
AVAIL="${AVAIL# }"
[ -n "$AVAIL" ] || abort "Tidak ada file Image.<gki|clo>.<ksu|noksu> di paket ini | No kernel image found in this package."

# Daftar nilai unik untuk satu dimensi
avail_values() {
  av_out=""
  for av_img in $AVAIL; do
    av_k="${av_img%%.*}"; av_s="${av_img#*.}"
    if [ "$1" = "kernel" ]; then
      av_v="$av_k"
    else
      [ -n "$2" ] && [ "$av_k" != "$2" ] && continue
      av_v="$av_s"
    fi
    case " $av_out " in *" $av_v "*) ;; *) av_out="$av_out $av_v" ;; esac
  done
  echo "${av_out# }"
}

########################################################################
# [4] INPUT TOMBOL
########################################################################
clear_input() {
  ci=0
  while [ "$ci" -lt 8 ]; do
    ev=$(timeout "$DEBOUNCE" getevent -qlc 1 2>/dev/null)
    [ -z "$ev" ] && return 0
    ci=$((ci + 1))
  done
  sleep 0.3 2>/dev/null || sleep 1
}

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

# Menu generik. Hasil di $sel_result / $sel_how.
select_option() {
  s_title="$1"; s_up_txt="$2"; s_up_val="$3"
  s_dn_txt="$4"; s_dn_val="$5"; s_def="$6"; s_pre="$7"

  if [ -n "$s_pre" ]; then
    sel_result="$s_pre"; sel_how="preset"; return 0
  fi

  if ! can_use_keys; then
    sel_result="$s_def"; sel_how="default (tanpa input)"
    ui_print "  ! Tombol tidak tersedia, memakai default: $(label_of "$s_def")"
    return 0
  fi

  # Clear input sekali saja sebelum menu pertama
  [ -z "${input_cleared:-}" ] && { clear_input; input_cleared=1; }

  mark_up="" mark_dn=""
  [ "$s_def" = "$s_up_val" ] && mark_up="  (default)"
  [ "$s_def" = "$s_dn_val" ] && mark_dn="  (default)"

  ui_print " "
  box_line
  box_row "$s_title"
  box_line
  box_row "[Vol +]  ${s_up_txt}${mark_up}"
  box_row "[Vol -]  ${s_dn_txt}${mark_dn}"
  box_row "[Power]  Batal / Exit"
  box_row ""
  box_row "Tanpa input ${INPUT_WAIT} detik = pilih default"
  box_line
  read_key; rc=$?
  clear_input

  case $rc in
    1) sel_result="$s_up_val"; sel_how="tombol" ;;
    2) sel_result="$s_dn_val"; sel_how="tombol" ;;
    4) abort "Dibatalkan oleh user | canceled by user  (Power button)." ;;
    *) sel_result="$s_def";    sel_how="default (timeout)" ;;
  esac
  ui_print "  > Dipilih|Selected : $(label_of "$sel_result")"
}

# Auto-pick jika hanya 1 opsi; validasi preset
auto_pick() {
  ap_vals="$1"; ap_pre="$2"; ap_n=0; ap_last=""
  for ap_x in $ap_vals; do ap_n=$((ap_n + 1)); ap_last="$ap_x"; done
  if [ -n "$ap_pre" ]; then
    case " $ap_vals " in *" $ap_pre "*) ;; *) ui_print "  ! Preset '$ap_pre' tidak ada di paket, diabaikan"; ap_pre="" ;; esac
  fi
  [ "$ap_n" -eq 1 ] && { sel_result="$ap_last"; sel_how="otomatis (hanya tersedia)"; return 0; }
  return 1
}

# Pemilihan kernel + KSU (unified helper)
choose() {
  ch_dim="$1"; ch_pre="$2"; ch_def="$3"
  shift 3
  ch_vals=$(avail_values "$@")
  [ -n "$ch_vals" ] || abort "Tidak ada opsi valid untuk '$ch_dim' | No valid option."

  case "$ch_dim" in
    kernel) ch_title="Pilih Varian Cryo | Choose Cryo Variant" ;;
    ksu)    ch_title="Pilih Dukungan KernelSU | KSU Support?" ;;
    *)      abort "Dimensi tidak dikenal: '$ch_dim' | Unknown dimension." ;;
  esac

  if auto_pick "$ch_vals" "$ch_pre"; then
    ui_print " "
    box_line
    box_row "$ch_title"
    box_line
    box_row ">>> SKIPPED"
    box_row ""
    box_row "Hanya satu opsi | Only one option"
    box_row ">> $(label_of "$sel_result")"
    box_line
    return 0
  fi

  case " $ch_vals " in *" $ch_pre "*) ;; *) ch_pre="" ;; esac
  case "$ch_dim" in
    kernel) select_option "$ch_title" "GKI" "gki" "CLO" "clo" "$ch_def" "$ch_pre" ;;
    ksu)    select_option "$ch_title" "With KSU" "ksu" "Vanilla" "noksu" "$ch_def" "$ch_pre" ;;
    *)      abort "Dimensi tidak dikenal: '$ch_dim' | Unknown dimension." ;;
  esac
}

########################################################################
# [5] PROSES PEMILIHAN
########################################################################
ui_print " "
env_name="$(detect_env)"
ui_print "Environment mode : $env_name"
ui_print "Image tersedia : $AVAIL"

choose kernel "$pre_kernel" "$DEFAULT_KERNEL_TYPE" kernel
kernel_type="$sel_result"; kernel_how="$sel_how"

choose ksu "$pre_ksu" "$DEFAULT_KSU_TYPE" ksu "$kernel_type"
ksu_type="$sel_result"; ksu_how="$sel_how"

# Tentukan dan validasi image terpilih
selected_kernel="Image.${kernel_type}.${ksu_type}"
case "$selected_kernel" in
  Image.gki.ksu|Image.gki.noksu|Image.clo.ksu|Image.clo.noksu) ;;
  *) abort "Nama image tidak valid: $selected_kernel" ;;
esac
[ -s "$AKHOME/$selected_kernel" ] || abort "Kernel file kosong/tidak ditemukan: $selected_kernel"

ui_print " "
box_line
box_row "Ringkasan Pilihan | Summary of options"
box_line
box_row "Variant   : $(label_of "$kernel_type")  [$kernel_how]"
box_row "KernelSU  : $(label_of "$ksu_type")  [$ksu_how]"
box_row "Image     : $selected_kernel"
box_row "Tersedia  : $AVAIL"
box_line
ui_print " "

if mv -f "$AKHOME/$selected_kernel" "$AKHOME/Image" 2>/dev/null && [ -s "$AKHOME/Image" ]; then
  ui_print "Flashing: $selected_kernel"
else
  abort "Gagal memasang kernel: $selected_kernel"
fi

########################################################################
# [6] BOOT INSTALL
########################################################################
# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || [ -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot
    flash_boot
else
    dump_boot
    write_boot
fi
## end boot install
