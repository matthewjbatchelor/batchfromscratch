<?php
/**
 * Category, tag, author and date archives.
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;

get_header();
?>

<div class="wrap">
	<header class="entry-header wrap--narrow">
		<?php
		the_archive_title( '<h1>', '</h1>' );
		the_archive_description( '<div class="archive-description">', '</div>' );
		?>
		<p class="entry-meta">
			<?php
			printf(
				/* translators: %s: number of posts */
				esc_html( _n( '%s post', '%s posts', (int) $GLOBALS['wp_query']->found_posts, 'batchfromscratch' ) ),
				esc_html( number_format_i18n( (int) $GLOBALS['wp_query']->found_posts ) )
			);
			?>
		</p>
	</header>

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
			'class'     => 'pagination',
			'mid_size'  => 2,
			'prev_text' => __( 'Newer', 'batchfromscratch' ),
			'next_text' => __( 'Older', 'batchfromscratch' ),
		) );
		?>
	<?php else : ?>
		<p><?php esc_html_e( 'Nothing filed here yet.', 'batchfromscratch' ); ?></p>
	<?php endif; ?>
</div>

<?php get_footer(); ?>
