<?php
/**
 * Main archive template — also serves the blog home, categories, tags and dates
 * via archive.php, which simply adds a heading before including this loop.
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;

get_header();
?>

<div class="wrap">
	<?php if ( have_posts() ) : ?>

		<ul class="grid">
			<?php
			while ( have_posts() ) :
				the_post();
				get_template_part( 'template-parts/content', 'card' );
			endwhile;
			?>
		</ul>

		<?php
		the_posts_pagination( array(
			'class'              => 'pagination',
			'mid_size'           => 2,
			'prev_text'          => __( 'Newer', 'batchfromscratch' ),
			'next_text'          => __( 'Older', 'batchfromscratch' ),
			'screen_reader_text' => __( 'Posts navigation', 'batchfromscratch' ),
		) );
		?>

	<?php else : ?>

		<div class="entry-header">
			<h1><?php esc_html_e( 'Nothing here yet', 'batchfromscratch' ); ?></h1>
			<p><?php esc_html_e( 'Try a search, or pick a category above.', 'batchfromscratch' ); ?></p>
			<?php get_search_form(); ?>
		</div>

	<?php endif; ?>
</div>

<?php get_footer(); ?>
