#!/usr/bin/env bash
# MCAP - native (no Docker) production deploy: Django + Gunicorn + PostgreSQL + Nginx.
# Target: Debian 12 / Ubuntu 22.04+ (run as root or with sudo).
#
# Usage:
#   sudo ./deploy.sh deploy             first-time install (prompts for token, .env, TLS email)
#   sudo ./deploy.sh update             backup, pull, deps, migrate, restart (auto-rollback of code on failed health check)
#   sudo ./deploy.sh backup             DB + public media + private media
#   sudo ./deploy.sh restore [TS]       no TS = list available backups
#   sudo ./deploy.sh status | restart | health
#   sudo ./deploy.sh logs [app|access|nginx|deploy|all]
#   sudo ./deploy.sh manage <args...>   run manage.py as the app user (e.g. manage shell)
#
# Env vars (all optional):
#   REPO_URL, BRANCH, APP_DIR, APP_USER, PY_VERSION, SERVER_NAME, WORKERS
#   LETSENCRYPT_EMAIL   enables HTTPS via Let's Encrypt (webroot) for SERVER_NAME
#   SETUP_FIREWALL      1 (default) = configure ufw + fail2ban; 0 = skip
#   PUBLIC_MEDIA_DIR    default $APP_DIR/media          (served by nginx at /media/)
#   PRIVATE_MEDIA_DIR   default $APP_DIR/private_media  (NOT exposed by nginx)
#   BACKUP_DIR          default /var/backups/mcap
#   KEEP_BACKUPS        default 14 backup sets
#   BACKUP_REMOTE       optional rsync target, e.g. user@host:/backups/mcap
#   BACKUP_SSH_KEY      optional ssh key for BACKUP_REMOTE
#   GIT_TOKEN / GIT_USER  HTTPS token auth (token is never written to disk)
#
# Logs:
#   /var/log/mcap/deploy.log           this script (rotated)
#   /var/log/mcap/gunicorn-error.log   app errors + captured stdout/stderr (Django logging to console)
#   /var/log/mcap/gunicorn-access.log  app access log
#   /var/log/nginx/mcap.{access,error}.log
#
# Source: if REPO_URL is empty, the directory containing this script is rsynced into APP_DIR.

set -Eeuo pipefail
cd /tmp

# --------------------------------------------------------------- config ---
NAME="mcap"
REPO_URL="${REPO_URL:-https://github.com/rijfas/mcap.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-/opt/mcap}"
APP_USER="${APP_USER:-mcap}"
PY_VERSION="${PY_VERSION:-3.14}"
SERVER_NAME="${SERVER_NAME:-mcap.dtekerala.in}"
GIT_TOKEN="${GIT_TOKEN:-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}"
GIT_USER="${GIT_USER:-git}"
DEPLOY_KEY="${DEPLOY_KEY:-/home/$APP_USER/.ssh/deploy_key}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
SETUP_FIREWALL="${SETUP_FIREWALL:-1}"

PUBLIC_MEDIA_DIR="${PUBLIC_MEDIA_DIR:-$APP_DIR/media}"
PRIVATE_MEDIA_DIR="${PRIVATE_MEDIA_DIR:-$APP_DIR/private_media}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/$NAME}"
KEEP_BACKUPS="${KEEP_BACKUPS:-14}"
BACKUP_REMOTE="${BACKUP_REMOTE:-}"
BACKUP_SSH_KEY="${BACKUP_SSH_KEY:-}"

_cpus="$(nproc 2>/dev/null || echo 1)"
_w=$(( _cpus * 2 + 1 )); [ "$_w" -gt 8 ] && _w=8
WORKERS="${WORKERS:-$_w}"

SERVICE="$NAME-gunicorn"
LOG_DIR="/var/log/$NAME"
LOG_FILE="$LOG_DIR/deploy.log"
NGINX_SITE="/etc/nginx/sites-available/$NAME"
CERT_DIR="/etc/letsencrypt/live/${SERVER_NAME%% *}"
ACME_ROOT="/var/www/certbot"
LOCK_FILE="/var/lock/$NAME-deploy.lock"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF")"

log()  { printf '[%s] ==> %s\n' "$(date '+%F %T')" "$*"; }
warn() { printf '[%s] [warn] %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { printf '[%s] [error] %s\n' "$(date '+%F %T')" "$*" >&2; exit 1; }
trap 'die "Failed at line $LINENO (command: $BASH_COMMAND)"' ERR

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo ./deploy.sh ...)"

IS_WSL=0
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL=1

require_systemd() {
  [ -d /run/systemd/system ] && return 0
  die "systemd is not running. On WSL, add these two lines to /etc/wsl.conf:  [boot] / systemd=true  then run 'wsl --shutdown' from Windows and reopen Ubuntu."
}


banner() {
  cat <<'BANNER'

 __  __   ____     _     ____  
|  \/  | / ___|   / \   |  _ \ 
| |\/| || |      / _ \  | |_) |
| |  | || |___  / ___ \ |  __/ 
|_|  |_| \____|/_/   \_\|_|    

