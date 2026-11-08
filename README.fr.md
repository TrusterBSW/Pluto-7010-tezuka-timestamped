# Firmware Tezuka horodaté pour le Pluto+ « Fishball » de HamGeek (Zynq 7010 + AD9363)

*[English version: README.md](README.md)*

Firmware Tezuka pour la carte **HamGeek Fishball** (clone Pluto+ : Zynq XC7Z010, AD9363 en LVDS,
1 Go de RAM, Ethernet gigabit, démarrage sur SD), avec :

- l'**horodatage des échantillons RX/TX** dans le FPGA, nécessaire à **srsRAN (4G LTE)** et
  **osmo-trx (2G GSM)**, transmis par **Ethernet gigabit** (pas besoin d'USB) ;
- un **mode éco** qui réduit la chauffe au repos : interface web à la demande, AD9363 en sommeil
  quand aucun logiciel n'est connecté, oscillateur TX coupé quand rien n'émet.

> ⚠️ Uniquement pour la carte Fishball Zynq **7010**. Ne pas l'installer sur un PlutoSDR, un Pluto+,
> une LibreSDR ou une carte 7020.

## Contenu

| Chemin | Rôle |
|---|---|
| `firmware/tezuka-fishball-ts.zip` | image de carte SD (copier le contenu du zip à la racine d'une carte FAT32) |
| `firmware/eco/` | scripts du mode éco (inclus dans l'image), [README](firmware/eco/README.md) |
| `firmware/kernel-cpufreq/` | essai : noyau Tezuka recompilé avec cpufreq (non retenu, pas de gain), [README](firmware/kernel-cpufreq/README.md) |
| `srsran/` | image Docker : srsRAN 4G + SoapyPlutoSDR horodaté, génération de la config |
| `gsm/` | image Docker : osmo-trx-soapy + pile Osmocom, **prête à configurer, rien n'est configuré** |
| `docs/RESEAU-sdr.md` | réseau entre la carte et le PC (ports, pare-feu, réglages) |
| `docs/2G-osmocom.md`, `docs/ECO-energie.md` | notes 2G, mesures du mode éco |

## Contenu de l'image SD

- Noyau et rootfs Tezuka fishball v0.3.24 (F5OEO).
- `system_top.bin` : bitstream construit à partir du maia-sdr de F5OEO (branche `refactor`) **avec
  l'horodatage de Phil Greenland** (compteur 64 bits, cpack/upack horodatés), Maia conservé.
- `system_top_tezuka.bin` : bitstream Tezuka d'origine (sans horodatage).
- Démon `sdr_ip_gadget` (chemin UDP rapide et horodaté).
- Mode éco (`/usr/sbin/eco`, `eco.conf` à la racine de la carte).
- `devicetree.dtb` : devicetree Tezuka avec l'**atténuation TX au maximum (89,75 dB) au démarrage**
  (`adi,tx-attenuation-mdB = <89750>` au lieu de 10 dB) : rien n'est émis tant qu'un logiciel ne règle
  pas le gain TX. L'original est gardé sous `devicetree_orig.dtb`.

Pour revenir au bitstream d'origine, **remplacer** `system_top.bin` par `system_top_tezuka.bin` (en
gardant une copie). Changer `bitstream_image` dans `uEnv.txt` ne suffit pas.

## Démarrage rapide

1. Copier le contenu de `tezuka-fishball-ts.zip` à la racine d'une microSD FAT32, puis démarrer la carte dessus.
2. La carte est en **DHCP** : trouver son adresse dans les baux du routeur (MAC `00:60:88:…`). En cas
   de souci, utiliser la console série sur le port USB du FT2232 (115200 8N1, `root` / `analog`).
3. Conseillé (une seule voie, moins de chauffe) : `ssh root@<ip-carte>` puis `fw_setenv mode 1r1t; reboot`.
4. Vérifier l'horodatage depuis un PC en filaire :
   ```bash
   SoapySDRUtil --probe="driver=plutosdr,hostname=<ip-carte>,direct=1,timestamp_every=1920"
   # attendu : Timestamps: YES
   ```
   Il faut le SoapyPlutoSDR de Phil Greenland (branche `sdr_gadget_timestamping`), déjà inclus
   dans les images Docker.

### 4G (srsRAN)

```bash
cd srsran && docker compose build
PLUTO_IP=<ip-carte> docker compose run --rm srsran probe
PLUTO_IP=<ip-carte> PRB=6 docker compose run --rm srsran all     # EPC + eNB
```
Arguments générés : `driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=1920|3840|5760,loopback=0`
(6 / 15 / 25 PRB). Voir [srsran/README.md](srsran/README.md).

### 2G (osmo-trx)

```bash
cd gsm && docker compose build
PLUTO_IP=<ip-carte> docker compose run --rm gsm probe
PLUTO_IP=<ip-carte> docker compose run --rm gsm test-ts   # bouclage TX→RX horodaté, sans câble
```
Arguments osmo-trx : `driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=2500,loopback=0`.
La pile BTS/BSC/MSC est installée avec des configs d'exemple mais **n'est pas configurée**. Voir
[gsm/README.md](gsm/README.md).

### Règles réseau

PC **en filaire** sur le même réseau local, utiliser l'adresse IP (pas `pluto.local`), autoriser
l'UDP entrant venant de la carte, Docker en `network_mode: host`. Détails dans `docs/RESEAU-sdr.md`.

## Mode éco (actif par défaut)

| | Par défaut |
|---|---|
| Interface web Tezuka/Maia | arrêtée. En SSH : `webui on` / `webui off` |
| AD9363 | en sommeil après 30 s sans client, réveil automatique à la connexion (+~1 s) |
| Oscillateur TX | coupé jusqu'au premier échantillon émis |
| Ethernet | toujours en gigabit. Option 100 Mbit/s au repos : `ETH_ECO`, désactivée |

Mesuré : Zynq **77 °C → 65 °C** au repos (dissipateur cuivre d'origine, sans ventilateur). Les
scripts du tableau de bord d'origine prenaient à eux seuls ~25 % du CPU ; le démon éco en prend
~2,5 %. `eco etat` affiche l'état. Réglages et limites : [firmware/eco/README.md](firmware/eco/README.md).

Essayé puis écarté (aucun gain mesurable) : fréquence CPU 666↔333 MHz pendant le sommeil (noyau
recompilé avec cpufreq) et power-down automatique de la DDR3. Recette et chiffres :
[firmware/kernel-cpufreq/README.md](firmware/kernel-cpufreq/README.md).

## Résultats des tests (2026-11-05 → 08)

- `Timestamps: YES` en RX et en TX, lien gigabit, 2 cœurs CPU.
- Bouclage horodaté (`gsm test-ts`, 10 000 blocs de 1 ms) : **9 999/9 999 blocs RX à 1 ms exactement**, en 1R1T + mode éco.
- Réception par le réseau : ~7,4 Méch/s CS16 au maximum avec horodatage (~30 Mo/s).
- Réception FM identique à celle du bitstream Tezuka d'origine.

## Limites connues

- La latence de bouclage TX→RX est constante pendant une session mais change d'une session à
  l'autre (≈ 70 à 136 échantillons). Non résolu.
- Sans `direct=1`, le pilote passe par iiod : pas d'horodatage (`Timestamps: NO`).
- Les tests en émission réelle se font en cage de Faraday ou en liaison câblée avec atténuateurs.

## Remerciements

- [Firmware Tezuka](https://github.com/F5OEO/tezuka_fw) et fork maia-sdr : F5OEO.
- [Maia SDR](https://maia-sdr.org) : Daniel Estévez.
- HDL d'horodatage, `sdr_ip_gadget` et SoapyPlutoSDR horodaté : Phil Greenland (pgreenland).
- [osmo-trx_soapy](https://github.com/iliasam/osmo-trx_soapy) : iliasam. srsRAN, Osmocom, HDL et Linux d'Analog Devices.

Chaque composant garde sa propre licence.
