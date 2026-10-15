# Homeserver

Mein kleiner Server zu Hause (Raspberry Pi 3, später ggf. ein Mini-PC) für eigene Projekte.
In diesem Repository liegt nur die Einrichtung, keine Daten und keine Schlüssel.

```
iPhone / Laptop ──Tailscale (HTTPS)──▶ homeserver
                                         └── Caddy :8080 (zentraler Eingang)
                                               ├── /finanzen  → FinTS-Brücke (Meine Finanzen)
                                               └── /…         → weitere Projekte
```

- **Docker:** Jedes Projekt läuft in eigenen Containern, mit eigenem Ordner unter `/srv/projects/<name>`.
- **Tailscale:** Zugriff nur von deinen eigenen Geräten. Nichts ist öffentlich im Internet, am Router muss nichts freigegeben werden.
- **Caddy:** verteilt Anfragen anhand des Pfades an das passende Projekt.
- **Pflege:** Sicherheitsupdates installieren sich automatisch, Container starten nach einem Stromausfall von selbst neu, jede Nacht wird ein Backup gemacht.

## Erstinstallation

Voraussetzungen: Raspberry Pi OS Lite **(64-bit)**, SSH aktiviert, ein Tailscale-Konto. In der Tailscale-Verwaltung
unter **DNS** müssen **MagicDNS** und **HTTPS Certificates** eingeschaltet sein.

```bash
ssh DEINNAME@homeserver.local
git clone https://github.com/JGHosting/homeserver.git
cd homeserver
bash setup.sh
```

Das Skript fragt einmal nach deinem Passwort und zeigt einen Tailscale-Anmeldelink. Am Ende nennt es die Adresse des
Servers, z. B. `https://homeserver.tail1234.ts.net`. Danach einmal ab- und wieder anmelden, damit `docker` ohne
`sudo` funktioniert.

## Projekt: Meine Finanzen (FinTS-Brücke)

Sobald die FinTS-Registrierungsnummer da ist:

```bash
nano /srv/projects/finanzen/.env     # FINTS_BLZ, FINTS_USER, FINTS_PRODUCT_ID eintragen (BRIDGE_TOKEN ist schon erzeugt)
cd /srv/projects/finanzen
docker compose up -d
docker compose logs -f               # sollte "FinTS-Brücke läuft …" zeigen (Strg+C zum Beenden)
```

In der App unter Mehr → Bankverbindung:
- **Adresse:** `https://homeserver.<tailnet>.ts.net/finanzen`
- **Zugangsschlüssel:** der Wert von `BRIDGE_TOKEN` (`grep BRIDGE_TOKEN /srv/projects/finanzen/.env`)

Auf dem iPhone muss beim Synchronisieren die Tailscale-App verbunden sein.

**Aktualisieren** (das Image baut GitHub automatisch bei jeder Änderung):
```bash
cd /srv/projects/finanzen && docker compose pull && docker compose up -d
```

## Neues Projekt hinzufügen

1. Ordner anlegen: `mkdir -p /srv/projects/<name>` mit einer `docker-compose.yml`. Der Container hängt sich ins Netz
   `web` und bekommt einen festen Namen:
   ```yaml
   services:
     app:
       image: …
       container_name: <name>-app
       env_file: .env
       volumes: [./data:/data]
       networks: [web]
       restart: unless-stopped
   networks:
     web:
       external: true
   ```
2. In `/srv/proxy/Caddyfile` einen Block ergänzen:
   ```
   handle_path /<name>/* {
       reverse_proxy <name>-app:<port>
   }
   ```
3. Starten: `cd /srv/projects/<name> && docker compose up -d` und
   `docker compose -f /srv/proxy/docker-compose.yml restart caddy`.
4. Die Vorlage hier im Repo unter `projects/<name>/` ablegen, damit eine Neuinstallation sie wieder mitbringt.

Kein Port wird nach außen geöffnet. Erreichbar ist alles nur über Tailscale unter `https://homeserver…/name`.

## Backup & Wiederherstellung

- Jede Nacht um 03:30 Uhr: `/srv/backup/homeserver-JJJJ-MM-TT.tar.gz` mit Konfiguration und Daten aller Projekte, die letzten 14 Tage.
- Von Hand: `sudo homeserver-backup`
- Ab und zu auf einen anderen Rechner holen: `scp DEINNAME@homeserver.local:/srv/backup/homeserver-*.tar.gz .`
- Wiederherstellen (z. B. auf neuem Gerät nach `setup.sh`): `sudo tar -xzf homeserver-….tar.gz -C /srv` und die Projekte neu starten.

Die Finanzdaten selbst liegen nicht auf dem Server, sondern nur in der App auf dem iPhone. Deren Backup machst du
in der App.

## Nützliche Befehle

| Was | Befehl |
|---|---|
| Was läuft? | `docker ps` |
| Logs eines Projekts | `cd /srv/projects/<name> && docker compose logs -f` |
| Projekt neu starten | `docker compose restart` |
| Tailscale-Adresse | `tailscale status` / `tailscale serve status` |
| Speicher, Temperatur | `free -h`, `df -h`, `vcgencmd measure_temp` |

## Umzug auf einen Mini-PC

Debian oder Ubuntu Server installieren, dieses Repo klonen, `bash setup.sh`, dann das letzte Backup nach `/srv`
entpacken und die Projekte starten. Alle Ordner und Compose-Dateien bleiben gleich.
