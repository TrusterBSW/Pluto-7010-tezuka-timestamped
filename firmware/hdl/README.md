# Correctifs FPGA : émission 8 bits (`ip_cs8=1`) et voie TX2

Bitstream **v5** (`system_top.bin` du zip depuis le 2026-11-27) = v3 + les deux patches de ce dossier.
Sources : maia-sdr (F5OEO), branche `refactor` fbc289b + horodatage (branche `fishball-ts-ref`) +
`0001-…patch` (v4) + `0002-…patch` (v5). Le patch `axi_ad9361` (`maia-hdl/patches/adi-hdl/`) s'applique
dans le sous-module `adi-hdl` (`patch -p1`).

## Défauts corrigés

**v4 : émission 8 bits de la voie 1** (le cas `ip_cs8=1` de srsRAN). Le pilote n'active que le canal I et range
I et Q sur 8 bits dans le même mot de 16 bits ; le FPGA (logique CS8 de Tezuka) doit séparer les deux octets.
- `system_bd.tcl` choisissait le chemin 8 bits quand **I** était coupé (`din_enable_0`) au lieu de **Q**
  (`din_enable_1`), alors que la réception (`dout_enable_1`) teste bien Q : le chemin 8 bits n'était jamais pris ;
- le canal Q, absent du masque, était mis par le pilote noyau sur la source DDS, désactivée dans ce design
  (`DAC_DDS_DISABLE`) : Q sortait à zéro. Le patch `axi_ad9361` fait suivre à Q0 la donnée DMA quand I0 est seul
  actif (`dac_force_dma`).

Effet en v3 : le DAC recevait I = mot `{I8,Q8}` lu comme un seul nombre et Q = 0. Le signal émis était réel, avec
une image miroir aussi forte que la raie utile. La réception 8 bits et les modes 16 bits n'étaient pas touchés. Les
essais srsRAN 50 PRB du 08 et 09/11 (`TX_GAIN=0`) mesuraient le débit, la charge et les blocs TX en retard : ces
chiffres restent valables, mais le signal émis n'avait pas été contrôlé.

**v5 : voie TX2 (mode 2R2T)**, défaut déjà présent dans le bitstream Tezuka d'origine :
- la sortie des sélecteurs de la voie 2 n'était reliée à rien (`din_data_2/3` du FIFO DAC en l'air) : **TX2
  émettait des zéros dans tous les modes**, 16 bits compris. Elle est maintenant reliée en direct ;
- mode 8 bits de la voie 2 : `enable_in_1` de I et Q inversés, octets placés sur les bits 11..4 au lieu de 15..8
  (24 dB trop bas), pas de `dac_force_dma` sur Q1. Corrigés comme pour la voie 1.

Limites qui restent :
- TX2 ne passe pas par l'interpolateur ×32 de Tezuka (il n'a que deux voies) : avec l'interpolateur actif (bit 0 de
  `up_dac_gpio_out`, jamais utilisé avec l'horodatage), TX2 n'est pas filtrée ;
- 8 bits sur les deux voies à la fois : le pilote noyau refuse les masques I1 + I2 (0x5) ; une seule voie en 8 bits
  à la fois (comme le pilote Soapy `ip_cs8`, qui n'accepte qu'une voie).

## Vérification (2026-11-27, rebouclage numérique AD9363)

Tonalités émises puis relues après le rebouclage interne de l'AD9363 (`loopback=1`), 3,84 Méch/s.

**1R1T, pilote Soapy** (`cs8loop.cpp`, tonalité à +fs/8) :

| Bitstream | TX | RX | Q reçu | Image −fs/8 / raie | Bruit hors raie |
|---|---|---|---|---|---|
| v3 | 16 bits | 16 bits | oui | −180 dB | −67 dB |
| v3 | **8 bits** | 16 bits | **0** | **0 dB** | −42 dB |
| v4, v5 | 8 bits | 16 bits | oui | −180 dB | −44 dB (quantification 8 bits, amplitude 0,5) |
| v4, v5 | 8 bits | 8 bits | oui | −180 dB | — |
| v4, v5 | 16 bits | 16 / 8 bits | oui | −180 dB | inchangé |

**2R2T, libiio** (`iioloop.c` lancé par `suite2.sh` ; TX1 à +fs/8, TX2 à +3fs/16, niveau attendu −6 dBFS) :

| Bitstream | TX1 → RX1 (16 et 8 bits) | TX2 16 bits → RX2 | TX2 8 bits → RX2 (16 / 8 bits) | Fuite d'une voie sur l'autre |
|---|---|---|---|---|
| v4 | −6 dBFS, correct | **rien (RX2 = 0)** | **rien** | — |
| v5 | −6 dBFS, correct | −6 dBFS, image < −150 dB | −6 dBFS, image −107 dB | aucune |

**srsRAN 4G autonome** (EPC + eNodeB dans le conteneur `srsran/`, `TX_GAIN=0`, VM sans autre charge), carte
suivie toutes les 10 s (blocs TX rejetés par le FPGA, datagrammes UDP perdus) :

| Essai | v4 | v5 |
|---|---|---|
| 50 PRB, 8 bits (`IP_CS8=1`), 10 min : blocs TX rejetés | 85 | 100 |
| 25 PRB, 16 bits, 3 min : blocs TX rejetés | 76 | 42 |
| UDP perdus, erreurs srsRAN | 0, 0 | 0, 0 |

Même ordre que le test d'1 h du 09/11 en v3 (33 rejets sur ses 10 premières minutes, 261 sur l'heure).
Attention à la VM partagée : un premier essai v4 fait pendant une compilation Vivado d'une autre session a
donné 3 985 rejets en 10 min (srsRAN privé de processeur), à ne pas confondre avec un défaut de la carte.

Timing : v4 WNS +0,046 ns / WHS +0,018 ns ; v5 WNS +0,184 ns / WHS +0,007 ns.

## Outils

- `cs8loop.cpp` (Soapy) : `g++ -O2 -o cs8loop cs8loop.cpp -lSoapySDR -lpthread`, puis
  `cs8loop "driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=0,loopback=1" <tx_cs8 0|1> 0.5 <rx_cs8 0|1>` ;
- `iioloop.c` (libiio, deux voies) : `gcc -O2 -o iioloop iioloop.c -liio -lm`, puis
  `iioloop ip:<ip> <masque TX> <masque RX> 0.5` (masques sur voltage0..3 = I1 Q1 I2 Q2 ; I seul = 8 bits ; carte en
  `fw_setenv mode 2r2t` pour la voie 2). Il remet `timestamp_every` à 0 (registre 0xBC du cœur, adresse
  `0x800000BC` : sans le bit 0x80000000, l'accès part sur le SPI de l'AD9363).

Les deux se compilent dans l'image Docker `srsran/`, qui contient SoapySDR et libiio.
