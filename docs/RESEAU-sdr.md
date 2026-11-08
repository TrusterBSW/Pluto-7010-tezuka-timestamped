# Utiliser le Fishball par le réseau (srsRAN, osmo-trx, OpenBTS-UMTS, outils SDR)

Valable pour la carte démarrée avec `firmware/tezuka-fishball-ts.zip` (Tezuka fishball v0.3.24
+ bitstream horodaté + démon `sdr_ip_gadget`). Commun à `srsran/` (4G), `gsm/` (2G) et `umts/` (3G, voir `docs/3G-openbts-umts.md`).

## 1. Comment les données circulent

| Flux | Côté carte | Côté PC | Utilisé par |
|---|---|---|---|
| Contrôle de l'AD9363 (libiio / iiod) | TCP **30431** | port quelconque | tous (fréquence, gain, débit) |
| Contrôle du streaming horodaté | UDP **30432** | port quelconque | SoapyPlutoSDR `direct=1` |
| Échantillons TX (PC → carte) | UDP **30433** | port quelconque | SoapyPlutoSDR `direct=1` |
| Échantillons RX (carte → PC) | port quelconque | **UDP éphémère choisi par le PC** | SoapyPlutoSDR `direct=1` |
| Interface web Tezuka / Maia | TCP 80 / 443, MQTT 9001 | navigateur | réglages, spectre (arrêtée par défaut : `webui on`) |
| SSH | TCP 22 (`root` / `analog`) | | administration |

`direct=1` = le chemin rapide de Phil Greenland : les échantillons ne passent plus par iiod mais
par UDP (paquets de 1 472 octets, MTU 1 500 ; pas de trames jumbo, le contrôleur Ethernet du
Zynq ne les gère pas). L'horodatage n'existe que sur ce chemin.

## 2. Adresse de la carte : DHCP

La carte reste en **DHCP** (comportement par défaut de Tezuka) : laisser `ipaddr_eth` **vide**
dans `config.txt` (le renseigner passerait la carte en IP fixe). Pas d'IP de secours.

