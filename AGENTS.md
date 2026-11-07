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
| `vezzi-ios/Application/AppDependencies.swift` | Constructs shared dependencies; prepares optional caching and restores authentication independently. |
| `vezzi-ios/Application/AuthenticationSession.swift` | App-wide observable account state, restoration, and temporary profile preferences. |
| `vezzi-ios/Application/Localizable.xcstrings` | English and Russian interface strings. |
| `vezzi-ios/Application/InfoPlist.xcstrings` | Localized bundle metadata, including the display name. |
| `vezzi-ios/Application/Info.plist` | Additional plist keys merged with generated metadata; registers bundled fonts. |
| `vezzi-ios/Router/` | Tab selection, navigation paths, root composition, and destination construction. |
| `vezzi-ios/Modules/Demo/` | Standalone MVVM / binding example, available through previews. |
| `vezzi-ios/Modules/Home/` | Draft product grid and detail sheet, with feature-local mock data and quantities. |
| `vezzi-ios/Authentication/` | Shared authentication models, service contract and implementation, Keychain storage, and explicit preview mock. |
| `vezzi-ios/Networking/` | URLSession transport, API configuration, JSON decoding, and safe HTTP errors. |
| `vezzi-ios/Modules/Login/` | Login screen and its MVVM presentation state. |
| `vezzi-ios/Components/Moti/` | Reusable mascot views, face geometry, and motion used by login and debug screens. |
| `vezzi-ios/Modules/Profile/` | Profile overview and native editors for temporary session preferences. |
| `vezzi-ios/Modules/Debug/` | Diagnostic screens opened from the profile's Debug section. |
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
- Home currently uses `HomeMockData` and an owned `HomeViewModel` for layout prototyping. The product sheet observes that same model and passes quantity bindings to its controls and alternative product cards. Quantities reset on scene recreation and are not imported into the catalog or persisted as shopping lists. The sheet uses native navigation title/subtitle and keeps `HomeProductActions` in a bottom `safeAreaBar`. The address and profile entry use the native navigation toolbar; at accessibility text sizes, the address scrolls with the catalog to preserve usable space. The dinner banner always scrolls with the catalog.
- Category filters use a native pinned section header and a horizontal glass button strip. `HomeViewModel.selectedCategory` filters the Home feed; `nil` shows all products without clearing quantities. Preserve vertical position while the banner is visible; only scroll to the results container when the feed is below its start. Keep that container's ID outside lazy children. For a shorter feed, animate scrolling first, then apply the latest selection to the view's `displayedCategory` when `onScrollPhaseChange` reports idle; respect Reduce Motion. Observe only the Boolean top threshold, not every offset. Tapping the active category only centers its chip. Keep short filtered sections tall enough to retain the pinned header.
- Home cards place store placeholders and quantity controls over the artwork, outside the product button. Names reserve two lines and truncate at the end; names, package labels, and prices have independent text sizes. At accessibility text sizes, show full names, move controls below the content, and retain the native `Stepper`. Quantity controls use native `GlassEffectContainer` morphing with distinct add/counter effect IDs in a local namespace and `numericText` for numbers; disable motion for Reduce Motion.
- Product details use a standard sheet with its own navigation path of product IDs, independent of the tab paths. Selecting an alternative pushes a new page in that sheet. Only the root page shows Close; pushed pages use the native Back button and preserve the previous page's scroll position. All pages share Home's quantities.
- Observe quantity changes for haptic feedback once in `HomeView`, using the shared quantities so card and sheet edits do not create duplicate feedback handlers.
- Use `.shimmer()` on gray placeholders for remotely loaded images, including product artwork and store logos. For store avatars over artwork, pair `.shimmer(style: .lighter)` with `Color.Background.placeholderLighter`. Derive phase from a fixed time origin so reused views stay synchronized. The modifier caps updates at 60 fps and fades in and out over 0.2 seconds; remove its timeline after fading out when loading ends, content is covered, or it leaves the scroll viewport. Remove immediately for Reduce Motion, inactive scenes, or disappearing views. Set `isShimmerEnabled` to false on content covered by a sheet, without disabling the sheet's own placeholders. Once real images are connected, drive `shimmer(isActive:)` from loading state and stop on success or failure.
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
- The catalog starts empty and restores cached data when available. `CatalogSource` is the adapter boundary for a future file or API; no production catalog source is configured yet. Sample catalog records belong only in previews/tests. Authentication uses separate Keychain storage; account-specific catalog data and synchronization remain future layers outside the Core Data adapter.
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

## Authentication and profile

