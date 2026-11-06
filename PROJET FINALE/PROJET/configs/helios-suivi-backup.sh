#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
umask 077

destination=/srv/helios/archives/suivi
staging=

log() {
  logger -t helios-suivi-backup -- "$*"
}

cleanup() {
  if [[ -n "$staging" ]]; then
    rm -rf -- "$staging"
  fi
}

trap cleanup EXIT
trap 'log "Erreur interne ligne $LINENO"; exit 1' ERR

exec 9>/run/lock/helios-suivi-backup.lock
if flock -n -E 2 9; then
  :
else
  status=$?
  log "Verrou indisponible (code $status)"
  exit "$status"
fi

sources=(
  srv/helios/suivi
  etc/systemd/system/helios-suivi.service
  etc/systemd/system/helios-suivi-publish.service
  etc/systemd/system/helios-suivi-publish.timer
  etc/systemd/system/helios-suivi-backup.service
  etc/systemd/system/helios-suivi-backup.timer
  etc/sudoers.d/92-helios-suivi
  etc/zabbix/zabbix_agent2.d/helios-suivi.conf
  usr/local/sbin/helios-suivi-publish.sh
  usr/local/sbin/helios-suivi-backup.sh
)

for source in "${sources[@]}"; do
  if [[ ! -r "/$source" ]]; then
    log "Source illisible : /$source"
    exit 3
  fi
done

archive="suivi-$(date +%Y%m%d-%H%M%S).tar.gz"
staging=$(mktemp -d "$destination/.backup.XXXXXX")

tar --acls --selinux -czf "$staging/$archive" -C / "${sources[@]}"
(cd "$staging" && sha256sum "$archive" > "$archive.sha256")
mv -- "$staging/$archive" "$staging/$archive.sha256" "$destination/"

shopt -s nullglob
archives=("$destination"/suivi-*.tar.gz)
for ((i=0; i < ${#archives[@]} - 7; i++)); do
  rm -- "${archives[i]}" "${archives[i]}.sha256"
done

log "Sauvegarde creee : $archive"
exit 0
