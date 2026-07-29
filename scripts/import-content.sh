#!/usr/bin/env bash
# Import a WordPress WXR export into this installation.
#
# Run inside the container — locally:
#     docker compose exec -u www-data wordpress /var/www/html/scripts/import-content.sh /migration/export.xml
# or against Railway:
#     railway ssh -- /var/www/html/scripts/import-content.sh /migration/export.xml
#
# By default the importer downloads every attachment referenced in the export
# straight from the old live site. That is deliberate: the media library is over a
# gigabyte, and having the container pull it over HTTP is far less painful than
# pushing it up from a laptop. It does mean the OLD SITE MUST STILL BE SERVING —
# run this before the DNS cutover, not after.
set -euo pipefail

WXR="${1:-}"
if [ -z "${WXR}" ] || [ ! -f "${WXR}" ]; then
    echo "usage: $0 /path/to/export.xml" >&2
    exit 64
fi

WP() { wp --path=/var/www/html "$@"; }

echo "==> checking WordPress is installed"
if ! WP core is-installed 2>/dev/null; then
    echo "WordPress is not installed yet. Complete the install wizard first, or run:" >&2
    echo "  wp core install --url=... --title='Batch From Scratch' --admin_user=... --admin_email=..." >&2
    exit 1
fi

echo "==> installing the WordPress Importer plugin"
WP plugin is-installed wordpress-importer >/dev/null 2>&1 || WP plugin install wordpress-importer
WP plugin activate wordpress-importer

echo "==> counting what is already here (so the import can be judged)"
before_posts=$(WP post list --post_type=post --format=count)
before_media=$(WP post list --post_type=attachment --format=count)
echo "    posts=${before_posts} attachments=${before_media}"

echo "==> importing ${WXR}"
# --authors=create keeps the original author on each post rather than
# reassigning everything to whoever runs the import.
WP import "${WXR}" --authors=create

echo "==> results"
after_posts=$(WP post list --post_type=post --format=count)
after_pages=$(WP post list --post_type=page --format=count)
after_media=$(WP post list --post_type=attachment --format=count)
echo "    posts=${after_posts} (was ${before_posts})"
echo "    pages=${after_pages}"
echo "    attachments=${after_media} (was ${before_media})"

echo "==> permalink structure"
# The old site uses /%postname%/. Anything else and every existing link,
# bookmark and search result breaks.
WP option update permalink_structure '/%postname%/'
WP rewrite flush --hard

echo "==> rewriting any absolute URLs left pointing at the old host"
# The importer rewrites attachment URLs but leaves hardcoded links in post bodies.
# Dry run first: this prints what would change without touching anything.
WP search-replace 'http://batchfromscratch.me' 'https://batchfromscratch.me' --all-tables-with-prefix --dry-run || true
echo "    (dry run only — re-run without --dry-run once the output looks right)"

echo
echo "Done. Next: regenerate thumbnails for the new theme's image sizes with"
echo "  wp media regenerate --only-missing --yes"
echo "That is slow over a library this size; run it in a screen/tmux session."
