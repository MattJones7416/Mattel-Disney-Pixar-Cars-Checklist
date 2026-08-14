# App Store Connect Setup

These values are already fixed in the Xcode project and StoreKit code. Use them exactly:

| Setting | Value |
| --- | --- |
| App name | Pixar Cars Checklist |
| Bundle ID | `com.mattjproductions.PixarCarsChecklist` |
| SKU suggestion | `PIXAR-CARS-CHECKLIST-IOS` |
| App version | `1.0` |
| Pro type | Non-Consumable |
| Pro reference name | Cars Checklist Pro Unlock |
| Pro product ID | `com.mattjproductions.PixarCarsChecklist.pro` |
| Suggested UK price | £4.99 |
| Display name | Cars Checklist Pro Unlock |
| Description | Unlock all collection and backup tools. |
| Privacy policy | `https://pixar-cars-social-api.mattjones7416.workers.dev/privacy` |

The product ID is case-sensitive and cannot be edited or reused after it is saved, so copy it rather than retyping it. Apple documents the allowed product-ID characters and immutability in [In-App Purchase information](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information).

## 1. Agreements, tax, and banking

In App Store Connect, open **Business → Agreements**. The Account Holder must accept the Paid Apps Agreement before the account can offer an In-App Purchase. Complete the requested banking information and tax forms; Apple requires a US tax form even for developers outside the US. See Apple’s [agreement](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/) and [tax](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information) guidance.

## 2. Register the app identifier

In **Certificates, Identifiers & Profiles → Identifiers**, create an explicit App ID:

- Description: `Pixar Cars Checklist`
- Bundle ID: `com.mattjproductions.PixarCarsChecklist`
- Enable **Push Notifications**.
- In-App Purchase is enabled by default for an explicit App ID.

The identifier must exactly match the Xcode target. Apple’s current steps are in [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id).

Then open the target in Xcode, choose the correct Team under **Signing & Capabilities**, and confirm **In-App Purchase** and **Push Notifications** are present. Automatic signing should regenerate the provisioning profile after the App ID capability is enabled.

## 3. Create the app record

In **App Store Connect → Apps**, click **+ → New App** and enter:

- Platform: iOS
- Name: `Pixar Cars Checklist`
- Primary language: English (U.K.) or your preferred primary language
- Bundle ID: `com.mattjproductions.PixarCarsChecklist`
- SKU: `PIXAR-CARS-CHECKLIST-IOS`
- User access: Full Access unless this app needs to be limited to selected team members

Apple requires the app record before the first build upload; see [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

## 4. Create the one-time Pro unlock

Open the app record, then **Monetization → In-App Purchases → +**:

1. Type: **Non-Consumable**.
2. Reference Name: `Cars Checklist Pro Unlock`.
3. Product ID: `com.mattjproductions.PixarCarsChecklist.pro`.
4. Availability: make it available in the same storefronts as the app.
5. Price: select the price point that displays as £4.99 in the UK (or choose a different final price).
6. Add English (U.K.) localization:
   - Display Name: `Cars Checklist Pro Unlock`
   - Description: `Unlock all collection and backup tools.`
7. Upload a review screenshot that clearly shows the in-app **Pro Unlock** purchase sheet.
8. Review Notes suggestion: `A single non-consumable purchase permanently unlocks favourites, wishlist, quantities, unboxed tracking, collection photos and notes, and backup/export tools. The purchase screen is available from Settings > Unlock Pro and Restore Purchases is on the same screen.`

Apple’s creation flow is documented in [Create consumable or non-consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/). Display names are limited to 30 characters and descriptions to 45; the values above fit those limits.

## 5. Test purchases

The repository includes `PixarCarsChecklist/Pro Unlock.storekit` with the exact product ID. In Xcode choose **Product → Scheme → Edit Scheme → Run → Options**, then select **Pro Unlock.storekit** under StoreKit Configuration. Apple explains this local flow in [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode/).

Test at least:

- purchase succeeds and unlocks all Pro controls;
- cancelling leaves controls locked;
- deleting/reinstalling and tapping Restore Purchases restores access;
- a revoked/refunded transaction removes access after entitlement refresh;
- the real App Store Connect product loads its localized price in a Sandbox account and TestFlight.

Before a TestFlight test, switch the scheme’s StoreKit Configuration to **None** so the app uses Apple’s sandbox rather than the local file. Product metadata changes can take up to one hour to appear in sandbox.

## 6. Configure App Privacy

Open **App Privacy**, set the Privacy Policy URL to the URL above, and declare that the Community service collects data. Apple requires both a privacy-policy URL and accurate data-practice answers; see [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

For the current backend, the conservative declarations are all for **App Functionality**, **linked to the user**, and **not used for tracking**:

- Contact Info → Email Address
- Identifiers → User ID
- User Content → Photos or Videos
- User Content → Other User Content (messages, deal links, reports, and shared collection data)
- Identifiers → Device ID (the APNs device token, when notifications are enabled)

Local checklist status, private photos/notes, and StoreKit payment details are not sent to the community backend. Recheck these answers whenever analytics, advertising, crash reporting, or another SDK is added.

## 7. Community review preparation

The app already includes rules acceptance, objectionable-word filtering, report and block controls, admin moderation, published support contact information, and in-app account deletion. These are important because Apple’s [Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content) requires filtering, reporting, blocking, and reachable contact information for user-generated content.

Before submission:

- Create the administrator Community account using `mattjones7416@gmail.com`.
- Create a separate non-admin demo account for App Review.
- Put the demo username/password and navigation steps in **App Review Information → Notes**.
- Explain that the Feed can be read anonymously, posting requires the demo account, report/block actions are on each post, and account deletion is in Settings.
- Keep the `/admin` moderation page monitored while the app is available.

## 8. Push notifications (optional for first release)

The app and Worker are ready for APNs, but delivery is intentionally disabled until credentials are added. In Apple Developer, create a key with APNs enabled, download the `.p8` file once, and add its Key ID, Team ID, and private key to Cloudflare using the commands in `social-worker/CLOUDFLARE_SETUP_GUIDE.md`. Apple’s current token-key instructions are in [Communicate with APNs using authentication tokens](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/).

If push is not configured for version 1.0, the Community feed still works; do not advertise push notifications in App Store metadata until end-to-end delivery has been tested on a physical device.

## 9. Upload and submit

In Xcode, select **Any iOS Device (arm64)**, choose **Product → Archive**, then **Distribute App → App Store Connect → Upload**. In App Store Connect, finish the version metadata, screenshots, age rating, support URL, export-compliance questions, and select the uploaded build.

For this first non-consumable purchase, add the Pro unlock to the same submission as app version 1.0. Apple explicitly requires the first non-consumable to be submitted with a new app version; follow [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/).

Final review notes should call out:

- the exact route to the purchase screen and Restore Purchases;
- the Community demo account;
- report, block, moderation, and account-deletion locations;
- that the app is an unofficial collector checklist and is not affiliated with Mattel, Disney, or Pixar;
- that catalogue metadata is attributed under CC BY-SA 4.0 and product images are remotely linked rather than bundled.
