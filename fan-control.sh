#!/bin/bash
# fan-control.sh - autoritativer Daemon: temperaturautomatische EC-Lueftersteuerung
# Stufen (empirisch): 0x0A=~2050RPM, 0x14=~5120RPM, 0xFF=~5700RPM
ECX=/opt/fanctl/ecx
FANB=$((0xFE0B0300))
LOG=/var/log/fan-control.log
LOW=55        # unterhalb -> idle
HIGH=70       # oberhalb  -> max
HYS=4         # Hysterese in C
POLL=15       # Sekunden

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

[ -x "$ECX" ] || { echo "fan-control: $ECX fehlt" >>"$LOG"; exit 1; }

LAST=""
while :; do
  t=$(hottest)
  case "$LAST" in
    0A) if [ "$t" -ge $((LOW+HYS)) ]; then want=14; else want=0A; fi ;;
    14) if [ "$t" -ge $HIGH ]; then want=FF; elif [ "$t" -lt $LOW ]; then want=0A; else want=14; fi ;;
    FF) if [ "$t" -lt $((HIGH-HYS)) ]; then want=14; else want=FF; fi ;;
    *)  if [ "$t" -ge $HIGH ]; then want=FF; elif [ "$t" -lt $LOW ]; then want=0A; else want=14; fi ;;
  esac
  # EC-Istbyte lesen und Reassert (korrigiert auch manuelle Uebersteuerungen)
  ecb=$(dd if=/dev/mem bs=1 skip=$FANB count=1 2>/dev/null | xxd -p)
  need=""
  case "$want" in 0A) need=0a;; 14) need=14;; FF) need=ff;; esac
  if [ "$want" != "$LAST" ] || [ "$ecb" != "$need" ]; then
    echo "$(date '+%F %T') temp=${t}C -> level=$want (was $LAST, ec=$ecb)" >>"$LOG"
    upload "$want"
    LAST="$want"
  fi
  sleep "$POLL"
done
