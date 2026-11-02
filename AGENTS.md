# Project instructions

## Project overview

- Polka / Полка is a native iPhone and iPad app. The repository, Xcode project, target, and scheme are named `vezzi-ios`.
- The app is currently a foundation with four placeholder tabs. An educational MVVM demo is kept in the source files without an in-app entry point.
- Stack: SwiftUI, Foundation, and Combine. There are currently no third-party dependencies.
- The project was created with Xcode 26.2. The app target supports iOS 26.0+, uses Swift 5 language mode, and enables default MainActor isolation. Project-level deployment settings currently specify 26.2; the target overrides them.
- This is a Git repository

## Source layout

Paths below are relative to the repository root.

| Path | Responsibility |
| --- | --- |
| `vezzi-ios/Application/vezziApp.swift` | App entry point; presents `AppRootView`. |
| `vezzi-ios/Application/Localizable.xcstrings` | English and Russian interface strings. |
| `vezzi-ios/Application/InfoPlist.xcstrings` | Localized bundle metadata, including the display name. |
| `vezzi-ios/Router/` | Tab selection, navigation paths, root composition, and destination construction. |
| `vezzi-ios/Modules/Demo/` | Standalone MVVM / binding example, available through previews. |
| `vezzi-ios/Modules/Home/View/` | Home placeholder. |
| `vezzi-ios/Modules/ShoppingList/View/` | Shopping list placeholder. |
| `vezzi-ios/Modules/Stores/View/` | Stores placeholder. |
| `vezzi-ios/Modules/Search/View/` | Search placeholder. |
| `vezzi-ios/Extensions/` | Shared text, color, image, and view helpers. |
| `vezzi-ios/SupportingFiles/Assets.xcassets` | App icons, semantic colors, and images with appearance variants. |
| `vezzi-ios.xcodeproj/project.pbxproj` | Explicit source/resource membership and build configuration. |

## Architecture and state ownership

