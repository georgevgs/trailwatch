# TrailWatch

A minimal Apple Watch GPX hiking navigator. Import a GPX on the iPhone, send it to the Watch, then hike with the iPhone left behind: the trail on a map, your live position, progress and distance to go, a haptic alert when you stray, and a hiking workout with its route saved to Apple Health.

Requires Xcode 27, **iOS 27 and watchOS 27**. Native frameworks only (SwiftUI, MapKit, CoreLocation, WatchConnectivity, HealthKit, Swift Charts, WidgetKit, App Intents).

## iOS and watchOS 27

Built against the 27 SDKs and using what they add where it helps a hiker, checked against the SDK interfaces and the Apple guides bundled with Xcode:

- **Map places for hikers:** `MapStyle.trail()` shows only outdoor points of interest, including the categories new in 27: scenic views, picnic areas, rest areas, ranger stations, visitor centres and information booths.
- **Heart-rate zones:** the Watch's Stats page shows live heart rate and the zone you're in, from HealthKit's new `workoutBuilder(_:didUpdateWorkoutZone:)`, using the zones set in the Health app.
- **Drag to reorder** routes on both iPhone and Watch with `reorderable()` and `reorderContainer(for:)`.
- **Cross-fade** between the hike map and its stats (`navigationTransition(.crossFade)`).
- **Double tap** (`handGestureShortcut(.primaryAction)`) starts a hike from route details, shows the way back from the off-route screen and closes the summary.
- **Workout effort** (watchOS 11+): the summary asks how hard the hike was on Apple's 1–10 scale and relates it to the workout with `relateWorkoutEffortSample`, so Fitness shows it and counts it in training load.
- **Siri and the system's workout controls:** `PauseWorkoutIntent` / `ResumeWorkoutIntent` App Intents with App Shortcuts ("Pause hike in TrailWatch").
- **Complication and Smart Stack:** a WidgetKit extension (`WatchWidgets`) puts TrailWatch on watch faces (circular, corner, rectangular, inline). During a hike it shows progress, km to go, the running time and arrival, or Paused: the Watch app writes a `HikeGlance` to the app group `group.eu.vagdas.trailwatch` and reloads the widget on each whole percent, pause or resume, or every two minutes. Reloads during a workout don't count against WidgetKit's budget ([Apple DTS](https://developer.apple.com/forums/thread/819899)). If the app stops updating it, the complication goes back to a launcher after 30 minutes.
- **Always On:** with the wrist down (`isLuminanceReduced`) or in Low Power Mode the offline map draws only the trails, the route and you, and the map buttons hide, as Apple's Always On guidance asks. CoreLocation already pauses GPS by itself while you stand still.
- **Liquid Glass** as Apple's guide describes it: the map's floating controls share a `GlassEffectContainer`, the tappable progress pill uses interactive glass, and primary actions use `.glassProminent` / `.glass` button styles.

## Using it

1. **iPhone:** get the `.gpx` into Files (AirDrop it from the Mac and choose Files, or use iCloud Drive), open TrailWatch, tap **+** and pick it. Several files can be imported at once.
2. Right after import the iPhone downloads the **offline map**: the OpenStreetMap paths, tracks, roads, water and landmarks, plus contour lines and hill shading, within 600 m of the route (route › Offline Map shows its status; tap **Try Again** or **Update Map** if needed).
3. Open the route and tap **Send to Apple Watch**. The watch icon in the list shows which routes the Watch has. If the Watch is away, the route arrives the next time it's nearby.
4. **Watch:** routes with a map show **✓ Offline map**. Pick the route: its details show distance, ascent, the elevation profile, an estimated time (Tobler's hiking function), today's sunset (orange if you'd finish after dark) and its GPX waypoints. Turn on **Reverse direction** to walk it from the finish. Tap **Start** (or double tap). Allow location and Health access the first time, on this screen. A warning shows on the routes list when the free install has under three days left.
5. The map follows you; turn the Digital Crown to zoom and drag to pan, and the location button follows you again. With an offline map, the globe button switches to Apple Maps and back. The walked part of the trail is solid, the rest faded. The pill at the bottom left shows progress (or how far away the trail is before you reach it); tap it for stats. The top corners hold **End** (✕) and **Pause**; the Stats page has both too, and pressing the side button and Digital Crown together pauses as in any workout. While paused the map still shows where you are, but time, distance, climb and the recorded route stop.
6. **Stats** (tap the progress pill) has time, distance, ascent, pace, heart rate and zone, the elevation profile with where you are, the climb and descent left, the time to finish and arrival time (Tobler's estimate, adjusted to your own pace after the first kilometre), sunset, battery, and the next waypoint. Passing within 40 m of a GPX waypoint taps your wrist and shows its name; if your pace would bring you in after sunset, the Watch taps once and the map shows **Finish after sunset**.
7. Stray more than the off-route distance (Routes › Off-route alert: 30, 40, 50 or 75 m) and the Watch taps your wrist and shows how far and which way the trail is. It taps again when you're back.
8. **End** asks what to do: **Save Hike** shows the summary (with the battery used per hour, and an effort rating to save to Fitness) and saves the workout and route to Apple Health; **Discard Hike** throws it away and goes back to the routes. Until you choose, the hike keeps going: no screen can be left with the workout still running.

Swipe a route left to delete it; drag to reorder.

## Layout

```text
TrailKit/            Swift package shared by both apps, tested on the Mac
  Sources/TrailKit/  RoutePoint, GPXRoute, GPXParser, RouteCalculator (+ ClimbCounter),
                     RouteTracker (progress, waypoint stops), OffRouteMonitor, Waypoint (+ alerts), Stopwatch,
                     ElevationProfile (+ FinishEstimate, Tobler), Sun (sunset), ProvisioningProfile, RouteLibrary, Format,
                     Terrain (contours and hill shading from elevation tiles), HikeGlance (complication data),
                     TrailMap + Overpass + MapProjection (offline map data), MapStyle.trail()
  Tests/             Swift Testing; Fixtures/ holds the Kaisariani GPX
PhoneApp/            iPhone app: import, route list and map, WatchTransferService, OfflineMapService
WatchApp/            Watch app (embedded in the iPhone app, runs on its own)
  Routes/            Routes list, details, thumbnail
  Hike/              HikeManager, HikeSession, HikeProgress, LocationService, WorkoutRecorder, TrailMapView,
                     ElevationChart, hike screens
  HikeIntents.swift  Pause / Resume Hike App Intents and App Shortcuts
WatchWidgets/        Watch-face complication and Smart Stack widget (WidgetKit extension in the Watch app)
PhoneApp-Info.plist  Declares the GPX file type
WatchApp-Info.plist  Background modes: workout-processing and location
WatchApp.entitlements  HealthKit, app group
WatchWidgets.entitlements  App group (reads the hike in progress)
WatchWidgets-Info.plist  Declares the WidgetKit extension
Design/make_icon.py  Draws the app icon from the Kaisariani route (needs Pillow)
```

Design: Claude Design canvas "TrailWatch · watchOS" (Routes, Route details, Navigation, Stats, Off route, Summary).

### How the pieces work

- **Transfer.** The iPhone sends each route as a JSON file with `WCSession.transferFile`, which the system queues and finishes in the background. The Watch saves it to its own library (Application Support/routes.json) and sends back the list of route IDs as its application context, so the iPhone knows what's on the Watch.
- **Progress.** `RouteTracker` projects each fix onto the nearest segment and measures distance along the polyline. Where the route passes the same place twice (a loop's start and finish, an out-and-back) it takes the match that carries on from the last one, preferring forward.
- **Off route.** `OffRouteMonitor` alerts once you've been beyond the threshold for 10 s of usable fixes, clears within 60% of it, skips fixes less accurate than the threshold, and stays quiet until you've first reached the route.
- **Offline map.** `OfflineMapService` sends one Overpass API query per route for the area 600 m around it and keeps the result, slimmed to what the Watch draws (about 150 KB for the Kaisariani loop), inside the route. `TrailMapLayers` turns it into SwiftUI paths once, in flat metres; `TrailMapView` draws them in a `Canvas` with a single transform per frame, so panning and crown zoom stay smooth.
- **Recording.** An `HKWorkoutSession` (hiking, outdoor) keeps the app running with the wrist down. It follows HealthKit's order: start the activity and the live builder's collection; pause and resume through the session (so the side button and Digital Crown pause works too); to end, stop the activity, wait for `.stopped`, end collection, finish the workout, then end the session. The GPS route goes into the workout builder's own route builder (`seriesBuilder(for: .workoutRoute())`), which HealthKit saves with the workout, and the climb is stored as the workout's elevation ascended. Without Health access the hike still works and is just not recorded.
- **Hike lifecycle.** The hike belongs to the app (`HikeManager`), not to a screen, and takes over the whole app until it's ended. If the app quits mid-hike, watchOS relaunches it and calls `handleActiveWorkoutRecovery()`; the workout is recovered from HealthKit and the hike carries on with its saved distance and climb (`HikeProgress`). If watchOS ends the workout itself, for example when another workout app starts one, the hike is saved and its summary shown.

## Tests

The shared code runs on the Mac, with no simulator or device:

```sh
swift test --package-path TrailKit
```

## Install (free Apple Account)

One-time setup: your Apple Account with a *Personal Team* in Xcode › Settings › Accounts (team `Z47YFZ63B6`); **Developer Mode** on in the iPhone's and Watch's Settings › Privacy & Security; the developer certificate trusted under iPhone Settings › General › VPN & Device Management.

In Xcode: choose the **PhoneApp** scheme and your iPhone, **Run**; then the **WatchApp** scheme and your Watch, **Run**. Keep both unlocked, the Watch near the iPhone and Mac with Wi‑Fi on.

From the terminal (identifiers from `xcrun devicectl list devices`):

```sh
PHONE=<iphone identifier>; WATCH=<watch identifier>
xcodebuild -project TrailWatch.xcodeproj -scheme PhoneApp -configuration Debug \
  -destination "id=$PHONE" -derivedDataPath build/run -allowProvisioningUpdates build
xcrun devicectl device install app --device "$PHONE" build/run/Build/Products/Debug-iphoneos/PhoneApp.app
xcrun devicectl device install app --device "$WATCH" build/run/Build/Products/Debug-watchos/WatchApp.app
```

The Watch talks to the Mac over Wi‑Fi and sometimes drops mid-install; run the last command again.

Free provisioning lasts **seven days**; then the apps won't open until you install again (both apps warn three days ahead). A free team can create 10 App IDs a week and run 3 of its apps per device (TrailWatch uses one on each). The complication is its own App ID: if the Watch refuses the install with "This provisioning profile cannot be installed on this device", build the **WatchApp** scheme once with the Watch as destination so Xcode adds the Watch to the complication's profile, then build PhoneApp again.

## Offline maps

The route, your position, progress, off-route alerts and recording always work with no iPhone and no signal. For the map underneath, TrailWatch draws its own from **OpenStreetMap data** downloaded with each route: paths and tracks (other trails and junctions matter most when you've strayed), roads, streams, lakes, woods, peaks with their heights, springs, drinking water, viewpoints and shelters. It works anywhere in the world without an account, and the lines stay sharp at any zoom.

Why this rather than map images:

- **Apple Maps offline downloads can't be used by apps.** Apple's DTS says third-party apps can't load the areas Maps downloads ([Apple Developer Forums](https://developer.apple.com/forums/thread/765857)), and MapKit has no download API. On the Watch, `MKTileOverlay` and `MKMapView` are unavailable in the watchOS 27 SDK, so MapKit can't show custom tiles either.
- **Free tile servers forbid pre-downloading.** The OpenStreetMap and OpenTopoMap servers ban prefetching areas for offline use ([OSM tile policy](https://operations.osmfoundation.org/policies/tiles/), [openmaps.fr policy](https://openmaps.fr/tile-usage-policy.html)); Thunderforest only allows pre-caching on paid plans ([terms](https://www.thunderforest.com/terms/)); MapTiler's offline use is on paid plans.
- **Map data is allowed.** One small Overpass query per route is far inside the public instance's fair use (about 10,000 queries a day, [OSM wiki](https://wiki.openstreetmap.org/wiki/Overpass_API)). The map shows "© OpenStreetMap" as the OSMF attribution guidelines ask ([guidelines](https://osmfoundation.org/wiki/Attribution)).

**Contour lines** come from [Terrain Tiles](https://registry.opendata.aws/terrain-tiles/), open elevation data (SRTM, EU-DEM, USGS and national surveys) that Mapzen built and AWS hosts as Open Data, free with no account and no download limits stated. The iPhone fetches the elevation tiles around the route (zoom 13, about 15 m a pixel; usually two to six tiles), traces the contours itself (marching squares, then Douglas–Peucker) and sends only the lines: 37 lines and about 30 KB for the Kaisariani loop. The spacing suits the terrain, from 10 m in gentle country to 100 m in high mountains, with every fifth line bolder. Credit is shown as the sources ask ([attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)).

**Hill shading** comes from the same tiles: each slope is lit by a sun in the north-west, 45° up (Horn's method, as GDAL draws it), with the relief exaggerated 1.5× so moderate hills still read on a small screen. It goes to the Watch as a see-through PNG of at most 768 px across (about 17 KB for Kaisariani), drawn under the lines: black in the shadows, white on the slopes facing the light. Routes downloaded before contours and shading existed get them with **Update Map**.

Routes without map data (imported before this, or when the download failed) use Apple Maps; where its tiles aren't cached, the trail, start, your position and progress still draw over a blank background.

## Known limits

- Distance walked comes from the Watch's GPS (steps of 5 m or more) and can differ a little from the distance Health records.
- The off-route arrow is north-up, like the design, not turned to the way you face.
- After a relaunch mid-hike, progress along the route is found again from the next GPS fix.
- The offline map covers 600 m around the route; beyond that it's blank. Contours aren't labelled, hill shading is as coarse as the elevation data (about 15 m), and woods or lakes mapped as multipolygon relations aren't drawn. Shading and contours are hidden with the wrist down and in Low Power Mode.
- Time estimates use Tobler's hiking function until you've walked a kilometre on the route, then your own pace; long stops without pausing count as slower walking.
- Waypoint alerts come from the GPX file's `<wpt>` points only, not from map landmarks.
- The Overpass server is sometimes slow or busy (the Kaisariani query took 35 s); the download retries when you tap **Try Again**.
- Digital Crown zoom on Apple Maps is the system map's own behaviour; the offline map handles the crown itself.