BANNER
  printf '  Production deploy  |  host: %s  |  %s\n\n' "$(hostname)" "$(date '+%F %T')"
}

usage() {
  banner
  cat <<USAGE
Usage: sudo $0 <command> [args]

Setup & updates
  deploy                 First-time install (asks for GitHub token, .env values, HTTPS email)
  update                 Backup, pull latest code, migrate, restart (auto-rollback of code if unhealthy)

Operations
  status                 Show service status (app, nginx, postgresql, backup timer)
  health                 Quick health check of the app
  restart                Restart the app and reload nginx
  logs [name]            Tail logs: app (default) | access | nginx | deploy | systemd | all
  manage <args...>       Run manage.py as the app user (e.g. manage shell, manage createsuperuser)

Backups
  backup                 Backup database + public media + private media
  restore [timestamp]    Restore a backup (no timestamp = list available backups)

Common environment variables
  SERVER_NAME=$SERVER_NAME
  LETSENCRYPT_EMAIL=you@example.com   Enable HTTPS (Let's Encrypt)
  REPO_URL, BRANCH=$BRANCH, APP_DIR=$APP_DIR, APP_USER=$APP_USER
  WORKERS=$WORKERS, PY_VERSION=$PY_VERSION, SETUP_FIREWALL=$SETUP_FIREWALL
  BACKUP_DIR=$BACKUP_DIR, KEEP_BACKUPS=$KEEP_BACKUPS, BACKUP_REMOTE=<user@host:/path>

Examples
  sudo ./deploy.sh deploy
  sudo LETSENCRYPT_EMAIL=ops@example.com ./deploy.sh deploy
  sudo ./deploy.sh update
  sudo ./deploy.sh logs access
  sudo ./deploy.sh restore 20261104_021500

Logs: $LOG_DIR/   Backups: $BACKUP_DIR/
USAGE
}


# ------------------------------------------------------ logging / locking ---
setup_logging() {
  install -d -m 755 "$LOG_DIR"
  touch "$LOG_FILE"; chmod 640 "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
  banner
  log "---- $NAME: '$*' started by ${SUDO_USER:-root} on $(hostname) ----"
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Another $NAME deploy/backup/restore is already running."
}

# ---------------------------------------------------------------- helpers ---
# Run a command as the app user inside APP_DIR with .env loaded and venv on PATH
as_app() {
  sudo -u "$APP_USER" -H bash -c "
    set -Eeuo pipefail
    cd '$APP_DIR'
    set -a; . ./.env; set +a
    export UV_PROJECT_ENVIRONMENT='$APP_DIR/.venv'
    export PATH='$APP_DIR/.venv/bin:/usr/local/bin:'\"\$PATH\"
    $*
  "
}

have_tty() { { : </dev/tty; } 2>/dev/null; }

# ask VAR "Prompt" [default] [secret]   (prompts go to the terminal only, never to the log)
ask() {
  local __n="$1" __p="$2" __d="${3:-}" __s="${4:-}" __v=""
  if [ "$__s" = secret ]; then
    printf '%s: ' "$__p" >/dev/tty
    read -rs __v </dev/tty; printf '\n' >/dev/tty
  else
    printf '%s%s: ' "$__p" "${__d:+ [$__d]}" >/dev/tty
    read -r __v </dev/tty
  fi
  printf -v "$__n" '%s' "${__v:-$__d}"
}

rand() { head -c 96 /dev/urandom | base64 | tr -d '\n=+/' | cut -c1-"${1:-32}"; }

# wrap in single quotes for .env (works for bash and systemd); reject embedded '
sq() {
  case "$1" in *"'"*) die "Single quotes (') are not allowed in values." ;; esac
  printf "'%s'" "$1"
}

