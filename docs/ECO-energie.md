# Mode éco du Fishball : moins de chauffe au repos

Inclus dans `firmware/tezuka-fishball-ts.zip` depuis le 2026-11-07, actif par défaut.
Sources et mode d'emploi : [`firmware/eco/`](../firmware/eco/) ([`README.md`](../firmware/eco/README.md)).

## Ce que ça fait

| Réglage | Effet | Par défaut |
|---|---|---|
| Interface web arrêtée | Tezuka relit tous ses paramètres toutes les 2 s (~56 processus/s, ~25 % du CPU en permanence) ; Maia, MQTT et ces scripts sont arrêtés au démarrage | `WEBUI=off` |
| Veille de l'AD9363 | sans client connecté ni activité pendant `DELAI` s : ENSM `sleep` (synthés RX/TX, ADC/DAC et horloge de données coupés, donc la logique FPGA cadencée par cette horloge s'arrête aussi) | `VEILLE=on`, `DELAI=30` |
| Oscillateur TX | coupé tant qu'aucun échantillon n'est émis, rallumé au premier (≤ 1 s) | `TX_ECO=on` |
| 1 voie (1R1T) | une chaîne RX + une TX au lieu de deux ; horloge de données FPGA 61,44 MHz au lieu de 122,88 | `fw_setenv mode 1r1t` (réglé sur cette carte) |

Mesuré le 2026-11-07 (dissipateur cuivre d'origine, sans ventilateur) : Zynq **77 °C → 67 °C**
en 7 min (web arrêté + AD9363 en sommeil, carte encore en 2R2T). Le démon de veille coûte ~2,5 % du CPU.

## Utilisation (SSH `root@<ip-carte>`, mot de passe `analog`)

```
eco etat        # radio, oscillateur TX, veille, interface web, températures
webui on        # démarre l'interface web Tezuka/Maia (http://<ip-carte>)
webui off       # l'arrête
eco pause       # réveille la radio et suspend la veille (tests en local sur la carte)
eco reprise     # relance la veille
```

Journal : `grep eco: /var/log/messages`.

**Côté PC, rien à changer.** Quand la radio dort, la première connexion (SDR++, CubicSDR,
GQRX, srsRAN, osmo-trx, page web) prend **~1 s de plus** : son premier paquet est ignoré, le
temps du réveil, puis le PC le renvoie tout seul. Raison : l'AD9363 endormi **refuse tous les
réglages** (fréquence, gain, débit → `Invalid argument`), et un logiciel les envoie ~20 ms
après s'être connecté.

La radio reste éveillée tant qu'un logiciel est connecté (iiod 30431, web 80/443, MQTT
9001/9002), même s'il ne reçoit rien ; elle s'endort `DELAI` s après la dernière déconnexion.
Le SSH (port 22) ne la réveille pas.

## Réglages : `eco.conf` à la racine de la carte SD (`/boot/eco.conf` sur la carte)

```
WEBUI=off     # on : interface web démarrée au boot
VEILLE=on     # off : AD9363 jamais mis en sommeil
DELAI=30      # secondes d'inactivité avant sommeil
TX_ECO=on     # off : oscillateur TX toujours allumé
```

Prise en compte au redémarrage (ou `eco pause ; eco reprise` pour VEILLE/DELAI/TX_ECO).
Comportement Tezuka d'origine : `WEBUI=on` et `VEILLE=off`.

Revenir en 2 voies (MIMO, RX2) : `fw_setenv mode 2r2t ; reboot`.

## Vérifié le 2026-11-07

- Mise en sommeil/réveil : mêmes stations FM et mêmes niveaux avant et après ; fréquence, gain
  et débit conservés pendant le sommeil.
- 4 connexions sur 4 pendant le sommeil : réglage du gain accepté, connexion en 1,06 s.
- Client connecté mais inactif 45 s : radio restée éveillée ; endormie 30 s après sa déconnexion.
- Interface web active sans navigateur : radio en sommeil ; ouverture de la page → réveil, page en 1,05 s.
- Chemin horodaté en 1R1T + mode éco (VM, `gsm test-ts`, 3 sessions × 10 000 blocs) : RX
  9 999/9 999 blocs à 1 ms ; latence de bouclage TX→RX constante dans une session (102, 104,
  136 échantillons selon la session, même comportement qu'en 2R2T). `probe` 2G et 4G : `Timestamps: YES`.

## Essayé et écarté (2026-11-07 soir)

- **Repos profond du CPU** (retirer `cpuidle.off=1` des bootargs dans `uEnv.txt`) : le pilote
  `zynq_idle` s'active (états WFI et « RAM_SR », qui dans Linux ne fait en pratique que WFI), mais
  l'émission horodatée se dégrade : 0,7 à 4,6 % de blocs TX en retard (contre 0,1 à 0,2 %), et
  aucun gain de température visible. Remis à l'origine (`cpuidle.off=1`, copie
  `/boot/uEnv.txt.cpuidle-off`). NB : ces 3 essais ont peut-être tourné pendant qu'une autre
  session testait son bitstream edgeQAM sur la carte, à confirmer.
- **Fréquence CPU variable (cpufreq) et power-down DDR3** (essai du 2026-11-08, noyau recompilé) :
  CPU 333 MHz 61,44 °C, 666 MHz 61,62 °C, 333 MHz + DDR power-down 61,15 °C (radio endormie) :
  aucun gain mesurable. Noyau d'origine conservé. Recette et détails :
  [`../firmware/kernel-cpufreq/README.md`](../firmware/kernel-cpufreq/README.md).

## Ethernet à 100 Mbit/s au repos (option `ETH_ECO`, désactivée)

Mesuré le 2026-11-08, carte au repos (radio en sommeil, web arrêté, 1R1T), relevé toutes les
10 s, moyenne après 5 min de stabilisation :

| Lien | Zynq |
|---|---|
| 1 Gbit/s (avant) | 65 °C (relevé au degré) |
| 100 Mbit/s | **63,1 °C** ± 0,4 |
| 1 Gbit/s (après) | **65,2 °C** ± 0,5 |

Gain ≈ **2 °C**. Chaque changement de vitesse coupe le lien **3,2 s** (switch et IP OK aussitôt).
libiio abandonne une connexion au bout de 5 s : le réseau doit revenir en moins de ~4 s après la
première demande (essais 3,5/3,8/4,0 s OK, 4,5 s échec). Avec le retour automatique au gigabit,
on est à ~3,5 s : ça passe depuis Linux, avec une marge faible et sans garantie pour d'autres OS
ou logiciels. D'où l'option désactivée par défaut (`ETH_ECO=on` dans `eco.conf` pour l'essayer ;
passage à 100 Mbit/s après `ETH_DELAI`=300 s de sommeil).

## Autres leviers, non appliqués

- `overclock/BOOT_fsbl_CPU495_DDR396` (sur la SD) : CPU 495 MHz et DDR 396 MHz au lieu de
  666/533, **en permanence** (pas de remontée à l'usage) → écarté : risque de manquer de CPU
  pour le débit du cellulaire.
- Ventilateur 5 V sur le dissipateur : le plus efficace, toujours valable.
- Ne pas utiliser les profils d'overclock CPU950/CPU1100 : la puce est déjà chaude.