- **Retrouver l'adresse** : baux DHCP du routeur (par exemple, sur OpenWrt : `/tmp/dhcp.leases`). La MAC de la carte commence par `00:60:88` (dérivée de son numéro de série).
- **Conseillé : réservation DHCP** de cette MAC sur le routeur, pour que l'adresse ne change
  pas d'un démarrage à l'autre (srsRAN et osmo-trx sont configurés avec l'IP).
- **Nom d'hôte** : `hostname = …` dans `config.txt` (annoncé en DHCP et en mDNS).

### Dépannage : console série

Le port USB relié au **FT2232** de la carte donne la console Linux, même sans réseau :

```bash
picocom -b 115200 /dev/ttyUSB1      # ou : screen /dev/ttyUSB1 115200
# login : root / analog ; puis par ex. « ip -br addr », « fw_printenv », « reboot »
```

Le FT2232 crée deux ports : la console est en général le second (`/dev/ttyUSB1`), le premier
sert au JTAG. Réglages : 115 200 bauds, 8N1, sans contrôle de flux.

## 3. Règles côté PC

1. **Filaire et même réseau local que la carte.** Pas de Wi-Fi, pas de passage par un tunnel
   WireGuard ou un routeur entre sites : srsRAN et osmo-trx jettent les échantillons en retard
   (fenêtre de l'ordre de 10 ms). Lien gigabit à vérifier : `ethtool <iface> | grep Speed`.
2. **Utiliser l'IP, pas `pluto.local`.** Si la carte est aussi branchée en USB, le nom mDNS peut
   pointer vers l'adresse USB (192.168.2.1) et tout passe alors par l'USB (problème vu par Phil).
3. **Pare-feu** : autoriser l'UDP entrant venant de l'IP de la carte (le port RX est choisi au
   hasard par le PC). Exemple nftables/iptables :
   `iptables -I INPUT -s <ip-carte> -p udp -j ACCEPT`.
4. **Docker en `network_mode: host`** (déjà le cas dans les deux `docker-compose.yml`) : un NAT
   Docker casserait le retour des échantillons RX vers le port éphémère.
5. **Gouverneur CPU** de l'hôte en `performance`
   (`cpupower frequency-set -g performance`, ou écrire dans `scaling_governor`).
6. **Tampons de sockets** (recommandation, le pilote ne règle pas lui-même `SO_RCVBUF`) :
   ```bash
   sysctl -w net.core.rmem_default=8388608 net.core.rmem_max=33554432
   sysctl -w net.core.wmem_default=8388608 net.core.wmem_max=33554432
   ```
7. **Machine virtuelle** : possible (la VM `fpga-build` est en virtio pontée sur `vmbr0`), mais
   en cas d'erreurs « RF gap » / « backwards timestamp », réessayer sur une machine physique.

## 4. Vérifier, dans l'ordre

```bash
ping -c 3 <ip-carte>
iio_info -u ip:<ip-carte> | head          # l'AD9361/AD9363 et les cœurs DMA apparaissent
SoapySDRUtil --probe="driver=plutosdr,hostname=<ip-carte>,direct=1,timestamp_every=1920"   # « Timestamps: YES »
# (sans direct=1, le pilote passe par iiod et affiche « Timestamps: NO » : normal)
```

Dans les images Docker : `PLUTO_IP=<ip-carte> docker compose run --rm srsran probe` (4G) ou
`… gsm probe` (2G). La 2G a aussi `… gsm test-ts` (boucle TX → RX horodatée, rebouclage numérique interne
de l'AD9363, sans câble).

## 5. Arguments Soapy du mode réseau horodaté

`driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=<N>,loopback=0`

| Argument | Rôle |
|---|---|
| `hostname=<ip>` | carte par le réseau (sans lui : recherche en USB) |
| `direct=1` | chemin UDP rapide de `sdr_ip_gadget` (sinon iiod, lent et sans horodatage) |
| `usb_direct=1` | équivalent par l'USB (démon USB de Phil, **non inclus** dans notre image SD) |
| `timestamp_every=N` | un horodatage tous les N échantillons ; doit correspondre à la taille de bloc du logiciel : srsRAN 1920 / 3840 / 5760 (6 / 15 / 25 PRB), osmo-trx-soapy **2500** |
| `loopback=0` | boucle numérique interne de l'AD9363 désactivée |

## 6. Mode de la carte, deux voies, mode éco

Cette carte est réglée en **1 émetteur / 1 récepteur** (`fw_setenv mode 1r1t`, moins de
chauffe), ce qui suffit pour la 2G et la 4G en 1×1. Pour les deux voies : `fw_setenv mode 2r2t ; reboot`.

**Mode éco** (actif par défaut) : interface web arrêtée (`webui on` en SSH pour l'avoir) et
AD9363 en sommeil quand aucun logiciel n'est connecté. Rien à changer côté PC ; une connexion
pendant le sommeil prend ~1 s de plus. Ethernet toujours en gigabit (option 100 Mbit/s au repos
disponible mais désactivée, voir [`../firmware/eco/README.md`](../firmware/eco/README.md)). Détails : [`ECO-energie.md`](ECO-energie.md).

## 7. Outils SDR « classiques » depuis un laptop

Pour écouter ou analyser (pas pour la 2G/4G), le chemin iiod standard suffit :
`SoapySDRUtil --find`, SDR++, GQRX (Soapy), SDRangel… avec l'URI `ip:<ip-carte>`. Les forks de
F5OEO (SDR++, SoapyPlutoPAPR, SatDump) savent utiliser le **mode 8 bits** de Tezuka (≈ 2 fois
plus de largeur). L'interface web **Maia** (`http://<ip-carte>`, après `webui on` en SSH) affiche spectre et cascade
jusqu'à 61,44 MHz calculés dans le FPGA, sans streaming d'IQ : utilisable même en Wi-Fi.