# ---------------------------------------------------------------- prompts ---
collect_git_token() {
  if [ -n "$GIT_TOKEN" ]; then return 0; fi
  if [[ "$REPO_URL" =~ ^https:// ]]; then
    have_tty || die "No terminal available. Run with GIT_TOKEN=... in the environment."
    echo "Repository: $REPO_URL" >/dev/tty
    ask GIT_TOKEN "GitHub personal access token (input hidden)" "" secret
    [ -n "$GIT_TOKEN" ] || die "A token is required for the private repository."
  fi
}

ENV_TMP=""
collect_env() {
  local envf="$APP_DIR/.env" a
  have_tty || return 0
  if [ -f "$envf" ]; then
    printf 'Existing %s found. Keep it? [Y/n]: ' "$envf" >/dev/tty
    read -r a </dev/tty
    case "${a:-Y}" in [Nn]*) ;; *) return 0 ;; esac
  fi

  local db_name db_user db_pass db_host db_port adm_user adm_pass secret debug hosts
  local em_host em_port em_user em_pass em_tls em_from
  { echo; echo "== Environment configuration (Enter accepts the [default]) =="; } >/dev/tty
  ask db_name  "Database name" "mcap"
  ask db_user  "Database user" "mcap"
  ask db_pass  "Database password (blank = generate)" "" secret
  [ -n "$db_pass" ] || db_pass="$(rand 32)"
  ask db_host  "Database host" "localhost"
  ask db_port  "Database port" "5432"
  ask adm_user "Admin username / email" "admin@example.com"
  ask adm_pass "Admin password (blank = generate)" "" secret
  if [ -z "$adm_pass" ]; then
    adm_pass="$(rand 20)"
    echo "Generated admin password (save it now): $adm_pass" >/dev/tty   # not logged
  fi
  ask secret   "Django SECRET_KEY (blank = generate)" "" secret
  [ -n "$secret" ] || secret="$(rand 64)"
  ask debug    "Django DEBUG (True/False)" "False"
  ask hosts    "Allowed hosts (comma separated)" "127.0.0.1,localhost,${SERVER_NAME%% *}"
  { echo; echo "== Email (SMTP) =="; } >/dev/tty
  ask em_host  "EMAIL_HOST" "localhost"
  ask em_port  "EMAIL_PORT" "587"
  ask em_user  "EMAIL_HOST_USER" ""
  ask em_pass  "EMAIL_HOST_PASSWORD (input hidden)" "" secret
  ask em_tls   "EMAIL_USE_TLS (True/False)" "True"
  ask em_from  "DEFAULT_FROM_EMAIL" "no-reply@${SERVER_NAME%% *}"

  ENV_TMP="$(mktemp)"; chmod 600 "$ENV_TMP"
  {
    echo "# --- Database ---"
    echo "DB_NAME=$(sq "$db_name")"
    echo "DB_USER=$(sq "$db_user")"
    echo "DB_PASSWORD=$(sq "$db_pass")"
    echo "DB_HOST=$(sq "$db_host")"
    echo "DB_PORT=$(sq "$db_port")"
    echo
    echo "# --- Default admin ---"
    echo "DEFAULT_USERNAME=$(sq "$adm_user")"
    echo "DEFAULT_PASSWORD=$(sq "$adm_pass")"
    echo
    echo "# --- Django ---"
    echo "SECRET_KEY=$(sq "$secret")"
    echo "DEBUG=$(sq "$debug")"
    echo "ALLOWED_HOSTS=$(sq "$hosts")"
    echo
    echo "# --- Email ---"
    echo "EMAIL_HOST=$(sq "$em_host")"
    echo "EMAIL_PORT=$(sq "$em_port")"
    echo "EMAIL_HOST_USER=$(sq "$em_user")"
    echo "EMAIL_HOST_PASSWORD=$(sq "$em_pass")"
    echo "EMAIL_USE_TLS=$(sq "$em_tls")"
    echo "DEFAULT_FROM_EMAIL=$(sq "$em_from")"
  } > "$ENV_TMP"
}

collect_tls_email() {
  [ -z "$LETSENCRYPT_EMAIL" ] || return 0
  [ "$SERVER_NAME" != "_" ] || return 0
  [ ! -f "$CERT_DIR/fullchain.pem" ] || return 0
  have_tty || return 0
  ask LETSENCRYPT_EMAIL "Email for Let's Encrypt HTTPS certificate (blank = HTTP only)" ""
}

# ------------------------------------------------------------- packages ---
install_packages() {
  log "Installing system packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  # gdk-pixbuf was renamed (libgdk-pixbuf2.0-0 -> libgdk-pixbuf-2.0-0) in newer Debian/Ubuntu
  local pixbuf_pkg
  if apt-cache show libgdk-pixbuf-2.0-0 >/dev/null 2>&1; then
    pixbuf_pkg="libgdk-pixbuf-2.0-0"
  else
    pixbuf_pkg="libgdk-pixbuf2.0-0"
  fi
  apt-get install -y --no-install-recommends \
    build-essential libpq-dev libffi-dev \
    postgresql postgresql-client \
    nginx git curl rsync openssh-client ca-certificates logrotate \
    libpango-1.0-0 libpangocairo-1.0-0 libcairo2 "$pixbuf_pkg" \
    shared-mime-info fonts-liberation fonts-noto-core fonts-noto-extra
  systemctl enable --now postgresql nginx

  if ! command -v uv >/dev/null 2>&1; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh \
      | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
  fi
}

ensure_user() {
  if ! id "$APP_USER" >/dev/null 2>&1; then
    log "Creating user $APP_USER..."
    useradd --system --create-home --shell /bin/bash "$APP_USER"
  fi
  install -d -o "$APP_USER" -g adm -m 750 "$LOG_DIR"
  chown "$APP_USER:adm" "$LOG_FILE" 2>/dev/null || true
  install -d -m 700 "$BACKUP_DIR"
}

