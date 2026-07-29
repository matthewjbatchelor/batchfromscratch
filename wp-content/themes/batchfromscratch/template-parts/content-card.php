<?php
/**
 * One post as a card in the grid.
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;
?>
<li <?php post_class( 'card' ); ?>>
	<a class="card__media" href="<?php the_permalink(); ?>" tabindex="-1" aria-hidden="true">
		<?php bfs_thumbnail( 'bfs-card' ); ?>
	</a>

	<p class="card__meta"><?php echo wp_kses_post( bfs_entry_meta() ); ?></p>

	<h2 class="card__title">
		<a href="<?php the_permalink(); ?>"><?php the_title(); ?></a>
	</h2>

	<p class="card__excerpt"><?php echo esc_html( get_the_excerpt() ); ?></p>
</li>
