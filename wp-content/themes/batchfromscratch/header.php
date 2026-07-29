<?php
/**
 * @package batchfromscratch
 */
defined( 'ABSPATH' ) || exit;
?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
	<meta charset="<?php bloginfo( 'charset' ); ?>">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<link rel="profile" href="https://gmpg.org/xfn/11">
	<?php wp_head(); ?>
</head>

<body <?php body_class(); ?>>
<?php wp_body_open(); ?>

<a class="skip-link" href="#main"><?php esc_html_e( 'Skip to content', 'batchfromscratch' ); ?></a>

<header class="masthead">
	<div class="wrap masthead__inner">
		<p class="masthead__title">
			<a href="<?php echo esc_url( home_url( '/' ) ); ?>" rel="home"><?php bloginfo( 'name' ); ?></a>
		</p>

		<?php if ( $description = get_bloginfo( 'description', 'display' ) ) : ?>
			<p class="masthead__tagline"><?php echo esc_html( $description ); ?></p>
		<?php endif; ?>

		<nav class="nav" aria-label="<?php esc_attr_e( 'Primary', 'batchfromscratch' ); ?>">
			<?php
			wp_nav_menu( array(
				'theme_location' => 'primary',
				'container'      => false,
				'depth'          => 1,
				'fallback_cb'    => false,
			) );
			?>
		</nav>
	</div>
</header>

<?php $rail = bfs_rail_categories(); ?>
<?php if ( ! empty( $rail ) ) : ?>
<nav class="rail" aria-label="<?php esc_attr_e( 'Categories', 'batchfromscratch' ); ?>">
	<div class="wrap">
		<ul>
			<?php foreach ( $rail as $cat ) : ?>
				<li>
					<a href="<?php echo esc_url( get_category_link( $cat ) ); ?>">
						<?php echo esc_html( $cat->name ); ?>
					</a>
				</li>
			<?php endforeach; ?>
		</ul>
	</div>
</nav>
<?php endif; ?>

<main id="main">