# ---------------------------------------------------------------- source ---
git_as_app() {
  local askpass="" rc=0
  local -a envs=(GIT_TERMINAL_PROMPT=0)
  if [ -n "$GIT_TOKEN" ]; then
    askpass="$(mktemp)"
    printf '%s\n' '#!/bin/sh' \
      'case "$1" in Username*) echo "$GIT_USER";; *) echo "$GIT_TOKEN";; esac' > "$askpass"
    chown "$APP_USER" "$askpass"; chmod 700 "$askpass"
    envs+=(GIT_ASKPASS="$askpass" GIT_TOKEN="$GIT_TOKEN" GIT_USER="$GIT_USER")
  fi
  if [ -f "$DEPLOY_KEY" ]; then
    envs+=(GIT_SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/home/$APP_USER/.ssh/known_hosts")
  fi
  ( cd /tmp && sudo -u "$APP_USER" -H env "${envs[@]}" git "$@" ) || rc=$?
  if [ -n "$askpass" ]; then rm -f "$askpass"; fi
  return "$rc"
}

setup_git_auth() {
  [ -n "$REPO_URL" ] || return 0
  if [[ "$REPO_URL" =~ ^(git@|ssh://) ]]; then
    local home="/home/$APP_USER" host
    host="$(printf '%s' "$REPO_URL" \
      | sed -E 's#^ssh://([^@]+@)?([^/:]+).*#\2#; s#^[^@]+@([^:]+):.*#\1#')"
    install -d -m 700 -o "$APP_USER" -g "$APP_USER" "$home/.ssh"
    if [ ! -f "$DEPLOY_KEY" ]; then
      log "Generating deploy key $DEPLOY_KEY ..."
      sudo -u "$APP_USER" ssh-keygen -q -t ed25519 -N "" -C "deploy@$(hostname)" -f "$DEPLOY_KEY"
      {
        echo
        echo "Add this public key as a READ-ONLY deploy key on your repository:"
        echo "----------------------------------------------------------------"
        cat "$DEPLOY_KEY.pub"
        echo "----------------------------------------------------------------"
      } >/dev/tty 2>/dev/null || cat "$DEPLOY_KEY.pub"
      have_tty || die "Add the key above to the repo, then re-run."
      printf 'Press Enter once the key has been added... ' >/dev/tty
      read -r _ </dev/tty
    fi
    if ! sudo -u "$APP_USER" ssh-keygen -F "$host" -f "$home/.ssh/known_hosts" >/dev/null 2>&1; then
      log "Trusting SSH host key for $host (first use)..."
      ssh-keyscan -H "$host" 2>/dev/null \
        | sudo -u "$APP_USER" tee -a "$home/.ssh/known_hosts" >/dev/null
      chmod 600 "$home/.ssh/known_hosts"
    fi
  elif [[ "$REPO_URL" =~ ^https:// ]]; then
    [ -n "$GIT_TOKEN" ] || die "Private HTTPS repo needs GIT_TOKEN, or use an SSH REPO_URL."
    log "Checking access to $REPO_URL ..."
    git_as_app ls-remote --exit-code "$REPO_URL" HEAD >/dev/null 2>&1 \
      || die "Cannot access the repository. Check the token (needs repo read access) and URL."
  fi
}

sync_source() {
  install -d -o "$APP_USER" -g "$APP_USER" "$APP_DIR"
  chown -R "$APP_USER:$APP_USER" "$APP_DIR"
  if [ -n "$REPO_URL" ] || [ -d "$APP_DIR/.git" ]; then
    setup_git_auth
    if [ -d "$APP_DIR/.git" ]; then
      log "Updating repo ($BRANCH)..."
      git_as_app -C "$APP_DIR" fetch --all --prune
      git_as_app -C "$APP_DIR" checkout "$BRANCH"
      git_as_app -C "$APP_DIR" pull --ff-only origin "$BRANCH"
    else
      [ -z "$(ls -A "$APP_DIR")" ] || die "$APP_DIR is not empty and is not a git repo."
      log "Cloning $REPO_URL ..."
      git_as_app clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
    fi
  elif [ "$SCRIPT_DIR" != "$APP_DIR" ]; then
    log "Copying project from $SCRIPT_DIR to $APP_DIR..."
    rsync -a --delete \
      --exclude '.git' --exclude '.venv' --exclude '.python' --exclude '.env' \
      --exclude 'staticfiles' --exclude 'media' --exclude 'private_media' \
      --exclude 'backups' --exclude '__pycache__' \
      "$SCRIPT_DIR/" "$APP_DIR/"
  fi
  [ -f "$APP_DIR/pyproject.toml" ] || die "pyproject.toml not found in $APP_DIR"

  mkdir -p "$APP_DIR/staticfiles" "$PUBLIC_MEDIA_DIR" "$PRIVATE_MEDIA_DIR"
  chown -R "$APP_USER:$APP_USER" "$APP_DIR" "$PUBLIC_MEDIA_DIR" "$PRIVATE_MEDIA_DIR"
  chmod 755 "$APP_DIR" "$PUBLIC_MEDIA_DIR"
  chmod 750 "$PRIVATE_MEDIA_DIR"   # nginx (www-data) must not read this
}

# ------------------------------------------------------------------- env ---
check_env() {
  local envf="$APP_DIR/.env" v
  if [ -n "$ENV_TMP" ] && [ -f "$ENV_TMP" ]; then
    if [ -f "$envf" ]; then
      cp -p "$envf" "$envf.bak.$(date +%Y%m%d_%H%M%S)"
      log "Existing .env saved as a .bak file."
    fi
    install -m 600 -o "$APP_USER" -g "$APP_USER" "$ENV_TMP" "$envf"
    rm -f "$ENV_TMP"; ENV_TMP=""
    log "Wrote $envf"
  fi
  if [ ! -f "$envf" ]; then
    cat > "$envf" <<EOF
# --- Database ---
DB_NAME=mcap
DB_USER=mcap
DB_PASSWORD=change-me
DB_HOST=localhost
DB_PORT=5432

# --- Default admin (created on first deploy) ---
DEFAULT_USERNAME=admin@example.com
DEFAULT_PASSWORD=change-me

# --- Django ---
SECRET_KEY=change-me
DEBUG=False
ALLOWED_HOSTS=127.0.0.1,localhost,${SERVER_NAME%% *}

# --- Email ---
EMAIL_HOST=localhost
EMAIL_PORT=587
EMAIL_HOST_USER=change-me
EMAIL_HOST_PASSWORD=change-me
EMAIL_USE_TLS=True
DEFAULT_FROM_EMAIL=no-reply@${SERVER_NAME%% *}
EOF
    chown "$APP_USER:$APP_USER" "$envf"; chmod 600 "$envf"
    die "Created template $envf. Edit it with real values, then re-run."
  fi
  chown "$APP_USER:$APP_USER" "$envf"; chmod 600 "$envf"

  set -a; . "$envf"; set +a
  for v in SECRET_KEY DEBUG ALLOWED_HOSTS DB_NAME DB_USER DB_PASSWORD DB_HOST DB_PORT \
           EMAIL_HOST EMAIL_PORT EMAIL_USE_TLS DEFAULT_FROM_EMAIL DEFAULT_USERNAME DEFAULT_PASSWORD; do
    [ -n "${!v:-}" ] || die "Missing $v in $envf"
  done
  for v in SECRET_KEY DB_PASSWORD DEFAULT_PASSWORD; do
    case "${!v}" in *change-me*) die "$v in $envf is still the 'change-me' placeholder." ;; esac
  done
  [ "${#SECRET_KEY}" -ge 32 ] || warn "SECRET_KEY is shorter than 32 characters."
  case "${DEBUG,,}" in true|1|yes|on) warn "DEBUG is enabled - do NOT run production with DEBUG=True." ;; esac
  for kv in "PUBLIC_MEDIA_DIR=$PUBLIC_MEDIA_DIR" "PRIVATE_MEDIA_DIR=$PRIVATE_MEDIA_DIR"; do
    grep -q "^${kv%%=*}=" "$envf" || echo "$kv" >> "$envf"
  done
  grep -q 'change-me' "$envf" && warn ".env still contains 'change-me' placeholders (email?)."
  return 0
}

# -------------------------------------------------------------- database ---
db_is_local() { case "${DB_HOST:-localhost}" in localhost|127.0.0.1|::1) return 0 ;; *) return 1 ;; esac; }

setup_database() {
  set -a; . "$APP_DIR/.env"; set +a
  if ! db_is_local; then
    log "DB_HOST=$DB_HOST is remote; skipping local PostgreSQL role/database setup."
    return 0
  fi
  log "Ensuring PostgreSQL role and database exist..."
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -v u="$DB_USER" -v p="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'u', :'p')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('ALTER ROLE %I WITH PASSWORD %L', :'u', :'p') \gexec
SQL
  sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -v d="$DB_NAME" -v u="$DB_USER" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'d', :'u')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'d') \gexec
SQL
}

