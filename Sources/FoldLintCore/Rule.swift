import Foundation

/// A rule that inspects one Swift file.
public protocol SwiftRule {
    var descriptor: RuleDescriptor { get }
    func check(_ file: SwiftFile) -> [Finding]
}

/// A rule that inspects one Info.plist.
public protocol PlistRule {
    var descriptor: RuleDescriptor { get }
    func check(path: String, plist: [String: Any]) -> [Finding]
}

/// A rule that needs information about the whole project.
public protocol ProjectRule {
    var descriptor: RuleDescriptor { get }
    func check(_ facts: ProjectFacts) -> [Finding]
}

/// Project-wide facts gathered while scanning.
public struct ProjectFacts {
    public struct Location: Hashable {
        public let file: String
        public let line: Int
        public let column: Int
    }

    /// Types that conform to `UIApplicationDelegate`.
    public var appDelegates: [Location] = []
    /// Types that conform to `UIWindowSceneDelegate`.
    public var sceneDelegates: [Location] = []
    /// `@main struct X: App` declarations (SwiftUI lifecycle).
    public var swiftUIApps: [Location] = []
    /// `application(_:configurationForConnecting:options:)` implementations, which
    /// TN3187 accepts as an alternative to a scene manifest.
    public var sceneConfigurationProviders: [Location] = []
    /// True if any Info.plist declares `UIApplicationSceneManifest`.
    public var plistDeclaresSceneManifest = false

    public init() {}

    mutating func merge(_ other: ProjectFacts) {
        appDelegates += other.appDelegates
        sceneDelegates += other.sceneDelegates
        swiftUIApps += other.swiftUIApps
        sceneConfigurationProviders += other.sceneConfigurationProviders
        plistDeclaresSceneManifest = plistDeclaresSceneManifest || other.plistDeclaresSceneManifest
    }
}

/// The built-in rules, in documentation order.
public enum RuleRegistry {
    public static let swiftRules: [SwiftRule] = [
        UIScreenMainRule(),
        ScreenBoundsLayoutRule(),
        IdiomBranchingRule(),
        OrientationBranchingRule(),
        OrientationLockRule(),
        StandaloneBarRule(),
        TextOnlyBarItemRule(),
        ArrangementInScrollRule(),
        NavigationInsideArrangementRule(),
        AppWideWindowRule(),
        VideoMirroringRule(),
        FrontCameraAssumptionRule(),
        CameraDiscoveryRule(),
    ]

    public static let plistRules: [PlistRule] = [
        RequiresFullScreenRule(),
    ]

    public static let projectRules: [ProjectRule] = [
        SceneLifecycleRule(),
    ]

    public static var all: [RuleDescriptor] {
        swiftRules.map(\.descriptor) + plistRules.map(\.descriptor) + projectRules.map(\.descriptor)
    }

    static let docsBase = "https://github.com/divyaravitech/foldlint/blob/main/docs/rules.md"
}
