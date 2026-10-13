import Foundation
import SwiftSyntax

private func ref(_ id: String) -> String { "\(RuleRegistry.docsBase)#\(id)" }

// MARK: - uiscreen-main

/// `UIScreen.main` is deprecated (iOS 26) and ambiguous on a device with two displays.
public struct UIScreenMainRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "uiscreen-main",
        name: "UIScreen.main",
        severity: .warning,
        weight: 10,
        summary: "UIScreen.main is deprecated (iOS 26) and ambiguous on iPhone Duo, which has two displays.",
        fix: "Use the trait collection (traitCollection.displayScale, @Environment(\\.displayScale)), view or scene bounds, or view.window?.windowScene?.screen.",
        reference: ref("uiscreen-main")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(MemberAccessExprSyntax.self).compactMap { node in
            guard node.memberName == "main",
                  node.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "UIScreen" else { return nil }
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}

// MARK: - screen-bounds-layout

/// Sizing from a screen ignores Split View, side bars and the fold.
public struct ScreenBoundsLayoutRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "screen-bounds-layout",
        name: "Layout from screen bounds",
        severity: .warning,
        weight: 8,
        summary: "Sizing from screen bounds ignores Split View, vertical bars and the fold on iPhone Duo.",
        fix: "Size from the view, the scene, or GeometryReader, inset by the safe area.",
        reference: ref("screen-bounds-layout")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(MemberAccessExprSyntax.self).compactMap { node in
            guard ["bounds", "nativeBounds"].contains(node.memberName),
                  let base = node.normalizedBase else { return nil }
            // `UIScreen.main.bounds` is already reported by uiscreen-main.
            if base == "UIScreen.main" { return nil }
            let last = base.lastPathComponentOfMemberChain
            guard last == "screen" || last == "mainScreen" else { return nil }
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}

// MARK: - idiom-branching

/// iPhone Duo is `.phone` but has regular size classes on the inner display.
public struct IdiomBranchingRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "idiom-branching",
        name: "Branching on idiom",
        severity: .warning,
        weight: 8,
        summary: "iPhone Duo reports .phone even on its regular-width inner display, so idiom checks pick the wrong layout.",
        fix: "Branch on horizontalSizeClass (environment or traitCollection) instead of userInterfaceIdiom.",
        reference: ref("idiom-branching")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(MemberAccessExprSyntax.self).compactMap { node in
            guard node.memberName == "userInterfaceIdiom" else { return nil }
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}

// MARK: - orientation-branching

/// The inner display doesn't honor supported orientations, so orientation is a poor layout signal.
public struct OrientationBranchingRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "orientation-branching",
        name: "Layout from orientation",
        severity: .warning,
        weight: 6,
        summary: "Interface orientation doesn't tell you the available width on iPhone Duo; the inner display ignores supported orientations.",
        fix: "Use size classes or the view's bounds to choose a layout.",
        reference: ref("orientation-branching")
    )

    private static let alwaysFlag: Set<String> = [
        "interfaceOrientation",
        "statusBarOrientation",
        "orientationDidChangeNotification",
    ]

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(MemberAccessExprSyntax.self).compactMap { node in
            let name = node.memberName
            let flagged: Bool
            if Self.alwaysFlag.contains(name) {
                flagged = true
            } else if name == "orientation", let base = node.normalizedBase {
                flagged = base == "UIDevice.current" || base.hasSuffix(".UIDevice.current")
            } else {
                flagged = false
            }
            guard flagged else { return nil }
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}

// MARK: - orientation-lock

/// Orientation locks aren't honored on the inner display for resizable apps.
public struct OrientationLockRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "orientation-lock",
        name: "Orientation lock",
        severity: .info,
        weight: 2,
        summary: "The iPhone Duo inner display doesn't honor supported interface orientations for resizable apps, so the app is scaled there.",
        fix: "Make the layout work at any size instead of relying on an orientation lock.",
        reference: ref("orientation-lock")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        var findings: [Finding] = []
        for decl in file.nodes(VariableDeclSyntax.self) {
            let isOverride = decl.modifiers.contains { $0.name.text == "override" }
            guard isOverride else { continue }
            for binding in decl.bindings {
                if binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "supportedInterfaceOrientations" {
                    let loc = file.location(of: binding)
                    findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
                }
            }
        }
        for function in file.nodes(FunctionDeclSyntax.self) where function.name.text == "application" {
            let labels = function.signature.parameterClause.parameters.map { $0.firstName.text }
            if labels.contains("supportedInterfaceOrientationsFor") {
                let loc = file.location(of: function.name)
                findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
            }
        }
        return findings
    }
}

// MARK: - app-wide-window

/// App-wide window lookups are ambiguous with multiple scenes and displays.
public struct AppWideWindowRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "app-wide-window",
        name: "App-wide window lookup",
        severity: .warning,
        weight: 6,
        summary: "App-wide window and scene lookups can return the wrong window when iPhone Duo shows more than one scene.",
        fix: "Use view.window, view.window?.windowScene, or the scene passed to your scene delegate.",
        reference: ref("app-wide-window")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(MemberAccessExprSyntax.self).compactMap { node in
            guard let base = node.normalizedBase else { return nil }
            let name = node.memberName
            let flagged =
                (base.hasSuffix("UIApplication.shared") && (name == "keyWindow" || name == "windows"))
                || (base.hasSuffix("UIApplication.shared.connectedScenes") && name == "first")
            guard flagged else { return nil }
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}
