<?php
/**
 * Batch From Scratch theme setup.
 *
 * @package batchfromscratch
 */

defined( 'ABSPATH' ) || exit;

define( 'BFS_VERSION', '0.1.0' );

/**
 * Theme supports.
 */
add_action( 'after_setup_theme', function () {
	load_theme_textdomain( 'batchfromscratch', get_template_directory() . '/languages' );

	add_theme_support( 'title-tag' );
	add_theme_support( 'post-thumbnails' );
	add_theme_support( 'automatic-feed-links' );
	add_theme_support( 'responsive-embeds' );
	add_theme_support( 'html5', array(
		'search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script',
	) );

	register_nav_menus( array(
		'primary' => __( 'Primary menu', 'batchfromscratch' ),
		'footer'  => __( 'Footer menu', 'batchfromscratch' ),
	) );

	// Card thumbnails are 4:3 and rendered at most 19rem wide, so 760px covers
	// a 2x display without shipping the 1.75MB originals to a phone.
	add_image_size( 'bfs-card', 760, 570, true );
	// Full-bleed hero on single posts.
	add_image_size( 'bfs-hero', 1800, 1100, true );
} );

/**
 * Assets. Fonts are self-hosted rather than loaded from Google to avoid the
 * third-party request and the associated consent question for UK visitors.
 */
add_action( 'wp_enqueue_scripts', function () {
	wp_enqueue_style( 'bfs-style', get_stylesheet_uri(), array(), BFS_VERSION );

	if ( is_singular() && comments_open() && get_option( 'thread_comments' ) ) {
		wp_enqueue_script( 'comment-reply' );
	}
} );

/**
 * Sensible srcset widths for a library of large photographs.
 */
add_filter( 'wp_calculate_image_sizes', function ( $sizes, $size ) {
	if ( is_singular() ) {
		return '(max-width: 56rem) 92vw, 56rem';
	}
	return '(max-width: 40rem) 92vw, 19rem';
}, 10, 2 );

/**
 * Excerpt tuning — the cards want two lines, not fifty-five words.
 */
add_filter( 'excerpt_length', fn() => 24 );
add_filter( 'excerpt_more', fn() => '&nbsp;&hellip;' );

/**
 * The category rail lists only categories that actually have posts, in
 * descending order of use, so the busiest sections lead.
 */
function bfs_rail_categories(): array {
	$cats = get_categories( array(
		'hide_empty' => true,
		'orderby'    => 'count',
		'order'      => 'DESC',
		'number'     => 16,
	) );
	return is_wp_error( $cats ) ? array() : $cats;
}

/**
 * Post meta line: date plus primary category.
 */
function bfs_entry_meta(): string {
	$parts = array();

	$parts[] = sprintf(
		'<time datetime="%s">%s</time>',
		esc_attr( get_the_date( DATE_W3C ) ),
		esc_html( get_the_date() )
	);

	$cats = get_the_category();
	if ( ! empty( $cats ) ) {
		$parts[] = sprintf(
			'<a href="%s">%s</a>',
			esc_url( get_category_link( $cats[0] ) ),
			esc_html( $cats[0]->name )
		);
	}

	return implode( ' <span aria-hidden="true">&middot;</span> ', $parts );
}

/**
 * Fall back to the first image in the post body when no featured image was set.
 * Much of the 2017 archive predates the author using featured images, and a grid
 * of grey placeholders would be a poor advert for a photography-led blog.
 */
function bfs_thumbnail( string $size = 'bfs-card' ): void {
	if ( has_post_thumbnail() ) {
		the_post_thumbnail( $size, array( 'loading' => 'lazy', 'decoding' => 'async' ) );
		return;
	}

	$attachments = get_attached_media( 'image', get_the_ID() );
	if ( ! empty( $attachments ) ) {
		$first = array_shift( $attachments );
		echo wp_get_attachment_image( $first->ID, $size, false, array(
			'loading'  => 'lazy',
			'decoding' => 'async',
		) );
		return;
	}

	printf(
		'<img src="%s" alt="" width="760" height="570" loading="lazy">',
		esc_url( get_template_directory_uri() . '/assets/placeholder.svg' )
	);
}
