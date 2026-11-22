# NoNeedCloud for macOS

Native macOS client (Swift 6 / SwiftUI, macOS 15+). See the root `README.md` for the product overview, `docs/PRD.md` for requirements and `docs/design/macos-ux-spec.md` for UX.

## Layout

```
apps/macos/
├── project.yml                 # XcodeGen spec — source of truth for the Xcode project
├── NoNeedCloud.xcodeproj       # Generated from project.yml (committed so Xcode opens it directly)
├── Config/Signing.xcconfig     # Bundle ID + signing; local overrides in Signing.local.xcconfig
├── App/                        # App target: SwiftUI scenes and views, entitlements, assets
└── Packages/NoNeedCloudCore/   # Models, persistence, setup and (later) the backup engine + tests
```

Anything that doesn't need AppKit/SwiftUI goes in `NoNeedCloudCore`, so it can be tested with `swift test` without launching the app.

## Build & test

Open `NoNeedCloud.xcodeproj` in Xcode and run the `NoNeedCloud` scheme, or from the terminal:

```bash
xcodebuild -project NoNeedCloud.xcodeproj -scheme NoNeedCloud build
xcodebuild -project NoNeedCloud.xcodeproj -scheme NoNeedCloud test
```

Core tests alone (fastest):

```bash
cd Packages/NoNeedCloudCore && swift test
```

After adding/removing files or changing targets, regenerate the project (`brew install xcodegen`):

```bash
xcodegen generate
```

## Sandbox & signing

- The app runs in the App Sandbox. Folders the user picks are stored as security-scoped bookmarks (`FolderReference`); always open them through `withAccess(_:)`.
- Entitlements: user-selected read/write, app-scoped bookmarks, Photos library.
- Debug builds are signed ad hoc ("Sign to Run Locally"). To use your Apple Developer team, create `Config/Signing.local.xcconfig` (git-ignored) with `DEVELOPMENT_TEAM = <TEAMID>` and `CODE_SIGN_IDENTITY = Apple Development`.
- `com.noneedcloud.mac` is a placeholder bundle ID until the team picks the real one.

## Status

M0 (project foundation) done. Next: M1, the single main window from the UX spec, replacing the interim setup wizard.