- Keep the existing MVVM approach based on `ObservableObject` and `@Published`. The user explicitly chose this approach; do not introduce an incidental migration to `@Observable` / Observation.
- Models hold data without depending on SwiftUI. ViewModels own presentation state and behavior. Views handle layout and forward user actions.
- Use `@StateObject` where an observable object is owned, `@ObservedObject` where it is injected, and `@Binding` for a child control that reads and writes a parent's value. Use `@State` for local value state.
- `AppRootView` owns `AppRouter` with `@StateObject`. `DemoView` receives a `DemoViewModel` through its initializer and observes it; the demo is currently disconnected from app navigation.
- Keep mutable UI state on the main actor. `AppRouter` is explicitly `@MainActor`.
- Keep the explicit `nonisolated deinit` in `AppRouter` and `DemoViewModel` while supporting early iOS 26 runtimes; they avoid [Swift runtime issue #88036](https://github.com/swiftlang/swift/issues/88036).
- Follow `Modules/<Feature>/Model`, `ViewModel`, and `View` as a feature grows. Add only the layers that have actual responsibilities; empty screens do not need empty models or view models.
- Prefer straightforward, readable code. The demo is also used to explain architecture to a beginner.

## Navigation

- The three main tabs are Home / Главная, List / Список, and Stores / Магазины. Search / Поиск uses a separate native tab button with `.prominent` on iOS 27+ and `.search` on iOS 26, selected by `AppRootView.searchTabRole`.
- Demo has no tab, route, or gesture-based entry point. Keep its files and previews available for future integration.
- Each tab has its own `NavigationStack` and typed path. Do not combine them into one shared navigation history.
- `AppRouter` owns selection and paths. Use `selectTab`, `push`, `pop`, `popToRoot`, and `setPath` rather than adding competing navigation state to feature views.
- `selectTab` resets that tab's path when called with the already selected tab. Switching to a different tab preserves the other tabs' paths.
- `DestinationFactory` maps routes to module screens and applies navigation titles. Keep destination construction centralized here.
- Routes should contain simple, hashable navigation data, such as an item ID. Do not put views, view models, or UI animation namespaces in route values.
- When adding a section or destination, update the appropriate `Tab` / `Route` cases, destination factory, tab composition, and localized labels together.
- The navigation reference was [SmartRecorder](https://github.com/WoTRemboy/SmartRecorder/tree/main/SmartRecorder/Router). The local implementation is the source of truth; there is no dependency on that repository.

## UI, localization, and code style

- Use four-space indentation, Swift naming conventions, and the surrounding file's `// MARK:` structure.
- Extract layout and animation numeric literals into a private `enum Const` near the relevant view, with descriptive names and appropriate types such as `CGFloat`.
- Reuse semantic colors from `Color.Background`, `Color.Label`, and `.accentColor`. Reuse image helpers such as `Image.Demo.main`; add shared assets to the existing asset catalog.
- Support light and dark appearances using asset variants and semantic colors.
- Add user-facing text to `Application/Localizable.xcstrings` in both English and Russian, and expose it through the relevant namespace in `Texts` in `Extensions/Labels.swift`. English is the source language.
- `InfoPlist.xcstrings` is for bundle metadata. The base display name comes from the target's `INFOPLIST_KEY_CFBundleDisplayName`. Xcode generates `Info.plist`; avoid introducing a duplicate file for routine localization changes.
- Keep identifiers and router comments in English. The demo contains intentional Russian teaching comments; preserve their purpose and language when editing it.
- Provide useful `#Preview` configurations for changed views. For an interactive binding preview, use `@Previewable @State` and pass `$value` to the control.

## Xcode project maintenance

- The project uses explicit `PBXGroup` entries, not synchronized filesystem groups. Creating a Swift file on disk alone does not add it to the app target.
- For new or moved Swift files, update file references, groups, and Sources membership in `project.pbxproj`. Add resources to the appropriate Resources phase.
- Keep project-file edits focused and preserve existing identifiers and unrelated settings. Do not change deployment targets, bundle identifiers, signing, or product names as incidental cleanup.
- Inspect current file contents before editing: the user may be working in Xcode at the same time. Preserve staged and unstaged work unrelated to the task.

## Build and validation

Run commands from the repository root using Xcode 27+ (the iOS 27 SDK is required for `TabRole.prominent`). If an older Xcode is selected, prefix commands with `DEVELOPER_DIR='/Applications/Xcode 27.1.app/Contents/Developer'` or the path to the installed Xcode 27+. For changes to Swift code, resources, or project configuration, build for the simulator without code signing:

```sh
xcodebuild \
  -project vezzi-ios.xcodeproj \
  -scheme vezzi-ios \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/vezzi-ios-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Useful focused checks:

```sh
git diff --check
plutil -lint vezzi-ios.xcodeproj/project.pbxproj
```

- There are currently no checked-in test targets, test schemes, or formatter configuration. Do not report a successful build as a successful test run.
- For navigation changes, check all four tabs, separate search presentation, and independent histories.
- For UI changes, inspect relevant light/dark and English/Russian states. Check large text and compact layouts when the change affects sizing.
- Discover available simulators with `xcrun simctl list devices available`; do not hard-code a device UUID from a previous session. Restore simulator appearance settings changed during verification.
- Simulator builds require access to CoreSimulator and its runtimes. Distinguish environment/access failures from source errors and report checks that could not run.
- Keep build output, screenshots, and temporary verification projects outside the repository. Documentation-only and comment-only edits do not require a full app build.

## Collaboration

- Discuss changes with the user in Russian unless they request another language. Keep explanations concrete and concise.
- Commit messages use English Conventional Commits, normally one line, such as `feat: add tab navigation with separate search button`.
- When asked for a commit title, inspect current changes and provide the title. A request for a title does not mean creating a commit or pushing it.
- Keep this file concise and update it when architecture or build conventions change. Record durable project guidance here, not temporary task logs.
