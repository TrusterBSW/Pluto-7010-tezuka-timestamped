# Tezuka timestamped firmware for the HamGeek "Fishball" Pluto+ (Zynq 7010 + AD9363)

*[Version française : README.fr.md](README.fr.md)*

Tezuka firmware build for the **HamGeek Fishball** board (Pluto+ clone: Zynq XC7Z010, AD9363 over
LVDS, 1 GB RAM, gigabit Ethernet, SD boot), with:

- **RX/TX sample timestamping** in the FPGA, as needed by **srsRAN (4G LTE)** and **osmo-trx
  (2G GSM)**, streamed over **gigabit Ethernet** (no USB needed);
- an **eco mode** that cuts idle heat: web UI on demand, AD9363 put to sleep when no client is
  connected, TX oscillator off when nothing transmits.

> ⚠️ Only for the Fishball Zynq **7010** board. Do not flash it on a PlutoSDR, Pluto+, LibreSDR or a
> 7020 board.

## Contents

| Path | What |
|---|---|
| `firmware/tezuka-fishball-ts.zip` | SD card image (copy the zip contents to the root of a FAT32 card) |
| `firmware/eco/` | eco mode scripts (included in the image), [README](firmware/eco/README.md) |
| `firmware/kernel-cpufreq/` | experiment: Tezuka kernel rebuilt with cpufreq (not used, no gain), [README](firmware/kernel-cpufreq/README.md) |
| `srsran/` | Docker image: srsRAN 4G + timestamped SoapyPlutoSDR, config generator |
| `gsm/` | Docker image: osmo-trx-soapy + Osmocom stack, **ready to configure, nothing configured** |
| `docs/RESEAU-sdr.md` | network setup between the board and the PC (ports, firewall, tuning) |
| `docs/2G-osmocom.md`, `docs/ECO-energie.md` | 2G notes, eco mode measurements |

Docs are in French; commands and config snippets are universal.

## What's in the SD image

- Tezuka fishball v0.3.24 (F5OEO) kernel and rootfs.
- `system_top.bin`: bitstream built from F5OEO's maia-sdr (`refactor` branch) **plus Phil
  Greenland's timestamping** (64-bit sample counter, timestamped cpack/upack), Maia kept.
- `system_top_tezuka.bin`: original Tezuka bitstream (no timestamps).
- `sdr_ip_gadget` daemon (fast UDP sample path, timestamped).
- Eco mode (`/usr/sbin/eco`, `eco.conf` at the root of the card).
- `devicetree.dtb`: Tezuka devicetree with **TX attenuation at maximum (89.75 dB) at boot**
  (`adi,tx-attenuation-mdB = <89750>` instead of 10 dB), so nothing is emitted until a program sets the
  TX gain. The original is kept as `devicetree_orig.dtb`.

To go back to the stock bitstream, **replace** `system_top.bin` with `system_top_tezuka.bin` (keep a
copy). Changing `bitstream_image` in `uEnv.txt` is not enough.

## Quick start

1. Copy the contents of `tezuka-fishball-ts.zip` to the root of a FAT32 microSD card and boot the board from it.
2. The board uses **DHCP**; find its address in your router leases (MAC `00:60:88:…`). For
   troubleshooting, use the serial console on the FT2232 USB port (115200 8N1, `root` / `analog`).
3. Recommended: single channel, less heat: `ssh root@<board-ip>` then `fw_setenv mode 1r1t; reboot`.
4. Check timestamping from a wired PC:
   ```bash
   SoapySDRUtil --probe="driver=plutosdr,hostname=<board-ip>,direct=1,timestamp_every=1920"
   # expect: Timestamps: YES
   ```
   This needs Phil Greenland's SoapyPlutoSDR (`sdr_gadget_timestamping` branch), which is already
   included in the Docker images.

### 4G (srsRAN)

```bash
cd srsran && docker compose build
PLUTO_IP=<board-ip> docker compose run --rm srsran probe
PLUTO_IP=<board-ip> PRB=6 docker compose run --rm srsran all     # EPC + eNB
```
Device args generated: `driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=1920|3840|5760,loopback=0`
(6 / 15 / 25 PRB). See [srsran/README.md](srsran/README.md).

### 2G (osmo-trx)

```bash
cd gsm && docker compose build
PLUTO_IP=<board-ip> docker compose run --rm gsm probe
PLUTO_IP=<board-ip> docker compose run --rm gsm test-ts   # timestamped TX→RX loopback, no cable
```
osmo-trx device args: `driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=2500,loopback=0`.
The BTS/BSC/MSC stack is installed with example configs but **not configured**. See [gsm/README.md](gsm/README.md).

### Network rules

Use a **wired** PC on the same LAN, use the IP address (not `pluto.local`), allow incoming UDP from
the board, and run Docker with `network_mode: host`. Details in `docs/RESEAU-sdr.md`.

## Eco mode (on by default)

| | Default |
|---|---|
| Tezuka/Maia web UI | stopped. Use `webui on` / `webui off` over SSH |
| AD9363 | sleeps after 30 s without any client and wakes up automatically on connection (+~1 s) |
| TX oscillator | off until the first TX sample |
| Ethernet | always gigabit. Optional 100 Mbit/s while idle: `ETH_ECO`, off by default |

Measured: Zynq **77 °C → 65 °C** at idle (stock copper heatsink, no fan). The stock dashboard
scripts alone used ~25 % CPU; the eco daemon uses ~2.5 %. `eco etat` shows the state. All
settings and caveats: [firmware/eco/README.md](firmware/eco/README.md).

Also tried and dropped (no measurable gain): CPU frequency scaling 666↔333 MHz during sleep
(rebuilt kernel with cpufreq) and DDR3 auto power-down. Recipe and numbers:
[firmware/kernel-cpufreq/README.md](firmware/kernel-cpufreq/README.md) (French).

## Test results (2026-11-05 → 08)

- `Timestamps: YES` on RX and TX, gigabit link, 2 CPU cores.
- Timestamped loopback (`gsm test-ts`, 10,000 blocks of 1 ms): **9,999/9,999 RX blocks at exactly 1 ms**, 1R1T + eco mode.
- RX over the network: ~7.4 MS/s CS16 max with timestamps (~30 MB/s).
- FM reception identical to the stock Tezuka bitstream.

## Known limitations

- The TX→RX loopback latency is constant within a session but changes between sessions (≈ 70–136
  samples). Not solved yet.
- Without `direct=1`, the driver goes through iiod: no timestamps (`Timestamps: NO`).
- Over-the-air tests must be done in a Faraday cage or over cable with attenuators.

## Credits

- [Tezuka firmware](https://github.com/F5OEO/tezuka_fw) and the maia-sdr fork: F5OEO.
- [Maia SDR](https://maia-sdr.org): Daniel Estévez.
- Timestamping HDL, `sdr_ip_gadget` and timestamped SoapyPlutoSDR: Phil Greenland (pgreenland).
- [osmo-trx_soapy](https://github.com/iliasam/osmo-trx_soapy): iliasam. srsRAN, Osmocom, Analog Devices HDL/Linux.

Each component keeps its own license.
