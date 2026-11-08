# Mode éco du Fishball

Scripts du mode économie d'énergie, intégrés au ramdisk de `../tezuka-fishball-ts.zip`.
Mesures et détails : [`../../docs/ECO-energie.md`](../../docs/ECO-energie.md).

| Fichier | Sur la carte | Rôle |
|---|---|---|
| `eco` | `/usr/sbin/eco` (+ lien `/usr/sbin/webui`) | commandes et démon de veille |
| `S97eco` | `/etc/init.d/S97eco` | lance `eco boot` au démarrage |
| `eco.conf` | `/boot/eco.conf` (racine de la SD) | réglages, lus au démarrage |

## Par défaut

- Interface web Tezuka/Maia **arrêtée** (`webui on` pour la démarrer).
- AD9363 en **sommeil** quand aucun logiciel n'est connecté depuis 30 s ; réveil automatique à la
  connexion (la connexion prend alors ~1 s de plus).
- Oscillateur TX coupé tant que rien n'émet.
- Ethernet **toujours en gigabit**.
- Flux orphelin : si un logiciel est tué sans envoyer d'ordre d'arrêt (srsRAN coupé brutalement…),
  `sdr_ip_gadget` continuerait d'envoyer le flux RX indéfiniment (jusqu'à 45 Mo/s, 50 % du CPU) et la
  radio ne dormirait plus. Le mode éco le détecte (DMA RX actif sans aucun client iiod pendant
  `ORPH_DELAI` = 10 s) et relance `sdr_ip_gadget`. Vérifié le 2026-11-08 : flux coupé, radio en
  sommeil 30 s plus tard.

## Commandes (SSH `root@<ip-carte>`, mot de passe `analog`)

```
eco etat        # radio, oscillateur TX, veille, Ethernet, interface web, températures
webui on|off    # interface web à la demande
eco pause       # radio réveillée, veille suspendue (pour un logiciel lancé SUR la carte)
eco reprise     # relance la veille
```

Journal : `grep eco: /var/log/messages`.

## Réglages (`eco.conf`)

| Clé | Défaut | Effet |
|---|---|---|
| `WEBUI` | `off` | `on` : interface web démarrée au boot |
| `VEILLE` | `on` | `off` : AD9363 jamais mis en sommeil |
| `DELAI` | `30` | secondes d'inactivité avant le sommeil |
| `TX_ECO` | `on` | `off` : oscillateur TX toujours allumé |
| `ETH_ECO` | `off` | option Ethernet 100 Mbit/s, voir ci-dessous |
| `ETH_DELAI` | `300` | secondes de sommeil avant le passage à 100 Mbit/s |
| `CPU_ECO` | `on` | CPU à 333 MHz pendant le sommeil (seulement avec le noyau cpufreq, sinon sans effet) |
| `ORPH_DELAI` | `10` | secondes de flux RX sans client avant relance de `sdr_ip_gadget` |
| `DDR_ECO` | `off` | DDR3 en power-down automatique pendant le sommeil (essai, gain non mesurable) |

Comportement Tezuka d'origine : `WEBUI=on`, `VEILLE=off`. Prise en compte au redémarrage (ou
`eco pause ; eco reprise` pour la veille).

## Option `ETH_ECO` : Ethernet à 100 Mbit/s pendant le sommeil (désactivée)

Avec `ETH_ECO=on`, une fois la radio endormie depuis `ETH_DELAI` secondes, la carte renégocie son
lien à 100 Mbit/s. À la première demande (connexion iiod, web), elle repasse en gigabit avant de
réveiller la radio.

- Gain mesuré : **≈ 2 °C** sur le Zynq (63,1 °C contre 65,2 °C, le 2026-11-08).
- Chaque changement de vitesse **coupe le lien ~3,2 s** (adresse IP conservée, switch OK aussitôt).
- Après un passage à 100 Mbit/s, la première connexion prend **~4 s**. Or libiio abandonne au bout
  de 5 s : ça passe depuis Linux (vérifié par simulation), mais la marge est faible et rien n'est
  garanti pour Windows ou des logiciels qui ont leur propre délai. En cas d'échec, relancer la
  connexion suffit (le lien est alors revenu en gigabit).
- Les sessions SSH ouvertes ne sont pas coupées (gel de ~3 s), mais le SSH ne fait pas repasser en
  gigabit.

Pour l'essayer : `ETH_ECO=on` dans `eco.conf`, puis `reboot`. Pour revenir : `ETH_ECO=off`.

## Options `CPU_ECO` / `DDR_ECO` (essai, non retenu)

Fréquence CPU 333 MHz et power-down DDR3 pendant le sommeil : testés le 2026-11-08 avec un noyau
cpufreq, sans gain de température mesurable. Voir [`../kernel-cpufreq/README.md`](../kernel-cpufreq/README.md).
