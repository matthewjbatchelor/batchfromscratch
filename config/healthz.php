<?php
/**
 * Liveness endpoint for Railway.
 *
 * Deliberately does not touch WordPress or the database. Its job is to answer
 * "is this container able to serve PHP?" — if the database is down we still want
 * the container to stay up and serve a WordPress error, rather than have Railway
 * kill and restart it in a loop while the database recovers.
 */
header( 'Content-Type: text/plain; charset=utf-8' );
header( 'Cache-Control: no-store' );
echo "ok\n";
