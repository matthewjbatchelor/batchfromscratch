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
    printf '%s\n' \
        'RemoteIPHeader X-Forwarded-For' \
        'ServerTokens Prod' \
        'ServerSignature Off' \
        'TraceEnable Off' \
        > /etc/apache2/conf-available/zz-railway.conf; \
    a2enconf zz-railway; \
    # Assert the module set actually starts. This is the check that would have caught
    # the MPM clash at build time instead of at Railway's healthcheck. The vhost here
    # is still the base image's, since ours is only rendered at boot — CI's boot step
    # is what covers the templated one.
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
ENV WORDPRESS_CONFIG_EXTRA="require '/usr/local/etc/wordpress/wp-config-extra.php';"

COPY docker/entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["apache2-foreground"]
