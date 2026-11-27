# Correctif FPGA : émission 8 bits (`ip_cs8=1`)

Bitstream **v4** (`system_top.bin` du zip depuis le 2026-11-27) = v3 + ce correctif.
Sources : maia-sdr (F5OEO), branche `refactor` fbc289b + horodatage (branche `fishball-ts-ref`) + `0001-tx-cs8.patch`.

## Le défaut (v3, image v0.2.0 avant le 2026-11-27)

Avec `ip_cs8=1`, le pilote n'active que le canal I et range I et Q sur 8 bits dans le même mot de 16 bits.
Le FPGA (logique CS8 de Tezuka) doit alors séparer les deux octets. En émission, deux erreurs :

- **mauvais signal de sélection** : `system_bd.tcl` choisissait le chemin 8 bits quand **I** était coupé
  (`din_enable_0`) au lieu de **Q** (`din_enable_1`), alors que la réception (`dout_enable_1`) et la 2e voie TX
  (`din_enable_3`) testent bien Q. Avec `ip_cs8=1`, le chemin 8 bits n'était donc jamais choisi ;
- **Q à zéro au DAC** : le pilote noyau met le canal Q, absent du masque, sur la source DDS, qui est désactivée
  dans ce design (`DAC_DDS_DISABLE`). Corriger la sélection ne suffit donc pas : le patch `axi_ad9361` fait suivre
  à Q0 la donnée DMA quand I0 est seul actif (`dac_force_dma`).

Effet en v3 : le DAC recevait I = mot `{I8,Q8}` lu comme un seul nombre, et Q = 0. Le signal émis était réel,
avec une image miroir aussi forte que la raie utile. La réception 8 bits et tous les modes 16 bits n'étaient pas
touchés. Les essais srsRAN 50 PRB du 08 et 09/11 (`TX_GAIN=0`) mesuraient le débit, la charge et les blocs TX en
retard : ces chiffres restent valables, mais le signal émis n'avait pas été contrôlé.

## Vérification (2026-11-27, rebouclage numérique AD9363, `cs8loop.cpp`)

Tonalité complexe à +fs/8 (3,84 Méch/s) émise par Soapy, relue après le rebouclage interne de l'AD9363 (`loopback=1`).

| Bitstream | TX | RX | Q reçu | Image −fs/8 / raie | Bruit hors raie |
|---|---|---|---|---|---|
| v3 | 16 bits | 16 bits | oui | −180 dB | −67 dB |
| v3 | **8 bits** | 16 bits | **0** | **0 dB** | −42 dB |
| v4 | 8 bits | 16 bits | oui | −180 dB | −44 dB (quantification 8 bits, amplitude 0,5) |
| v4 | 8 bits | 8 bits | oui | −180 dB | — |
| v4 | 16 bits | 16 / 8 bits | oui | −180 dB | inchangé |

srsRAN 50 PRB `IP_CS8=1` (horodaté) sur v4 : eNodeB démarré, aucun bloc en retard ni sous-débit en 90 s.
Timing v4 : WNS +0,046 ns, WHS +0,018 ns.

Programme : à compiler dans l'image `srsran/`, par exemple
`g++ -O2 -o cs8loop cs8loop.cpp -lSoapySDR -lpthread`, puis
`cs8loop "driver=plutosdr,hostname=<ip>,direct=1,timestamp_every=0,loopback=1" <tx_cs8 0|1> 0.5 <rx_cs8 0|1>`.

## Non corrigé

La 2e voie TX (mode 2R2T) a aussi des erreurs dans le même bloc : `enable_in_1` d'I et de Q inversés, I placé sur
les bits 11..4 au lieu de 15..8, et pas de `dac_force_dma` sur Q1. Elle n'est pas utilisée en 1R1T (mode conseillé)
et le pilote `ip_cs8` n'accepte qu'une voie.
