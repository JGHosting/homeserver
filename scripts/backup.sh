#!/usr/bin/env bash
# Sichert die Konfiguration und Daten aller Projekte nach /srv/backup (14 Tage).
# Für echte Sicherheit zusätzlich ab und zu auf einen anderen Rechner kopieren.
set -euo pipefail
DEST=/srv/backup
STAMP=$(date +%F)
mkdir -p "$DEST"
tar --exclude='*/node_modules' -czf "$DEST/homeserver-$STAMP.tar.gz" -C /srv proxy projects
chmod 600 "$DEST/homeserver-$STAMP.tar.gz"
find "$DEST" -name 'homeserver-*.tar.gz' -mtime +14 -delete
echo "$(date '+%F %T') Backup ok: $DEST/homeserver-$STAMP.tar.gz"
