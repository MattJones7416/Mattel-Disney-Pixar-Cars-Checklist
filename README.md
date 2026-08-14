# Pixar Cars Checklist

An unofficial native SwiftUI collection tracker for Mattel Disney and Pixar *Cars* die-cast vehicles.

## What it tracks

- 1:55 die-cast releases, Mini Racers, collector exclusives, and premium/larger-scale releases
- Owned quantity and carded/unboxed state
- Favourites and wishlist
- Personal photos and notes
- Backup and restore across iPhone, iPad, and Mac
- Catalogue refreshes from the companion Cloudflare Worker
- Optional collector community with accounts, posts, photos, friends, shared collections, reporting, blocking, and moderation
- A one-time Pro unlock implemented with StoreKit 2

The bundled catalogue contains 1,490 distinct released Cars variants at the time of generation. The Planes spin-off and non-vehicle plastic product lines are intentionally excluded.

## Local development

Open `PixarCarsChecklist.xcodeproj` in Xcode and run the `PixarCarsChecklist` scheme.

To refresh the catalogue from the source database:

```sh
npm run catalog:sync
npm run catalog:validate
```

The public catalogue service is under `catalog-worker/`. The community API, D1 migrations, R2 binding, and moderation page are under `social-worker/`.

The permanent StoreKit product identifier is `com.mattjproductions.PixarCarsChecklist.pro`. See [APP_STORE_CONNECT_SETUP.md](APP_STORE_CONNECT_SETUP.md) before creating it in App Store Connect; Apple does not allow a saved product ID to be edited or reused.

## Deployed services

- Catalogue: <https://pixar-cars-catalog.mattjones7416.workers.dev>
- Community API: <https://pixar-cars-social-api.mattjones7416.workers.dev>
- Privacy policy: <https://pixar-cars-social-api.mattjones7416.workers.dev/privacy>

## Independence and attribution

This is an independent collector project and is not affiliated with, endorsed by, or sponsored by Mattel, Disney, or Pixar. Catalogue metadata is adapted from the community-maintained Disney•Pixar CARS Wiki under CC BY-SA 4.0. Product images are linked from their source pages and are not bundled in this repository. See [DATA_NOTICE.md](DATA_NOTICE.md).
