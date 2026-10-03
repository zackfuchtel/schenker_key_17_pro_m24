# SCHENKER KEY 17 Pro M24 — Taming the fans, capping the GPU

> English below. — Deutsch weiter unten.
> *English first, German after. See [Deutsch](#deutsch) for the German section.*

---

## English

### Why this repository exists: TUXEDO Control Center, and its spectacular uselessness on a SCHENKER

SCHENKER and TUXEDO are corporate siblings — both grew up under the same roof (Schenker Technologies).
You would therefore reasonably expect **TUXEDO Control Center**, the vendor's flagship "we handle your
Clevo/TongFang-based hardware" application, to feel right at home on a SCHENKER KEY 17 Pro.

It does not.

On this machine it is the IT equivalent of a **decorative fireplace**: beautifully rendered, full of
confidence, spectacularly inert. Fan curves, performance levels, power profiles — all are acknowledged,
none are applied. The embedded controller listens to exactly one thing: a raw firmware curve uploaded
into its RAM through the ACPI EC ports. Every standard control path (`acpi_fan`, ACPI `_FSL`, `SF1R`,
`DUT`) is met with majestic silence, and the cTGP registers that `tuxedo_nb02_nvidia_power_ctrl` so
eagerly exposes turn into pure decoration the moment the GPU is handed over to a VFIO guest.

So this repository is the community-grade answer for the fan part: a tiny C tool (`ecx`) and a bash
daemon with a firm but honest relationship with the embedded controller. It is the *"kitchen cabinet
assembled with a cordless drill and optimism"* school of system administration — functional,
occasionally loud, and entirely reboot-free.

### Hardware (`nb`, the machine itself)

| What | Detail |
|---|---|
| Notebook | SCHENKER KEY 17 Pro M24 (17″, 2024) |
| Barebone / mainboard | TongFang X370SNx1 |
| Embedded controller | Clevo/TongFang VK35, firmware **VK35GTC**, EC-ID **"LIONVK35"** |
| Cooling | 2 fans, driven by an EC RAM *curve* (not by ACPI fan control) |
| GPU | NVIDIA RTX 4080 Laptop (Max-Q), PCI `10de:27e0`, VFIO-PCI passthrough to a VM |
| EC registers (fan) | curve at `0xFE0B0300` (112 bytes), EC RAM base `0xFE0B0100`, ACPI EC ports `0x62`/`0x66` |
| EC registers (GPU) | cTGP `0x743`–`0x746` (TUXEDO `nb02` mapping) — dead inside VFIO |

### Operating system layout

- **Host:** Proxmox VE (Debian-based). Runs the fan daemon (`fan-control.service`) and `ecx` under `/opt/fanctl/`.
- **Guest VM:** a Linux VM with the NVIDIA driver. Runs the GPU power cap (`gpu-powerlimit.timer`, a
  self-healing systemd unit).

The GPU power limit has to live in the guest; the fan control has to live on the host. Neither works
from the other side — which is why the two pieces are split across both boxes.

### The two problems, and the two fixes

| Problem | Why the obvious fix fails | Solution |
|---|---|---|
| Fan noise / thermals | The EC ignores `acpi_fan`, `_FSL`, `SF1R`, `DUT`; only an EC **curve upload** works | `fan-control.sh` daemon, 5 stages, temperature-driven (host) |
| GPU at ~150 W is too hot / too loud | `nvidia-smi -pl` → *"Changing power management limit is not supported"* (Max-Q fixed TGP); EC cTGP registers are inert in VFIO passthrough | Clock ceiling via `nvidia-smi -lgc` → **~99 W** (guest) |

---

### 1. Fan control (host)

A daemon measures the hottest thermal zone and uploads the matching curve value to the EC.
The EC is not *informed* about the desired RPM — it is *seduced* by a full 112-byte firmware curve.

**Stages (measured, both fans, settled):**

| EC value | Stage | RPM | Purpose |
|---|---|---|---|
| `0x0A` | idle | ~2050 | below 55 °C |
| `0x0F` | lowmid | ~3500 | ≥ 55 °C |
| `0x12` | premid | ~4600 | ≥ 60 °C |
| `0x14` | mid | ~5120 | ≥ 65 °C |
| `0xFF` | max | ~5700 | ≥ 70 °C |

**Full measured curve (for reference):**

| EC | RPM | EC | RPM | EC | RPM |
|---|---|---|---|---|---|
| `0x0A` | ~2050 | `0x10` | ~4110–4400 | `0x13` | ~4660–4720 |
| `0x0B` | ~2300–2500 | `0x11` | ~4310–4370 | `0x14` | ~5070–5130 |
| `0x0C` | ~2600–2670 | `0x12` | ~4490–4620 | `0xFF` | ~5700 |
| `0x0D` | ~2900–2930 | | | | |
| `0x0E` | ~3170–3190 | | | | |
| `0x0F` | ~3400–3580 | | | | |

**Daemon behaviour (`fan-control.sh`):** thresholds `TH_LOWMID=55`, `TH_PREMID=60`, `TH_MID=65`,
`TH_MAX=70`, hysteresis `HYS=4`, poll interval `POLL=15` s.

- Heating: 55/60/65/70 °C → lowmid/premid/mid/max.
- Cooling: max→mid below 66 °C, mid→premid below 61 °C, premid→lowmid below 56 °C, lowmid→idle below 55 °C.
- The daemon re-asserts the curve from the EC RAM read-back, so it also corrects manual overrides.

The standard ACPI fan interfaces (`acpi_fan`, `_FSL`, `SF1R`, `DUT`) are **non-functional** on this
EC — amusingly for a machine whose vendor ships a "control center". Hence `ecx`.

**Manual control:**

```sh
fanctl.sh {idle|lowmid|premid|mid|max|status}
```

**Install (on the Proxmox host `<host>`):**

```sh
install -m 0755 ecx /opt/fanctl/ecx
install -m 0755 fan-control.sh /opt/fanctl/fan-control.sh
install -m 0755 fanctl.sh /opt/fanctl/fanctl.sh
install -m 0644 fan-control.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now fan-control.service
```

Log: `/var/log/fan-control.log`. Logic test: `bash test-decide.sh` (23 cases).

> **Troubleshooting:** an interrupted SSH session can kill the script and leave `fan-control.service`
> inactive — the fans then run uncontrolled. After any remote test, always check
> `systemctl is-active fan-control.service` and restart if needed. Give long-running fan tests a
> generous timeout (≥ 200 s).

---

### 2. GPU power cap (guest, ~99 W)

The RTX 4080 Mobile in this barebone is **Max-Q** with a production-locked TGP:

- `nvidia-smi -pl <value>` → *"Changing power management limit is not supported"* for **every** value
  (exit code 0, value stubbornly stays ~150 W).
- The EC cTGP path (`tuxedo_nb02_nvidia_power_ctrl`, registers `0x743`–`0x746`, bit masks
  GENERAL/DB/CTGP) is **writable but inert** in VFIO passthrough — there is no NVIDIA driver on the
  host to coordinate with the EC, so even a +25 W performance setup changes nothing on the power draw.

**That leaves the clock ceiling** — `nvidia-smi -lgc` — as the only lever that works.

**Calibration (at 100 % GPU load):**

| SM clock (cap) | Power | Temp |
|---|---|---|
| 2055 MHz (uncapped) | ~150 W | 76 °C |
| 1950 MHz | ~132 W | 72 °C |
| 1900 MHz | ~125.6 W | 70 °C |
| 1880 MHz | ~123 W | 69 °C |
| 1800 MHz | ~119 W | 70 °C |
| 1750 MHz | ~110 W | 65 °C |
| 1670 / 1666 MHz | ~100.1 W | 64 °C |
| **1660 MHz (chosen)** | **~99.3 W** | **63 °C** |
| 1650 MHz | ~99 W | 64 °C |
| 1500 MHz | ~86 W | 67 °C |

The SM clock steps in 15 MHz increments; 1660 lands on the 1650 MHz SM cap at ~99.3 W. The sweet spot
between 1666 (→100.1 W) and 1664 (→99.3 W) is exactly there.

**Install (on the guest `<guest>`):**

```sh
install -m 0755 gpu-powerlimit.sh /usr/local/sbin/gpu-powerlimit.sh
install -m 0644 gpu-powerlimit.service /etc/systemd/system/
install -m 0644 gpu-powerlimit.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gpu-powerlimit.service gpu-powerlimit.timer
```

- Sets persistence mode (`-pm 1`) and applies `nvidia-smi -lgc "210,1660"` (~99 W).
- Runs once at boot (Oneshot) and is re-applied by the timer every 5 minutes (idempotent).

Live check: `nvidia-smi -q -d CLOCK,POWER` → SM cap 1650 MHz, draw ~99 W, ~63 °C at full load.

---

### Repository layout

| File | Where it lives |
|---|---|
| `ecx.c` | compiles to `/opt/fanctl/ecx` (host) — ACPI EC access tool |
| `fan-control.sh` | `/opt/fanctl/` (host) — the 5-stage fan daemon |
| `fanctl.sh` | `/opt/fanctl/` (host) — manual fan override |
| `fan-control.service` | `/etc/systemd/system/` (host) |
| `gpu-powerlimit.sh` | `/usr/local/sbin/` (guest) — `lgc` clock cap, `TARGET="1660"` |
| `gpu-powerlimit.service` / `.timer` | `/etc/systemd/system/` (guest) |
| `test-decide.sh` | logic test for the fan decision (runs on the host, sources `fan-control.sh`) |
| `test-idle.sh` / `test-max.sh` | end-to-end EC upload tests, use a scratch `ecx` in `/tmp` |

### Safety & disclaimer

- **No affiliation.** SCHENKER, TUXEDO, Clevo and TongFang are trademarks of their respective owners.
  This is a personal, unaffiliated project.
- **Use at your own risk.** `ecx` writes to EC RAM via `ioperm(0x62/0x66)`; `fan-control.sh` writes a
  112-byte block to `/dev/mem`. Keep the vendor EC parameters in mind, and don't blame the firmware
  if a fan test goes sideways. There is no warranty of any kind.
- Thresholds, targets and clock caps are conservative defaults that were validated on **this** unit —
  re-measure after any thermal/mechanical change.

---

---

# Deutsch

<a name="deutsch"></a>

### Warum dieses Repository existiert: das TUXEDO Control Center und seine spektakuläre Nutzlosigkeit auf einem SCHENKER

SCHENKER und TUXEDO sind Geschwister unter einem Dach (Schenker Technologies) — man dürfte also erwarten,
dass das **TUXEDO Control Center**, die Vorzeige-Anwendung „wir kümmern uns um deine Clevo-/TongFang-Hardware",
auf einem SCHENKER KEY 17 Pro zuhause ist.

Ist es nicht.

Auf diesem Gerät ist es das IT-Pendant zum **Zierkamin**: hübsch gerendert, voller Selbstvertrauen,
spektakulär leistungslos. Lüfterkurven, Performance-Profile, Energieoptionen — alles wird zur Kenntnis
genommen, nichts wird angewendet. Der Embedded Controller hört auf genau eine Sache: eine rohe
Firmware-Kurve, die über die ACPI-EC-Ports in seinen RAM geladen wird. Jeder Standard-Steuerweg
(`acpi_fan`, ACPI `_FSL`, `SF1R`, `DUT`) wird mit majestätischem Schweigen quittiert, und die
cTGP-Register, die `tuxedo_nb02_nvidia_power_ctrl` so eifrig anbietet, werden zur reinen Deko, sobald
die GPU an einen VFIO-Gast verschenkt ist.

Dieses Repository ist daher die Antwort in Eigenbau für den Lüfter-Teil: ein kleines C-Tool (`ecx`) und
ein Bash-Daemon mit einem ehrlichen, wertschätzenden Verhältnis zum Embedded Controller. Es ist die
*„Küchenschrank-mit-Akkuschrauber-und-Optimismus"-Schule* der Systemadministration — funktional,
gelegentlich laut und komplett ohne Reboot.

### Hardware (das `nb` selbst)

| Was | Detail |
|---|---|
| Notebook | SCHENKER KEY 17 Pro M24 (17″, Baujahr 2024) |
| Barebone / Mainboard | TongFang X370SNx1 |
| Embedded Controller | Clevo/TongFang VK35, Firmware **VK35GTC**, EC-ID **"LIONVK35"** |
| Kühlung | 2 Lüfter, gesteuert über eine EC-RAM-*Kurve* (nicht über ACPI-Lüftersteuerung) |
| GPU | NVIDIA RTX 4080 Laptop (Max-Q), PCI `10de:27e0`, VFIO-PCI-Passthrough in eine VM |
| EC-Register (Lüfter) | Kurve bei `0xFE0B0300` (112 Byte), EC-RAM-Basis `0xFE0B0100`, ACPI-EC-Ports `0x62`/`0x66` |
| EC-Register (GPU) | cTGP `0x743`–`0x746` (TUXEDO-`nb02`-Mapping) — in VFIO wirkungslos |

### Betriebssystem-Aufbau

- **Host:** Proxmox VE (Debian-basiert). Läuft der Lüfter-Daemon (`fan-control.service`) samt `ecx` unter `/opt/fanctl/`.
- **Gast-VM:** eine Linux-VM mit NVIDIA-Treiber. Läuft dort das GPU-Leistungslimit
  (`gpu-powerlimit.timer`, eine selbstheilende systemd-Unit).

Das GPU-Leistungslimit muss im Gast leben, die Lüftersteuerung auf dem Host. Keiner von beiden
funktioniert von der jeweils anderen Seite — deshalb sind die zwei Teile über beide Maschinen verteilt.

### Die zwei Probleme und die zwei Lösungen

| Problem | Warum der naheliegende Weg scheitert | Lösung |
|---|---|---|
| Lüfterlautstärke / Thermik | Der EC ignoriert `acpi_fan`, `_FSL`, `SF1R`, `DUT`; nur die EC-**Kurven**-Übertragung wirkt | `fan-control.sh`-Daemon, 5 Stufen, temperaturgetrieben (Host) |
| GPU mit ~150 W zu heiß / zu laut | `nvidia-smi -pl` → *"Changing power management limit is not supported"* (Max-Q, TGP fixiert); EC-cTGP-Register im VFIO-Passthrough inert | Takt-Obergrenze per `nvidia-smi -lgc` → **~99 W** (Gast) |

---

### 1. Lüftersteuerung (Host)

Ein Daemon misst die wärmste Thermal-Zone und lädt den passenden Kurvenwert in den EC. Der EC wird nicht
über die gewünschte Drehzahl *informiert* — er wird durch eine komplette 112-Byte-Firmware-Kurve *verführt*.

**Stufen (gemessen, beide Lüfter, eingeschwungen):**

| EC-Wert | Stufe | RPM | Zweck |
|---|---|---|---|
| `0x0A` | idle | ~2050 | unter 55 °C |
| `0x0F` | lowmid | ~3500 | ≥ 55 °C |
| `0x12` | premid | ~4600 | ≥ 60 °C |
| `0x14` | mid | ~5120 | ≥ 65 °C |
| `0xFF` | max | ~5700 | ≥ 70 °C |

**Komplette Messreihe (Referenz):**

| EC | RPM | EC | RPM | EC | RPM |
|---|---|---|---|---|---|
| `0x0A` | ~2050 | `0x10` | ~4110–4400 | `0x13` | ~4660–4720 |
| `0x0B` | ~2300–2500 | `0x11` | ~4310–4370 | `0x14` | ~5070–5130 |
| `0x0C` | ~2600–2670 | `0x12` | ~4490–4620 | `0xFF` | ~5700 |
| `0x0D` | ~2900–2930 | | | | |
| `0x0E` | ~3170–3190 | | | | |
| `0x0F` | ~3400–3580 | | | | |

**Daemon-Verhalten (`fan-control.sh`):** Schwellen `TH_LOWMID=55`, `TH_PREMID=60`, `TH_MID=65`,
`TH_MAX=70`, Hysterese `HYS=4`, Poll-Intervall `POLL=15` s.

- Aufheizen: 55/60/65/70 °C → lowmid/premid/mid/max.
- Abkühlen: max→mid unter 66 °C, mid→premid unter 61 °C, premid→lowmid unter 56 °C, lowmid→idle unter 55 °C.
- Der Daemon schreibt die Kurve anhand des EC-RAM-Readbacks erneut — er korrigiert dadurch auch manuelle
  Übersteuerungen.

Die Standard-ACPI-Lüfterschnittstellen (`acpi_fan`, `_FSL`, `SF1R`, `DUT`) sind an diesem EC **ohne
Funktion** — amüsant für ein Gerät, dessen Hersteller ein „Control Center" mitliefert. Daher `ecx`.

**Manuelle Steuerung:**

```sh
fanctl.sh {idle|lowmid|premid|mid|max|status}
```

**Installation (auf dem Proxmox-Host `<host>`):**

```sh
install -m 0755 ecx /opt/fanctl/ecx
install -m 0755 fan-control.sh /opt/fanctl/fan-control.sh
install -m 0755 fanctl.sh /opt/fanctl/fanctl.sh
install -m 0644 fan-control.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now fan-control.service
```

Log: `/var/log/fan-control.log`. Logik-Test: `bash test-decide.sh` (23 Fälle).

> **Fehlersuche:** Eine abgerissene SSH-Sitzung kann das Skript beenden und `fan-control.service`
> inaktiv zurücklassen — die Lüfter laufen dann ungeregelt! Nach jedem Remote-Test unbedingt
> `systemctl is-active fan-control.service` prüfen und ggf. neu starten. Lange Lüftertests mit
> großzügigem Timeout (≥ 200 s) ausführen.

---

### 2. GPU-Leistungslimit (Gast, ~99 W)

Die RTX 4080 Mobile in diesem Barebone ist **Max-Q** mit produktionsseitig fixiertem TGP:

- `nvidia-smi -pl <wert>` → *"Changing power management limit is not supported"* bei **jedem** Wert
  (Exit-Code 0, der Wert bleibt stur bei ~150 W).
- Der EC-cTGP-Weg (`tuxedo_nb02_nvidia_power_ctrl`, Register `0x743`–`0x746`, Bit-Masken GENERAL/DB/CTGP)
  ist **schreibbar, aber im VFIO-Passthrough wirkungslos** — auf dem Host gibt es keinen NVIDIA-Treiber,
  der sich mit dem EC koordinieren könnte; selbst ein +25-W-Performance-Setup ändert am Power-Draw nichts.

**Also bleibt die Takt-Obergrenze** — `nvidia-smi -lgc` — als einziger Hebel, der funktioniert.

**Kalibrierung (bei 100 % GPU-Vollast):**

| SM-Takt (Cap) | Leistung | Temp |
|---|---|---|
| 2055 MHz (ungedeckelt) | ~150 W | 76 °C |
| 1950 MHz | ~132 W | 72 °C |
| 1900 MHz | ~125,6 W | 70 °C |
| 1880 MHz | ~123 W | 69 °C |
| 1800 MHz | ~119 W | 70 °C |
| 1750 MHz | ~110 W | 65 °C |
| 1670 / 1666 MHz | ~100,1 W | 64 °C |
| **1660 MHz (gewählt)** | **~99,3 W** | **63 °C** |
| 1650 MHz | ~99 W | 64 °C |
| 1500 MHz | ~86 W | 67 °C |

Der SM-Takt rastet in 15-MHz-Schritten; 1660 landet auf dem 1650-MHz-SM-Cap bei ~99,3 W. Der Übergang
zwischen 1666 (→100,1 W) und 1664 (→99,3 W) liegt exakt dort.

**Installation (auf dem Gast `<guest>`):**

```sh
install -m 0755 gpu-powerlimit.sh /usr/local/sbin/gpu-powerlimit.sh
install -m 0644 gpu-powerlimit.service /etc/systemd/system/
install -m 0644 gpu-powerlimit.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gpu-powerlimit.service gpu-powerlimit.timer
```

- Aktiviert den Persistence-Mode (`-pm 1`) und setzt `nvidia-smi -lgc "210,1660"` (~99 W).
- Läuft einmal beim Boot (Oneshot) und wird vom Timer alle 5 Minuten erneut angewendet (idempotent).

Live-Check: `nvidia-smi -q -d CLOCK,POWER` → SM-Cap 1650 MHz, ~99 W, ~63 °C unter Volllast.

---

### Repo-Aufbau

| Datei | Einsatzort |
|---|---|
| `ecx.c` | kompiliert zu `/opt/fanctl/ecx` (Host) — ACPI-EC-Zugriff |
| `fan-control.sh` | `/opt/fanctl/` (Host) — der 5-Stufen-Lüfter-Daemon |
| `fanctl.sh` | `/opt/fanctl/` (Host) — manuelle Lüfter-Übersteuerung |
| `fan-control.service` | `/etc/systemd/system/` (Host) |
| `gpu-powerlimit.sh` | `/usr/local/sbin/` (Gast) — `lgc`-Taktlimit, `TARGET="1660"` |
| `gpu-powerlimit.service` / `.timer` | `/etc/systemd/system/` (Gast) |
| `test-decide.sh` | Logik-Test der Lüfter-Entscheidung (läuft auf dem Host, sourced `fan-control.sh`) |
| `test-idle.sh` / `test-max.sh` | End-to-End-Tests des EC-Uploads, nutzen ein Scratch-`ecx` in `/tmp` |

### Sicherheit & Haftung

- **Keine Verbindung zum Hersteller.** SCHENKER, TUXEDO, Clevo und TongFang sind Marken ihrer
  jeweiligen Inhaber. Persönliches, unabhängiges Projekt.
- **Nutzung auf eigene Gefahr.** `ecx` schreibt per `ioperm(0x62/0x66)` in EC-RAM;
  `fan-control.sh` schreibt einen 112-Byte-Block nach `/dev/mem`. Hersteller-EC-Parameter beachten —
  und die Firmware nicht verantwortlich machen, wenn ein Lüftertest schiefgeht. Keinerlei Garantie.
- Schwellen, Zielwerte und Taktgrenzen sind konservative, auf **diesem** Gerät validierte Defaults —
  nach jeder thermischen/mechanischen Änderung neu vermessen.
