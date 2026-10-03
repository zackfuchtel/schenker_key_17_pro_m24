#!/bin/bash
# fanctl.sh - manuelle Steuerung der EC-Luefterkurve (SCHENKER KEY 17 Pro / Clevo VK35)
# usage: fanctl.sh {idle|mid|max|status}
ECX=/opt/fanctl/ecx
FANB=$((0xFE0B0300))
upload(){ # $1 = hex byte (2 Zeichen), $2 = label
  local v=$1
  local hex=""
  for i in $(seq 1 112); do hex="$hex$v"; done
  echo -n "$hex" | xxd -r -p | dd of=/dev/mem bs=1 seek=$FANB count=112 conv=notrunc 2>/dev/null
  $ECX write 0xa1 0x0b >/dev/null
  $ECX write 0xa2 0x00 >/dev/null
  $ECX write 0xa0 0xd8 >/dev/null
  sleep 1
  $ECX write 0xa2 0x70 >/dev/null
  $ECX write 0xa0 0xd8 >/dev/null
  echo "fanctl: Kurve gesetzt ($2, 0x$v)."
}
case "$1" in
  idle)  upload 0A "idle ~2050RPM" ;;
  mid)   upload 14 "mid ~5120RPM" ;;
  max)   upload FF "max ~5700RPM" ;;
  status)
    echo "fans: $(cat /sys/class/hwmon/hwmon1/fan1_input) / $(cat /sys/class/hwmon/hwmon2/fan1_input) RPM"
    echo "warmste Zone: $(for z in /sys/class/thermal/thermal_zone*/temp; do cat "$z"; done | sort -n | tail -1 | awk '{print $1/1000 "C"}')" ;;
  *) echo "usage: $0 {idle|mid|max|status}"; exit 1 ;;
esac
