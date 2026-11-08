# sdr_ip_gadget optimisé (GSO UDP)

`sdr_ip_gadget` est le démon de Phil Greenland qui transporte les échantillons horodatés entre la
carte et le PC en UDP (`direct=1`). Version de base : [pgreenland/pluto-sdr-ip-gadget](https://github.com/pgreenland/pluto-sdr-ip-gadget)
commit `9b3864d`. Le binaire modifié est dans le ramdisk de l'image SD depuis la v0.2.0.

## Ce que change `sdr_ip_gadget-perf.patch`

| Changement | Effet |
|---|---|
| **UDP GSO** (`UDP_SEGMENT`) en réception RX | chaque tampon est remis au noyau en un seul message, découpé en paquets au dernier moment : la pile réseau n'est traversée qu'une fois pour ~40 paquets au lieu d'une fois par paquet. **Paquets identiques sur le réseau**, aucun changement côté PC. Repli automatique si le noyau refuse. |
| Réception TX par lots (`recvmmsg`) | après le premier paquet d'un tampon, les suivants sont lus d'un coup directement à leur place dans le tampon DMA (gain faible). |
| Cœur des threads réglable | `SDR_IP_GADGET_RX_CPU` / `SDR_IP_GADGET_TX_CPU` (défaut 1, comme l'original). Le cœur 0 fige le flux : ne pas l'utiliser. |

Désactivation pour comparer : `SDR_IP_GADGET_NO_GSO=1`, `SDR_IP_GADGET_NO_RECVMMSG=1`.

## Mesures (2026-11-08, carte sans overclock, srsRAN sur une VM en filaire)

Débit RX horodaté maximal (`SoapySDRUtil --rate`) :

| | Méch/s |
|---|---|
| gadget d'origine, 16 bits | 8,3 |
| gadget d'origine, overclock 950/600 | 11,4 |
| **GSO, 16 bits** | **12,2** |
| **GSO, 8 bits convertis par le FPGA** (`ip_cs8=1`) | **17,4** |

srsRAN 4G, CPU moyen de la carte sur 30 s (et blocs TX arrivés en retard, rejetés par le FPGA) :

| | gadget d'origine | GSO |
|---|---|---|
| 25 PRB, 16 bits | 94 % (91 / 30 s) | **35 %** (2 / 30 s) |
| 25 PRB, 8 bits | 84 % | **9 %** |
| 50 PRB, 8 bits | 97 %, saturé (30 / 30 s) | **43 à 80 %** (0 à 6 / 30 s) |

Le mode 8 bits n'est pas dans le gadget : c'est le FPGA (logique CS8 de Tezuka, active quand le canal
Q est désactivé) qui range I et Q sur 8 bits ; le pilote SoapyPlutoSDR patché (`ip_cs8=1`, voir
`../../srsran/soapy-ip-cs8.patch`) n'ouvre que le canal 0. Voir [`../../srsran/README.md`](../../srsran/README.md).

## Compiler

```bash
git clone https://github.com/pgreenland/pluto-sdr-ip-gadget.git && cd pluto-sdr-ip-gadget && git checkout 9b3864d
patch -p1 < sdr_ip_gadget-perf.patch
# compilation croisée ARM avec libiio 0.26 (sysroot) :
mkdir build-arm && cd build-arm
cmake .. -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
         -DCMAKE_C_FLAGS="-I<sysroot>/include -O2" -DCMAKE_EXE_LINKER_FLAGS="-L<sysroot>/lib"
make
```
