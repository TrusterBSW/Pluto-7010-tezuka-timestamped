# Noyau Tezuka + cpufreq (essai, non retenu)

Essai du 2026-11-08 : faire varier la fréquence CPU (666 ↔ 333 MHz) pendant la veille de la radio.
**Ça marche, mais sans gain de température mesurable : l'image SD garde le noyau Tezuka d'origine.**
Cette recette reste ici pour qui voudrait refaire l'essai.

## Contenu

| Fichier | Rôle |
|---|---|
| `build.sh` | compile le noyau Tezuka fishball v0.3.24 à l'identique + cpufreq, et le module `maia-sdr.ko` |
| `board.config` | configuration exacte du noyau de la carte (`zcat /proc/config.gz`) |
| `cpufreq.config` | options ajoutées (cpufreq-dt, gouverneurs performance/powersave/ondemand/userspace) |

Même source (ADI linux `bf1d49f` + patchs Tezuka `adi-6.12.y`), même config, même compilateur
(Bootlin gcc 15.1, binutils 2.44), même emballage (`uImage` LZMA, chargé en 0x8000). Le binaire
fait 1,6 Ko de plus que celui de Tezuka. `CONFIG_MODVERSIONS` est actif : les 37 modules (dont
`maia-sdr.ko`, maia-sdr 0.12.0 + patchs Tezuka) doivent être recompilés et ajoutés au ramdisk avec
`/lib/modules/6.12.77`.

Le devicetree de la carte déclare déjà les points de fonctionnement 666 667 et 333 334 kHz à 1,0 V
(pas de changement de tension possible sur le Zynq-7000).

## Utilisation avec le mode éco

Avec ce noyau, `eco` met le CPU en `powersave` (333 MHz) quand la radio s'endort et en
`performance` (666 MHz) avant chaque réveil et sur `eco pause` (`CPU_ECO=on` dans `eco.conf`).
Pendant l'usage (radio réveillée, `eco pause`), le CPU reste à 666 MHz : aucun impact sur le débit
ou l'horodatage. Sans cpufreq dans le noyau, ces commandes ne font rien.

## Résultats (carte au repos, radio endormie, relevé toutes les 10 s, moyenne après 5 min)

| Réglage | Zynq |
|---|---|
| CPU 333 MHz | 61,44 °C ± 0,54 |
| CPU 666 MHz | 61,62 °C ± 0,63 |
| CPU 333 MHz + DDR3 en power-down automatique | 61,15 °C ± 0,36 |

Écarts dans le bruit de mesure. Au repos, les cœurs sont déjà en WFI (horloge coupée) : baisser
leur fréquence ne change presque rien. Le power-down DDR3 (bit 1 de `ddrc_ctrl` 0xF8006000,
`DDR_ECO=on`) soulage surtout la puce mémoire, à côté du Zynq.

Vérifié aussi : démarrage OK, `maia_sdr` chargé, horloge système sans dérive à 333 MHz (chrony
9 ppm), réveil en 1,03 s avec réglage du gain accepté.

La **fréquence de la DDR** ne peut pas changer en marche sur le Zynq : elle est fixée par le FSBL
au démarrage (PLL DDR + calibration). Le FSBL `overclock/BOOT_fsbl_CPU495_DDR396` de Tezuka la
baisse, mais en permanence (CPU compris) : écarté, pour garder la marge CPU du cellulaire.

## Revenir au noyau d'origine

Sur la SD : `uImage_orig` → `uImage` et l'ancien ramdisk → `uramdisk.image.xz` (les modules
recompilés ne se chargent pas dans le noyau d'origine, et inversement).
