# Pixar Cars Checklist

An unofficial native SwiftUI collection tracker for Mattel Disney and Pixar *Cars* die-cast vehicles. It is a reworked version of the Metal Earth Checklist app, with a Cars-specific catalogue and collector workflow.

## What it tracks

- 1:55 die-cast releases, Mini Racers, collector exclusives, and premium/larger-scale releases
- Owned quantity and carded/unboxed state
- Favourites and wishlist
- Personal photos and notes
- Backup and restore across iPhone, iPad, and Mac
- Catalogue refreshes from the companion Cloudflare Worker

The bundled catalogue contains 1,490 distinct released Cars variants at the time of generation. The Planes spin-off and non-vehicle plastic product lines are intentionally excluded.

## Local development

Open `PixarCarsChecklist.xcodeproj` in Xcode and run the `PixarCarsChecklist` scheme.

To refresh the catalogue from the source database:

```sh
npm run catalog:sync
npm run catalog:validate
```

The Cloudflare catalogue service is under `catalog-worker/`.

## Independence and attribution

This is an independent collector project and is not affiliated with, endorsed by, or sponsored by Mattel, Disney, or Pixar. Catalogue metadata is adapted from the community-maintained Disney•Pixar CARS Wiki under CC BY-SA 4.0. Product images are linked from their source pages and are not bundled in this repository. See [DATA_NOTICE.md](DATA_NOTICE.md).
