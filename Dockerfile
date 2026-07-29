# Batch From Scratch — WordPress on Railway
#
# Based on the official WordPress image: WordPress core, PHP and Apache all come
# from upstream and nothing self-updates in place.
#
# Pinned by digest, not by tag. This started as the rolling `php8.3-apache` tag, which
# meant CI and Railway resolved it independently and built different images from the
# same commit: CI went green while Railway crash-looped on an Apache misconfiguration
# that CI's image did not have. A rolling tag makes "it passed CI" a statement about
# an image nobody deploys. The digest below is the one CI validated.
#
# To move it: bump the digest, let CI go green, then deploy. `docker buildx imagetools
# inspect wordpress:php8.3-apache` prints the current one.
ARG WP_IMAGE_TAG=php8.3-apache@sha256:9fac4d47b61186131ffefb5d966f0045d0eea94bfd7bd40cafae29b78a709d1b
FROM wordpress:${WP_IMAGE_TAG}

# --- system packages -------------------------------------------------------
# less + mysql-client are wp-cli dependencies (db export/import, interactive output).
# rsync is used by the entrypoint to sync bundled themes into the wp-content volume.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        less \
        rsync \
        default-mysql-client \
        ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*

# --- wp-cli ----------------------------------------------------------------
# Used for the content import and for any maintenance run against the live service.
# Pulled from the GitHub release rather than the wp-cli/builds gh-pages tree: that tree
# only publishes an unversioned wp-cli.phar, which tracks latest and would defeat the
# pinning above. The release URL is versioned and immutable.
ENV WP_CLI_VERSION=2.12.0
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/wp \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
    chmod +x /usr/local/bin/wp; \
    wp --allow-root --info

# --- PHP configuration -----------------------------------------------------
COPY config/php/uploads.ini /usr/local/etc/php/conf.d/zz-uploads.ini
COPY config/php/opcache.ini /usr/local/etc/php/conf.d/zz-opcache.ini

# --- Apache ----------------------------------------------------------------
# The vhost is templated at boot because Railway assigns the listen port via $PORT.
COPY config/apache/000-default.conf.template /etc/apache2/sites-available/000-default.conf.template
RUN set -eux; \
    a2enmod rewrite expires headers remoteip; \
    # mod_php is not thread-safe, so this image has to run prefork. Debian enables
    # mpm_event by default and the upstream PHP image switches it to prefork; if both
    # ever end up enabled, Apache exits at startup with "AH00534: More than one MPM
    # loaded" and every request is a refused connection rather than an error page —
    # which reads as a network or healthcheck fault and sends you looking in entirely
    # the wrong place. Pinning it to exactly one is cheap; leaving it implicit is not.
    a2dismod mpm_event 2>/dev/null || true; \
    a2dismod mpm_worker 2>/dev/null || true; \
    a2enmod mpm_prefork; \
    # Trust Railway's edge proxy so REMOTE_ADDR is the real client IP, not the router.
    # ServerName stops the AH00558 warning Apache logs on every start, having guessed
    # a name from the container's IPv6 address. Nothing depends on the value: the vhost
    # is a catch-all and WordPress builds its URLs from WP_HOME/WP_SITEURL. It only
    # silences noise that would otherwise be permanent.
    printf '%s\n' \
        'ServerName localhost' \
        'RemoteIPHeader X-Forwarded-For' \
        'ServerTokens Prod' \
        'ServerSignature Off' \
        'TraceEnable Off' \
        > /etc/apache2/conf-available/zz-railway.conf; \
    a2enconf zz-railway; \
    # Count the MPMs directly. Railway shipped an image carrying both mpm_event and
    # mpm_prefork whose build passed `apache2ctl configtest` — so configtest does not
    # reliably detect this condition and cannot be the guard. Counting the symlinks
    # tests the thing that actually matters and cannot be fooled.
    test "$(ls /etc/apache2/mods-enabled/mpm_*.load | wc -l | tr -d '[:space:]')" = 1; \
    # configtest still earns its place for everything else: a typo in the conf above
    # would otherwise surface as a crash loop on deploy. Note it runs against the base
    # image's vhost — ours is rendered at boot, and the entrypoint re-tests it there.
    apache2ctl configtest

# --- site content bundled into the image -----------------------------------
# The official image keeps pristine WordPress in /usr/src/wordpress and copies it
# into /var/www/html on boot. Dropping our theme and mu-plugins in there means they
# are refreshed from the image on every deploy rather than living only in a volume.
COPY --chown=www-data:www-data wp-content/themes/batchfromscratch \
     /usr/src/wordpress/wp-content/themes/batchfromscratch
COPY --chown=www-data:www-data wp-content/mu-plugins \
     /usr/src/wordpress/wp-content/mu-plugins

# Static health endpoint. Deliberately not a WordPress route: Railway's health check
# should tell us Apache and PHP are alive even if the database is unreachable, and a
# WordPress URL would either redirect or return a themed error page.
#
# Staged outside /usr/src/wordpress so it does not ride in on the upstream entrypoint's
# copy step. That copy is conditional — it only runs when the docroot has no WordPress
# in it — so a health endpoint that depends on it is a health endpoint that disappears
# in exactly the situations worth alerting on. The entrypoint installs it directly.
COPY config/healthz.php /usr/local/share/batchfromscratch/healthz.php

# --- WordPress configuration ----------------------------------------------
# The upstream entrypoint appends WORDPRESS_CONFIG_EXTRA verbatim into wp-config.php.
# Rather than embed multi-line PHP in a Dockerfile ENV — where a single escaping
# mistake yields a site that fatals on every request and a value that no linter will
# ever look at — the real configuration lives in config/wp-config-extra.php and this
# is a one-line require. It is kept outside the document root so that it can never be
# requested directly — a file in /var/www/html would be one Apache misconfiguration
# away from dumping the database credentials it has access to.
COPY config/wp-config-extra.php /usr/local/etc/wordpress/wp-config-extra.php
ENV WORDPRESS_CONFIG_EXTRA="require_once '/usr/local/etc/wordpress/wp-config-extra.php';"

# WORDPRESS_CONFIG_EXTRA alone is not enough. The upstream entrypoint inserts it by
# matching a marker comment in wp-config-docker.php, and on WordPress 7.0 that match
# fails silently: the variable is set correctly and the require never appears in the
# generated wp-config.php. The effect is a site with no HTTPS proxy handling and no
# WP_HOME, which redirects to http://host:8080 and loops.
#
# So the require is written into the template at build time instead, immediately
# before wp-settings.php — late enough that DB_NAME exists, early enough to precede
# WordPress. require_once in both places, so if upstream's insertion starts working
# again the file is still only included once. The grep is the assertion: if the
# anchor ever moves, this fails the build rather than shipping a looping site.
RUN set -eux; \
    sed -i "s#^require_once ABSPATH . 'wp-settings.php';#require_once '/usr/local/etc/wordpress/wp-config-extra.php';\nrequire_once ABSPATH . 'wp-settings.php';#" \
        /usr/src/wordpress/wp-config-docker.php; \
    grep -q "wp-config-extra.php" /usr/src/wordpress/wp-config-docker.php; \
    php -l /usr/src/wordpress/wp-config-docker.php

COPY docker/entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["apache2-foreground"]
