# Batch From Scratch

WordPress for [batchfromscratch.me](https://batchfromscratch.me), running as a container
on Railway, with a new theme replacing Receptar.

## How this is put together

WordPress core, PHP and Apache come from the official `wordpress` image, pinned by tag
in the `Dockerfile`. Nothing self-updates: a WordPress or PHP upgrade is a tag bump and
a commit, which means the version running in production is always the version described
by this repository.

The container filesystem is thrown away on every deploy. Two things therefore have to be
deliberate about where they live:

- **`wp-content` is a Railway volume.** Uploads and any plugins installed through the
  admin survive redeploys because they are on that volume.
- **The theme and the must-use plugin are owned by this repository.** They are baked into
  the image and the entrypoint pushes them into the volume on every boot, overwriting
  whatever is there. Editing the theme through the WordPress admin is pointless — the
  next deploy will undo it. That is why `DISALLOW_FILE_EDIT` is on.

The practical consequence: **plugins and content, manage in the admin. Theme and
infrastructure, manage in git.**

## Layout

```
Dockerfile                     image: WordPress + wp-cli + config
docker/entrypoint.sh           port binding, DB variable mapping, volume sync
config/apache/                 vhost template (rendered with $PORT at boot)
config/php/                    upload limits and opcache
config/healthz.php             Railway health check target
railway.json                   builder and health check settings
docker-compose.yml             local development, mirrors the Railway topology
wp-content/themes/batchfromscratch/   the new theme
wp-content/mu-plugins/         platform-level settings, cannot be deactivated
scripts/import-content.sh      WXR import runbook, as a script
scripts/optimise-media.sh      shrink the originals before importing
docs/migration.md              the full cutover procedure
```

## Local development

Requires Docker.

```sh
cp .env.example .env
docker compose up --build
```

The site comes up on <http://localhost:8080>. The first visit is the WordPress install
wizard. The theme directory is bind-mounted, so edits to `wp-content/themes/batchfromscratch`
show up on refresh without a rebuild.

WP-CLI against the local stack:

```sh
docker compose run --rm wpcli plugin list
docker compose run --rm wpcli media regenerate --only-missing --yes
```

## Deploying

See `docs/migration.md` for the full sequence. In short: a Railway project with a MySQL
service and this repository connected, a volume mounted at `/var/www/html/wp-content`,
and the environment variables listed in `.env.example`.

The one variable that is easy to skip and expensive to skip: **the eight
`WORDPRESS_*_KEY` / `WORDPRESS_*_SALT` values**. Without them WordPress generates new
salts per container, which invalidates every session cookie on every deploy.

## CI

`.github/workflows/ci.yml` lints PHP and shell, builds the image, boots it against a real
MySQL, and asserts three things: the health endpoint answers, WordPress responds rather
than 500ing, and a PHP file dropped into `wp-content/uploads` is refused with a 403. That
last check is the one worth keeping — it is the difference between a hardening rule that
is written down and one that actually works.

Docker was not available in the environment this repository was built in, so CI's first
run on GitHub's runners is also the first real build.
