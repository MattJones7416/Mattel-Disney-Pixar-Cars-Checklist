# Pixar Cars Community — Cloudflare Setup

The production community backend is deployed at:

```text
https://pixar-cars-social-api.mattjones7416.workers.dev
```

It uses a Worker for the API and admin page, D1 for accounts/posts/moderation, a private R2 bucket for uploaded photos, and a once-per-minute cron for notification delivery. It is separate from the Metal Earth service and does not expose the NAS.

## Provisioned resources

- Worker: `pixar-cars-social-api`
- D1 database: `pixar-cars-social-db`
- D1 ID: `7b11c13e-bb40-423b-b891-321f40e28a46`
- R2 bucket: `pixar-cars-social-media`
- Configuration: `wrangler.jsonc`
- Privacy page: `/privacy`
- Admin page: `/admin`

All five migrations have been applied to production. `JWT_SECRET` is already installed as a Cloudflare secret. Uploaded images remain private and are served only through authenticated Worker routes.

## Local checks and deployment

```bash
npm ci
npm audit
npm run check
npm run db:migrate:local
npm run db:migrate:remote
npm run deploy
```

Health check:

```bash
curl https://pixar-cars-social-api.mattjones7416.workers.dev/health
```

## Admin account

The account registered in the app with `mattjones7416@gmail.com` becomes the administrator. Open `/admin` and sign in with that Community account to approve/hold/reject posts, delete content, suspend users, and maintain the catalogue.

## Optional APNs configuration

Community features work now, but push delivery remains disabled until Apple credentials are installed. After enabling Push Notifications for `com.mattjproductions.PixarCarsChecklist`, create an APNs authentication key and add its values:

```bash
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_PRIVATE_KEY
```

Paste the complete `.p8` content for `APNS_PRIVATE_KEY`, including its begin/end lines. One APNs key works in both sandbox and production. Never commit the key.

## Optional GitHub catalogue editing

Normal users cannot edit the shared catalogue; those endpoints require a Community administrator. To allow the admin tools to commit catalogue changes, add a fine-grained GitHub token with Contents read/write access limited to `MattJones7416/Mattel-Disney-Pixar-Cars-Checklist`:

```bash
npx wrangler secret put GITHUB_TOKEN
```

The Worker updates both `PixarCarsChecklist/checked.json` and `catalog-worker/public/catalog.json` in one commit. Without this optional secret, catalogue editing returns a safe `503`; all checklist and community features continue to work.

## Security rules

- Keep `pixar-cars-social-media` private.
- Never commit `.dev.vars`, APNs keys, `JWT_SECRET`, or GitHub tokens.
- Do not put Cloudflare or GitHub credentials in the iOS app.
- Do not port-forward the NAS for this service.
- Keep the one-megabyte image limit and moderation controls unless capacity is deliberately increased.
- Authentication rate limits store a one-way keyed signature of the network address, not the raw address.

## Main routes

Public: `GET /health`, `GET /privacy`, `GET /v1/feed`, `GET /v1/posts/:id/image`

Account: `POST /v1/auth/register`, `POST /v1/auth/login`, `GET /v1/me`, `DELETE /v1/me`

Signed in: create/delete/report posts, block users, manage friends and collection visibility, upload collection snapshots, and register/unregister push tokens.

Admin: `/admin`, post/report/user moderation, and catalogue maintenance.
