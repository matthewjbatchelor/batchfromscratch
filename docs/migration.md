# Migrating batchfromscratch.me onto Railway

The order matters more than any individual step. The old site has to stay up until the
new one is verified, because the new installation pulls the media library from it.

## What is being moved

Counted from the 29 July 2026 export:

| | |
|---|---|
| Published posts | 27, dated March 2017 – October 2018 |
| Drafts | 5, all from March 2017, never published |
| Pages | 2 — "The to do list", "The who and the why" |
| Categories in use | 14 |
| Attachments | 426, all hosted on batchfromscratch.me |
| Media on disk incl. generated sizes | 2,798+ files, over 1GB |
| Genuine comments | 23 (18 real comments, 5 pingbacks) |
| Current theme | Receptar |

## The export is 214MB and 99.3% of it is spam

This is the single most important fact about this migration. The raw WXR is 214MB. The
blog itself is 1.5MB. The difference:

- **53,690 unapproved comments** out of 53,713. Pharma, CBD, porn and SEO link spam,
  accumulated in the moderation queue since 2017. One post — "The icing on the cake" —
  carries 49,059 of them on its own. Only **23 comments are approved**, and those are the
  real ones: friends and family on the doughnuts post, plus internal pingbacks.
- **13,191 `itempress_tag` terms**, plus 21 `itempress_category`. Names like
  `( 1 ) 10.6 Ounce Box` — product descriptors injected by an affiliate plugin.
- **Two spam categories**, `! Без рубрики` and `Artificial intelligence (AI)`, holding no
  posts. The standard fingerprint of an SEO injection.

Importing the file as-is would recreate every one of those on the new server. So don't:

```sh
python3 scripts/clean-wxr.py wordpress-backup.xml batchfromscratch-clean.xml
```

214MB becomes 1.5MB, and the result is small enough to upload anywhere. The script prints
what it removed and flags any surviving comment that reads like spam.

## Before you start

The spam above is a symptom, not the disease. Something let an affiliate plugin write
13,000 taxonomy terms. Before exporting anything, look at the users list for accounts you
do not recognise, `wp-content/plugins` for anything you did not install, and the scheduled
posts queue. A migration is an excellent way to carry a compromise across to a clean
server — and the new install starts from a stock WordPress image, so this is the one
chance to leave it behind.

Also: change the admin password. It was shared over chat.

## 1. Export the content

WP Admin → **Tools → Export → All content** → *Download Export File*. This produces a
WXR file, which is XML: posts, pages, categories, tags, comments, menus and the metadata
that ties them together. It references attachments by URL rather than embedding them,
which is exactly what we want.

Then run it through `scripts/clean-wxr.py` as described above. Everything below assumes
the cleaned file.

It does **not** include: theme settings, widget configuration, plugin settings, or user
passwords. Receptar is being replaced so its settings do not matter; the widget sidebar
will need rebuilding by hand, which for this site is "recent posts, recent comments,
archives".

## 2. Stand the new site up

1. Create a Railway project and add a **MySQL** service.
2. Add a service from this GitHub repository. Railway will read `railway.json` and build
   the `Dockerfile`.
3. Attach a **volume** to the WordPress service, mounted at `/var/www/html/wp-content`.
   Size it at 2GB — comfortably above the current library, with room for thumbnails
   regenerated at the new theme's sizes.
4. Set the service variables:

   ```
   WP_HOME    = https://<the generated railway domain>
   WP_SITEURL = https://<the generated railway domain>
   ```

   plus the eight salts from <https://api.wordpress.org/secret-key/1.1/salt/>, as
   `WORDPRESS_AUTH_KEY`, `WORDPRESS_SECURE_AUTH_KEY`, `WORDPRESS_LOGGED_IN_KEY`,
   `WORDPRESS_NONCE_KEY`, `WORDPRESS_AUTH_SALT`, `WORDPRESS_SECURE_AUTH_SALT`,
   `WORDPRESS_LOGGED_IN_SALT`, `WORDPRESS_NONCE_SALT`.

   The database variables do not need setting: the entrypoint reads Railway's
   `MYSQLHOST`/`MYSQLUSER`/… from the MySQL service. If the two services are in the same
   project this works with no extra configuration.

5. Generate a domain and open it. You should get the WordPress install wizard. Complete
   it with a fresh admin username — not `mattjbatchelor`, and not the password that has
   been in a chat window.

## 3. Import

Upload the WXR file to the running service and run the importer. From the Railway CLI:

```sh
railway ssh
# then, inside the container:
wp --path=/var/www/html plugin install wordpress-importer --activate
wp --path=/var/www/html import /path/to/export.xml --authors=create
```

or use `scripts/import-content.sh`, which wraps the same sequence with before/after
counts and the permalink fix.

The importer downloads every attachment from `https://batchfromscratch.me` as it goes.
**This is why the old site must still be serving.** Over a gigabyte of images, this takes
a while and will occasionally drop one; re-running the import is safe, as it skips
anything already present.

If fetching fails, the fallback is the local copy of `wp-content/uploads` — restore it
into the volume and re-run the import with `--skip=attachment` so the database rows are
created without re-downloading.

### Then

```sh
wp --path=/var/www/html option update permalink_structure '/%postname%/'
wp --path=/var/www/html rewrite flush --hard
wp --path=/var/www/html theme activate batchfromscratch
wp --path=/var/www/html media regenerate --only-missing --yes
```

The permalink structure has to match the old site or every existing link breaks. The
regenerate step builds the theme's `bfs-card` and `bfs-hero` sizes; it is slow over this
library, so run it in a session you can leave.

## 4. Verify before touching DNS

On the Railway domain:

- Every post from the old site is present, with its images.
- `/the-icing-on-the-cake/`, `/christmas-cake-sugar-and-spice-and-all-things-nice/` and a
  handful of others resolve — these are the old URLs and they must not change.
- The two pages render.
- Category archives show the right counts.
- Comments carried across.
- The menu is rebuilt (Appearance → Menus) — the export carries menu items but they
  usually need re-assigning to the theme's Primary location.

## 5. Cut over

1. In Railway, add the custom domains `batchfromscratch.me` and `www.batchfromscratch.me`
   to the WordPress service. Railway issues a CNAME target for each.
2. Update DNS at the registrar. Lower the TTL a day beforehand if you can.
3. Once DNS has propagated, change `WP_HOME` and `WP_SITEURL` to
   `https://batchfromscratch.me` and redeploy.
4. Run the URL rewrite for anything hardcoded in post bodies:

   ```sh
   wp --path=/var/www/html search-replace 'http://batchfromscratch.me' 'https://batchfromscratch.me' --all-tables-with-prefix --dry-run
   # inspect, then run again without --dry-run
   ```

5. Confirm HTTPS, confirm a few old URLs, confirm the admin still logs in.

Keep the old host running for a week or two. It costs little and it is the only way back
if something turns up that the verification missed.

## Worth doing at some point

The media library is unoptimised — 1.75MB average for images displayed at most 1800px
wide. `scripts/optimise-media.sh` resizes and re-encodes the originals, typically saving
around 85% with no visible difference. Doing it *before* the import saves the transfer
and the storage; doing it after means re-uploading. Either works, but before is cheaper.
