#!/usr/bin/env bash
# Einrichtung des Homeservers (Raspberry Pi OS Lite 64-bit oder Debian/Ubuntu auf einem Mini-PC).
# Aufruf auf dem Server:  bash setup.sh
# Das Skript ist wiederholbar: Bereits Erledigtes wird übersprungen.
set -euo pipefail

SRV=/srv
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_NAME="${SUDO_USER:-$USER}"
say() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m✓ %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { echo "Bitte als normaler Benutzer starten (nicht mit sudo). Das Skript fragt selbst nach dem Passwort."; exit 1; }
[[ "$(uname -m)" =~ ^(aarch64|x86_64)$ ]] || { echo "Nur 64-Bit-Systeme (aarch64/x86_64) werden unterstützt. Bitte Raspberry Pi OS Lite (64-bit) installieren."; exit 1; }

say "System aktualisieren"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq full-upgrade
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install ca-certificates curl git unattended-upgrades jq
ok "System aktuell"

say "Automatische Sicherheitsupdates"
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
ok "Sicherheitsupdates werden täglich installiert"

say "Auslagerungsspeicher (wichtig bei 1 GB RAM)"
if [[ -f /etc/dphys-swapfile ]]; then
  sudo sed -i 's/^#\?CONF_SWAPSIZE=.*/CONF_SWAPSIZE=1024/' /etc/dphys-swapfile
  sudo systemctl restart dphys-swapfile || true
  ok "Swap 1 GB"
elif ! swapon --show | grep -q .; then
  sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile >/dev/null && sudo swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  ok "Swap 1 GB"
else
  ok "Swap bereits vorhanden"
fi

say "Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER_NAME"
sudo systemctl enable --now docker >/dev/null
# Container-Logs begrenzen (schont SD-Karte/USB-Stick)
echo '{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }' | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker
sudo docker network inspect web >/dev/null 2>&1 || sudo docker network create web >/dev/null
ok "Docker läuft, gemeinsames Netz 'web' vorhanden"

say "Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! sudo tailscale status >/dev/null 2>&1; then
  echo "Gleich erscheint ein Link – im Browser öffnen und mit deinem Tailscale-Konto anmelden."
  sudo tailscale up --hostname=homeserver
fi
ok "Tailscale verbunden: $(sudo tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"

say "Ordner unter $SRV"
sudo mkdir -p "$SRV"/{proxy,backup,projects}
sudo chown -R "$USER_NAME":"$USER_NAME" "$SRV"
cp -n "$REPO_DIR"/proxy/* "$SRV/proxy/"
for p in "$REPO_DIR"/projects/*/; do
  name=$(basename "$p")
  mkdir -p "$SRV/projects/$name"
  cp -n "$p"docker-compose.yml "$SRV/projects/$name/" 2>/dev/null || true
  [[ -f "$p.env.example" && ! -f "$SRV/projects/$name/.env" ]] && cp "$p.env.example" "$SRV/projects/$name/.env" && chmod 600 "$SRV/projects/$name/.env"
  mkdir -p "$SRV/projects/$name/data" && sudo chown 1000:1000 "$SRV/projects/$name/data"
done
ok "Projektordner angelegt"

# Zugangsschlüssel der FinTS-Brücke automatisch erzeugen (falls noch leer)
ENV_F="$SRV/projects/finanzen/.env"
if [[ -f "$ENV_F" ]] && grep -q '^BRIDGE_TOKEN=$' "$ENV_F"; then
  sed -i "s/^BRIDGE_TOKEN=$/BRIDGE_TOKEN=$(openssl rand -hex 32)/" "$ENV_F"
  ok "Zugangsschlüssel für die App erzeugt (steht in $ENV_F unter BRIDGE_TOKEN)"
fi

say "Zentraler Eingang (Caddy) starten"
sudo docker compose -f "$SRV/proxy/docker-compose.yml" up -d
sudo tailscale serve --bg 8080 >/dev/null
ok "Erreichbar unter https://$(sudo tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')/"

say "Tägliches Backup (03:30 Uhr)"
sudo install -m 755 "$REPO_DIR/scripts/backup.sh" /usr/local/bin/homeserver-backup
echo "30 3 * * * root /usr/local/bin/homeserver-backup >> /var/log/homeserver-backup.log 2>&1" | sudo tee /etc/cron.d/homeserver-backup >/dev/null
ok "Backups landen in $SRV/backup (die letzten 14 Tage)"

cat <<MSG

──────────────────────────────────────────────────────────────
Fertig. Nächste Schritte:

1. FinTS-Brücke konfigurieren (sobald die Registrierungsnummer da ist):
     nano $SRV/projects/finanzen/.env
2. Starten:
     cd $SRV/projects/finanzen && docker compose up -d
3. In der App als Adresse eintragen:
     https://$(sudo tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')/finanzen

Hinweis: Damit 'docker' ohne sudo geht, einmal ab- und wieder anmelden.
──────────────────────────────────────────────────────────────
MSG
