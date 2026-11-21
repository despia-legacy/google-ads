# Google Ads

Source preview for Despia V3. This snapshot requires the runtime update currently awaiting release and an approved extension-enabled native build. Uploading these files does not change an installed app.

Firebase Analytics app events for the Despia V3 native extension runtime on iOS and Android. This adapter is independent of AppsFlyer. It reports native events to Firebase Analytics so a linked Google Ads account can use eligible events as conversions. It does not display ads or include AdMob.

Source preview. Requires the upcoming approved V3 extension build release. Verify campaign attribution in your advertising account before launch. First-party V4 support comes through the new package registry.

The JavaScript API works with React, Next.js, TanStack, Vue, Svelte and HTML5. Projects built with Lovable, Base44, Replit and other app builders need custom JavaScript and static file hosting. Claude Code, Codex and Cursor can edit the same extension files. Native features run inside an approved Despia V3 app build.

## Install

1. Copy `googleads/` into your web project's `public/despia/googleads/`.
2. Add `googleads` to `public/despia/extensions.json`:

   ```json
   { "extensions": ["googleads"] }
   ```

3. Register the iOS and Android apps in the same intended Firebase project. Keep one Google app ID for each distributed app variant. Link Firebase Analytics to your Google Ads account and choose the appropriate conversions there.
4. For iOS, supply the matching `GoogleService-Info.plist` through the app's Despia build configuration. The V3 build copies this file even when Firebase push is disabled. This extension uses that file when no default Firebase app exists. It does not replace an existing app's configuration file.
5. For Android, an app's generated Firebase resources take priority. When the app has none, fill the empty strings in `googleads/android/googleads/src/main/res/values/google_ads.xml` with the Firebase Android app's `google_app_id`, `google_api_key`, `project_id` and project number `gcm_defaultSenderId`. These names belong to the Firebase SDK. They are not Despia client IDs. Do not put service account credentials or server keys in the app.
6. Rebuild the app through the V3 Extensions approval flow. Copying files to the website does not change an installed app.

This extension pins the existing iOS Firebase SDK version, 10.29.0, through CocoaPods. Its CocoaPods dependency versions and SDK contents are pinned for approval. It uses Android Firebase BOM 34.11.0. It adds no Messaging dependency and never enables push or calls a Messaging API.

See [V3 Extensions](https://setup.despia.com/experiments/v3-extensions) and the [extension skill](https://github.com/despia-legacy/extension-skill).

## Collection and consent

`configure` reuses the default Firebase app or creates it from the build's existing Firebase configuration. It leaves existing collection and consent settings untouched. Analytics only logs for Firebase's default app; the adapter never creates a second named app.

The adapter starts with its own event routes disabled. That does not mean the Firebase SDK is globally disabled: Firebase can collect automatic events before a JavaScript call, and another integration may already have enabled collection. To disable collection from startup, set Firebase's documented `FIREBASE_ANALYTICS_COLLECTION_ENABLED` Boolean to `false` in the iOS app's Info.plist and `firebase_analytics_collection_enabled` Boolean metadata to `false` in the Android application's manifest. Coordinate these app-wide settings with existing Firebase integrations. The extension does not silently override them.

The explicit `consent` route changes the app-wide Firebase Analytics collection setting and all four Firebase consent types. `enabled` controls analytics storage and adapter event routes. The optional ad consent parameters default to `false`. Calling the route also affects other code using the same SDK. Firebase persists its settings, while the adapter's own `enabled` state starts as `false` each process launch.

ATT permission is separate. This adapter does not request the ATT prompt or claim that Firebase consent grants ATT permission. The iOS closure includes advertising identifier support. Configure your privacy disclosures, ATT flow and any required advertiser network settings for your app.

## JavaScript SDK

Install the published SDK in your web app:

```sh
npm install despia-native
```

Import `despia` directly from `despia-native`. The examples use SDK 1.0.28. Run native calls from browser event handlers or mounted client hooks; importing the SDK during server rendering is safe. The installed Despia V3 app must include the approved extension.

Pass the route's exact output variable as the second argument. The SDK resolves an object whose matching property contains the full native envelope: `ok`, `code`, `error` and `data`, with runtime metadata. A native `ok: false` answer does not reject the SDK promise. Check `ok` before reading `data`. A single watched value becomes `undefined` after 30 seconds without an answer. Await calls using the same output variable sequentially.

## Calls

Apply the user's collection choice before sending events. Encode JSON query values with `encodeURIComponent(JSON.stringify(...))`.

```javascript
import despia from 'despia-native';

const configuredReply = await despia('extension://googleads/configure', ['googleadsConfigureResult']);
const configured = configuredReply.googleadsConfigureResult;
if (!configured?.ok) throw new Error(configured?.error ?? 'No native answer');

const consentReply = await despia('extension://googleads/consent?enabled=true&ad_storage=false&ad_user_data=false&ad_personalization=false', ['googleadsConsentResult']);
const consent = consentReply.googleadsConsentResult;
if (!consent?.ok) throw new Error(consent?.error ?? 'No native answer');

const properties = { currency: 'USD', value: 12.5 };
const loggedReply = await despia(
  `extension://googleads/event?name=generate_lead&properties=${encodeURIComponent(JSON.stringify(properties))}`,
  ['googleadsEventResult']
);
const logged = loggedReply.googleadsEventResult;
if (!logged?.ok) throw new Error(logged?.error ?? 'No native answer');

