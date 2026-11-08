# srsRAN 4G horodaté pour le Fishball 7010

Image Docker : srsRAN 4G `release_23_04` + SoapySDR 0.8.1 + **SoapyPlutoSDR de Phil Greenland
(branche `sdr_gadget_timestamping`)** + libiio 0.26 / libad9361 0.3. Elle pilote la carte
flashée avec `../firmware/tezuka-fishball-ts.zip` (bitstream horodaté + démon `sdr_ip_gadget`).

## Réseau entre la carte et le PC

Guide complet (DHCP, ports, pare-feu, tampons, console série) :
[`../docs/RESEAU-sdr.md`](../docs/RESEAU-sdr.md). L'essentiel :

- La carte est en **DHCP** : relever son adresse dans les baux du routeur (MAC `00:60:88:…`),
  idéalement la réserver. Dépannage par la console série FT2232 (115 200 bauds, `root`/`analog`).
- Toujours passer **l'IP** dans `PLUTO_IP` (pas `pluto.local`, qui peut pointer vers l'USB).
- Le conteneur est en `network_mode: host` : obligatoire, la carte renvoie les échantillons RX
  en UDP vers un port choisi au hasard par le PC (un NAT Docker les perdrait).
- Pare-feu de l'hôte : accepter l'UDP entrant venant de l'IP de la carte.
- Ce que génère le script (`device_args`) :
  `driver=plutosdr,hostname=<PLUTO_IP>,direct=1,timestamp_every=<1920|3840|5760>,loopback=0`
  (`direct=1` = chemin UDP horodaté via les ports 30432/30433 de la carte).
- Mode éco de la carte (par défaut) : AD9363 en sommeil sans client ; srsenb se connecte
  ~1 s plus tard si la carte dormait, rien à régler. Voir [`../docs/ECO-energie.md`](../docs/ECO-energie.md).

## Où la faire tourner

Sur une machine **branchée en filaire**, sur le même réseau que la carte. srsRAN rejette les
échantillons qui arrivent en retard (fenêtre d'environ 10 ms) : le Wi-Fi du laptop et les
machines virtuelles avec USB passthrough sont déconseillés. Pistes : une VM avec carte réseau
virtio pontée sur le LAN, ou directement un hôte Linux filaire.
Mettre le gouverneur CPU de l'hôte en `performance`.

## Construire

```bash
cd srsran && docker compose build        # ~15 min, image pluto-srsran:ts
```

## Tester, dans l'ordre

```bash
# 1. La carte répond et l'horodatage est actif : chercher « Timestamps: YES »
PLUTO_IP=<ip-carte> docker compose run --rm srsran probe

# 2. Cellule LTE 1,4 MHz (6 PRB), cœur srsepc intégré, PLMN 001/01
cp config/user_db.csv.example config/user_db.csv   # puis mettre IMSI / Ki / OPc de vos SIM
PLUTO_IP=<ip-carte> PRB=6 docker compose run --rm srsran all

# 3. Monter en largeur : PRB=15 (3 MHz), puis PRB=25 (5 MHz, maximum en Ethernet d'après Phil)
```

Variables utiles : `EARFCN` (défaut 1575 = bande 3, DL 1842,5 MHz), `TX_GAIN`/`RX_GAIN`,
`TRANSPORT=usb` (USB direct au lieu d'Ethernet), `MASQ_IF=<iface>` (accès Internet des UE).

| PRB | Largeur | Débit | `timestamp_every` | `prach_freq_offset` |
|---|---|---|---|---|
| 6 | 1,4 MHz | 1,92 MS/s | 1920 | 0 |
| 15 | 3 MHz | 3,84 MS/s | 3840 | 4 |
| 25 | 5 MHz | 7,68 MS/s | 5760 | 4 |

## Avec le cœur open5gs de `~/claude/LTE/docker_open5gs`

Lancer le cœur (MME en 172.22.0.9 dans `.env`), puis l'eNB seul :

```bash
PLUTO_IP=<ip-carte> MME_ADDR=172.22.0.9 ENB_BIND=<ip-hote-joignable-par-le-MME> \
  docker compose run --rm srsran enb
```

Les SIM déjà provisionnées dans open5gs (PLMN 001/01) s'attachent alors sans `user_db.csv`.

## Dépannage (d'après les retours sur l'article Quantulum)

- `Timestamps: NO` : `direct=1` absent des arguments, mauvais bitstream (c'est le fichier `/boot/system_top.bin` qui est chargé ; `bitstream_image` dans `uEnv.txt` n'est pas pris en compte) ou démon absent
  (`ps | grep sdr_ip_gadget` sur la carte).
- « Detected RF gap » ou « Backwards timestamp » : latence réseau ou CPU (VM, Wi-Fi, gouverneur).
- Le téléphone ne voit pas la cellule : écart de fréquence. Mesurer l'erreur (B210 ou autre)
  et régler `xo_correction` dans `config.txt` de la carte, ou utiliser l'entrée 10 MHz.
- Collision PRACH/PUCCH au démarrage : vérifier `prach_freq_offset` pour le PRB choisi.

⚠️ Émission sur bandes cellulaires : cage de Faraday ou liaison câblée avec atténuateurs.

## Charge mesurée et overclock (2026-11-08)

srsRAN `all` sur la VM (filaire), carte en 1R1T, bitstream v3, `TX_GAIN=0`, 90 s par palier
(`charge.sh`). Aucune erreur RF (pas de L/U/O) à 6, 15 et 25 PRB.

| PRB | Débit | CPU de la carte (666 MHz) | CPU (overclock 950/600) | Zynq |
|---|---|---|---|---|
| 6 | 1,92 Méch/s | 53–57 % | – | 67 °C |
| 15 | 3,84 Méch/s | 72–74 % | 60–70 % | 68–70 °C |
| 25 | 5,76 Méch/s | **88–96 %** (limite) | 82–95 % | 70–72 °C (73–77 °C overclocké) |
| 50 | 11,52 Méch/s | ne fonctionne pas (« Unable to set BB rate », flux TX absent) | idem | |

Débit RX maximal horodaté (`SoapySDRUtil --rate`, `direct=1`) : **8,3 Méch/s** à 666/533 MHz,
**11,4 Méch/s** avec le FSBL `overclock/BOOT_fsbl_CPU950_DDR600` (+38 %). Le flux est donc limité
par le CPU de la carte (`sdr_ip_gadget`).

Conclusion : 25 PRB passe sans overclock mais sans marge ; 50 PRB ne passe pas, même overclocké
(il faudrait 11,52 Méch/s en RX **et** en TX, et le réglage du débit échoue). L'overclock (hors
spécifications du Zynq -1 et de la DDR3, +4 à 5 °C) n'est donc pas activé par défaut. Pour
l'essayer : `cp /boot/BOOT.bin /boot/BOOT_orig.bin; cp /boot/overclock/BOOT_fsbl_CPU950_DDR600
/boot/BOOT.bin; sync; reboot` (retour : `BOOT_orig.bin` → `BOOT.bin`).

Correctif inclus dans l'image Docker : `soapy-hostname-first.patch`. Avec `hostname=`, le pilote de
Phil se connecte directement ; sinon son scan réseau (Avahi, absent du conteneur) échouait et
srsRAN, qui énumère les périphériques avant de les ouvrir, ne trouvait pas la carte.
