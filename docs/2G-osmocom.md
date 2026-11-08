# 2G (GSM / EDGE) avec le Fishball 7010 — logiciel prêt, configuration à faire

État au 2026-11-05 : **logiciel installé et prêt à être configuré, rien n'est configuré.**
Aucune BTS, aucun BSC ni cœur réseau n'a été paramétré (à la demande : pas encore de cœur).
Couche radio testée le 2026-11-05 (probe, débit RX, boucle horodatée) ; la pile GSM, elle, n'est pas configurée.

## 1. Chaîne complète

```
 Fishball 7010 (SD tezuka-fishball-ts)          PC / VM Linux filaire (image pluto-gsm:ts)
 ┌───────────────────────────────┐   UDP    ┌─────────────────────────────────────────────┐
 │ AD9363 ─ FPGA horodaté ─ DMA  │◄────────►│ SoapyPlutoSDR (pgreenland, horodaté)         │
 │ sdr_ip_gadget (Phil Greenland)│ Ethernet │   └ osmo-trx-soapy  (couche 1 : burst IQ)    │
 └───────────────────────────────┘          │       └ osmo-bts-trx (couche 2 / Abis)       │
                                            │           └ osmo-bsc (RAN) ─── osmo-mgw (RTP)│
                                            │               └ osmo-stp (SIGTRAN/M3UA)      │
                                            │                   └ osmo-msc ── osmo-hlr      │  ← « cœur »
                                            │  Données (EDGE) : osmo-pcu ─ osmo-sgsn ─ osmo-ggsn
                                            └─────────────────────────────────────────────┘
```

- **Couche radio** (liée à la carte) : firmware horodaté + `sdr_ip_gadget` sur la carte,
  `SoapyPlutoSDR` (branche `sdr_gadget_timestamping`) + `osmo-trx-soapy` côté PC.
- **BTS** : `osmo-bts-trx` parle à osmo-trx (TRXC/TRXD) et au BSC (Abis/IPA).
- **RAN** : `osmo-bsc` gère la cellule (ARFCN, canaux, puissance) ; `osmo-mgw` relaie la voix.
- **Cœur circuit** : `osmo-stp` (transport de signalisation), `osmo-msc` (appels/SMS),
  `osmo-hlr` (abonnés). **Absent pour l'instant chez l'utilisateur** : l'image contient les
  paquets, mais rien n'est configuré.
- **Cœur paquets (EDGE/GPRS)** : `osmo-pcu` (à côté de la BTS), `osmo-sgsn`, `osmo-ggsn` (TUN + NAT).

## 2. Ce qui est prêt

Dossier `~/claude/pluto-dvb/gsm/` (copie sur la VM `fpga-build`, `~/gsm/`) :

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Ubuntu 24.04 + dépôt Osmocom « latest » + libad9361 0.3 + SoapyPlutoSDR horodaté + osmo-trx-soapy |
| `docker-compose.yml` | réseau de l'hôte, privilégié, `./config` monté sur `/config` (vide) |
| `entrypoint.sh` | modes `aide`, `versions`, `probe`, `test-ts`, `trx`, `shell` ; ne lance rien seul |
| `osmo-trx-soapy.cfg.modele` | modèle de la seule config liée à la carte (couche radio) |
| `config/` | vide : y mettre les futurs `.cfg` |

Dans l'image, non utilisés : `/usr/share/doc/pluto-gsm/exemples-iliasam/{VOICE,EDGE}` (configs
complètes de l'auteur qui a fait marcher la 2G sur PlutoSky 7020) et `/etc/osmocom/` (configs
d'origine des paquets).

Image construite sur la VM : `pluto-gsm:ts` (voir `docker compose run --rm gsm versions`).

## 3. Tester la couche radio sans cœur (aucune configuration réseau nécessaire)

Prérequis : carte démarrée avec `firmware/tezuka-fishball-ts.zip`, en Ethernet, sur une machine
**filaire** (pas le laptop en Wi-Fi). Les commandes se lancent dans `~/gsm` sur la VM.

1. **La carte répond, l'horodatage est actif** :
   `PLUTO_IP=<ip> sudo -E docker compose run --rm gsm probe` → chercher **`Timestamps: YES`**.
2. **Boucle émission → réception horodatée** (outil de Phil) : rebouclage **numérique interne**
   de l'AD9363 (`loopback=1`), sans câble. Par prudence (le test règle l'émetteur sur 800 MHz),
   atténuation TX au maximum sur la carte, puis
   `PLUTO_IP=<ip> sudo -E docker compose run --rm gsm test-ts`. ✅ validé le 2026-11-05.
   Attendu : des lignes `Samples: 1920 … TimeDiff: 1000000` (1 ms entre blocs) ; les premiers
   blocs manquent normalement (délai TX de 4 ms).
3. **osmo-trx seul** : copier le modèle en `config/osmo-trx-soapy.cfg`, remplir
   `hostname=<ip>`, puis `… run --rm gsm trx`. osmo-trx doit ouvrir la carte, régler
   1,0833 Méch/s et attendre la BTS sur le port 5700. Aucune émission tant que la BTS n'a
   pas démarré la cellule.

## 4. Ce qu'il faudra configurer plus tard (liste de contrôle)

Valeurs de référence = celles d'iliasam (exemples fournis), **à adapter**.

