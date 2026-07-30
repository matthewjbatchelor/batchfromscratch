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

# Identify the image on every boot. A crash loop looks byte-identical across deploys,
# so without this there is no way to tell from the logs whether a fix has actually
# shipped or whether you are reading the previous deployment still cycling. Railway
# supplies the commit; the WordPress version comes from the image itself.
wp_version="$(grep -m1 "^\$wp_version" /usr/src/wordpress/wp-includes/version.php | cut -d"'" -f2 || true)"
log "image: WordPress ${wp_version:-unknown}, commit ${RAILWAY_GIT_COMMIT_SHA:-unset}"

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
# 2. Apache module sanity
# ---------------------------------------------------------------------------
# Apache exits at startup with "AH00534: More than one MPM loaded" if more than one
# is enabled, and because it never binds, the symptom is a refused connection rather
# than an error page — it reads as a network fault and sends you looking in the wrong
# place. The Dockerfile enables exactly one and asserts it with `apache2ctl
# configtest`, so a build that succeeded cannot have shipped two.
#
# The state is nevertheless reported here on every boot, and repaired if wrong. A
# build-time assertion only covers what the build produced; this covers what the
# container is actually running, which is the thing that was in question.
mpm_list() { ls /etc/apache2/mods-enabled/mpm_*.load 2>/dev/null || true; }
mpm_count="$(mpm_list | wc -l | tr -d ' ')"
log "MPMs enabled (${mpm_count}): $(mpm_list | tr '\n' ' ')"

if [ "${mpm_count}" != "1" ]; then
    log "ERROR: ${mpm_count} MPMs enabled — Apache will refuse to start with AH00534."
    log "ERROR: the image was built with exactly one, so something changed it after"
    log "ERROR: the build. Repairing at runtime; this needs investigating, not ignoring."
    a2dismod mpm_event  >/dev/null 2>&1 || true
    a2dismod mpm_worker >/dev/null 2>&1 || true
    a2enmod  mpm_prefork >/dev/null 2>&1 || true
    log "MPMs after repair ($(mpm_list | wc -l | tr -d ' ')): $(mpm_list | tr '\n' ' ')"
fi

# Test the config Apache will actually load — the build-time check ran against the
# base image's vhost, not the one rendered from the template a few lines above.
if configtest="$(apache2ctl configtest 2>&1)"; then
    log "configtest: $(printf '%s' "${configtest}" | tr '\n' ' ')"
else
    log "ERROR: configtest FAILED — Apache will not start:"
    printf '%s\n' "${configtest}" >&2
fi

# ---------------------------------------------------------------------------
# 3. Database wiring
# ---------------------------------------------------------------------------
# Railway's MySQL service publishes MYSQLHOST/MYSQLPORT/... and a MYSQL_URL.
# The WordPress image wants WORDPRESS_DB_*. Translate only when the WordPress
# variables are absent, so an explicit override in the Railway dashboard still wins.

# Report which of these the container can actually see. "absent" and "empty" mean
# different things and point at different mistakes: absent is a variable that was
# never added to this service, empty is one that was added but whose ${{...}}
# reference resolved to nothing — usually a mistyped service name. Presence only;
# these include the database password, and a log line is not a safe place for it.
env_state() {
    local name="$1"
    if   [ -z "${!name+x}" ]; then printf '%s=absent' "${name}"
    elif [ -z "${!name}"   ]; then printf '%s=EMPTY'  "${name}"
    else                           printf '%s=set'    "${name}"
    fi
}
log "database env: $(env_state MYSQLHOST) $(env_state MYSQLPORT) $(env_state MYSQLUSER)" \
    "$(env_state MYSQLPASSWORD) $(env_state MYSQLDATABASE) $(env_state MYSQL_URL)" \
    "$(env_state WORDPRESS_DB_HOST)"
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

