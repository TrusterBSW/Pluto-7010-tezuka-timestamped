#!/bin/bash
# srsRAN all (EPC+eNB) sur le Fishball, TX_GAIN=0 (atténuation max), 90 s par PRB
cd ~/srsran
for prb in ${PRBS:-6 15 25 50}; do
  echo "######## PRB=$prb $(date +%T)"
  PLUTO_IP=10.5.1.96 PRB=$prb TX_GAIN=0 timeout -s INT 90 docker compose run --rm --name srstest srsran all > /tmp/srs_$prb.log 2>&1
  docker rm -f srstest >/dev/null 2>&1; sleep 3
  echo "fin $(date +%T)"; grep -E "device_args|tx_gain" /tmp/srs_$prb.log | head -2
  grep -ciE "late|underflow|overflow|lost|error" /tmp/srs_$prb.log
  grep -iE "late|underflow|overflow|lost|error|RF|Timestamp" /tmp/srs_$prb.log | sort | uniq -c | sort -rn | head -8
  sleep 40
done