- Keep authentication infrastructure in `Authentication/{Model,Service,Storage,Preview}` and HTTP transport in `Networking`. `Application/AuthenticationSession.swift` coordinates app-wide observable state; `Modules/Login` owns form presentation. Infrastructure must not depend on screen modules or SwiftUI. The reusable mascot belongs to `Components/Moti`.
- `AppDependencies` owns one `AuthenticationSession`, injected through root composition and `DestinationFactory`. Guest profile taps present the router's authentication sheet; authenticated taps push the profile on Home's path. Successful login only dismisses the sheet and preserves the current screen; open the profile only on an explicit profile tap. Signing out returns Home to its root.
- Production injects `DefaultAuthenticationService`, an actor using `APIClient` and `KeychainSessionStore`, against `https://vezzi.vps.webdock.cloud/api/v1/`. Previews explicitly use `AuthenticationSession.preview()`; mocks never select the production backend. Requests follow `/openapi.json`: registration accepts 8–128 Unicode scalars, login 1–128. Never trim passwords or persist/log credentials or response bodies; validation errors may echo the input. Profile preferences remain temporary local values.
- Store tokens, expiry and the minimal user snapshot as one Keychain item with `WhenUnlockedThisDeviceOnly`. Restore independently of splash/cache preparation and revalidate on foregrounding. Retain cached users on ordinary offline/5xx failures. Report storage failures; do not pretend local logout succeeded when deletion fails.
- Reject cancelled or server-invalid sessions in memory before attempting Keychain cleanup. A UUID-only invalidation file prevents restoration across launches if deletion fails; never store credentials there. Retry cleanup on subsequent access. A successful new commit replaces the old record and cancels its pending cleanup; late discards must neither delete the new session nor invalidate a newer sign-in attempt's generation. `sessionCleanupFailed` clears the UI account, unlike an ordinary storage error.
- One shared refresh task owns rotation. Refresh tokens are single-use; persist a pending marker before sending and replace the pair atomically afterward. An interrupted exchange, ambiguous transport failure or malformed/5xx refresh response requires sign-in, never replay of the old token. Definite pre-connection failures and rate limits preserve the session. Keep a rotated pair in memory if persistence fails and retry storage before further requests. Future authorized requests must reuse this owner; `/users/me` currently retries one 401 after refresh. Fence stale replies across logout/account changes and revoke known abandoned grants best effort.
- Login animates validation messages, loading indicators, and the success confirmation; honor Reduce Motion. Disable both action buttons while busy; replace the active title with a spinner without changing its layout size. Its terms link scrolls below the buttons, hides on success, and intentionally has no destination yet. The authentication sheet uses a native zoom transition from Home's profile toolbar item; `AppRootView` owns the shared namespace, passed through `DestinationFactory` to `HomeView`, outside router state.
- `LoginViewModel` validates input and owns request state. The view's `.task(id:)` owns the attempt. Receive a provisional grant, check request identity/cancellation, then persist and publish the accepted session before showing success. Closing an unfinished attempt discards its grant; closing the success animation keeps the already committed account. Dismiss on `didComplete`, without pushing the profile. Passwords and pending requests are cleared on cancellation/completion. Native haptics follow success/error transitions; tapping outside fields clears focus.
- The login mascot uses `MotiFaceGeometry`, authored `MotiMotion` gestures, and Core Animation in `MotiAnimationView`. Morph from current presentation paths/opacity/transforms before replacing animations, so interruptions remain continuous. Preserve matching Bézier topology and loop endpoints. Stop on inactive scenes, Reduce Motion, and removal from the window. Original artwork lives in `Documentation/Design/Moti`; only the yarn image is bundled in Assets. The splash still uses Lottie.
- Profile's Debug section opens `MotiDebugView` through the shared router. It uses the same mascot as login, with local emotion selection, a no-motion toggle, and a cancellable rapid-transition sequence. The toggle can disable animation but cannot override system Reduce Motion. Debug controls do not change authentication state.

## UI, localization, and code style

- Use four-space indentation, Swift naming conventions, and the surrounding file's `// MARK:` structure.
- Keep SwiftUI `body` focused on composition. Extract meaningful nested sections into `private var ...: some View` or `private func ... -> some View` instead of building a deeply nested, monolithic view hierarchy.
- Reuse `.pressScaleEffect()` from `Extensions/PressScaleEffect.swift` for a button or a card containing a primary button. Let that button inherit the modifier's style and give secondary controls explicit styles. Feedback scales down immediately at touch-down, animates back on release or scrolling, and respects Reduce Motion. A passive UIKit touch observer bypasses delayed scroll-view highlighting without recognizing an action or preventing other gestures; do not delay the button's action for feedback.
- Extract layout and animation numeric literals into a private `enum Const` near the relevant view, with descriptive names and appropriate types such as `CGFloat`.
- Define palette colors in Assets and expose them through `ColorExtension` (`Color.Background`, `Color.Label`, `Color.Border`, `Color.Shadow`); use these helpers in views and previews instead of system palette colors or built-in color literals. `.accentColor` uses the existing accent asset; `Color.clear` is reserved for transparent surfaces. Keep one palette across supported iOS versions, with light/dark and increased-contrast variants where needed. Reuse image helpers such as `Image.Demo.main`; add shared assets to the existing asset catalog.
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
- Authentication tests use URLProtocol stubs for requests, cancellation, concurrent refresh, rotation recovery and storage failures. The actual Keychain round-trip test needs a signed app-hosted simulator run (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`); unsigned runs skip it only for `errSecMissingEntitlement`. Never use real accounts or print tokens in automated tests.
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
