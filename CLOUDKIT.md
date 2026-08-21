# Vane CloudKit

Vane's SwiftData store syncs through the private CloudKit database in
`iCloud.com.codearc.vane` on signed Apple devices. The simulator uses the same
schema locally because the current Xcode simulator signing context does not
embed iCloud entitlements.

Debug builds use the CloudKit Development environment. Release builds use the
Production environment.

## Current targets

- `Vane`: owns the SwiftData store and has iCloud/CloudKit, push notification,
  background remote notification, WeatherKit, and app-group capabilities.
- `VaneWidgets`: reads the app-group widget snapshot. It does not open the
  SwiftData store or the CloudKit container directly.

## Adding another Vane app target

For a future watchOS, macOS, iPadOS, or visionOS app that opens this SwiftData
store:

1. Add the iCloud capability and select CloudKit.
2. Select the existing `iCloud.com.codearc.vane` container. Do not create a
   separate container for the new target.
3. Add Push Notifications and the remote-notification background mode where
   the platform supports them.
4. Use `VaneCloudKit.cloudBackedConfiguration(schema:)` with the shared Vane
   schema and migration plan.
5. Test conflict behavior using two Apple devices signed in to the same Apple
   Account before release.

## Release checklist

After a development build has initialized any new schema changes, open CloudKit
Console for `iCloud.com.codearc.vane`, review the Development schema, and deploy
it to Production before shipping the matching TestFlight or App Store build.
CloudKit production schemas are append-only, so model changes must continue to
use a reviewed `VersionedSchema` migration.

The initial `CD_SavedPlace`, `CD_WeatherCheckIn`, and `CD_WeatherProfile` schema
was deployed to Production on August 20, 2026.
