<?php
/**
 * Configuration that has to run before WordPress bootstraps.
 *
 * This is required from wp-config.php via the WORDPRESS_CONFIG_EXTRA hook in the
 * official image. It lives in its own file rather than inline in the Dockerfile so
 * that it can be syntax-checked in CI — an escaping mistake in a Dockerfile ENV
 * string produces a site that fataly errors on every request, and the Dockerfile
 * is the worst possible place to debug PHP.
 *
 * Nothing here can be an mu-plugin: by the time plugins load, WordPress has already
 * decided whether the request is HTTPS and has already computed the site URL.
 */

/*
 * Note the guard: NOT `defined( 'ABSPATH' )`, which is the usual idiom. This file is
 * included partway through wp-config.php, before ABSPATH exists — the conventional
 * guard would silently exit() and serve a blank page on every request. DB_NAME is
 * defined above the injection point, so it is the reliable signal that we are being
 * included from wp-config.php rather than reached some other way.
 */
defined( 'DB_NAME' ) || exit;

/*
 * Railway terminates TLS at its edge and forwards plain HTTP to the container.
 * Left alone, WordPress sees an insecure request, generates http:// URLs, and the
 * edge redirects them back to https:// — a redirect loop, and mixed-content
 * warnings on anything that does get through.
 */
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] )
	&& 'https' === strtolower( (string) $_SERVER['HTTP_X_FORWARDED_PROTO'] ) ) {
	$_SERVER['HTTPS']       = 'on';
	$_SERVER['SERVER_PORT'] = 443;
}

if ( ! empty( $_SERVER['HTTP_X_FORWARDED_HOST'] ) ) {
	// May be a comma-separated chain if more than one proxy is involved; the
	// first entry is the host the client actually asked for.
	$forwarded_host        = explode( ',', (string) $_SERVER['HTTP_X_FORWARDED_HOST'] )[0];
	$_SERVER['HTTP_HOST']  = trim( $forwarded_host );
}

/*
 * Site addresses come from the environment, so moving from the Railway-generated
 * domain to batchfromscratch.me is a variable change and a restart rather than a
 * search-replace across every table in the database.
 */
foreach ( array( 'WP_HOME', 'WP_SITEURL' ) as $bfs_url_constant ) {
	$bfs_url_value = getenv( $bfs_url_constant );
	if ( $bfs_url_value && ! defined( $bfs_url_constant ) ) {
		// rtrim, not untrailingslashit — WordPress's own functions do not exist yet
		// at this point in wp-config.php.
		define( $bfs_url_constant, rtrim( $bfs_url_value, '/' ) );
	}
}
unset( $bfs_url_constant, $bfs_url_value );

/*
 * The container filesystem is discarded on every deploy, and core is pinned to the
 * image tag. Updating through the admin would appear to succeed and then silently
 * revert, so the machinery is switched off rather than left to mislead.
 */
defined( 'WP_AUTO_UPDATE_CORE' ) || define( 'WP_AUTO_UPDATE_CORE', false );
defined( 'DISALLOW_FILE_EDIT' ) || define( 'DISALLOW_FILE_EDIT', true );
defined( 'AUTOMATIC_UPDATER_DISABLED' ) || define( 'AUTOMATIC_UPDATER_DISABLED', true );

/*
 * Errors belong in the container log, which Railway collects. Never on the page.
 */
defined( 'WP_DEBUG_DISPLAY' ) || define( 'WP_DEBUG_DISPLAY', false );
defined( 'WP_DEBUG_LOG' ) || define( 'WP_DEBUG_LOG', false );

/*
 * WordPress's own cron fires on page requests, which on a low-traffic blog means it
 * fires erratically or not at all. Left enabled for now because nothing here depends
 * on scheduled work; if that changes, disable it and drive wp-cron from a Railway
 * cron service instead.
 */

/*
 * Trash retention: the default 30 days is fine, but an explicit value documents that
 * it was considered.
 */
defined( 'EMPTY_TRASH_DAYS' ) || define( 'EMPTY_TRASH_DAYS', 30 );

/*
 * Post revisions are unbounded by default. A recipe post edited over several evenings
 * can accumulate dozens, all of which travel with every database backup.
 */
defined( 'WP_POST_REVISIONS' ) || define( 'WP_POST_REVISIONS', 10 );
