#!/usr/bin/env bash
set -euo pipefail

source_csv=/var/lib/helios/telemetry.csv
www=/srv/helios/suivi/www
tmp=

log() {
  logger -t helios-suivi-publish -- "$*"
}

cleanup() {
  if [[ -n "$tmp" ]]; then
    rm -f -- "$tmp"
  fi
}

trap cleanup EXIT
trap 'log "Erreur interne ligne $LINENO"; exit 1' ERR

if [[ ! -r "$source_csv" || ! -d "$www" || ! -w "$www" || ! -x "$www" ]]; then
  log "Prerequis manquant : CSV illisible ou repertoire web non inscriptible"
  exit 3
fi

exec 9<"$www"
if flock -n -E 2 9; then
  :
else
  status=$?
  if [[ "$status" -eq 2 ]]; then
    log "Publication deja en cours"
    exit 2
  fi
  log "Impossible de verrouiller le repertoire web"
  exit 1
fi

tmp=$(mktemp "$www/.etat.XXXXXX")
python3 - "$source_csv" "$tmp" <<'PY'
import csv
import json
import socket
import sys
from datetime import datetime

with open(sys.argv[1], newline="", encoding="utf-8") as source:
    count = 0
    last = None
    for row in csv.reader(source):
        if row:
            count += 1
            last = row

if last is None or len(last) != 3:
    raise SystemExit("Derniere ligne de telemetrie absente ou invalide")

timestamp, load, memory = last
datetime.fromisoformat(timestamp)
data = {
    "genere": datetime.now().astimezone().isoformat(timespec="seconds"),
    "hote": socket.gethostname(),
    "derniere_mesure": timestamp,
    "charge_1min": float(load),
    "mem_dispo_ko": int(memory),
    "mesures": count,
}
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(data, output, indent=2, allow_nan=False)
    output.write("\n")
PY

mv -fT -- "$tmp" "$www/etat.json"
tmp=
log "Publication de etat.json terminee"
exit 0
