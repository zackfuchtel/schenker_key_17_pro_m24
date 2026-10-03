#!/bin/bash
# fan-control.sh - autoritativer Daemon: temperaturautomatische EC-Lueftersteuerung
# Stufen (empirisch, 2026-10-03):
#   0x0A idle   ~2050 RPM
#   0x0F lowmid ~3500 RPM
#   0x12 premid ~4600 RPM
#   0x14 mid    ~5120 RPM
#   0xFF max    ~5700 RPM
#
# Temperaturschwellen (Eintritt beim Aufheizen, Rueckfall je -HYS bzw. unter TH_LOWMID):
#   TH_LOWMID=55  TH_PREMID=60  TH_MID=65  TH_MAX=70   HYS=4
ECX=/opt/fanctl/ecx
FANB=$((0xFE0B0300))
LOG=/var/log/fan-control.log

TH_LOWMID=55
TH_PREMID=60
TH_MID=65
TH_MAX=70
HYS=4
POLL=15

upload(){ # $1 = 2 Zeichen Hex (z.B. 0A)
  local v=$1 hex=""
  for i in $(seq 1 112); do hex="$hex$v"; done
  echo -n "$hex" | xxd -r -p | dd of=/dev/mem bs=1 seek=$FANB count=112 conv=notrunc 2>/dev/null
  $ECX write 0xa1 0x0b >/dev/null
  $ECX write 0xa2 0x00 >/dev/null
  $ECX write 0xa0 0xd8 >/dev/null
  sleep 1
  $ECX write 0xa2 0x70 >/dev/null
  $ECX write 0xa0 0xd8 >/dev/null
}

hottest(){
  local t=0 v=0
  for z in /sys/class/thermal/thermal_zone*/temp; do
    v=$(cat "$z" 2>/dev/null); [ -z "$v" ] && continue
    [ "$v" -gt "$t" ] && t=$v
  done
  echo $((t/1000))
}

# Entscheidungslogik (testbar per Quelle: decide "$temp" "$letzteStufe")
decide(){
  local t=$1 last=$2 want=""
  case "$last" in
    0A) if [ "$t" -ge $((TH_LOWMID+HYS)) ]; then want=0F; else want=0A; fi ;;
    0F) if [ "$t" -ge $TH_PREMID ];         then want=12
        elif [ "$t" -lt $TH_LOWMID ];       then want=0A
        else want=0F; fi ;;
    12) if [ "$t" -ge $TH_MID ];            then want=14
        elif [ "$t" -lt $((TH_PREMID-HYS)) ]; then want=0F
        else want=12; fi ;;
    14) if [ "$t" -ge $TH_MAX ];            then want=FF
        elif [ "$t" -lt $((TH_MID-HYS)) ];  then want=12
        else want=14; fi ;;
    FF) if [ "$t" -lt $((TH_MAX-HYS)) ];    then want=14
        else want=FF; fi ;;
    *)  if [ "$t" -ge $TH_MAX ];            then want=FF
        elif [ "$t" -ge $TH_MID ];          then want=14
        elif [ "$t" -ge $TH_PREMID ];       then want=12
        elif [ "$t" -ge $TH_LOWMID ];       then want=0F
        else want=0A; fi ;;
  esac
  echo "$want"
}

# Nur als Daemon starten; beim Sourcen (Smoke-Tests) nur Funktionen laden
if [ -n "${BASH_SOURCE:-}" ] && [ "$(basename "${BASH_SOURCE[0]}")" = "$(basename "$0")" ]; then
  [ -x "$ECX" ] || { echo "fan-control: $ECX fehlt" >>"$LOG"; exit 1; }

  LAST=""
  while :; do
    t=$(hottest)
    want=$(decide "$t" "$LAST")
    # EC-Istbyte lesen und Reassert (korrigiert auch manuelle Uebersteuerungen)
    ecb=$(dd if=/dev/mem bs=1 skip=$FANB count=1 2>/dev/null | xxd -p)
    need=""
    case "$want" in 0A) need=0a;; 0F) need=0f;; 12) need=12;; 14) need=14;; FF) need=ff;; esac
    if [ "$want" != "$LAST" ] || [ "$ecb" != "$need" ]; then
      echo "$(date '+%F %T') temp=${t}C -> level=$want (was $LAST, ec=$ecb)" >>"$LOG"
      upload "$want"
      LAST="$want"
    fi
    sleep "$POLL"
  done
fi
