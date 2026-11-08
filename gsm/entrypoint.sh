#!/bin/bash
# Point d'entrée de l'image 2G. Rien n'est configuré ni lancé automatiquement.
set -euo pipefail
MODE=${1:-aide}
PLUTO_IP=${PLUTO_IP:-}
DOC=/usr/share/doc/pluto-gsm

need_ip() { [ -n "$PLUTO_IP" ] || { echo "Définir PLUTO_IP=<ip de la carte>" >&2; exit 1; }; }

case "$MODE" in
  aide|help)
    cat <<EOF
Image 2G Osmocom pour Fishball horodaté — aucune configuration active.

  versions        versions installées
  probe           SoapySDRUtil --probe (attendu : « Timestamps: YES »)          [PLUTO_IP]
  test-ts         boucle émission → réception horodatée de Phil (TX relié à RX
                  par câble + atténuateur 30-40 dB)                              [PLUTO_IP]
  trx             osmo-trx-soapy -C /config/osmo-trx-soapy.cfg (couche radio seule)
  shell           bash

Modèles et exemples (non utilisés) : $DOC
  osmo-trx-soapy.cfg.modele      modèle TRX (seul fichier lié à la carte)
  exemples-iliasam/VOICE, EDGE   configs complètes d'iliasam (BTS/BSC/MSC/HLR/MGW/STP/PCU/SGSN/GGSN)
  /etc/osmocom/                  configs d'origine des paquets Osmocom
EOF
    ;;
  versions)
    for p in osmo-bts-trx osmo-bsc osmo-msc osmo-hlr osmo-mgw osmo-stp osmo-pcu osmo-sgsn osmo-ggsn libosmocore-dev libiio0 libsoapysdr0.8; do
      printf "%-18s %s\n" "$p" "$(dpkg-query -W -f '${Version}' "$p" 2>/dev/null || echo '?')"
    done
    printf "%-18s %s\n" osmo-trx-soapy "iliasam/osmo-trx_soapy cd9da9d (base osmo-trx 1.4.1)"
    SoapySDRUtil --info 2>/dev/null | grep -E "Lib Version|Available factories"
    ;;
  probe)   need_ip; exec SoapySDRUtil --probe="driver=plutosdr,hostname=${PLUTO_IP},direct=1,timestamp_every=2500,loopback=0" ;;
  test-ts) need_ip; exec test_timestamp_loopback --uri "ip:${PLUTO_IP}" ;;
  trx)
    [ -f /config/osmo-trx-soapy.cfg ] || {
      echo "Absent : /config/osmo-trx-soapy.cfg (partir de $DOC/osmo-trx-soapy.cfg.modele)" >&2; exit 1; }
    exec osmo-trx-soapy -C /config/osmo-trx-soapy.cfg ;;
  shell)   exec bash ;;
  *)       exec "$@" ;;
esac
