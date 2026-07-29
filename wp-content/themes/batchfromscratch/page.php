<?php
/**
 * A static page — "The to do list" and "The who and the why".
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;

get_header();

while ( have_posts() ) :
	the_post();
	?>

	<article <?php post_class(); ?>>

		<?php if ( has_post_thumbnail() ) : ?>
			<div class="wrap hero"><?php the_post_thumbnail( 'bfs-hero' ); ?></div>
		<?php endif; ?>

		<header class="entry-header wrap wrap--narrow">
			<h1><?php the_title(); ?></h1>
		</header>

		<div class="wrap">
			<div class="entry-content">
				<?php the_content(); ?>
			</div>

			<?php
			if ( comments_open() || get_comments_number() ) {
				echo '<div class="comments">';
				comments_template();
				echo '</div>';
			}
			?>
		</div>
	</article>

	<?php
endwhile;

get_footer();
