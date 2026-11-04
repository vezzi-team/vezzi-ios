# Project instructions

## Project overview

- Polka / Полка is a native iPhone and iPad app. The repository, Xcode project, target, and scheme are named `vezzi-ios`.
- The app has Home, List, Stores, and Search tabs. Home is a temporary mock storefront; Search observes the repository's catalog. List and Stores remain placeholders. An educational MVVM demo is kept in the source files without an in-app entry point.
- Stack: SwiftUI, Foundation, Combine, and Core Data. Lottie 4.6.1 is resolved through the official `lottie-spm` package; keep `Package.resolved` in version control.
- The project was created with Xcode 26.2. The app target supports iOS 26.0+, uses Swift 5 language mode, and enables default MainActor isolation. Project-level deployment settings currently specify 26.2; the target overrides them.
- This is a Git repository

## Source layout

Paths below are relative to the repository root.

| Path | Responsibility |
| --- | --- |
| `vezzi-ios/Application/VezziApp.swift` | App entry point; presents `AppLaunchView` and prepares caching independently. |
| `vezzi-ios/Application/AppLaunchView.swift` | Keeps `AppRootView` alive beneath a temporary splash overlay. |
| `vezzi-ios/Application/AppDependencies.swift` | Constructs shared repositories immediately and prepares optional caching. |
| `vezzi-ios/Application/Localizable.xcstrings` | English and Russian interface strings. |
| `vezzi-ios/Application/InfoPlist.xcstrings` | Localized bundle metadata, including the display name. |
| `vezzi-ios/Application/Info.plist` | Additional plist keys merged with generated metadata; registers bundled fonts. |
| `vezzi-ios/Router/` | Tab selection, navigation paths, root composition, and destination construction. |
| `vezzi-ios/Modules/Demo/` | Standalone MVVM / binding example, available through previews. |
| `vezzi-ios/Modules/Home/` | Draft product grid and detail sheet, with feature-local mock data and quantities. |
| `vezzi-ios/Modules/ShoppingList/View/` | Shopping list placeholder. |
| `vezzi-ios/Modules/Stores/View/` | Stores placeholder. |
| `vezzi-ios/Modules/Search/` | Search UI and observable presentation state. |
| `vezzi-ios/Modules/Splash/` | Moti animation, bottom wordmark, and bounded splash presentation state. |
| `vezzi-ios/CoreData/Catalog/` | Catalog models, session actor, indexed queries, repository, and optional cache adapter. |
| `vezzi-ios/CoreData/Persistence/` | Persistent container and versioned `Polka.xcdatamodeld`. |
| `vezzi-iosTests/` | App-hosted repository integration tests. |
| `vezzi-ios/Extensions/` | Shared text, color, image, and view helpers. |
| `vezzi-ios/SupportingFiles/Assets.xcassets` | App icons, semantic colors, and images with appearance variants. |
| `vezzi-ios/SupportingFiles/LaunchScreen.storyboard` | Static system launch screen; shares the splash background and wordmark layout. |
| `vezzi-ios/SupportingFiles/Animations/` | Bundled Lottie JSON; Moti includes all image data and needs no network. |
| `vezzi-ios/SupportingFiles/Fonts/` | Onest variable font and its SIL Open Font License. |
| `vezzi-ios.xcodeproj/project.pbxproj` | Explicit source/resource membership and build configuration. |

## Architecture and state ownership

