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

srsRAN 4G (moyenne sur 60 s, blocs TX arrivés en retard et rejetés par le FPGA) :

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
