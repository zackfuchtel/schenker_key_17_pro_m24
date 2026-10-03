#!/bin/bash
# End-to-end-Test des kompilierten ecx auf dem SCHENKER KEY 17 Pro M24
set -u
TMP=/tmp/fanctl-test
mkdir -p "$TMP"
ECX=/tmp/ecx_new
FANB=$((0xFE0B0300))

poll() {
  sleep 18
  echo -n "fans: "
  cat /sys/class/hwmon/hwmon1/fan1_input /sys/class/hwmon/hwmon2/fan1_input | tr '\n' ' '
  echo
}

upload() { # $1 = 2 Zeichen Hex (z.B. FF)
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

echo "== TEST MAX (FF) mit neuem ecx =="
upload FF
poll

echo "== READBACK Register =="
"$ECX" dump 0xa0 0xa2
echo -n "FANB 1st byte: "
dd if=/dev/mem bs=1 skip="$FANB" count=1 2>/dev/null | xxd -p
