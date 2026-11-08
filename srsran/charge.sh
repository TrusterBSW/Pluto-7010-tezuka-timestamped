#!/bin/bash
# Test de charge : srsRAN all (EPC+eNB) sur le Fishball, TX_GAIN=0 (atténuation maximale), DUREE s par PRB.
#   PLUTO_IP=<ip-carte> PRBS="6 15 25 50" IP_CS8=1 DUREE=90 ./charge.sh
# Entre deux paliers, srsRAN est arrêté proprement (docker stop) ; il ne coupe pas pour autant son flux :
# relancer sdr_ip_gadget sur la carte (/etc/init.d/S55sdr_ip_gadget restart) avant le palier suivant,
# sinon le nouveau srsRAN démarre mal (le mode éco coupe le flux orphelin au bout de 2 min).
cd "$(dirname "$0")"
: "${PLUTO_IP:?définir PLUTO_IP=<ip-carte>}"
for prb in ${PRBS:-6 15 25 50}; do
  echo "######## PRB=$prb IP_CS8=${IP_CS8:-0} $(date +%T)"
  docker rm -f srstest >/dev/null 2>&1
  PLUTO_IP=$PLUTO_IP PRB=$prb TX_GAIN=0 IP_CS8=${IP_CS8:-0} docker compose run -d --name srstest srsran all >/dev/null
  sleep "${DUREE:-90}"
  docker stop -t 15 srstest >/dev/null; docker logs srstest > /tmp/srs_$prb.log 2>&1; docker rm -f srstest >/dev/null
  echo "fin $(date +%T)"; grep -E "device_args" /tmp/srs_$prb.log | head -1
  grep -E "BB rate|^[LUO]+$|Late|nderflow|verflow|eNodeB started" /tmp/srs_$prb.log | sort | uniq -c
  sleep 5
done
