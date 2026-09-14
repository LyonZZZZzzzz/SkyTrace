# SkyTrace Architecture

## Overview

SkyTrace is a multi-platform star map with one shared astronomy core and two
native presentation layers.

```text
SkyTraceCore + AstronomyEngine
            │
            ├── SkyTraceUI
            │
    ┌───────┴────────┐
    │                │
 iOS App         macOS App
UIKit bridge     AppKit bridge
```

## Packages

### AstronomyEngine

A vendored MIT-licensed C implementation of Astronomy Engine with a Swift API.
It calculates dates, equatorial coordinates, horizontal coordinates, planets,
Sun, Moon and rise/set-related data without network access.

### SkyTraceCore

Contains:

- Astronomy and catalog models
- Yale Bright Star Catalogue loader
- Constellation and Messier resources
- CoreLocation abstraction
- Astronomy calculations
- SkyViewModel
- Camera state and projection
- Shared SceneKit scene controller

The package owns `Stars.bin`, `Constellations.json`, `DeepSky.json`,
`StarLabels.json` and `Cities.json` in its SwiftPM resource bundle.

### SkyTraceUI

Contains platform-neutral SwiftUI theme and presentation components:

- Color and material tokens
- Shared glass panels and icon buttons
- Sky labels and density settings
- Object list rows
- Object detail content

## Targets

### SkyTrace

The iOS/iPadOS application. It provides UIKit gesture bridging, full-screen sky
interaction, sheets and mobile time controls.

### SkyTraceMac

The native macOS application. It provides an AppKit SCNView adapter, a
three-column `NavigationSplitView`, menu commands, keyboard shortcuts, settings
and trackpad input.

## Data Flow

1. `CatalogRepository` loads and validates bundled resources.
2. `SkyViewModel` combines observer context, time and catalog data.
3. Astronomy Engine converts J2000 coordinates to horizontal coordinates.
4. `SkySnapshot` stores star positions, constellation segments and anchors.
5. `SkySceneController` renders stars and lines from the snapshot.
6. `SkyProjection` projects the same horizontal vectors into label coordinates.

## Camera Invariant

`SkyCameraState.basis` is the only source of camera orientation:

- `forward`: viewing direction
- `right`: screen right axis
- `up`: screen up axis
- `roll`: additional rotation in the camera plane

SceneKit constructs its camera matrix from this basis. SwiftUI labels project
through the same basis. Platform code must not duplicate this math.

## Rendering Invariant

Each star is a tangent-plane quad with a radial transparent texture.

- No `SCNGeometryPrimitiveType.point`
- No HDR/Bloom post-processing
- Alpha blending is enabled
- Depth writing is disabled for stars
- Magnitude controls size
- B-V color index controls color

## Testing Layers

- SkyTraceCore package tests validate data, astronomy and rendering invariants
- iOS unit/UI tests validate mobile launch, search and core integration
- macOS unit/UI tests validate desktop state, launch and search
- GitHub Actions validates Core, macOS unit tests and iOS unit tests
