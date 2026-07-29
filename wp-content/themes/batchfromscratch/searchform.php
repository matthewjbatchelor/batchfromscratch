<?php
/**
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;
?>
<form role="search" method="get" class="search-form" action="<?php echo esc_url( home_url( '/' ) ); ?>">
	<label class="screen-reader-text" for="s"><?php esc_html_e( 'Search recipes', 'batchfromscratch' ); ?></label>
	<input type="search" id="s" name="s" value="<?php echo esc_attr( get_search_query() ); ?>"
	       placeholder="<?php esc_attr_e( 'Search recipes&hellip;', 'batchfromscratch' ); ?>">
	<button class="btn" type="submit"><?php esc_html_e( 'Search', 'batchfromscratch' ); ?></button>
</form>
