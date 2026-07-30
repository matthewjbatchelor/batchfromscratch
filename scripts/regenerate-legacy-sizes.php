<?php
/**
 * Recreate the intermediate image sizes the old Receptar theme generated.
 *
 * Post bodies hardcode filenames like IMG_6814-595x595.jpg. Those sizes were
 * registered by the old theme; the new one registers bfs-card and bfs-hero
 * instead, so `wp media regenerate` never recreated them and every inline image
 * in the imported posts 404s.
 *
 * Rather than guess at Receptar's add_image_size() calls, this reads the
 * filenames the posts actually reference and generates exactly those, from the
 * originals already on the volume. Crop is decided per file: if the requested
 * dimensions match the original's aspect ratio it is a proportional resize,
 * otherwise a centre crop -- which is how WordPress produced them originally.
 *
 * Idempotent: anything already present on disk is skipped.
 *
 * Usage: wp --allow-root eval-file fix-sizes.php [dry]
 *
 * wp-cli passes trailing positional arguments to the script as $args, so the
 * dry-run switch is a bare word rather than a flag -- eval-file rejects unknown
 * flags before the script ever runs.
 */

$dry = in_array( 'dry', $args ?? array(), true );
$base = '/var/www/html/wp-content/uploads/';

global $wpdb;

// 1. Every sized upload filename referenced by a post.
$contents = $wpdb->get_col(
	"SELECT post_content FROM wp_posts WHERE post_status IN ('publish','draft','inherit')"
);

$refs = array();
foreach ( $contents as $content ) {
	if ( preg_match_all(
		'#wp-content/uploads/([0-9]{4}/[0-9]{2}/[^"\'\s>)]+?-([0-9]+)x([0-9]+)\.(?:jpe?g|png|gif))#i',
		$content,
		$matches,
		PREG_SET_ORDER
	) ) {
		foreach ( $matches as $m ) {
			$refs[ $m[1] ] = array( (int) $m[2], (int) $m[3] );
		}
	}
}

printf( "referenced sized files: %d\n", count( $refs ) );

$made = $skipped = $no_original = $failed = 0;

foreach ( $refs as $rel => $dims ) {
	list( $want_w, $want_h ) = $dims;
	$target = $base . $rel;

	if ( file_exists( $target ) ) {
		++$skipped;
		continue;
	}

	$orig = preg_replace( '#-[0-9]+x[0-9]+(\.[a-z]+)$#i', '$1', $base . $rel );

	// The import ran twice. The first pass wrote a number of originals as zero
	// bytes; the retry landed alongside them with WordPress's -1 dedupe suffix
	// and holds the real image. Fall back to the first healthy twin.
	if ( ! file_exists( $orig ) || 0 === filesize( $orig ) ) {
		$found = '';
		$ext   = pathinfo( $orig, PATHINFO_EXTENSION );
		$stem  = substr( $orig, 0, - ( strlen( $ext ) + 1 ) );
		foreach ( range( 1, 3 ) as $n ) {
			$twin = "{$stem}-{$n}.{$ext}";
			if ( file_exists( $twin ) && filesize( $twin ) > 0 ) {
				$found = $twin;
				break;
			}
		}
		// One post references a filename from before the image was edited in
		// WordPress; only the edited copy, carrying an -e<timestamp> suffix,
		// still exists. That is the same picture, so use it.
		if ( ! $found ) {
			$edited = glob( "{$stem}-e[0-9]*.{$ext}" );
			foreach ( (array) $edited as $candidate ) {
				if ( filesize( $candidate ) > 0 ) {
					$found = $candidate;
					break;
				}
			}
		}
		if ( ! $found ) {
			printf( "  NO ORIGINAL  %s\n", $rel );
			++$no_original;
			continue;
		}
		$orig = $found;
	}

	$size = getimagesize( $orig );
	if ( ! $size ) {
		printf( "  UNREADABLE   %s\n", $rel );
		++$failed;
		continue;
	}

	// Proportional if the requested box matches the source ratio, else crop.
	// Two pixels of slack absorbs WordPress's rounding.
	$scaled_h = (int) round( $want_w * $size[1] / $size[0] );
	$crop     = abs( $scaled_h - $want_h ) > 2;

	if ( $dry ) {
		printf( "  would make   %-52s %dx%d crop=%s\n", basename( $rel ), $want_w, $want_h, $crop ? 'yes' : 'no' );
		++$made;
		continue;
	}

	$editor = wp_get_image_editor( $orig );
	if ( is_wp_error( $editor ) ) {
		printf( "  EDITOR FAIL  %s (%s)\n", $rel, $editor->get_error_message() );
		++$failed;
		continue;
	}

	$editor->set_quality( 90 );
	$resized = $editor->resize( $want_w, $want_h, $crop );
	if ( is_wp_error( $resized ) ) {
		printf( "  RESIZE FAIL  %s (%s)\n", $rel, $resized->get_error_message() );
		++$failed;
		continue;
	}

	$saved = $editor->save( $target );
	if ( is_wp_error( $saved ) ) {
		printf( "  SAVE FAIL    %s (%s)\n", $rel, $saved->get_error_message() );
		++$failed;
		continue;
	}

	++$made;
}

printf(
	"\n%s: created=%d  already present=%d  no original=%d  failed=%d\n",
	$dry ? 'DRY RUN' : 'DONE',
	$made,
	$skipped,
	$no_original,
	$failed
);