| Composant | Paramètres à fixer | Référence iliasam |
|---|---|---|
| osmo-trx-soapy | `dev-args` (`hostname=`, `timestamp_every=2500` impératif), `tx-sps`=`rx-sps`=4 | `test1.cfg` non modifié |
| osmo-bts-trx | adresses osmo-trx, `osmotrx tx-attenuation` (puissance), `band`, `ipa unit-id`, `oml remote-ip` (BSC) | `tx-attenuation 10`, `GSM900`, `unit-id 901 0` |
| osmo-bsc | **PLMN** (MCC/MNC), **bande et ARFCN**, LAC, `nominal power`, plan des 8 timeslots, codecs, adresse MGW et STP | 250/07, ARFCN 100, LAC 13415, TS0 CCCH+SDCCH4, TS1 SDCCH8, TS2-7 TCH/F |
| osmo-stp | routage M3UA BSC ↔ MSC | config par défaut |
| osmo-msc | PLMN, `authentication optional` ou obligatoire, adresse HLR (GSUP), MGW, SMS | `authentication optional` |
| osmo-hlr | base `hlr.db` (`osmo-hlr-db-tool create`), création d'abonnés, USSD | `subscriber-create-on-demand`, `*#100#` → numéro |
| osmo-mgw | IP RTP | 127.0.0.1 |
| EDGE : osmo-pcu, osmo-sgsn, osmo-ggsn | `gprs mode egprs` côté BSC, NSEI/NSVC, APN, `tun-device`, plage IP, DNS | voir `exemples-iliasam/EDGE` |

Ordre de démarrage (scripts d'iliasam) : osmo-hlr → osmo-stp → osmo-msc → osmo-mgw → osmo-bsc,
puis osmo-bts-trx et osmo-trx-soapy.

Fréquences : GSM-900 : DL = 935,0 + 0,2 × ARFCN MHz (ARFCN 1-124), UL = DL − 45 MHz.
DCS-1800 : DL = 1805,2 + 0,2 × (ARFCN − 512) MHz (512-885), UL = DL − 95 MHz. **Vérifier au
préalable que le canal est libre** (Maia sur la carte suffit pour regarder).

PLMN : pour réutiliser les SIM déjà programmées pour la 4G (`~/claude/LTE`), prendre **001/01**
et renseigner leurs IMSI/Ki/OPc dans osmo-hlr (ou `authentication optional` pour un premier essai).

Ports par défaut utiles : TRX 5700-5702 (UDP), Abis/IPA 3002-3003, M3UA 2905, MGCP 2427,
GSUP 4222 ; VTY (telnet) : osmo-trx 4237, osmo-stp 4239, osmo-pcu 4240, osmo-bts 4241,
osmo-bsc 4242, osmo-mgw 4243, osmo-sgsn 4245, osmo-msc 4254, osmo-hlr 4258, osmo-ggsn 4260.

## 5. Points d'attention

- **Horodatage en LVDS** : sur la PlutoSky, l'horloge `l_clk` vaut 4× la fréquence
  d'échantillonnage ; iliasam a dû diviser son compteur par 4. Notre bitstream compte les
  échantillons valides (même strobe que le packer) : ce piège est évité par construction,
  à confirmer par le test de boucle (section 3.2).
- **Bas débit** : 1,0833 Méch/s est sous le minimum direct de l'AD9363 (2,083 Méch/s) ;
  libad9361 active alors les filtres FIR de décimation/interpolation (géré par SoapyPlutoSDR).
- **Fréquence** : TCXO 0,5 ppm ≈ 450 Hz d'erreur à 900 MHz, toléré par les téléphones chez
  iliasam. Sinon corriger `xo_correction` dans `config.txt` de la carte ou utiliser l'entrée 10 MHz.
- **Latence** : machine filaire, gouverneur CPU `performance`. iliasam a eu des résultats faux en
  machine virtuelle avec USB ; en Ethernet virtio c'est à vérifier.
- **Puissance** : `tx-attenuation` élevée au départ (iliasam : 60 dB ≈ −30 dBm).
- **Versions** : paquets Osmocom récents (osmo-bsc 1.15, osmo-bts 1.12, libosmocore 1.14), mais
  `osmo-trx-soapy` est basé sur osmo-trx 1.4.1 (2022). Le protocole TRX est compatible ; en cas de
  souci, porter le dossier `Transceiver52M/device/soapy_trx` sur un osmo-trx récent.
- **EDGE chez iliasam** : ping 1,5 à 4 s, montée ≈ 5 kbit/s, MSS à limiter à 400 (iptables TCPMSS).
- **Légal** : bandes GSM réservées ; cage de Faraday ou liaison câblée avec atténuateurs.

## 6. Alternatives notées

- `~/claude/LTE/docker_open5gs` contient déjà des services `osmomsc` et `osmohlr` (avec open5gs) :
  piste pour le futur cœur 2G, partagé avec la 4G.
- osmo-trx directement sur l'ARM du Zynq (`osmo-trx-pluto`, discussion Osmocom
  « plutosdr-zynq-ad9361-osmo-trx ») : le reste de la station tournerait ailleurs.

## 7. Références

- Article iliasam (Habr, russe) : https://habr.com/ru/articles/1017672/ et suite CSD :
  https://habr.com/ru/articles/1039636/
- osmo-trx Soapy : https://github.com/iliasam/osmo-trx_soapy (configs : branche `my_tests`,
  dossier `Osmocom_configs`)
- SoapyPlutoSDR horodaté : https://github.com/pgreenland/SoapyPlutoSDR/tree/sdr_gadget_timestamping
- Paquets Osmocom : https://osmocom.org/projects/cellular-infrastructure/wiki/Binary_Packages
- Réseau complet Osmocom : https://osmocom.org/projects/cellular-infrastructure/wiki/Osmocom_Network_In_The_Box
- Manuel OsmoTRX : https://ftp.osmocom.org/docs/latest/osmotrx-usermanual.pdf
- Docker 2G/4G Pluto (DAST) : https://github.com/SitrakaResearchAndPOC/osmobts_allsdr_docker
- Article Quantulum (4G, commentaires 2G) : https://www.quantulum.co.uk/blog/private-lte-with-plutoplus-sdr/
