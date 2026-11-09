# Note : déplacer une partie de l'eNodeB (srsRAN 4G) dans le FPGA du Fishball

Note de faisabilité du 2026-11-09 (session « pluto cpu optim »), à la demande de l'utilisateur. Rien
n'est commencé.

## Point de départ

- Le Fishball sert de **tête radio horodatée** : il transporte des échantillons temporels entre l'AD9363 et
  le PC (srsRAN). Depuis la v0.2.0 (8 bits rangés par le FPGA + `sdr_ip_gadget` en GSO UDP), **50 PRB
  (10 MHz) tient sans overclock** : 11,52 Méch/s dans chaque sens, 23 Mo/s par sens sur le réseau,
  cœur le plus chargé à 72 % (charge réelle, mesurée par compteur d'inactivité). Limite mesurée en RX : 17,4 Méch/s.
- Ressources du XC7Z010 : 17 600 LUT, 35 200 FF, 60 BRAM36, 80 DSP48. Bitstream v3 (avec Maia) :
  LUT 59 %, FF 45 %, BRAM 68 %, DSP 62 %. Sans Maia (comme l'image edgeQAM), on libère l'essentiel.
- Référence utile : le modulateur DVB-T de la session « dvbtx-fpga » (IFFT 8192 points en pipeline +
  toute la chaîne DVB-T, 4 multiplex) tient en ~7 300 LUT, 23 DSP, 51 BRAM18 (`docs/EDGEQAM.md`).
  Une IFFT/FFT LTE (1024 points au plus) est bien plus petite.

## Ce que fait un eNodeB et où ça pourrait aller

| Bloc | Coût sur le PC | Dans le FPGA ? | Commentaire |
|---|---|---|---|
| OFDM DL : IFFT + préfixe cyclique | moyen | **oui, facile** | IFFT 768/1024 points + CP : quelques milliers de LUT, < 10 DSP. |
| SC-FDMA UL : retrait du CP + FFT | moyen | **oui, facile** | même IP en sens inverse. |
| Détection PRACH (accès aléatoire) | faible à moyen | possible | corrélation périodique ; gain faible. |
| Estimation de canal, égalisation UL | moyen | possible mais lourd | dépend de l'ordonnancement (MAC), donc de messages de contrôle du PC. |
| Modulation/démodulation QAM, embrouillage | faible | possible | peu d'intérêt seul. |
| **Décodage turbo UL (PUSCH)** | **élevé** (le plus coûteux) | difficile | gros en ressources (IP Xilinx sous licence, cœurs libres rares) ; et il faudrait envoyer des « soft bits » au FPGA, plus volumineux que les échantillons : **le trafic augmente au lieu de baisser**. |
| Codage turbo DL | faible | inutile | |
| MAC, RLC, PDCP, RRC, S1 (couches hautes) | élevé (logiciel) | **non** | logique de protocole ; et le Cortex-A9 double cœur à 666 MHz est bien trop faible pour faire tourner srsenb (un Raspberry Pi 4 peine déjà au-delà de 15 PRB). |

## Le seul découpage réaliste : « split 7 » (FFT dans le FPGA)

Le FPGA ferait l'IFFT/FFT et le préfixe cyclique ; le PC échangerait des **symboles dans le domaine
fréquentiel**, seulement sur les sous-porteuses utiles (600 sur 768/1024 à 50 PRB, 1 200 à 100 PRB) :

- débit réseau à 50 PRB : 600 × 14 × 1 000 = 8,4 M valeurs complexes/s contre 11,52 Méch/s, soit
  **−27 %** ; avec une compression par blocs (« block floating point » 8-9 bits, comme O-RAN), on gagne
  encore un peu ;
- le vrai intérêt serait **100 PRB (20 MHz)** : 15,36 Méch/s en temporel (au-delà de nos 17,4 Méch/s en RX
  dès qu'on ajoute le TX), contre 16,8 M valeurs/s en fréquentiel compressé : à la limite, pas mieux.

**Coût du travail :**
1. FPGA : IFFT/FFT + CP + mise en trame par symbole OFDM, horodatage par symbole (le compteur 64 bits
   existe) : quelques jours à une semaine (on peut s'inspirer du cœur DVB-T HLS).
2. srsRAN 4G : **il n'a pas d'interface « split 7 »** ; sa couche radio est purement temporelle. Il faudrait
   un pilote radio qui court-circuite son OFDM (`srsran_ofdm_*`) dans le PHY : modification profonde,
   à maintenir soi-même. srsRAN Project (5G) a un split 7.2 O-RAN, mais pour la 5G et des radios O-RAN.
3. Nouveau protocole réseau carte ↔ PC (symboles + numéros de symbole/sous-trame), à la place de
   celui de `sdr_ip_gadget`.

## Conclusion et recommandation

- **Tout l'eNodeB dans le Fishball : impossible** (couches hautes trop lourdes pour l'A9, turbo-décodage
  trop gros pour le 7010 et sans gain réseau).
- **Une partie : techniquement faisable** (FFT/IFFT, voire PRACH), mais le gain est modeste à 50 PRB
  (−27 % de trafic) alors que 50 PRB passe déjà ; il ne deviendrait utile que pour viser 100 PRB, et le
  gros du travail est côté srsRAN (pas d'interface prévue), pas côté FPGA.
- Pistes plus rentables d'abord, si l'on veut plus de marge : passer la VM srsRAN sur une machine
  physique (moins de rafales de rattrapage, voir l'analyse de variation CPU), UDP GRO en réception sur la
  carte, et la variabilité de charge à comprendre (2026-11-09).

## Mise à jour 2026-11-09 : peut-on viser 100 PRB (20 MHz) ?

L'utilisateur est intéressé si ça permet 100 PRB. L'AD9363 plafonne à 20 MHz de bande : 100 PRB est donc le
maximum possible (23,04 Méch/s ; 46 Mo/s par sens en 8 bits, le gigabit suit).

Charge réelle mesurée : 50 PRB en 8 bits = cœur 1 à 72 %. Le coût suit le trafic (25 PRB 16 bits = même
trafic = même charge). En temporel 8 bits, 100 PRB demanderait **~144 %** du cœur 1 : impossible tel quel.

Leviers et effet estimé sur le cœur 1 à 100 PRB :

| Levier | Charge estimée |
|---|---|
| aucun (temporel 8 bits) | ~144 % |
| + split 7 (FFT dans le FPGA : 1 200 sous-porteuses × 14 symboles × 1 000 = 16,8 M valeurs/s au lieu de 23,04 Méch/s, préfixe cyclique compris : −27 %) | ~105 % |
| + compression 6-7 bits par bloc (BFP) au lieu de 8 | ~85 % |
| + overclock CPU 950 / DDR 600 (+42 % de cycles, hors spécifications, +4-5 °C) | ~60 % |

Donc **100 PRB n'est envisageable qu'en cumulant split 7 + compression + overclock**, avec beaucoup de
développement (FPGA, protocole, et surtout srsRAN sans interface split 7). Autres pistes à creuser avant :
réduire le coût par paquet de la pile réseau (AF_XDP si le pilote macb le permet, réception UDP GRO,
interruptions réparties) ; le Zynq-7000 n'accepte pas les trames jumbo, et le PHY Ethernet est câblé sur le
PS : impossible de construire les paquets dans le FPGA.
