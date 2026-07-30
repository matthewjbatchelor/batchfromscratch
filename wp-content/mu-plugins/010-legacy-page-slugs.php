<?php
/**
 * Plugin Name: Batch From Scratch — legacy page slug redirects
 * Description: 301s a page's previous URL to its current one. WordPress does this
 *              for posts but explicitly refuses to for pages.
 *
 * WordPress records a page's former slug in _wp_old_slug whenever the slug
 * changes, but wp_old_slug_redirect() bails out before using it:
 *
 *     // Do not attempt redirect for hierarchical post types.
 *     if ( is_post_type_hierarchical( $post_type ) ) {
 *         return;
 *     }
 *
 * So renaming a page silently breaks its old URL. That is not hypothetical here:
 * the importer preserves post_name and the permalink structure matches the old
 * site, so every page slug carried over from batchfromscratch.me is a URL that
 * has been live since 2017 and may well be linked from elsewhere.
 *
 * This fills that gap for pages only. Posts keep using core's implementation.
 */

defined( 'ABSPATH' ) || exit;

add_action(
	'template_redirect',
	function () {
		if ( ! is_404() ) {
			return;
		}

		// Pages are matched on `pagename`, not `name` -- which is the other
		// reason core's version does not see them. For a nested page this is
		// the full path, e.g. "parent/child", exactly as it was requested.
		$requested = get_query_var( 'pagename' );
		if ( '' === $requested ) {
			return;
		}

		// Only the final segment is ever stored as a slug.
		$slug = (string) substr( strrchr( '/' . $requested, '/' ), 1 );
		if ( '' === $slug ) {
			return;
		}

		$matches = get_posts(
			array(
				'post_type'        => 'page',
				'post_status'      => 'publish',
				'numberposts'      => 2,
				'fields'           => 'ids',
				'suppress_filters' => false,
				'meta_query'       => array(
					array(
						'key'   => '_wp_old_slug',
						'value' => $slug,
					),
				),
			)
		);

		// More than one page having claimed this slug is ambiguous; sending the
		// visitor to an arbitrary one of them would be worse than the 404.
		if ( 1 !== count( $matches ) ) {
			return;
		}

		$url = get_permalink( $matches[0] );
		if ( ! $url ) {
			return;
		}

		// Guard against redirecting a URL to itself, which would loop.
		if ( untrailingslashit( $url ) === untrailingslashit( home_url( add_query_arg( array() ) ) ) ) {
			return;
		}

		wp_safe_redirect( $url, 301 );
		exit;
	}
);