- Keep the existing MVVM approach based on `ObservableObject` and `@Published`. The user explicitly chose this approach; do not introduce an incidental migration to `@Observable` / Observation.
- Models hold data without depending on SwiftUI. ViewModels own presentation state and behavior. Views handle layout and forward user actions.
- Use `@StateObject` where an observable object is owned, `@ObservedObject` where it is injected, and `@Binding` for a child control that reads and writes a parent's value. Use `@State` for local value state.
- `AppRootView` owns `AppRouter` with `@StateObject`. `DemoView` receives a `DemoViewModel` through its initializer and observes it; the demo is currently disconnected from app navigation.
- Repositories are injected through `AppDependencies` and `DestinationFactory`. `SearchView` owns its `SearchViewModel` with `@StateObject`; feature views and view models do not access Core Data.
- Keep mutable UI state on the main actor. `AppRouter` is explicitly `@MainActor`.
- Keep the explicit `nonisolated deinit` in `AppRouter` and `DemoViewModel` while supporting early iOS 26 runtimes; they avoid [Swift runtime issue #88036](https://github.com/swiftlang/swift/issues/88036).
- Follow `Modules/<Feature>/Model`, `ViewModel`, and `View` as a feature grows. Add only the layers that have actual responsibilities; empty screens do not need empty models or view models.
- Prefer straightforward, readable code. The demo is also used to explain architecture to a beginner.
- Home currently uses `HomeMockData` and an owned `HomeViewModel` for layout prototyping. Its quantities are shared with the product sheet through bindings, reset on scene recreation, and are not imported into the catalog or persisted as shopping lists.
- The splash plays once per scene creation for 1.1 seconds, then reveals the interface with a short scale-down transition. Scale tab content only; keep the native tab bar stationary. Never gate dismissal on cache/network readiness. Skip the splash and transition for Reduce Motion, dismiss without motion on backgrounding, and retain the 1.6-second fallback if Lottie does not complete. Keep the system launch wordmark size/inset in sync with `SplashView`.

## Persistence and catalog

- `Polka.xcdatamodeld` currently contains Product, Store, and Offer entities. Shopping lists and plans are a later stage; do not infer their status or import semantics before reviewing actual data.
- `CatalogRepository` exposes independent, non-failing search publishers through Combine and delivers results on the main queue. Subscribe and cancel on the main actor. Search returns at most `CatalogSearch.resultLimit` products; refresh errors are independent of query changes.
- `DefaultCatalogRepository` coordinates `CatalogSource`, a `CatalogSession` actor, and an optional `CatalogCache`. The actor serializes atomic session changes off MainActor; immutable snapshots maintain product ordering and an offer index. Search uses a background queue and the same query implementation in previews.
- `CoreDataCatalogCache` only loads snapshots and saves `CatalogCacheBatch` changes. There is no separate Core Data/FRC query implementation. The repository accepts session imports without waiting for disk writes; this is not a durability guarantee for future user edits.
- Keep one active cache writer and coalesce pending record IDs. Read the latest values when writing; include referenced parents without resaving unrelated offers. Retain dirty IDs on failure. Cache failures must not block source results or subscriptions; report them separately and allow retry.
- Merge a late cache load without rolling back session changes. Keep the same repository instance during cache recovery so UI state and subscriptions survive.
- Core Data entities stay inside storage code and their context's queue. Value models and import logic are explicitly `nonisolated`; disk reads/writes use the container's background API. The app UI observes session snapshots, not managed objects.
- Read SQLite snapshots through `PersistenceController.performSnapshotRead`, which pins one query generation across all fetches. Each new read gets a fresh context; in-memory stores skip unsupported query generation pinning.
- Route app catalog updates through `DefaultCatalogRepository` so session data and optional persistence stay consistent. Future source and synchronization code must not write to the cache behind the app repository.
- Existing queries must reflect changes to products, offers, and stores, including offer reassignment and store deactivation.
- Import batches upsert stable string IDs and save atomically. Missing records are retained. Reject duplicate IDs, invalid quantities/prices, and missing offer references. Preserve Decimal prices, currency, source timestamps, and provenance.
- An older or undated offer must not overwrite an existing dated, newer offer; use the shared replacement rule. `StoredCatalogOffer.cachedAt` is receipt time, preserved across queueing, recovery, and disk writes. Unrelated changes must not refresh it; it is not evidence that the source price is current.
- `PolkaV2` stores exact prices and package quantities as locale-independent decimal strings. Legacy numeric attributes remain for lightweight migration from version 1; read them only when the text field is absent. Malformed text is a cache error, not grounds to silently use a rounded number. Migration cannot reconstruct digits already lost by version 1.
- The app starts with an empty session and restores cached catalog data when available. `CatalogSource` is the adapter boundary for a future file or API; no production source is configured yet. Sample records belong only in previews/tests. Authentication, account-specific data, and synchronization are future layers, not responsibilities of the Core Data adapter.
- Never delete/recreate the store to recover from an opening or migration error. Continue with session data, surface cache failure without blocking the app, and allow retry. Add model versions as persistent schema changes.

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
- Keep SwiftUI `body` focused on composition. Extract meaningful nested sections into `private var ...: some View` or `private func ... -> some View` instead of building a deeply nested, monolithic view hierarchy.
- Extract layout and animation numeric literals into a private `enum Const` near the relevant view, with descriptive names and appropriate types such as `CGFloat`.
- Reuse semantic colors from `Color.Background`, `Color.Label`, and `.accentColor`. Reuse image helpers such as `Image.Demo.main`; add shared assets to the existing asset catalog.
- Centralize SF Symbols in `Image.System` in `Extensions/ImageExtension.swift`. Pass these images through native label closures for buttons, tabs, and empty states instead of keeping symbol-name strings in views or the router.
- Support light and dark appearances using asset variants and semantic colors.
- Prefer `.onestTextStyle(_:weight:)` for brand text: it applies the sizes (48, 32, 20, 16, 14 pt), line heights, Dynamic Type, and system Bold Text adjustment. For explicit design metrics, use `.onestTextStyle(size:lineHeight:weight:relativeTo:)` without changing the shared named styles. `Font.onest` is the font-only factory; it scales with Dynamic Type but does not read Bold Text from the environment. Pass weights through these helpers to select exact named Onest instances. The variable font comes from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/onest); keep its license bundled.
- Add user-facing text to `Application/Localizable.xcstrings` in both English and Russian, and expose it through the relevant namespace in `Texts` in `Extensions/Labels.swift`. English is the source language.
- Split growing `Texts` feature namespaces into nested enums by screen or reusable component, and keep mock content in a separate group. For Home, use `Main`, `Product`, `Quantity`, and `Mock`; share declarations across consumers instead of duplicating them.
- Keep accessibility identifiers in `Extensions/AccessibilityID.swift`, grouped by feature. Use constants for fixed controls and functions with stable model IDs for repeated elements. Do not localize identifiers; VoiceOver labels still use `Texts`.
- `InfoPlist.xcstrings` is for bundle metadata. The base display name comes from the target's `INFOPLIST_KEY_CFBundleDisplayName`. Xcode merges `Application/Info.plist` (currently `UIAppFonts`) with generated metadata; keep display names, launch screen, and scene settings in the existing build settings.
- Keep identifiers and router comments in English. The demo contains intentional Russian teaching comments; preserve their purpose and language when editing it.
- Provide useful `#Preview` configurations for changed views. For an interactive binding preview, use `@Previewable @State` and pass `$value` to the control.
- Do not wrap `#Preview` declarations or their supporting preview types in `#if DEBUG`.

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

- The shared `vezzi-ios` scheme includes the `vezzi-iosTests` target. Run `xcodebuild -project vezzi-ios.xcodeproj -scheme vezzi-ios -destination 'platform=iOS Simulator,id=<discovered UUID>' -derivedDataPath /tmp/vezzi-ios-derived-data CODE_SIGNING_ALLOWED=NO test` with Xcode 27+. There is no formatter configuration.
- Keep tests for atomic import, duplicate prevention, indexed queries and linked-data updates, independent errors, coalesced writes/recovery, exact Decimal round trips through SQLite, migration from version 1, and operation with an absent, slow, or failing cache. A build is not a test run.
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