const purchaseReply = await despia('extension://googleads/purchase?amount=12.50&currency=USD&transaction_id=order123', ['googleadsPurchaseResult']);
const purchase = purchaseReply.googleadsPurchaseResult;
if (!purchase?.ok) throw new Error(purchase?.error ?? 'No native answer');
```

| Route | Parameters | Successful answer | SDK output variable |
| --- | --- | --- | --- |
| `status` | None | `configured`, adapter `enabled`, `sdk` | `googleadsStatusResult` |
| `configure` | None | `configured: true`, adapter `enabled` | `googleadsConfigureResult` |
| `consent` | Required `enabled` Boolean, optional `ad_storage`, `ad_user_data`, `ad_personalization` Booleans | `enabled` | `googleadsConsentResult` |
| `event` | Required `name`, optional JSON string `properties` | `accepted: true` | `googleadsEventResult` |
| `purchase` | Required `amount`, uppercase three-letter `currency`, `transaction_id`, optional JSON string `properties` | `accepted: true` | `googleadsPurchaseResult` |
| `user` | Optional `id`; omit to clear | `accepted: true` | `googleadsUserResult` |
| `property` | Required `name`, optional `value`; omit the value to clear | `accepted: true` | `googleadsPropertyResult` |
| `reset` | None | `accepted: true` | `googleadsResetResult` |

These are the bridge result's payload fields. `accepted` means the request was handed to the SDK, not that Google recorded or attributed it. The SDK can reject event names and parameters under its own rules. Purchase uses Firebase's `purchase` event and overrides `value`, `currency` and `transaction_id` in `properties` with the explicit arguments.

`properties` accepts a JSON object of strings and finite numbers, plus Firebase's `items` array of objects containing strings and finite numbers. Booleans, nulls and other nested objects are rejected. Clearing a user ID, clearing a property and resetting Analytics data remain available after disabling adapter collection. Reset affects the shared Firebase Analytics instance and does not delete historical server records or change consent.

Errors include `not_configured`, `configuration_conflict`, `consent_required` and `bad_request`. Android also reports `sdk_error` if Firebase cannot use the app configuration. A mismatched existing default app is preserved and reported as a configuration conflict.

## Platform limits

The iOS adapter uses the Firebase version already present in the V3 build. It supports Analytics events, purchases and consent controls. Current automatic Google Ads on-device event conversion measurement needs a coordinated Firebase SDK upgrade and is not included here.

Android uses Firebase Analytics through the existing Firebase BOM. Both platforms use the default Firebase app and require configuration for the application's own bundle ID or package. Collection settings and reset operations affect the shared Analytics instance.

A successful bridge reply does not confirm a Google Ads conversion. App registration, Google Ads linkage, event eligibility, consent and live campaign attribution must be verified for each app before launch.

Vendor references: [Firebase default app and reliable reporting](https://firebase.google.com/docs/projects/multiprojects), [iOS collection controls](https://firebase.google.com/docs/analytics/ios/configure-data-collection), [Android collection controls](https://firebase.google.com/docs/analytics/android/configure-data-collection), [Google Ads integration](https://support.google.com/firebase/answer/6383833?hl=en).

## License

Source available under the [Despia V3 Extension Source-Available Commercial License](LICENSE). Commercial use requires a valid Despia commercial license and Despia project for the application and operating system. Vendor SDKs retain their own licenses. This repository is not open source.

## Source and licensing

Browse, clone or fork this source to inspect it. Public GitHub forks remain public. For private development, clone into a private workspace or private repository. Modification, building, execution and deployment require a valid Despia commercial license and a valid Despia project for the application. The standard price is USD 249 per application per operating system. Licensed users may customize the extension or use it as a reference for new functionality in that licensed app. Keep the license and applicable notices. See [LICENSE](LICENSE) for the terms.
