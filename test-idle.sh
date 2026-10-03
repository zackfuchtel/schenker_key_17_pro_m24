#!/bin/bash
# Idle-Test + Daemon-Neustart-Verifikation
set -u
ECX=/tmp/ecx_new
FANB=$((0xFE0B0300))

poll() {
  sleep 18
  echo -n "fans: "
  cat /sys/class/hwmon/hwmon1/fan1_input /sys/class/hwmon/hwmon2/fan1_input | tr '\n' ' '
  echo
}

upload() { # $1 = 2 Zeichen Hex (z.B. 0A)
  local v="$1" hex=""
  for i in $(seq 1 112); do hex="$hex$v"; done
  echo -n "$hex" | xxd -r -p | dd of=/dev/mem bs=1 seek="$FANB" count=112 conv=notrunc 2>/dev/null
  "$ECX" write 0xa1 0x0b >/dev/null
  "$ECX" write 0xa2 0x00 >/dev/null
  "$ECX" write 0xa0 0xd8 >/dev/null
  sleep 1
  "$ECX" write 0xa2 0x70 >/dev/null
  "$ECX" write 0xa0 0xd8 >/dev/null
  echo "upload done ($1)"
}

echo "== TEST IDLE (0A) mit neuem ecx =="
upload 0A
poll

echo "== Daemon starten =="
systemctl start fan-control
sleep 3
systemctl is-active fan-control
systemctl status fan-control --no-pager | head -8
echo "== letzte Logzeilen =="
tail -6 /var/log/fan-control.log
echo "== aktuelle Temp =="
cat /sys/class/thermal/thermal_zone0/temp