# Probe the connection. WordPress renders "Error establishing a database connection"
# identically whether the host is unreachable, the credentials are rejected, or the
# database does not exist — three different faults with three different fixes. The
# mysql client is already in the image for the content import, so asking it directly
# costs a second at boot and turns that one page into a specific answer.
#
# Non-fatal by design: a database that is still starting should not stop Apache from
# coming up, or the healthcheck fails and Railway restarts into the same race.
if [ -n "${WORDPRESS_DB_HOST:-}" ]; then
    db_host="${WORDPRESS_DB_HOST%%:*}"
    db_port="${WORDPRESS_DB_HOST##*:}"
    [ "${db_port}" = "${db_host}" ] && db_port=3306
    # MYSQL_PWD rather than -p so the password never appears in the process list.
    if db_probe="$(MYSQL_PWD="${WORDPRESS_DB_PASSWORD:-}" mysql \
            --connect-timeout=5 \
            -h "${db_host}" -P "${db_port}" \
            -u "${WORDPRESS_DB_USER:-root}" \
            -e 'SELECT 1' "${WORDPRESS_DB_NAME:-}" 2>&1)"; then
        log "database: connected to ${db_host}:${db_port}/${WORDPRESS_DB_NAME:-}"
    else
        log "ERROR: database connection FAILED — every page will show 'Error"
        log "ERROR: establishing a database connection'. The client reported:"
        printf '%s\n' "${db_probe}" >&2
    fi

    # The client above proves the network path and the credentials, and nothing more.
    # WordPress connects through PHP's mysqli, which differs in TLS defaults and in
    # which authentication plugins it supports — so it can fail where the client
    # succeeds. That gap is invisible unless it is tested directly.
    php_probe="$(php -r '
        $host = getenv("WORDPRESS_DB_HOST"); $port = 3306;
        if (($p = strrpos($host, ":")) !== false) {
            $port = (int) substr($host, $p + 1);
            $host = substr($host, 0, $p);
        }
        $m = mysqli_init();
        if (@mysqli_real_connect($m, $host, getenv("WORDPRESS_DB_USER"),
                getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME"), $port)) {
            echo "ok server=" . $m->server_info;
        } else {
            echo "FAILED(" . mysqli_connect_errno() . "): " . mysqli_connect_error();
        }
    ' 2>&1)"
    case "${php_probe}" in
        ok*) log "database: PHP mysqli connected — ${php_probe#ok }" ;;
        *)   log "ERROR: PHP mysqli could NOT connect where the client could."
             log "ERROR: this is the path WordPress uses. It reported: ${php_probe}" ;;
    esac

    # ---------------------------------------------------------------------
    # Repair a site address the installer left blank
    # ---------------------------------------------------------------------
    # WordPress writes siteurl and home to the database when it installs. This site
    # was installed while Apache was still redirecting to its internal port, and both
    # were recorded as empty strings. is_blog_installed() reads siteurl, finds it
    # empty, decides the site is not installed, then finds tables present and calls
    # dead_db() — so every page says "Error establishing a database connection" when
    # the database is entirely healthy and the address is simply blank.
    #
    # Here the address is configuration rather than database state: WP_HOME and
    # WP_SITEURL are service variables and wp-config-extra.php defines them as
    # constants, which is what makes moving to batchfromscratch.me a variable change.
    # Filling blank rows from them restores the intended value rather than inventing
    # one. Only blank rows are touched, so a site with a real address is untouched,
    # which also makes this idempotent across the redeploys Railway does freely.
    site_url="${WP_SITEURL:-${WP_HOME:-}}"
    site_url="${site_url%/}"
    case "${site_url}" in
        https://*|http://*)
            case "${site_url}" in
                # Refuse anything that could break out of the quoted SQL literal.
                *[\'\"\\\;]*|*' '*)
                    log "WARNING: WP_SITEURL/WP_HOME contains unexpected characters; not repairing"
                    ;;
                *)
                    # The trailing `|| true` is load-bearing. This repair is
                    # advisory, but on a first boot the WordPress tables do not
                    # exist yet and the UPDATE fails — and under `set -euo
                    # pipefail` a command substitution whose pipeline exits
                    # non-zero aborts the entrypoint on the spot, before Apache
                    # is ever started. The container then never binds a port, so
                    # the only symptom is a health check that times out against
                    # a silent container. That is what made a fresh database
                    # unbootable, and what CI had been failing on.
                    repaired="$(MYSQL_PWD="${WORDPRESS_DB_PASSWORD:-}" mysql \
                        --connect-timeout=5 -N -B \
                        -h "${db_host}" -P "${db_port}" \
                        -u "${WORDPRESS_DB_USER:-root}" "${WORDPRESS_DB_NAME:-}" -e "
                            UPDATE ${WORDPRESS_TABLE_PREFIX:-wp_}options
                               SET option_value = '${site_url}'
                             WHERE option_name IN ('siteurl','home')
                               AND (option_value IS NULL OR option_value = '');
                            SELECT ROW_COUNT();" 2>&1 | tail -1 || true)"
                    case "${repaired}" in
                        0) : ;;  # nothing blank; the usual case once healthy
                        [1-9]*) log "database: filled ${repaired} blank site address row(s) with ${site_url}" ;;
                        # An empty database is the expected state on a first
                        # boot, not a fault: WordPress has not installed yet, so
                        # there is no options table and nothing to repair.
                        *"doesn't exist"*|*"Unknown database"*)
                            log "database: no WordPress tables yet — skipping site address repair" ;;
                        *) log "WARNING: site address repair did not run cleanly: ${repaired}" ;;
                    esac
                    ;;
            esac
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 4. Persistent wp-content
# ---------------------------------------------------------------------------
# A Railway volume is mounted at /var/www/html/wp-content so uploads and any
# admin-installed plugins survive a redeploy. The theme and mu-plugins are the
# opposite: they are owned by this repository, so they are pushed into the volume
# on every boot and any drift on the volume is discarded.
WP_CONTENT=/var/www/html/wp-content

# Whether the volume is actually mounted is worth stating outright. Without it
# everything below still succeeds and the site still serves — uploads just go to the
# container filesystem and vanish on the next deploy. That is silent until it is
# expensive, and the only previous hint was the "first boot" message below recurring
# on every deploy, which is a symptom you have to already know how to read.
if grep -q " ${WP_CONTENT} " /proc/mounts 2>/dev/null; then
    log "wp-content: volume mounted — uploads persist across deploys"
else
    log "WARNING: wp-content is NOT a mount point; it is the container filesystem."
    log "WARNING: anything written to uploads is lost on the next deploy. Attach a"
    log "WARNING: Railway volume at ${WP_CONTENT} before importing any media."
fi

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
    # Says "no marker" rather than "first boot on this volume": if wp-content is not
    # actually a volume, this runs on every deploy, and the old wording asserted a
    # persistence that was not there.
    log "no ownership marker — normalising ownership (may take a moment)"
    chown -R www-data:www-data "${WP_CONTENT}" || true
    touch "${WP_CONTENT}/.ownership-done"
fi

# ---------------------------------------------------------------------------
# 5. Health endpoint
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
# 6. Hand off
# ---------------------------------------------------------------------------
# The upstream entrypoint only performs its setup when the command starts with
# "apache2", so it is invoked with the real command rather than a wrapper script.

log "handing off to the WordPress entrypoint"
exec docker-entrypoint.sh "$@"
