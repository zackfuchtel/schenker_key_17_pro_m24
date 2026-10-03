#!/bin/bash
# Smoke-Test der Entscheidungslogik (muss NACH Deployment unter /opt/fanctl/fan-control.sh laufen)
source /opt/fanctl/fan-control.sh
pass=0; fail=0
check(){ # $1=erwartet $2=tatsaechlich $3=desc
  if [ "$1" = "$2" ]; then echo "PASS $3 -> $2"; pass=$((pass+1)); else echo "FAIL $3: erwartet $1, bekommen $2"; fail=$((fail+1)); fi
}

# --- Aufheizen ---
check 0A "$(decide 54 0A)" "t54  idle bleibt"
check 0A "$(decide 58 0A)" "t58  idle (unter Eintritt 59)"
check 0F "$(decide 59 0A)" "t59  idle->lowmid"
check 0F "$(decide 59 0F)" "t59  lowmid bleibt"
check 12 "$(decide 60 0F)" "t60  lowmid->premid"
check 12 "$(decide 64 12)" "t64  premid bleibt"
check 14 "$(decide 65 12)" "t65  premid->mid"
check 14 "$(decide 69 14)" "t69  mid bleibt"
check FF "$(decide 70 14)" "t70  mid->max"
check FF "$(decide 75 FF)" "t75  max bleibt"
# --- Abkuehlen (mit Hysterese) ---
check FF "$(decide 66 FF)" "t66  max bleibt (Rueckfall erst <66)"
check 14 "$(decide 65 FF)" "t65  max->mid"
check 14 "$(decide 61 14)" "t61  mid bleibt (Rueckfall erst <61)"
check 12 "$(decide 60 14)" "t60  mid->premid"
check 12 "$(decide 56 12)" "t56  premid bleibt (Rueckfall erst <56)"
check 0F "$(decide 55 12)" "t55  premid->lowmid"
check 0F "$(decide 55 0F)" "t55  lowmid bleibt"
check 0A "$(decide 54 0F)" "t54  lowmid->idle"
# --- Frischer Start (kein letzter Zustand) ---
check 0A "$(decide 40 x)" "start t40"
check 0F "$(decide 58 x)" "start t58"
check 12 "$(decide 62 x)" "start t62"
check 14 "$(decide 68 x)" "start t68"
check FF "$(decide 72 x)" "start t72"

echo "== $pass passed, $fail failed =="
exit $fail
