<?php
/**
 * Search results.
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;

get_header();
?>

<div class="wrap">
	<header class="entry-header wrap--narrow">
		<h1>
			<?php
			printf(
				/* translators: %s: search query */
				esc_html__( 'Results for %s', 'batchfromscratch' ),
				'&ldquo;' . esc_html( get_search_query() ) . '&rdquo;'
			);
			?>
		</h1>
		<?php get_search_form(); ?>
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
		<?php the_posts_pagination( array( 'class' => 'pagination', 'mid_size' => 2 ) ); ?>
	<?php else : ?>
		<p class="wrap--narrow"><?php esc_html_e( 'No matches. Try a broader term &mdash; &ldquo;cake&rdquo; rather than &ldquo;Battenberg&rdquo;.', 'batchfromscratch' ); ?></p>
	<?php endif; ?>
</div>

<?php get_footer(); ?>
