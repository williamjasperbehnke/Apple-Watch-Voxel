# Watch App

A watchOS voxel-style world editor built with SwiftUI.

## Features

- Create, open, and delete worlds.
- Place/remove colored blocks on an isometric grid.
- Rotate camera, pan the world, and change build height.
- Export worlds to PNG and preview exports on-device.

## Screenshot

![App Screenshot](./screenshot.png)

## Project Structure

- `watch_app Watch App/ContentView.swift` - world list and navigation
- `watch_app Watch App/GameView.swift` - isometric editor/game view
- `watch_app Watch App/ExportViews.swift` - export list and preview UI
- `watch_app Watch App/WorldModels.swift` - domain models
- `watch_app Watch App/WorldStore.swift` - world persistence and state
- `watch_app Watch App/WorldLibrary.swift` - world creation/export helpers

## Build

```bash
xcodebuild -project watch_app.xcodeproj -scheme "watch_app Watch App" -destination "generic/platform=watchOS" build
```
