# Changelog

All notable changes to SkyTrace are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/).

## [1.2.10] - 2026-09-16

### Added

- Added a 1 second/second real-time playback option on iOS, iPadOS and macOS
- Kept playback paused until Play is pressed and retained 1 day/second as the default speed

### Fixed

- Corrected playback speed conversion so day, hour, minute and second modes advance at the rates shown in their labels

## [1.2.9] - 2026-09-16

### Changed

- Reduced the visible label budget at wide field-of-view levels to stabilize names during maximum zoom-out rotation
- Added FOV capacity hysteresis with 100, 90 and 80 label tiers
- Prioritized previously visible labels over newly eligible non-critical labels when slots are scarce

## [1.2.8] - 2026-09-16

### Fixed

- Reduced label disappear-and-return flicker at maximum field of view by adding separate entry and retention bounds for edge labels
- Kept previously displayed labels visible through small off-screen and back-face jitter
- Continued rendering temporarily while label text textures are being prepared, then returned to 2 Hz idle keepalive

## [1.2.7] - 2026-09-16

### Fixed

- Stopped star-name glyph flicker caused by repeatedly assigning unchanged `SKLabelNode` font colors and opacity
- Added per-node label style caching so font texture properties are only touched when selection or object style changes
- Kept position, visibility, collision and SceneKit-aligned projection updates unchanged

## [1.2.6] - 2026-09-16

### Fixed

- Restored SceneKit-native projection for production labels so star positions and label positions remain aligned during rotation and zoom
- Kept the 0.25-point label position deadband to prevent sub-pixel text jitter after zooming stops
- Made collision checks use the stabilized label position instead of the raw projected point

## [1.2.5] - 2026-09-16

### Fixed

- Stopped sky labels from jittering in place after field-of-view zooming settled
- Replaced production `SCNView.projectPoint` label projection with the shared deterministic `SkyProjection`
- Quantized label positions to a 0.25-point grid and ignored sub-pixel movement below that threshold

## [1.2.4] - 2026-09-16

### Fixed

- Stopped sky labels from flickering when camera damping settled near a collision boundary
- Added separate show and hide thresholds so tiny pan, zoom or hand-off movements cannot repeatedly toggle label visibility
- Applied the same hysteresis to object labels and cardinal direction markers

## [1.2.3] - 2026-09-16

### Changed

- Reordered label priority to selected target, solar-system bodies, constellations, bright stars and deep-sky objects
- Resolved SpriteKit label overlaps in screen space while keeping the existing 100-label cap
- Cached measured label sizes so collision checks do not repeatedly measure text

### Fixed

- Prevented overlapping star, constellation and deep-sky names when the sky is zoomed out or densely populated
- Kept the selected target visible while hiding lower-priority labels that overlap it or cardinal markers

## [1.2.2] - 2026-09-16

### Changed

- Deferred observation-plan, sky-event and reminder computation until the Tonight/Events UI is requested
- Added a four-state render policy with 2 Hz idle keepalive frames and thermal/low-power suspension
- Switched frame telemetry to a fixed-capacity ring buffer
- Limited SpriteKit label texture creation to four labels per frame and added offscreen font prewarming
- Bound SpriteKit label nodes to stable object IDs so camera rotation no longer rebuilds label textures
- Added label projection caching so unchanged camera/scene frames skip all `projectPoint` calls
- Pre-indexed dynamic solar-system positions in the background snapshot and reused magnitude-sorted label candidates
- Removed the startup main-thread scan and dictionary construction over all 8,404 celestial objects
- Reworked camera interaction around quaternion orientation with damped following and release inertia
- SceneKit now pauses completely in the background and switches to on-demand rendering while the foreground scene is idle
- Time playback and CoreMotion pause in the background and resume from the previous state when the app returns
- Horizontal and vertical dragging can now cross the zenith and nadir continuously without hard altitude limits

### Fixed

- Removed the 45-degree camera roll jump caused by switching reference axes near 84.268 degrees altitude
- Prevented long background sessions from leaving the GPU active and causing sustained frame-rate loss after foregrounding
- Excluded background gaps from foreground frame-time samples so P95/P99 recover immediately after resume
- Kept SceneKit rendering, SpriteKit labels and picking aligned with the same current quaternion camera basis
- Reduced post-launch and post-idle first-turn frame hitches caused by SpriteKit label font rebuilding

## [1.2.1] - 2026-09-15

### Changed

- Reworked the SceneKit star map around a static J2000 catalog root, dynamic solar-system nodes, 4 Hz background snapshots and 60 Hz render interpolation
- Moved camera gestures and device-motion smoothing into the shared render controller so SwiftUI is no longer updated for every touch or sensor sample
- Replaced the full SwiftUI label projection layer with a fixed-size SpriteKit overlay of at most 100 labels plus cardinal markers
- Added bounded frame metrics for FPS, P95/P99 frame time, slow-frame runs, geometry rebuilds, dynamic-node updates and label projection time

### Fixed

- Fixed SceneKit renderer callback isolation on its private display-link queue by coalescing frame updates onto the main actor
- Kept render, picking, selection and labels on the same unrefracted camera transform while details and plans retain atmospheric refraction

## [1.2.0] - 2026-09-15

### Added

- Local observation log with rating, weather, equipment and notes
- Application Support JSON storage with atomic writes and corruption recovery
- Offline 120-day astronomy event planning
- Moon quarters, lunar eclipses, local solar eclipses, planet conjunctions and seasons
- Unified observatory center with Tonight, Events and Logs sections
- macOS event and observation-log sidebar sections
- Privacy manifests for app targets and SkyTraceCore
- Debug Logger and Signpost instrumentation

### Changed

- Bundle IDs updated to `com.lyonzzzzzzzz.SkyTrace` and `.mac`
- App version updated to 1.2.0 (build 3)
- Observation planning and astronomy events run asynchronously and cache recent results

## [1.1.0] - 2026-09-15

### Added

- Complete tonight observation plan with sunset, sunrise and three twilight phases
- Moon phase, illumination, moonrise and moonset information
- Per-object visibility windows, best viewing time, duration and recommendation reasons
- Local favorites for stars, planets, Sun, Moon, constellations and Messier objects
- Optional local reminders for the next best viewing time
- Favorites sections and observation timeline on both iOS and macOS
- Observation planner, favorite persistence, permission and short-window tests

### Changed

- Tonight recommendations now use the next dark interval instead of current altitude alone
- Object detail views include best time, duration and viewing-window context
- App version updated to 1.1.0 (build 2)

## [1.0.0] - 2026-09-14

### Added

- Native iOS 17+ star map with offline 8,404-star catalog
- Native macOS 14+ three-column observatory workspace
- Shared SkyTraceCore and SkyTraceUI Swift packages
- Sun, Moon, planet, constellation and Messier object calculations
- Time travel from 1900 through 2100
- CoreLocation, manual coordinates and built-in city locations
- Offline search, object details and tonight recommendations
- macOS menus, keyboard shortcuts, settings and trackpad controls
- GitHub Actions for Core, macOS and iOS validation

### Fixed

- Replaced square SceneKit point primitives with transparent radial star sprites
- Removed HDR/Bloom and label shadows that could create rectangular artifacts
- Unified camera basis calculations between SceneKit and label projection
- Anchored constellation names to the weighted center of their rendered lines
