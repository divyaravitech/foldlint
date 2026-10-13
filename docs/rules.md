# FoldLint rules

Every rule cites the Apple source it's based on. If the SDK changes and a rule goes stale, please [open an issue](https://github.com/divyaravitech/foldlint/issues/new?template=false-positive.yml).

| Rule | Default | Weight | Checks |
| --- | --- | ---: | --- |
| [`uiscreen-main`](#uiscreen-main) | warning | 10 | `UIScreen.main` |
| [`screen-bounds-layout`](#screen-bounds-layout) | warning | 8 | `<…>.screen.bounds`, `nativeBounds` |
| [`idiom-branching`](#idiom-branching) | warning | 8 | `userInterfaceIdiom` |
| [`orientation-branching`](#orientation-branching) | warning | 6 | `interfaceOrientation`, `statusBarOrientation`, `UIDevice.current.orientation`, `orientationDidChangeNotification` |
| [`orientation-lock`](#orientation-lock) | info | 2 | `override var supportedInterfaceOrientations`, `application(_:supportedInterfaceOrientationsFor:)` |
| [`standalone-bar`](#standalone-bar) | warning | 6 | `UIToolbar()`, `UINavigationBar()`, `UITabBar()` and subclasses |
| [`text-only-bar-item`](#text-only-bar-item) | info | 3 | `UIBarButtonItem(title:…)` without an image; `Button("…")` in `.toolbar` without a symbol |
| [`arrangement-in-scroll`](#arrangement-in-scroll) | warning | 6 | `ArrangementView` inside `List`, `Form`, `ScrollView` or a lazy stack/grid |
| [`navigation-inside-arrangement`](#navigation-inside-arrangement) | warning | 6 | `NavigationStack`, `NavigationSplitView`, `TabView` (or UIKit equivalents) inside `ArrangementView` |
| [`app-wide-window`](#app-wide-window) | warning | 6 | `UIApplication.shared.keyWindow`, `.windows`, `.connectedScenes.first` |
| [`video-mirroring`](#video-mirroring) | error | 8 | `isVideoMirrored =` with no `automaticallyAdjustsVideoMirroring = false` in the same file |
| [`front-camera-assumption`](#front-camera-assumption) | warning | 5 | `position == .front`, `case .front` on a position |
| [`camera-discovery`](#camera-discovery) | error | 6 | `AVCaptureDevice.default(.builtInOuterUltraWideCamera / .builtInInnerUltraWideCamera, …)` |
| [`requires-full-screen`](#requires-full-screen) | info | 2 | `UIRequiresFullScreen = true` in an Info.plist |
| [`scene-lifecycle`](#scene-lifecycle) | error | 10 | An app delegate with no scene delegate, SwiftUI `App`, scene manifest or scene-configuration method |

You can change any rule's severity in `.foldlint.json`. Weights decide how much each rule counts toward the [readiness score](../README.md#the-readiness-score). Run `foldlint --list-rules --format json` for machine-readable metadata.

---

## uiscreen-main

`UIScreen.main` is **deprecated in iOS 26**. On a device with two displays it's also ambiguous, because there's no single "main" screen.

```swift
let scale = UIScreen.main.scale                  // ❌
let scale = traitCollection.displayScale         // ✅ (SwiftUI: @Environment(\.displayScale))
let screen = view.window?.windowScene?.screen    // ✅ only when you truly need a UIScreen
```

**Source:** [`UIScreen.main`](https://developer.apple.com/documentation/uikit/uiscreen/main) deprecation message: "Use a UIScreen instance found through context instead (i.e, view.window.windowScene.screen), or for properties like UIScreen.scale with trait equivalents, use a traitCollection found through context." See also [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/), *Avoid screen assumptions*.

## screen-bounds-layout

Your app can run in Split View, beside a vertical bar, or across the fold. Its size is almost never the screen's size. `UIScreen.main.bounds` is already reported by `uiscreen-main`, so this rule covers every other screen reference.

```swift
let width = view.window!.screen.bounds.width                     // ❌
let width = view.bounds.inset(by: view.safeAreaInsets).width     // ✅
```

**Source:** [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo): "Avoid fixed widths and display-specific dependencies."

## idiom-branching

iPhone Duo reports `.phone`, but its inner display has **regular** width and height size classes. An `if idiom == .pad` check never shows the iPad-style layout there.

```swift
if UIDevice.current.userInterfaceIdiom == .pad { … }             // ❌
if traitCollection.horizontalSizeClass == .regular { … }         // ✅
```

**Source:** [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/), *Use size classes* and *Avoid screen assumptions*.

## orientation-branching

The inner display doesn't honor supported interface orientations, so "landscape" no longer means "wide". Choose layouts by size class or by available size.

**Source:** [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/): use size classes rather than checking interface orientation for layout decisions.

## orientation-lock

An orientation lock still works on the outer display, which behaves like any other iPhone. On the inner display, and in Split View, your app is scaled instead. This rule is informational: check that your layout survives the scaling.

**Source:** [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

## standalone-bar

On iPhone Duo, toolbars, tab bars and navigation controls move to the side of the display. Bars managed by `UINavigationController` and `UITabBarController` (or SwiftUI's `NavigationStack`, `TabView` and `.toolbar`) take part. Standalone `UIToolbar`, `UINavigationBar` and `UITabBar` instances don't.

**Source:** [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/), *Adapt custom views*.

## text-only-bar-item

"Labels that include text stay in a horizontal bar, so prefer a symbol wherever one works." Give items a title **and** a symbol: the system uses the symbol in the vertical bar and the title in overflow menus.

```swift
Button("Share") { … }                                                // ❌ in a toolbar
Button("Share", systemImage: "square.and.arrow.up") { … }           // ✅
UIBarButtonItem(title: "Share", image: UIImage(systemName: "square.and.arrow.up"), primaryAction: share) // ✅
```

Exempt: Cancel/Done items (`.cancellationAction`, `.confirmationAction`, `.destructiveAction`) and items inside `Menu`, `ToolbarOverflowMenu`, pickers, alerts and sheets.

**Source:** [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), *Vertical controls*.

## arrangement-in-scroll

`ArrangementView` lays out a whole area around the fold. Don't embed it in a list or scroll view. Put the scrolling content *inside* its primary and secondary views instead.

**Source:** [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/), *When not to use an arrangement*.

## navigation-inside-arrangement

"An arrangement view lays out content but doesn't handle navigation, so place navigation containers like navigation split views and tab views around it rather than within it."

```swift
ArrangementView { NavigationStack { Feed() } } secondary: { Player() }   // ❌
NavigationStack { ArrangementView { Feed() } secondary: { Player() } }   // ✅
```

**Source:** [HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), *Arrangement views*.

## app-wide-window

With several scenes on the inner display, app-wide lookups return an arbitrary window. `UIApplication.keyWindow` (iOS 13) and `UIApplication.windows` (iOS 15) are also deprecated. Use `view.window`, `view.window?.windowScene`, or the scene that UIKit passes to your scene delegate.

## video-mirroring

"Set `automaticallyAdjustsVideoMirroring` to `false` before you assign `isVideoMirrored`, because assigning it while the connection adjusts mirroring on its own raises an exception." Assigning it also raises an exception when `isVideoMirroringSupported` is `false`. On iPhone Duo you override mirroring whenever a camera's position and direction disagree, so this crash path is much easier to hit.

```swift
guard connection.isVideoMirroringSupported else { return }
connection.automaticallyAdjustsVideoMirroring = false
connection.isVideoMirrored = isFacingForward
```

FoldLint accepts the guard anywhere in the same file.

**Source:** [Choosing a camera by the direction it faces](https://developer.apple.com/documentation/avkit/choosing-a-camera-by-the-direction-it-faces), *Update your interface for the new camera*.

## front-camera-assumption

"The `position` property describes where a camera sits in relation to the device's display." On iPhone Duo it no longer tells you which way the camera points: a front camera can face away from the user, and a rear camera can face them. Ask `AVCaptureDeviceDirectionCoordinator` (AVKit) instead, and decide mirroring and selfie UI from its `forwardFacingDeviceDescriptors`.

Discovering the front camera with `position: .front` is still correct. On iPhone Duo it returns the virtual front camera, so this rule flags only **comparisons** against `.front`.

**Source:** [Choosing a camera by the direction it faces](https://developer.apple.com/documentation/avkit/choosing-a-camera-by-the-direction-it-faces).

## camera-discovery

The individual inner and outer cameras "may only be discovered using an AVCaptureDeviceDiscoverySession", so `AVCaptureDevice.default(_:for:position:)` won't return them.

```swift
AVCaptureDevice.default(.builtInOuterUltraWideCamera, for: .video, position: .front)     // ❌ nil
AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera],
    mediaType: .video, position: .unspecified
).devices                                                                                // ✅
```

**Source:** [`builtInOuterUltraWideCamera`](https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtinouterultrawidecamera).

## requires-full-screen

"iPhone Duo will continue to honor the UIRequiresFullScreen key, but your app will still resize when someone opens or closes their iPhone Duo."

**Source:** [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

## scene-lifecycle

"In the next major release following iOS 26, UIScene lifecycle will be required when building with the latest SDK; otherwise, your app won't launch." Multiple windows on iPhone Duo also depend on scenes.

FoldLint reports a `UIApplicationDelegate` type when the project has none of these: a `UIWindowSceneDelegate`, a `@main struct …: App`, an `application(_:configurationForConnecting:options:)` implementation, or `UIApplicationSceneManifest` in an Info.plist.

> If your Info.plist is generated from build settings (`INFOPLIST_KEY_…`), FoldLint can't see it. Disable the rule (`"disabled_rules": ["scene-lifecycle"]`) if it reports a false positive.

**Source:** [TN3187: Migrating to the UIKit scene-based life cycle](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle).
