# schenker_key_17_pro_m24

Verwaltung des Proxmox-Hosts SCHENKER KEY 17 Pro M24 (EC VK35GTC / LIONVK35, TongFang X370SNx1).

## Fan control (Host, Proxmox)

Lüfterkurve per EC-Kurven-Upload. Siehe `fan-control.sh`, `fan-control.service`, `ecx`, `fanctl.sh`.
Installiert unter `/opt/fanctl/`, Unit `fan-control.service` (enabled). Log: `/var/log/fan-control.log`.

**Stufen (empirisch gemessen, 2026-10-03):**

| EC-Wert | Stufe | RPM (beide Lüfter) | Bemerkung |
|---|---|---|---|
| `0x0A` | idle | ~2050 | unterste Stufe |
| `0x0B` | – | ~2300–2500 | zu dicht an idle |
| `0x0C` | – | ~2600–2670 | |
| `0x0D` | – | ~2900–2930 | |
| `0x0E` | – | ~3170–3190 | |
| **`0x0F`** | **lowmid** | **~3500** | **neue Stufe (gewählt)** |
| `0x10` | – | ~4110–4400 | deutlicher Sprung |
| `0x11` | – | ~4310–4370 | |
| **`0x12`** | **premid** | **~4600** | **neue Stufe (gewählt)** |
| `0x13` | – | ~4660–4720 | |
| `0x14` | mid | ~5120 | bisherige Mittelstufe |
| `0xFF` | max | ~5700 | oberste Stufe |

**Daemon-Schwellen (`fan-control.sh`):** `TH_LOWMID=55`, `TH_PREMID=60`, `TH_MID=65`, `TH_MAX=70`, `HYS=4`, `POLL=15`.
Verhalten: Aufheizen 55/60/65/70 °C → lowmid/premid/mid/max; Abkühlen mit 4 °C Hysterese
(Rückfall max→mid ab <66, mid→premid ab <61, premid→lowmid ab <56, lowmid→idle ab <55).

Manuell: `fanctl.sh {idle|lowmid|premid|mid|max|status}`. Logik-Test: `bash test-decide.sh` (23 Fälle).

## GPU power limit (~99 W)

**Problem:** Die NVIDIA RTX 4080 Laptop GPU (Max-Q, per vfio-PCI an die VM <guest> durchgereicht)
hat ein **festes TGP**:
- `nvidia-smi -pl <wert>` → „Changing power management limit is not supported" (für ALLE Werte, RC=0, Wert bleibt 150 W).
- EC-cTGP-Weg (TUXEDO `tuxedo_nb02_nvidia_power_ctrl`, EC-Register `0x743/0x744/0x745/0x746`,
  Bit-Maske GENERAL=0x01, DB=0x02, CTGP=0x04): Register sind schreibbar (`ecx write`), aber im
  vfio-Passthrough **wirkungslos** — auch +25-W-Performance-Setup ändert den Power-Draw nicht
  (150 W bleibt), und negative Offsets (0xE7 = -25) werden auf Default geklemmt. Kein NVIDIA-Treiber
  auf dem Host → keine EC↔GPU-Koordination möglich.

**Lösung (im Gast!):** Taktobergrenze per `nvidia-smi -lgc` als praktikables Power-Limit.
Kalibriert bei 100 % GPU-Volllast:

| SM-Takt (Cap) | Power Draw | Temp |
|---|---|---|
| 2055 MHz (ungedeckelt) | ~150 W | 76 °C |
| 1950 MHz | ~132 W | 72 °C |
| 1900 MHz | ~125.6 W | 70 °C |
| 1880 MHz | ~123 W | 69 °C |
| 1800 MHz | ~119 W | 70 °C |
| 1750 MHz | ~110 W | 65 °C |
| 1670 MHz | ~100.1 W | 64 °C |
| 1666 MHz | ~100.1 W | 64 °C |
| **1660 MHz (gewählt)** | **~99.3 W** | 63 °C |
| 1650 MHz | ~99 W | 64 °C |
| 1500 MHz | ~86 W | 67 °C |

**Installation (auf der Gast-VM <guest>):**
```
install -m 0755 gpu-powerlimit.sh /usr/local/sbin/gpu-powerlimit.sh
install -m 0644 gpu-powerlimit.service /etc/systemd/system/
install -m 0644 gpu-powerlimit.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gpu-powerlimit.service gpu-powerlimit.timer
```
- setzt Persistence-Mode (`-pm 1`) + `nvidia-smi -lgc 210,1660` (~99 W).
- läuft einmal beim Boot (Oneshot) und wird vom Timer alle 5 min erneut angewendet (idempotent).

**Hinweis:** Power-Limit ist damit im Gast daemonisiert (nicht am Host möglich — siehe oben).
Das Host-fan-control.service regelt unabhängig weiter.
