# Changelog

All notable changes to SkyTrace are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project follows [Semantic Versioning](https://semver.org/).

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
