#!/bin/bash
# Génère la configuration srsRAN pour le Fishball horodaté puis lance le mode demandé.
#   all   : srsepc + srsenb (cœur LTE intégré, le plus simple pour un premier test)
#   enb   : srsenb seul, relié au MME d'un cœur externe (ex. open5gs de docker_open5gs)
#   epc   : srsepc seul
#   probe : SoapySDRUtil --probe (doit afficher « Timestamps: YES »)
#   shell : bash
set -euo pipefail

MODE=${1:-all}
PLUTO_IP=${PLUTO_IP:-pluto.local}
TRANSPORT=${TRANSPORT:-ip}          # ip (Ethernet, sdr_ip_gadget) | usb
PRB=${PRB:-6}                        # 6, 15, 25 ou 50 (25 = maximum testé par Phil, en Ethernet ; 50 = essai)
EARFCN=${EARFCN:-1575}               # 1575 = bande 3 (DL 1842,5 MHz). À adapter.
MCC=${MCC:-001}
MNC=${MNC:-01}
TX_GAIN=${TX_GAIN:-89}               # 89 = atténuation TX minimale côté Pluto
RX_GAIN=${RX_GAIN:-20}
TIME_ADV=${TIME_ADV:-40}             # time_adv_nsamples (valeur de Phil)
MME_ADDR=${MME_ADDR:-127.0.1.100}    # mode enb : IP du MME externe
ENB_BIND=${ENB_BIND:-127.0.1.1}      # mode enb : IP locale vers le MME / GTP
MASQ_IF=${MASQ_IF:-}                 # interface de sortie Internet pour les UE (mode all/epc)

case "$PRB" in
  6)  TS_EVERY=1920; PRACH=0 ;;
  15) TS_EVERY=3840; PRACH=4 ;;
  25) TS_EVERY=5760; PRACH=4 ;;
  50) TS_EVERY=11520; PRACH=4 ;;
  *)  echo "PRB doit valoir 6, 15, 25 ou 50" >&2; exit 1 ;;
esac

if [ "$TRANSPORT" = usb ]; then
  DEV_ARGS="driver=plutosdr,usb_direct=1,timestamp_every=${TS_EVERY},loopback=0"
else
  DEV_ARGS="driver=plutosdr,hostname=${PLUTO_IP},direct=1,timestamp_every=${TS_EVERY},loopback=0"
fi

CFG=/root/cfg
mkdir -p "$CFG"
cp /etc/srsran/*.conf "$CFG"/
if [ -f /config/user_db.csv ]; then cp /config/user_db.csv "$CFG"/user_db.csv
else cp /etc/srsran/user_db.csv "$CFG"/user_db.csv; fi

# set_key fichier clé valeur : remplace « clé = ... » (même commentée) par « clé = valeur »
set_key() { sed -i -E "0,/^[#[:space:]]*$2[[:space:]]*=.*/s||$2 = $3|" "$1"; }

E=$CFG/enb.conf
set_key "$E" mcc "$MCC"
set_key "$E" mnc "$MNC"
set_key "$E" n_prb "$PRB"
set_key "$E" mme_addr "$MME_ADDR"
set_key "$E" gtp_bind_addr "$ENB_BIND"
set_key "$E" s1c_bind_addr "$ENB_BIND"
set_key "$E" dl_earfcn "$EARFCN"
set_key "$E" tx_gain "$TX_GAIN"
set_key "$E" rx_gain "$RX_GAIN"
set_key "$E" device_name soapy
set_key "$E" device_args "$DEV_ARGS"
set_key "$E" time_adv_nsamples "$TIME_ADV"
for f in sib rr rb; do set_key "$E" "${f}_config" "$CFG/$f.conf"; done
sed -i -E "s/(prach_freq_offset[[:space:]]*=[[:space:]]*)[0-9]+/\1${PRACH}/" "$CFG/sib.conf"

P=$CFG/epc.conf
set_key "$P" mcc "$MCC"
set_key "$P" mnc "$MNC"
set_key "$P" db_file "$CFG/user_db.csv"

echo "== Fishball horodaté : PRB=$PRB EARFCN=$EARFCN PLMN=$MCC/$MNC"
echo "== device_args = $DEV_ARGS"
grep -E "^(n_prb|dl_earfcn|device_name|device_args|tx_gain|rx_gain|time_adv_nsamples|mme_addr)" "$E" | sed 's/^/   /'
grep -E "prach_freq_offset" "$CFG/sib.conf" | sed 's/^/   /'

start_epc() {
  srsepc "$P" &
  EPC_PID=$!
  sleep 3
  [ -n "$MASQ_IF" ] && srsepc_if_masq.sh "$MASQ_IF" || true
}

cd "$CFG"
case "$MODE" in
  probe) exec SoapySDRUtil --probe="${DEV_ARGS}" ;;
  epc)   start_epc; wait "$EPC_PID" ;;
  enb)   exec srsenb "$E" ;;
  all)   start_epc; srsenb "$E"; kill "$EPC_PID" 2>/dev/null || true ;;
  shell) exec bash ;;
  *)     exec "$@" ;;
esac
