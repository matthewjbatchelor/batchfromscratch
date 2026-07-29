<?php
/**
 * A single recipe post.
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
			<div class="wrap hero">
				<?php the_post_thumbnail( 'bfs-hero', array( 'fetchpriority' => 'high' ) ); ?>
			</div>
		<?php endif; ?>

		<header class="entry-header wrap wrap--narrow">
			<p class="entry-meta"><?php echo wp_kses_post( bfs_entry_meta() ); ?></p>
			<h1><?php the_title(); ?></h1>
		</header>

		<div class="wrap">
			<div class="entry-content">
				<?php
				the_content();

				wp_link_pages( array(
					'before' => '<p class="page-links">' . esc_html__( 'Pages:', 'batchfromscratch' ),
					'after'  => '</p>',
				) );
				?>
			</div>

			<footer class="entry-footer">
				<?php
				$tags = get_the_tag_list( '', '' );
				if ( $tags ) {
					printf( '<p class="tag-list">%s</p>', wp_kses_post( $tags ) );
				}
				?>

				<?php
				the_post_navigation( array(
					'prev_text' => '<span class="screen-reader-text">' . esc_html__( 'Previous', 'batchfromscratch' ) . '</span> &larr; %title',
					'next_text' => '%title &rarr; <span class="screen-reader-text">' . esc_html__( 'Next', 'batchfromscratch' ) . '</span>',
				) );
				?>
			</footer>

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