# --------------------------------------------------------------- backups ---
backup_all() {
  set -a; . "$APP_DIR/.env"; set +a
  db_is_local || die "Backups only support a local PostgreSQL (DB_HOST=$DB_HOST)."
  local ts dest tmp name dir
  ts="$(date +%Y%m%d_%H%M%S)"
  dest="$BACKUP_DIR/$ts"
  tmp="$BACKUP_DIR/.$ts.partial"
  install -d -m 700 "$BACKUP_DIR" "$tmp"
  trap 'rm -rf "$tmp"; die "Backup failed at line $LINENO"' ERR

  log "Backing up database..."
  sudo -u postgres pg_dump "$DB_NAME" | gzip > "$tmp/db.sql.gz"

  for name in public private; do
    if [ "$name" = public ]; then dir="$PUBLIC_MEDIA_DIR"; else dir="$PRIVATE_MEDIA_DIR"; fi
    if [ -d "$dir" ]; then
      log "Backing up $name media ($dir)..."
      tar -czf "$tmp/media_$name.tar.gz" -C "$dir" .
    else
      warn "$name media dir $dir not found; skipping."
    fi
  done

  ( cd "$tmp" && sha256sum ./* > SHA256SUMS )
  mv "$tmp" "$dest"
  trap 'die "Failed at line $LINENO (command: $BASH_COMMAND)"' ERR

  # retention
  ls -1dt "$BACKUP_DIR"/*/ 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -rf

  if [ -n "$BACKUP_REMOTE" ]; then
    log "Copying backup to $BACKUP_REMOTE ..."
    local ssh_cmd="ssh"
    [ -n "$BACKUP_SSH_KEY" ] && ssh_cmd="ssh -i $BACKUP_SSH_KEY"
    rsync -a -e "$ssh_cmd" "$dest" "$BACKUP_REMOTE/" || warn "Offsite copy failed."
  fi
  log "Backup complete: $dest"
}

restore_backup() {
  local ts="${1:-}" ans
  if [ -z "$ts" ]; then
    echo "Available backups in $BACKUP_DIR:"; ls -1 "$BACKUP_DIR" 2>/dev/null | grep -v '^\.' || true
    die "Usage: $0 restore <timestamp>"
  fi
  local src="$BACKUP_DIR/$ts"
  [ -d "$src" ] || die "Backup $src not found."
  set -a; . "$APP_DIR/.env"; set +a
  have_tty || die "Restore needs an interactive terminal."

  printf "This REPLACES the database and both media dirs with backup %s. Type 'yes': " "$ts" >/dev/tty
  read -r ans </dev/tty
  [ "$ans" = yes ] || die "Aborted."

  log "Verifying checksums..."
  ( cd "$src" && sha256sum -c SHA256SUMS )

  log "Taking a safety backup of the current state first..."
  backup_all

  systemctl stop "$SERVICE" || true
  log "Restoring database..."
  sudo -u postgres dropdb --if-exists "$DB_NAME"
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
  gunzip -c "$src/db.sql.gz" | sudo -u postgres psql -v ON_ERROR_STOP=1 -q "$DB_NAME"

  local name dir
  for name in public private; do
    if [ "$name" = public ]; then dir="$PUBLIC_MEDIA_DIR"; else dir="$PRIVATE_MEDIA_DIR"; fi
    if [ -f "$src/media_$name.tar.gz" ]; then
      log "Restoring $name media..."
      mkdir -p "$dir"
      find "$dir" -mindepth 1 -delete
      tar -xzf "$src/media_$name.tar.gz" -C "$dir"
      chown -R "$APP_USER:$APP_USER" "$dir"
    fi
  done
  systemctl start "$SERVICE"
  log "Restore complete."
}

write_backup_timer() {
  log "Installing daily backup timer..."
  cat > "/etc/systemd/system/$NAME-backup.service" <<EOF
[Unit]
Description=MCAP backup (database + media)

[Service]
Type=oneshot
ExecStart=$SELF backup
Nice=10
IOSchedulingClass=idle
EOF
  cat > "/etc/systemd/system/$NAME-backup.timer" <<EOF
[Unit]
Description=Daily MCAP backup

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$NAME-backup.timer"
}

# ------------------------------------------------------------ python app ---
install_python_deps() {
  log "Installing Python $PY_VERSION and dependencies with uv..."
  sudo -u "$APP_USER" -H bash -c "
    set -Eeuo pipefail
    cd '$APP_DIR'
    export UV_PROJECT_ENVIRONMENT='$APP_DIR/.venv' UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
    export UV_PYTHON_INSTALL_DIR='$APP_DIR/.python'
    uv python install '$PY_VERSION'
    uv sync --frozen --no-dev --python '$PY_VERSION'
  "
}

run_django_tasks() {
  log "Applying migrations..."
  as_app "python manage.py migrate --noinput"

  if [ -f "$APP_DIR/seed/seed.py" ]; then
    log "Seeding initial data..."
    as_app "python seed/seed.py"
  fi

  log "Creating admin user (skipped if it exists)..."
  as_app "
    export DJANGO_SUPERUSER_USERNAME=\"\$DEFAULT_USERNAME\"
    export DJANGO_SUPERUSER_PASSWORD=\"\$DEFAULT_PASSWORD\"
    export DJANGO_SUPERUSER_EMAIL=\"\$DEFAULT_USERNAME\"
    python manage.py createsuperuser --noinput || true
  "

  log "Collecting static files..."
  as_app "python manage.py collectstatic --noinput"

  log "Django deployment checks (informational)..."
  as_app "python manage.py check --deploy" || warn "check --deploy reported issues (see above)."
}

# --------------------------------------------------------------- systemd ---
write_systemd() {
  log "Writing systemd unit /etc/systemd/system/${SERVICE}.service ..."
  cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=MCAP Gunicorn (Django)
After=network.target postgresql.service
Wants=postgresql.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
Environment=PYTHONUNBUFFERED=1
Environment=HOME=/var/cache/$NAME
Environment=XDG_CACHE_HOME=/var/cache/$NAME
CacheDirectory=$NAME
UMask=0022
ExecStart=$APP_DIR/.venv/bin/gunicorn config.wsgi:application \\
    --bind 127.0.0.1:8000 \\
    --workers $WORKERS \\
    --worker-tmp-dir /dev/shm \\
    --timeout 90 \\
    --graceful-timeout 30 \\
    --max-requests 1000 \\
    --max-requests-jitter 100 \\
    --access-logfile $LOG_DIR/gunicorn-access.log \\
    --error-logfile $LOG_DIR/gunicorn-error.log \\
    --log-level info \\
    --capture-output
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3
KillMode=mixed
TimeoutStopSec=30
LimitNOFILE=65535

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
ReadWritePaths=$PUBLIC_MEDIA_DIR $PRIVATE_MEDIA_DIR $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE"
}

write_logrotate() {
  log "Writing logrotate config..."
  cat > "/etc/logrotate.d/$NAME" <<EOF
$LOG_DIR/*.log {
    su $APP_USER adm
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    create 640 $APP_USER adm
    postrotate
        systemctl kill --kill-who=main --signal=USR1 $SERVICE.service >/dev/null 2>&1 || true
    endscript
}
EOF
}

# ----------------------------------------------------------------- nginx ---
nginx_common() {
  cat <<EOF
    client_max_body_size 50M;
    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
    }

    location ~ /\\.(?!well-known) { deny all; }

    location /static/ {
        alias $APP_DIR/staticfiles/;
        expires 30d;
        access_log off;
        include /etc/nginx/snippets/$NAME-security-headers.conf;
    }

    location /media/ {
        alias $PUBLIC_MEDIA_DIR/;
        expires 7d;
        include /etc/nginx/snippets/$NAME-security-headers.conf;
    }

    location / {
        limit_req zone=${NAME}_req burst=60 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 90s;
        proxy_send_timeout 90s;
    }
EOF
}

write_nginx() {
  log "Writing nginx config..."
  install -d "$ACME_ROOT" /etc/nginx/snippets

  cat > "/etc/nginx/snippets/$NAME-security-headers.conf" <<'EOF'
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
EOF

  cat > "/etc/nginx/conf.d/$NAME-global.conf" <<EOF
# Managed by deploy.sh
limit_req_zone \$binary_remote_addr zone=${NAME}_req:10m rate=20r/s;
limit_req_status 429;
gzip on;
gzip_comp_level 5;
gzip_min_length 1024;
gzip_vary on;
gzip_types text/plain text/css application/json application/javascript text/javascript application/xml image/svg+xml;
EOF

  local have_cert=0
  [ -f "$CERT_DIR/fullchain.pem" ] && have_cert=1

  {
    echo "# Managed by deploy.sh - edits will be overwritten"
    if [ "$have_cert" = 1 ]; then
      cat <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;
    access_log /var/log/nginx/$NAME.access.log;
    error_log  /var/log/nginx/$NAME.error.log;

    location ^~ /.well-known/acme-challenge/ { root $ACME_ROOT; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name $SERVER_NAME;
    access_log /var/log/nginx/$NAME.access.log;
    error_log  /var/log/nginx/$NAME.error.log;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    add_header Strict-Transport-Security "max-age=31536000" always;
    include /etc/nginx/snippets/$NAME-security-headers.conf;

$(nginx_common)
}
EOF
    else
      cat <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;
    access_log /var/log/nginx/$NAME.access.log;
    error_log  /var/log/nginx/$NAME.error.log;

    include /etc/nginx/snippets/$NAME-security-headers.conf;

$(nginx_common)
}
EOF
    fi
    if [ "$SERVER_NAME" != "_" ]; then
      cat <<'EOF'

# Reject requests for unknown hostnames / direct IP access
server {
    listen 80 default_server;
    server_name _;
    return 444;
}
EOF
      if [ "$have_cert" = 1 ]; then
        cat <<EOF

server {
    listen 443 ssl http2 default_server;
    server_name _;
    ssl_reject_handshake on;
}
EOF
      fi
    fi
  } > "$NGINX_SITE"

  ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/$NAME"
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx
}

setup_tls() {
  [ "$SERVER_NAME" != "_" ] || return 0
  if [ -f "$CERT_DIR/fullchain.pem" ]; then return 0; fi
  if [ -z "$LETSENCRYPT_EMAIL" ]; then
    warn "No LETSENCRYPT_EMAIL given: serving HTTP only. Re-run with LETSENCRYPT_EMAIL=you@example.com for HTTPS."
    return 0
  fi
  log "Requesting Let's Encrypt certificate for: $SERVER_NAME ..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends certbot
  local -a domains=()
  local d
  for d in $SERVER_NAME; do domains+=(-d "$d"); done
  if certbot certonly --webroot -w "$ACME_ROOT" --non-interactive --agree-tos \
       -m "$LETSENCRYPT_EMAIL" "${domains[@]}"; then
    install -d /etc/letsencrypt/renewal-hooks/deploy
    printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
    write_nginx
    log "HTTPS enabled. Auto-renewal runs via the certbot systemd timer."
  else
    warn "Certificate request failed (is DNS for $SERVER_NAME pointing at this server, and port 80 open?). Continuing with HTTP."
  fi
}

# -------------------------------------------------------------- firewall ---
setup_firewall() {
  if [ "$IS_WSL" = 1 ]; then log "WSL detected; skipping firewall setup."; return 0; fi
  [ "$SETUP_FIREWALL" = 1 ] || { log "Skipping firewall (SETUP_FIREWALL=0)."; return 0; }
  log "Configuring firewall (ufw) and fail2ban..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ufw fail2ban
  local ssh_port
  ssh_port="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
  ssh_port="${ssh_port:-22}"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${ssh_port}/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
  systemctl enable --now fail2ban
}

# ---------------------------------------------------------------- health ---
app_http_code() {
  curl -s -o /dev/null -m 10 -w '%{http_code}' -H 'X-Forwarded-Proto: https' http://127.0.0.1:8000/ || true
}

wait_healthy() {
  log "Waiting for gunicorn on 127.0.0.1:8000 ..."
  local code
  for _ in $(seq 1 40); do
    code="$(app_http_code)"
    if [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]; then
      log "App is up (HTTP $code)."; return 0
    fi
    sleep 2
  done
  warn "App did not respond. Recent logs:"
  journalctl -u "$SERVICE" -n 40 --no-pager || true
  tail -n 40 "$LOG_DIR/gunicorn-error.log" 2>/dev/null || true
  return 1
}

cmd_health() {
  local code; code="$(app_http_code)"
  echo "gunicorn: HTTP $code"
  systemctl is-active "$SERVICE" nginx postgresql || true
  [[ "$code" =~ ^[1-4][0-9][0-9]$ ]]
}

# ------------------------------------------------------------------ cmds ---
cmd_deploy() {
  collect_git_token
  collect_env
  collect_tls_email
  install_packages
  ensure_user
  sync_source
  check_env
  setup_database
  install_python_deps
  run_django_tasks
  write_systemd
  write_logrotate
  write_nginx
  setup_tls
  write_backup_timer
  setup_firewall
  systemctl restart "$SERVICE"
  wait_healthy || die "Deployment finished but the app is not healthy."
  log "Deployed. Visit http$([ -f "$CERT_DIR/fullchain.pem" ] && echo s)://${SERVER_NAME%% *}/"
}

rollback_code() {
  local prev="$1"
  [ -n "$prev" ] || { warn "No previous revision recorded; cannot roll back."; return 1; }
  warn "Rolling code back to $prev (database migrations are NOT reverted)..."
  git_as_app -C "$APP_DIR" reset --hard "$prev"
  install_python_deps
  as_app "python manage.py collectstatic --noinput" || true
  systemctl restart "$SERVICE"
  wait_healthy && warn "Rolled back to $prev; app is healthy." || warn "App still unhealthy after rollback."
}

cmd_update() {
  collect_git_token
  [ -f "$APP_DIR/.env" ] || die "$APP_DIR/.env not found. Run 'deploy' first."
  ensure_user
  backup_all || warn "Backup failed; continuing."
  local prev=""
  if [ -d "$APP_DIR/.git" ]; then prev="$(git_as_app -C "$APP_DIR" rev-parse HEAD 2>/dev/null || true)"; fi
  sync_source
  check_env
  install_python_deps
  run_django_tasks
  write_systemd
  write_logrotate
  write_nginx
  systemctl restart "$SERVICE"
  if ! wait_healthy; then
    rollback_code "$prev" || true
    die "Update failed health check."
  fi
  log "Update complete."
}

cmd_logs() {
  case "${1:-app}" in
    app)    exec tail -n 100 -F "$LOG_DIR/gunicorn-error.log" ;;
    access) exec tail -n 100 -F "$LOG_DIR/gunicorn-access.log" ;;
    nginx)  exec tail -n 100 -F "/var/log/nginx/$NAME.error.log" "/var/log/nginx/$NAME.access.log" ;;
    deploy) exec tail -n 200 -F "$LOG_FILE" ;;
    all)    exec tail -n 50 -F "$LOG_DIR"/*.log "/var/log/nginx/$NAME".*.log ;;
    systemd) exec journalctl -u "$SERVICE" -f -n 100 ;;
    *) die "Usage: $0 logs [app|access|nginx|deploy|systemd|all]" ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  deploy|update|backup|restore)
    require_systemd
    setup_logging "$@"
    acquire_lock
    ;;
esac

case "$cmd" in status|restart|health) banner ;; esac

case "$cmd" in
  deploy)  cmd_deploy ;;
  update)  cmd_update ;;
  backup)  ensure_user; backup_all ;;
  restore) restore_backup "${2:-}" ;;
  status)  systemctl --no-pager status "$SERVICE" nginx postgresql "$NAME-backup.timer" | cat ;;
  restart) systemctl restart "$SERVICE" && systemctl reload nginx && wait_healthy ;;
  health)  cmd_health ;;
  logs)    cmd_logs "${2:-app}" ;;
  manage)  shift; [ $# -gt 0 ] || die "Usage: $0 manage <args>"; as_app "python manage.py $(printf '%q ' "$@")" ;;
  *)       usage; exit 1 ;;
esac
