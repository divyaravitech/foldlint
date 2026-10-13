import Foundation
import SwiftSyntax

private func ref(_ id: String) -> String { "\(RuleRegistry.docsBase)#\(id)" }

// MARK: - standalone-bar

/// Bars you create yourself don't move to the vertical axis on iPhone Duo.
public struct StandaloneBarRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "standalone-bar",
        name: "Standalone bar",
        severity: .warning,
        weight: 6,
        summary: "Standalone UIToolbar/UINavigationBar/UITabBar instances don't adopt iPhone Duo's vertical bar layout.",
        fix: "Use bars managed by UINavigationController/UITabBarController (or NavigationStack/TabView and .toolbar).",
        reference: ref("standalone-bar")
    )

    static let barTypes: Set<String> = ["UIToolbar", "UINavigationBar", "UITabBar"]

    public func check(_ file: SwiftFile) -> [Finding] {
        var findings: [Finding] = []
        for call in file.nodes(FunctionCallExprSyntax.self) {
            guard let name = call.calleeName, Self.barTypes.contains(name) else { continue }
            let loc = file.location(of: call)
            findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
        }
        for decl in file.nodes(ClassDeclSyntax.self) {
            let inherited = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            if let bar = inherited.first(where: { Self.barTypes.contains($0) }) {
                let loc = file.location(of: decl.name)
                findings.append(descriptor.finding(
                    file: file.path, line: loc.line, column: loc.column,
                    message: "Subclassing \(bar) creates a standalone bar that won't adopt iPhone Duo's vertical bar layout."
                ))
            }
        }
        return findings
    }
}

// MARK: - text-only-bar-item

/// Text-only toolbar items stay horizontal and can't be shown as symbols.
public struct TextOnlyBarItemRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "text-only-bar-item",
        name: "Text-only bar item",
        severity: .info,
        weight: 3,
        summary: "Text-only toolbar items stay horizontal on iPhone Duo; give the item a symbol as well as a title.",
        fix: "Use Button(\"Title\", systemImage: \"symbol\") / Label, or UIBarButtonItem(title:image:...).",
        reference: ref("text-only-bar-item")
    )

    private static let toolbarContainers: Set<String> = ["toolbar", "ToolbarItem", "ToolbarItemGroup"]
    private static let menuLikeContainers: Set<String> = [
        "Menu", "ControlGroup", "Picker", "ToolbarOverflowMenu", "toolbarOverflowMenu",
        "contextMenu", "confirmationDialog", "alert", "sheet", "popover", "fullScreenCover",
    ]
    /// Placements where a text button is the platform convention (Cancel, Done).
    private static let textPlacements = [".cancellationAction", ".confirmationAction", ".destructiveAction"]

    public func check(_ file: SwiftFile) -> [Finding] {
        var findings: [Finding] = []
        for call in file.nodes(FunctionCallExprSyntax.self) {
            switch call.calleeName ?? "" {
            case "UIBarButtonItem":
                if call.hasArgument(label: "title") && !call.hasArgument(label: "image") {
                    let loc = file.location(of: call)
                    findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
                }
            case "Button":
                guard isTextOnlyButton(call), isInToolbar(call) else { continue }
                let loc = file.location(of: call)
                findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
            default:
                continue
            }
        }
        return findings
    }

    private func isTextOnlyButton(_ call: FunctionCallExprSyntax) -> Bool {
        guard let first = call.arguments.first, first.label == nil,
              first.expression.is(StringLiteralExprSyntax.self) else { return false }
        return !call.hasArgument(label: "systemImage") && !call.hasArgument(label: "image")
    }

    private func isInToolbar(_ call: FunctionCallExprSyntax) -> Bool {
        for enclosing in call.enclosingCalls() {
            guard let name = enclosing.calleeName else { continue }
            // Text items inside menus, pickers, alerts and sheets are fine.
            if Self.menuLikeContainers.contains(name) {
                return false
            }
            guard Self.toolbarContainers.contains(name) else { continue }
            if name == "ToolbarItem" || name == "ToolbarItemGroup" {
                let args = enclosing.arguments.trimmedDescription
                if Self.textPlacements.contains(where: { args.contains($0) }) {
                    return false
                }
            }
            return true
        }
        return false
    }
}

// MARK: - arrangement-in-scroll

/// Apple advises against embedding arrangement views in lists or scroll views.
public struct ArrangementInScrollRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "arrangement-in-scroll",
        name: "ArrangementView in a scroll container",
        severity: .warning,
        weight: 6,
        summary: "ArrangementView is a layout container for the whole area and shouldn't be embedded in a List, Form or ScrollView.",
        fix: "Make the ArrangementView the outer layout and put scrolling content inside its primary/secondary views.",
        reference: ref("arrangement-in-scroll")
    )

    private static let scrollContainers: Set<String> = [
        "List", "ScrollView", "Form", "LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid",
    ]

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(FunctionCallExprSyntax.self).compactMap { call in
            guard call.calleeName == "ArrangementView" else { return nil }
            guard let container = call.enclosingCalls().first(where: {
                $0.hasClosure && Self.scrollContainers.contains($0.calleeName ?? "")
            }) else { return nil }
            let loc = file.location(of: call)
            return descriptor.finding(
                file: file.path, line: loc.line, column: loc.column,
                message: "ArrangementView inside \(container.calleeName ?? "a scroll container"): arrangements lay out a whole area and shouldn't be embedded in lists or scroll views."
            )
        }
    }
}

// MARK: - navigation-inside-arrangement

/// Navigation containers belong around an arrangement view, not inside it.
public struct NavigationInsideArrangementRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "navigation-inside-arrangement",
        name: "Navigation inside ArrangementView",
        severity: .warning,
        weight: 6,
        summary: "ArrangementView lays out content but doesn't handle navigation; keep navigation containers outside it.",
        fix: "Wrap the ArrangementView in NavigationStack/NavigationSplitView/TabView instead of nesting them inside.",
        reference: ref("navigation-inside-arrangement")
    )

    private static let navigationContainers: Set<String> = [
        "NavigationStack", "NavigationView", "NavigationSplitView", "TabView",
        "UINavigationController", "UITabBarController", "UISplitViewController",
    ]

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(FunctionCallExprSyntax.self).compactMap { call in
            guard let name = call.calleeName, Self.navigationContainers.contains(name) else { return nil }
            guard call.enclosingCalls().contains(where: { $0.calleeName == "ArrangementView" }) else { return nil }
            let loc = file.location(of: call)
            return descriptor.finding(
                file: file.path, line: loc.line, column: loc.column,
                message: "\(name) inside ArrangementView: arrangements don't handle navigation, so keep navigation containers outside them."
            )
        }
    }
}
