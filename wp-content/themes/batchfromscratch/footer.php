<?php
/**
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;
?>
</main>

<footer class="site-footer">
	<div class="wrap site-footer__inner">
		<p>
			&copy; <?php echo esc_html( gmdate( 'Y' ) ); ?>
			<?php bloginfo( 'name' ); ?>.
			<?php esc_html_e( 'Cooking and things I&rsquo;ve learnt along the way.', 'batchfromscratch' ); ?>
		</p>

		<?php
		if ( has_nav_menu( 'footer' ) ) {
			wp_nav_menu( array(
				'theme_location' => 'footer',
				'container'      => 'nav',
				'depth'          => 1,
				'menu_class'     => 'nav-footer',
			) );
		}
		?>
	</div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
