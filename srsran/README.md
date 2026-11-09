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

## 50 PRB (10 MHz) : 8 bits + sdr_ip_gadget optimisé (2026-11-08)

```bash
PLUTO_IP=<ip-carte> PRB=50 IP_CS8=1 docker compose run --rm srsran all
```

- `IP_CS8=1` ajoute `ip_cs8=1` aux arguments : le **FPGA** range I et Q sur 8 bits (logique CS8 de
  Tezuka, active quand le canal Q est désactivé), d'où deux fois moins d'octets en DMA et sur le
  réseau, sans calcul sur le CPU de la carte. 8 bits ≈ 48 dB de dynamique : suffisant pour du
  64QAM (srsRAN 4G par défaut), limite pour du 256QAM.
- Nécessite l'image SD v0.2.0 (`sdr_ip_gadget` avec GSO UDP, voir
  [`../firmware/sdr_ip_gadget/README.md`](../firmware/sdr_ip_gadget/README.md)) et le pilote patché
  de cette image Docker (`soapy-ip-cs8.patch`).

Mesures (carte sans overclock, srsRAN sur une VM en filaire, moyenne sur 60 s) :

| | gadget d'origine | gadget v0.2.0 (GSO) |
|---|---|---|
| 25 PRB, 16 bits | cœur 0 74 %, **cœur 1 90 %** (147 blocs en retard / min) | cœur 0 65 %, **cœur 1 72 %** (0 / min) |
| 25 PRB, 8 bits | 48 %, 59 % (4 / min) | **41 %, 51 %** (1 / min) |
| 50 PRB, 8 bits | 75 %, **91 %**, saturé (152 / min) | **66 %, 72 %** (1 / min) |

Charge **réelle** mesurée par un compteur d'inactivité (un thread de priorité minimale par cœur, dont le
nombre d'itérations par seconde est comparé à celui de la carte au repos). Les pourcentages de `top` ou de
`/proc/stat` sont **faux** ici : le noyau compte le temps CPU par échantillonnage à chaque tic de 1 ms
(`CONFIG_TICK_CPU_ACCOUNTING`, `HZ=1000`) et le flux travaille lui aussi par tranches de 1 ms ; selon le
calage des deux horloges, qui dérive lentement, `top` affiche de 18 à 90 % pour la même charge.

50 PRB en 8 bits charge autant que 25 PRB en 16 bits (même trafic réseau). Marge restante à 50 PRB :
~28 % sur le cœur 1.

Débit RX horodaté maximal : 8,3 Méch/s (origine) → 12,2 (GSO, 16 bits) → **17,4 (GSO, 8 bits)**.
L'overclock CPU950/DDR600 de Tezuka (11,4 Méch/s avec le gadget d'origine, +4 à 5 °C, hors
spécifications) n'est plus utile et reste désactivé.

Pièges rencontrés :
- srsRAN arrêté (même proprement) n'envoie pas l'ordre d'arrêt du flux : `sdr_ip_gadget` continue
  d'émettre. Le mode éco le coupe au bout de 2 min (`ORPH_DELAI`). Un nouveau srsRAN lancé pendant
  ce flux orphelin démarre mal (« Unable to set BB rate », pas d'émission) : attendre, ou relancer
  le gadget (`/etc/init.d/S55sdr_ip_gadget restart`).
- `TX_GAIN=0` = atténuation maximale (srsRAN affiche alors « TX gain was not set »).

## Correctifs du pilote SoapyPlutoSDR (dans l'image Docker)

| Patch | Rôle |
|---|---|
| `soapy-hostname-first.patch` | avec `hostname=`, connexion directe (le scan « ip » passe par Avahi, absent du conteneur : srsRAN ne trouvait pas la carte) |
| `soapy-ip-cs8.patch` | argument `ip_cs8=1` : 8 bits convertis par le FPGA (canal 0 seul, horodatage sur 4 échantillons, `timestamp_every`/4) |
| `soapy-bbrate-log.patch` | code d'erreur et débit dans « Unable to set BB rate » |

Le pilote est compilé après srsRAN dans le Dockerfile : changer un patch ne recompile pas srsRAN.
