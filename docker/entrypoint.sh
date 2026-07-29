#!/usr/bin/env bash
# Railway-specific preparation, then hand control to the official WordPress entrypoint.
#
# Everything here is idempotent: Railway restarts containers freely and the same
# script has to produce the same result on a cold boot and on a redeploy over an
# existing volume.
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Listen port
# ---------------------------------------------------------------------------
# Railway assigns the port at runtime via $PORT and routes to it. The upstream
# image hardcodes 80, so the vhost and ports.conf are both rewritten here.
PORT="${PORT:-80}"
log "binding Apache to port ${PORT}"
printf 'Listen %s\n' "${PORT}" > /etc/apache2/ports.conf
sed "s/__PORT__/${PORT}/g" \
    /etc/apache2/sites-available/000-default.conf.template \
    > /etc/apache2/sites-available/000-default.conf

# ---------------------------------------------------------------------------
# 2. Database wiring
# ---------------------------------------------------------------------------
# Railway's MySQL service publishes MYSQLHOST/MYSQLPORT/... and a MYSQL_URL.
# The WordPress image wants WORDPRESS_DB_*. Translate only when the WordPress
# variables are absent, so an explicit override in the Railway dashboard still wins.
if [ -z "${WORDPRESS_DB_HOST:-}" ]; then
    if [ -n "${MYSQLHOST:-}" ]; then
        export WORDPRESS_DB_HOST="${MYSQLHOST}:${MYSQLPORT:-3306}"
        export WORDPRESS_DB_USER="${MYSQLUSER:-root}"
        export WORDPRESS_DB_PASSWORD="${MYSQLPASSWORD:-}"
        export WORDPRESS_DB_NAME="${MYSQLDATABASE:-railway}"
        log "database resolved from MYSQL* variables (${MYSQLHOST})"
    elif [ -n "${MYSQL_URL:-}" ]; then
        # mysql://user:pass@host:port/db — parsed with PHP rather than a regex so
        # percent-encoded passwords survive intact.
        eval "$(php -r '
            $u = parse_url(getenv("MYSQL_URL"));
            $out = [
                "WORDPRESS_DB_HOST"     => $u["host"] . ":" . ($u["port"] ?? 3306),
                "WORDPRESS_DB_USER"     => rawurldecode($u["user"] ?? "root"),
                "WORDPRESS_DB_PASSWORD" => rawurldecode($u["pass"] ?? ""),
                "WORDPRESS_DB_NAME"     => ltrim($u["path"] ?? "/railway", "/"),
            ];
            foreach ($out as $k => $v) { printf("export %s=%s\n", $k, escapeshellarg($v)); }
        ')"
        log "database resolved from MYSQL_URL"
    else
        log "WARNING: no database variables found — WordPress will fail to connect"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Persistent wp-content
# ---------------------------------------------------------------------------
# A Railway volume is mounted at /var/www/html/wp-content so uploads and any
# admin-installed plugins survive a redeploy. The theme and mu-plugins are the
# opposite: they are owned by this repository, so they are pushed into the volume
# on every boot and any drift on the volume is discarded.
WP_CONTENT=/var/www/html/wp-content
mkdir -p "${WP_CONTENT}/uploads" "${WP_CONTENT}/themes" "${WP_CONTENT}/mu-plugins"

sync_from_image() {
    local src="$1" dest="$2"
    [ -d "${src}" ] || return 0
    log "syncing ${dest} from image"
    rsync -a --delete "${src}/" "${dest}/"
}

sync_from_image /usr/src/wordpress/wp-content/themes/batchfromscratch \
                "${WP_CONTENT}/themes/batchfromscratch"
sync_from_image /usr/src/wordpress/wp-content/mu-plugins \
                "${WP_CONTENT}/mu-plugins"

# Volumes come back owned by root; Apache runs as www-data and needs to write
# uploads. Restricted to the directories that actually need it — chowning a
# 1GB media library on every boot would add minutes to each deploy.
chown www-data:www-data "${WP_CONTENT}" "${WP_CONTENT}/uploads" || true
if [ ! -f "${WP_CONTENT}/.ownership-done" ]; then
    log "first boot on this volume — normalising ownership (may take a moment)"
    chown -R www-data:www-data "${WP_CONTENT}" || true
    touch "${WP_CONTENT}/.ownership-done"
fi

# ---------------------------------------------------------------------------
# 4. Hand off
# ---------------------------------------------------------------------------
# The upstream entrypoint only performs its setup when the command starts with
# "apache2", so it is invoked with the real command rather than a wrapper script.
log "handing off to the WordPress entrypoint"
exec docker-entrypoint.sh "$@"
