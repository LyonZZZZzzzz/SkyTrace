# Changelog

All notable changes to SkyTrace are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Reworked camera interaction around quaternion orientation with damped following and release inertia
- SceneKit now pauses completely in the background and switches to on-demand rendering while the foreground scene is idle
- Time playback and CoreMotion pause in the background and resume from the previous state when the app returns
- Horizontal and vertical dragging can now cross the zenith and nadir continuously without hard altitude limits

### Fixed

- Removed the 45-degree camera roll jump caused by switching reference axes near 84.268 degrees altitude
- Prevented long background sessions from leaving the GPU active and causing sustained frame-rate loss after foregrounding
- Excluded background gaps from foreground frame-time samples so P95/P99 recover immediately after resume
- Kept SceneKit rendering, SpriteKit labels and picking aligned with the same current quaternion camera basis

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
