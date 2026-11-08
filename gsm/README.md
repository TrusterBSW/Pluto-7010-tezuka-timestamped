# 2G (GSM / EDGE) Osmocom pour le Fishball 7010 — logiciel prêt, à configurer

Image Docker `pluto-gsm:ts` : osmo-trx-soapy (iliasam) sur SoapyPlutoSDR horodaté (Phil
Greenland) + pile Osmocom récente (osmo-bts-trx, osmo-bsc, osmo-msc, osmo-hlr, osmo-mgw,
osmo-stp, osmo-pcu, osmo-sgsn, osmo-ggsn). **Aucune configuration active, rien ne démarre seul.**

- Documentation complète (chaîne, liste de ce qu'il faudra configurer, fréquences, ports,
  pièges) : [`../docs/2G-osmocom.md`](../docs/2G-osmocom.md)
- Réseau entre la carte et le PC (DHCP, ports, pare-feu, réglages) :
  [`../docs/RESEAU-sdr.md`](../docs/RESEAU-sdr.md)

## Carte

Carte SD : `../firmware/tezuka-fishball-ts.zip` (bitstream horodaté + démon `sdr_ip_gadget`).
Ethernet en DHCP ; repérer son adresse dans les baux du routeur (MAC `00:60:88:…`) et, idéalement,
la réserver. Console série FT2232 (115 200 bauds, `root` / `analog`) en cas de souci.
Mode éco actif par défaut (AD9363 en sommeil sans client, réveil ~1 s à la connexion ; interface
web : `webui on`) : voir [`../docs/ECO-energie.md`](../docs/ECO-energie.md).

## Construire et vérifier (machine filaire)

```bash
cd gsm
docker compose build                                   # image pluto-gsm:ts
docker compose run --rm gsm versions                   # versions installées
PLUTO_IP=<ip-carte> docker compose run --rm gsm probe  # attendu : « Timestamps: YES » (direct=1)
```

Test de la chaîne horodatée sans réseau GSM : `PLUTO_IP=<ip-carte> docker compose run --rm gsm test-ts`.
Rebouclage **numérique interne** de l'AD9363 (`loopback=1`) : pas de câble nécessaire. Le test
règle l'émetteur sur 800 MHz ; par prudence, mettre d'abord l'atténuation TX au maximum sur la carte
(`echo -89.75 > /sys/bus/iio/devices/iio:device0/out_voltage0_hardwaregain`).
Attendu : `TimeDiff: 1000000` (1 ms entre blocs de 1920 échantillons), « contains TX TS after 1
buffers » ; les 4 premiers blocs sans horodatage TX sont normaux (délai TX de 4 ms).
Validé le 2026-11-05 (bitstream v2) : 10 000 blocs, tous à 1 ms ; 7 blocs TX manqués sur 10 000
depuis la VM (latence réseau/VM). Revalidé le 2026-11-07 (bitstream v3, 1R1T, mode éco) :
3 × 10 000 blocs, RX à 1 ms ; latence TX→RX constante dans une session (102 à 136 échantillons
selon la session).

## Utiliser la carte par le réseau avec osmo-trx

La seule configuration liée à la carte est celle d'osmo-trx-soapy. Modèle fourni dans l'image
(`/usr/share/doc/pluto-gsm/osmo-trx-soapy.cfg.modele`) et ici (`osmo-trx-soapy.cfg.modele`).
Pour s'en servir le moment venu : le copier en `config/osmo-trx-soapy.cfg` et remplir
l'adresse de la carte dans la ligne :

```
dev-args driver=plutosdr,hostname=<ip-carte>,direct=1,loopback=0,timestamp_every=2500
```

- `hostname=<ip-carte>` : utiliser l'IP, pas `pluto.local` (le nom peut pointer vers l'USB).
- `direct=1` : chemin UDP rapide et horodaté (ports 30432/30433 de la carte).
- `timestamp_every=2500` : **ne pas changer**, c'est la taille de bloc du pilote soapy_trx.
- `tx-sps 4` / `rx-sps 4` : 1,0833 Méch/s ; le pilote exige des valeurs égales.

Lancement de la couche radio seule : `docker compose run --rm gsm trx` (attend ensuite
osmo-bts-trx sur le port 5700).

## Exemples fournis (non utilisés)

Dans l'image, `/usr/share/doc/pluto-gsm/` :

| Chemin | Contenu |
|---|---|
| `osmo-trx-soapy.cfg.modele` | modèle TRX pour le Fishball en Ethernet |
| `osmo-trx-soapy.test1.cfg` | config d'origine d'iliasam (USB) |
| `exemples-iliasam/VOICE/` | réseau voix + SMS complet : BTS, BSC, MSC, HLR, MGW, STP + scripts tmux |
| `exemples-iliasam/EDGE/` | même chose + données : PCU, SGSN, GGSN |
| `/etc/osmocom/` | configs d'origine des paquets Osmocom |

**Copie déjà faite dans ce dépôt : [`exemples/`](exemples/)** (dont
`exemples/paquets-osmocom-etc/` = configs d'origine des paquets). Ce ne sont que des
références : rien ne les utilise.

⚠️ Bandes GSM : cage de Faraday ou liaison câblée avec atténuateurs.
