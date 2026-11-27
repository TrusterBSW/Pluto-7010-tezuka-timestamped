#!/bin/bash
# suite 2R2T : TX1 tonalite +fs/8, TX2 +3fs/16 ; masque = voltage0..3 (I1 Q1 I2 Q2) ; I seul = 8 bits
for a in "0xf 0xf" "0xc 0xf" "0x3 0xf" "0x4 0xf" "0x1 0xf" "0xc 0xc" "0x4 0x4" "0xc 0x4" "0x4 0xc"; do
  echo "--- TX $a" | sed 's/ 0x/ \/ RX 0x/2'
  timeout 60 docker run --rm --network host -v ~/cs8test:/w --entrypoint /w/iioloop pluto-srsran:ts ip:10.5.1.96 $a 0.5 2>&1 | grep -v "^TX masque"
done
