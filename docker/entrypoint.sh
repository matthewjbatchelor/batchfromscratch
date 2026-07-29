#!/usr/bin/env bash
# Railway-specific preparation, then hand control to the official WordPress entrypoint.
#
# Everything here is idempotent: Railway restarts containers freely and the same
# script has to produce the same result on a cold boot and on a redeploy over an
# existing volume.
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 0. Unwrap a shell-wrapped command
# ---------------------------------------------------------------------------
# Railway runs a custom start command through a shell, so the container is invoked
# as `/bin/sh -c apache2-foreground` rather than `apache2-foreground`. The upstream
# WordPress entrypoint gates all of its work on `$1` starting with "apache2", so a
# wrapped command skips the copy out of /usr/src/wordpress and the generation of
# wp-config.php — Apache then serves an empty document root and every request 404s.
# railway.json no longer sets a start command, but one set in the Railway dashboard
# overrides the file, so the wrapping is undone here rather than merely avoided.
if [ "$#" -eq 3 ] && [ "$2" = '-c' ]; then
    case "$1" in
        sh|bash|/bin/sh|/bin/bash|/usr/bin/sh|/usr/bin/bash)
            case "$3" in
                # Anything containing shell syntax is left wrapped: splitting it on
                # whitespace here would change what it means, and a redirect or an
                # && chain genuinely does need a shell to run it.
                *[\;\&\|\<\>\$\(\)\`\'\"\\]*) ;;
                apache2*|php-fpm*)
                    log "unwrapping shell-wrapped start command: $3"
                    # Deliberately unquoted — splitting on whitespace was the only
                    # remaining job of the wrapper we are removing.
                    # shellcheck disable=SC2086
                    set -- $3
                    ;;
            esac
            ;;
    esac
fi
log "command: $*"

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
# 4. Health endpoint
# ---------------------------------------------------------------------------
# Installed on every boot, before WordPress exists, so that Railway's health check
# passes as soon as Apache is up and reports honestly if the WordPress install step
# later goes wrong. On a genuinely first boot this makes the document root non-empty
# and the upstream entrypoint logs "WARNING: /var/www/html is not empty! (copying
# anyhow)" — expected, and it does copy anyhow.
install -o www-data -g www-data -m 0644 \
    /usr/local/share/batchfromscratch/healthz.php \
    /var/www/html/healthz.php

# ---------------------------------------------------------------------------
# 5. Hand off
# ---------------------------------------------------------------------------
# The upstream entrypoint only performs its setup when the command starts with
# "apache2", so it is invoked with the real command rather than a wrapper script.
log "handing off to the WordPress entrypoint"
exec docker-entrypoint.sh "$@"
