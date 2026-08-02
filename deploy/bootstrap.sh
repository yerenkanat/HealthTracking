#!/usr/bin/env bash
# =============================================================================
# Umay — fresh-box bootstrap (Ubuntu 22.04 / 24.04). REVIEW before running.
#
# Brings a clean server to a running full-stack deploy: Node 24, PostgreSQL,
# Caddy (auto-HTTPS), the backend as a systemd service, DB built from schema.sql.
# Idempotent-ish: safe-ish to re-run, but read it first — it is a starting point,
# not a fire-and-forget.
#
# Run as a sudo-capable NON-root user. Set the CONFIG values below first.
#   chmod +x deploy/bootstrap.sh && ./deploy/bootstrap.sh
# =============================================================================
set -euo pipefail

# ---- CONFIG (edit these) ----------------------------------------------------
REPO_URL="${REPO_URL:?set REPO_URL to the git remote (or pre-clone to /opt/umay)}"
APP_DIR="/opt/umay"
DB_NAME="umay"
DB_USER="umay"
DB_PASS="${DB_PASS:?set DB_PASS to a strong Postgres password}"
# -----------------------------------------------------------------------------

echo "==> Packages: Node 24, PostgreSQL, Caddy, git"
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs postgresql git debian-keyring debian-archive-keyring apt-transport-https curl
# Caddy (official repo)
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update && sudo apt-get install -y caddy
fi

echo "==> App user + code"
sudo useradd -r -m -d "$APP_DIR" -s /usr/sbin/nologin umay 2>/dev/null || true
if [ -d "$APP_DIR/.git" ]; then sudo -u umay git -C "$APP_DIR" pull; else sudo git clone "$REPO_URL" "$APP_DIR" && sudo chown -R umay:umay "$APP_DIR"; fi
sudo -u umay bash -c "cd $APP_DIR/packages/backend && npm ci"

echo "==> PostgreSQL role + database + schema"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
# Fresh build from schema.sql (verified to build all 32 tables cleanly).
PGPASSWORD="$DB_PASS" psql "postgres://$DB_USER@127.0.0.1:5432/$DB_NAME" -v ON_ERROR_STOP=1 -f "$APP_DIR/packages/backend/db/schema.sql"

echo "==> Env, service, reverse proxy"
sudo mkdir -p /etc/umay
[ -f /etc/umay/backend.env ] || { sudo cp "$APP_DIR/deploy/backend.env.example" /etc/umay/backend.env; echo "   -> edit /etc/umay/backend.env (DATABASE_URL password, REAL_AUTH, keys)"; }
sudo sed -i "s#CHANGE_ME_DB_PASSWORD#$DB_PASS#" /etc/umay/backend.env
sudo chmod 600 /etc/umay/backend.env && sudo chown umay:umay /etc/umay/backend.env
sudo cp "$APP_DIR/deploy/umay-backend.service" /etc/systemd/system/
sudo cp "$APP_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
echo "   -> set the admin basic-auth hash in /etc/caddy/Caddyfile (caddy hash-password)"

sudo systemctl daemon-reload
sudo systemctl enable --now umay-backend
sudo systemctl reload caddy || sudo systemctl restart caddy

echo "==> Smoke test"
sleep 3
curl -fsS http://127.0.0.1:8080/health && echo "  backend /health OK"

cat <<'DONE'

==> Bootstrap done. Remaining MANUAL steps:
  1. Edit /etc/umay/backend.env: REAL_AUTH Firebase service account, any keys.
  2. Set the admin basic-auth hash in /etc/caddy/Caddyfile, then: systemctl reload caddy
  3. Confirm DNS A records (ana-bala.kz, www, admin) point here so Caddy gets TLS.
  4. Build the app:  flutter build apk --release --dart-define=API_BASE=https://ana-bala.kz --dart-define=MAPS_ENABLED=true
  5. (Optional) deploy packages/cry-classifier with a trained model.pkl, set CRY_API_URL.
DONE
