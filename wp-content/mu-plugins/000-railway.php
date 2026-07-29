<?php
/**
 * Plugin Name: Batch From Scratch — platform adjustments
 * Description: Settings that belong to the hosting environment rather than the theme.
 *              Loaded as a must-use plugin so it cannot be deactivated from the admin.
 *
 * The HTTPS/proxy handling deliberately lives in wp-config.php, not here — by the
 * time must-use plugins load, WordPress has already decided whether the request
 * is secure.
 */

defined( 'ABSPATH' ) || exit;

/**
 * The container filesystem is ephemeral outside the wp-content volume, and core
 * is pinned to the image tag. Surface that in the admin instead of offering an
 * update button that would appear to work and then vanish on the next deploy.
 */
add_action( 'admin_notices', function () {
	if ( ! current_user_can( 'update_core' ) ) {
		return;
	}
	$screen = get_current_screen();
	if ( ! $screen || ! in_array( $screen->id, array( 'dashboard', 'update-core', 'plugins' ), true ) ) {
		return;
	}
	printf(
		'<div class="notice notice-info"><p><strong>%s</strong> %s</p></div>',
		esc_html__( 'Hosted from a container image.', 'batchfromscratch' ),
		esc_html__( 'WordPress core and PHP are pinned by the Dockerfile in the site repository. Updating them means bumping the image tag and pushing a commit — the update screens here will not persist. Plugins and uploads do persist, because wp-content is on a volume.', 'batchfromscratch' )
	);
} );

/**
 * Trim the REST API and head output that this site has no use for. The
 * oEmbed discovery links and the generator tag in particular just advertise the
 * WordPress version to scanners.
 */
add_action( 'init', function () {
	remove_action( 'wp_head', 'wp_generator' );
	remove_action( 'wp_head', 'wlwmanifest_link' );
	remove_action( 'wp_head', 'rsd_link' );
	remove_action( 'wp_head', 'wp_shortlink_wp_head' );
} );

/**
 * Require authentication for the user-enumeration endpoints. Anonymous access to
 * /wp-json/wp/v2/users hands an attacker a list of valid login names.
 */
add_filter( 'rest_endpoints', function ( $endpoints ) {
	if ( is_user_logged_in() ) {
		return $endpoints;
	}
	foreach ( array( '/wp/v2/users', '/wp/v2/users/(?P<id>[\d]+)' ) as $route ) {
		if ( isset( $endpoints[ $route ] ) ) {
			unset( $endpoints[ $route ] );
		}
	}
	return $endpoints;
} );

/**
 * Block the ?author=N redirect, which leaks the same information as the REST
 * users endpoint by bouncing to /author/<login>/.
 */
add_action( 'template_redirect', function () {
	if ( is_admin() || is_user_logged_in() ) {
		return;
	}
	if ( isset( $_GET['author'] ) && ! empty( $_GET['author'] ) ) {
		wp_safe_redirect( home_url( '/' ), 301 );
		exit;
	}
} );

/**
 * WordPress generates a long ladder of intermediate image sizes. Given the size
 * of this library, the 1536px and 2048px extras roughly double the storage cost
 * of every upload for sizes the theme never requests.
 */
add_filter( 'intermediate_image_sizes_advanced', function ( $sizes ) {
	unset( $sizes['1536x1536'], $sizes['2048x2048'] );
	return $sizes;
} );

/**
 * Emails from a container have nowhere useful to come from and will fail SPF for
 * batchfromscratch.me. Until an SMTP service is wired up, make the failure mode
 * obvious in the log rather than silent.
 */
add_filter( 'wp_mail_from', function ( $from ) {
	$host = wp_parse_url( home_url(), PHP_URL_HOST );
	return $host ? 'wordpress@' . $host : $from;
} );
