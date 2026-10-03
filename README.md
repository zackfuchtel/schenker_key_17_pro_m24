# schenker_key_17_pro_m24

Verwaltung des Proxmox-Hosts SCHENKER KEY 17 Pro M24 (EC VK35GTC / LIONVK35, TongFang X370SNx1).

## Fan control (Host, Proxmox)

Lüfterkurve per EC-Kurven-Upload. Siehe `fan-control.sh`, `fan-control.service`, `ecx`, `fanctl.sh`.
Installiert unter `/opt/fanctl/`, Unit `fan-control.service` (enabled). Log: `/var/log/fan-control.log`.

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
