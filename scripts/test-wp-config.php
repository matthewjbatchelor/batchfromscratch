<?php
/**
 * Exercises config/wp-config-extra.php the way wp-config.php includes it.
 *
 * This file is included at a point where almost nothing exists — no WordPress
 * functions, no ABSPATH — and a mistake there is a fatal error on every request
 * with no useful message. Running it in CI is cheap insurance.
 *
 *     php scripts/test-wp-config.php
 */

$config = __DIR__ . '/../config/wp-config-extra.php';
$failures = array();

function check( string $label, bool $ok, string $detail = '' ): void {
	global $failures;
	if ( $ok ) {
		printf( "  ok    %s\n", $label );
	} else {
		printf( "  FAIL  %s%s\n", $label, $detail ? " — {$detail}" : '' );
		$failures[] = $label;
	}
}

/**
 * Each case runs in its own PHP process: the file defines constants, and constants
 * cannot be redefined within one process.
 */
function run( string $setup ): array {
	global $config;
	$code = '<?php define("DB_NAME","wordpress"); ' . $setup
		. ' require ' . var_export( $config, true ) . ';'
		. ' echo json_encode(["server"=>$_SERVER,"home"=>defined("WP_HOME")?WP_HOME:null,'
		. '"siteurl"=>defined("WP_SITEURL")?WP_SITEURL:null,'
		. '"file_edit"=>defined("DISALLOW_FILE_EDIT")?DISALLOW_FILE_EDIT:null,'
		. '"revisions"=>defined("WP_POST_REVISIONS")?WP_POST_REVISIONS:null]);';
	$tmp = tempnam( sys_get_temp_dir(), 'wpcfg' );
	file_put_contents( $tmp, $code );
	$out = shell_exec( escapeshellcmd( PHP_BINARY ) . ' ' . escapeshellarg( $tmp ) . ' 2>&1' );
	unlink( $tmp );
	$json = json_decode( (string) $out, true );
	if ( null === $json ) {
		fwrite( STDERR, "unparseable output: {$out}\n" );
		return array();
	}
	return $json;
}

echo "wp-config-extra.php\n";

// 1. Behind Railway's TLS-terminating proxy.
$r = run( '$_SERVER["HTTP_X_FORWARDED_PROTO"]="https";'
	. ' $_SERVER["HTTP_X_FORWARDED_HOST"]="batchfromscratch.me";'
	. ' putenv("WP_HOME=https://batchfromscratch.me/");'
	. ' putenv("WP_SITEURL=https://batchfromscratch.me/");' );
check( 'sets HTTPS=on from X-Forwarded-Proto', ( $r['server']['HTTPS'] ?? null ) === 'on' );
check( 'sets SERVER_PORT to 443', (int) ( $r['server']['SERVER_PORT'] ?? 0 ) === 443 );
check( 'adopts the forwarded host', ( $r['server']['HTTP_HOST'] ?? null ) === 'batchfromscratch.me' );
check( 'strips the trailing slash from WP_HOME',
	( $r['home'] ?? null ) === 'https://batchfromscratch.me',
	'got ' . var_export( $r['home'] ?? null, true ) );

// 2. A proxy chain — only the first host is the client's.
$r = run( '$_SERVER["HTTP_X_FORWARDED_HOST"]="batchfromscratch.me, internal.railway";' );
check( 'takes the first host from a forwarded chain',
	( $r['server']['HTTP_HOST'] ?? null ) === 'batchfromscratch.me' );

// 3. No proxy headers at all — must not invent HTTPS.
$r = run( '' );
check( 'leaves HTTPS unset without X-Forwarded-Proto', ! isset( $r['server']['HTTPS'] ) );
check( 'leaves WP_HOME undefined when the env var is absent', ( $r['home'] ?? null ) === null );

// 4. Plain http forwarded — also must not claim HTTPS.
$r = run( '$_SERVER["HTTP_X_FORWARDED_PROTO"]="http";' );
check( 'leaves HTTPS unset when forwarded as http', ! isset( $r['server']['HTTPS'] ) );

// 5. Hardening constants.
$r = run( '' );
check( 'disables the file editor', true === ( $r['file_edit'] ?? null ) );
check( 'caps post revisions', 10 === ( $r['revisions'] ?? null ) );

// 6. The direct-access guard.
$tmp = tempnam( sys_get_temp_dir(), 'wpcfg' );
file_put_contents( $tmp, '<?php require ' . var_export( $config, true ) . '; echo "REACHED";' );
$out = (string) shell_exec( escapeshellcmd( PHP_BINARY ) . ' ' . escapeshellarg( $tmp ) . ' 2>&1' );
unlink( $tmp );
check( 'exits when included without DB_NAME', ! str_contains( $out, 'REACHED' ), trim( $out ) );

echo "\n";
if ( $failures ) {
	printf( "%d check(s) failed\n", count( $failures ) );
	exit( 1 );
}
echo "all checks passed\n";
