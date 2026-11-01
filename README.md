# TrailWatch

GPX hiking navigator for Apple Watch. Import a route on the iPhone, send it to the Watch, and hike without the phone: map, live position, progress, off-route alerts, and a hiking workout saved to Apple Health.

Needs Xcode 27, iOS 27 and watchOS 27. Apple frameworks only.

## Using it

1. **iPhone:** put the `.gpx` in Files, open TrailWatch, tap **+**. The offline map (OpenStreetMap data, contours and hill shading, 600 m around the route) downloads right after.
2. Open the route and tap **Send to Apple Watch**. If the Watch is away, it arrives later.
3. **Watch:** pick the route to see distance, climb, elevation profile, estimated time and sunset. Optionally reverse it. Tap **Start** or double tap.
4. **On the hike:** the Crown zooms, drag pans. Tap the progress pill for stats (pace, heart rate zone, time to finish, next waypoint). The Watch taps your wrist at GPX waypoints, when you stray past the off-route distance (30–75 m, set on the routes list), and if you'll finish after sunset.
5. **End** → **Save Hike** (shows a summary and saves to Health) or **Discard Hike**.

Swipe a route to delete, drag to reorder.

## Layout

```text
TrailKit/      Shared Swift package: GPX parsing, route maths, tracking, offline map data. Tested on the Mac.
PhoneApp/      iPhone app: import, route list, sending to the Watch, offline map download
WatchApp/      Watch app: Routes/ (list, details), Hike/ (session, workout, map, screens), Siri intents
WatchWidgets/  Complication and Smart Stack widget
Design/        App icon script (needs Pillow)
```

## How it works

- **Transfer:** the iPhone sends each route as JSON with `WCSession.transferFile`. The Watch stores it and replies with the IDs it has.
- **Progress:** `RouteTracker` snaps each fix to the nearest segment. On loops and out-and-backs it picks the match that continues from the last one.
- **Off route:** `OffRouteMonitor` alerts after 10 s beyond the threshold and clears within 60% of it. It ignores inaccurate fixes and stays quiet until you've reached the route.
- **Recording:** an `HKWorkoutSession` (hiking, outdoor) keeps the app alive with the wrist down and saves the GPS route and climb. Without Health access, the hike still works but isn't saved.
- **Recovery:** the hike belongs to `HikeManager`, not a screen. If the app quits, watchOS relaunches it and the workout and progress are restored.
- **Complication:** the Watch app writes a `HikeGlance` to the app group `group.eu.vagdas.trailwatch` and reloads the widget on each whole percent, pause or resume, or every two minutes.

## Offline maps

The route, position, alerts and recording always work offline. The map underneath is drawn from data downloaded with the route:

- **OpenStreetMap** via one Overpass query per route: paths, roads, water, woods, peaks, springs, shelters. Apps can't use Apple Maps offline areas, watchOS MapKit has no custom tiles, and free tile servers forbid bulk downloads, so the app draws vector data itself.
- **Contours and hill shading** from [Terrain Tiles](https://registry.opendata.aws/terrain-tiles/). The iPhone traces the contours and renders the shading, then sends only lines and a small PNG.

Routes without map data fall back to Apple Maps.

## Tests

```sh
swift test --package-path TrailKit
```

## Install (free Apple Account)

One-time setup: add your Personal Team in Xcode › Settings › Accounts (team `Z47YFZ63B6`). Turn on Developer Mode on the iPhone and the Watch, and trust the certificate on the iPhone under Settings › General › VPN & Device Management.

In Xcode, run the **PhoneApp** scheme on the iPhone, then **WatchApp** on the Watch. From the terminal (IDs from `xcrun devicectl list devices`):

```sh
PHONE=<iphone id>; WATCH=<watch id>
xcodebuild -project TrailWatch.xcodeproj -scheme PhoneApp -configuration Debug \
  -destination "id=$PHONE" -derivedDataPath build/run -allowProvisioningUpdates build
xcrun devicectl device install app --device "$PHONE" build/run/Build/Products/Debug-iphoneos/PhoneApp.app
xcrun devicectl device install app --device "$WATCH" build/run/Build/Products/Debug-watchos/WatchApp.app
```

If the Watch install drops, run the last command again.

Free provisioning expires after 7 days. Both apps warn 3 days ahead. If the Watch says "This provisioning profile cannot be installed on this device", build **WatchApp** once with the Watch as the destination, then build PhoneApp again.

## Credits

- Map data © OpenStreetMap contributors, under the ODbL ([attribution guidelines](https://osmfoundation.org/wiki/Attribution)).
- Elevation from Terrain Tiles by Mapzen: SRTM, EU-DEM © Copernicus, USGS and others ([attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)).

Both credits are shown on the map in the app.

## Known limits

- Walked distance comes from GPS and can differ slightly from Health's.
- The off-route arrow points relative to north, not to the way you're facing.
- The offline map covers only 600 m around the route. Contours have no labels.
- Time estimates use Tobler's hiking function for the first kilometre, then your own pace.
- Overpass can be slow (35 s for the Kaisariani route). Tap **Try Again** if a download fails.
