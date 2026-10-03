#!/bin/bash
# GPU-Leistungslimit per Taktobergrenze.
# Hintergrund: NVIDIA RTX 4080 Mobile (Max-Q) hat ein per nvidia-smi -pl fixiertes TGP
# (150 W Default; "Changing power management limit is not supported"), und der Host-EC-
# cTGP-Weg wirkt im vfio-Passthrough nicht. Praktikabler Ersatz fuer ~99 W:
# Oberes SM-Taktlimit. Kalibriert bei 100 % GPU-Volllast:
#   2055 MHz -> ~150 W | 1950 -> ~132 W | 1900 -> ~125.6 W | 1880 -> ~123 W | 1790 -> ~116 W
#   1750 -> ~109 W | 1700 -> ~105.3 W | 1695 -> ~105.2 W | 1690 -> ~103.4 W
#   1666 MHz -> ~100.1 W (SM 1665) | 1664..1658 MHz -> ~99.3 W (SM 1650, Richtung 99.5 W)
# Zielwert hier: 1660 MHz ~ 99.3 W (99 W, eingeregelt Richtung 99.5 W).

TARGET="1660"

# Warten, bis der NVIDIA-Treiber die GPU meldet (max. 120 s)
for i in $(seq 1 60); do
    if nvidia-smi -L >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Persistence Mode aktivieren (stabil fuer den Daemon-Betrieb)
nvidia-smi -pm 1 >/dev/null 2>&1

# Takt-Obergrenze setzen (idempotent)
nvidia-smi -lgc "210,${TARGET}" >/dev/null 2>&1

exit 0
