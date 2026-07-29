<?php
/**
 * Not found.
 *
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;

get_header();
?>

<div class="wrap wrap--narrow">
	<header class="entry-header">
		<h1><?php esc_html_e( 'That recipe has wandered off', 'batchfromscratch' ); ?></h1>
		<p><?php esc_html_e( 'The page you were after is not here. Search for it, or browse a category above.', 'batchfromscratch' ); ?></p>
		<?php get_search_form(); ?>
	</header>
</div>

<?php get_footer(); ?>
