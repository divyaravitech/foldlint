import Foundation
import SwiftSyntax

private func ref(_ id: String) -> String { "\(RuleRegistry.docsBase)#\(id)" }

// MARK: - requires-full-screen

/// `UIRequiresFullScreen` doesn't stop resizing on iPhone Duo.
public struct RequiresFullScreenRule: PlistRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "requires-full-screen",
        name: "UIRequiresFullScreen",
        severity: .info,
        weight: 2,
        summary: "UIRequiresFullScreen is still honored, but the app still resizes when iPhone Duo opens or closes.",
        fix: "Make sure every screen handles a live size change; don't rely on full screen meaning a fixed size.",
        reference: ref("requires-full-screen")
    )

    public func check(path: String, plist: [String: Any]) -> [Finding] {
        guard (plist["UIRequiresFullScreen"] as? Bool) == true else { return [] }
        return [descriptor.finding(file: path, line: 1, column: 1)]
    }
}

// MARK: - scene-lifecycle

/// Apps built with the iOS 27 SDK are expected to adopt the UIScene lifecycle.
public struct SceneLifecycleRule: ProjectRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "scene-lifecycle",
        name: "Missing UIScene lifecycle",
        severity: .error,
        weight: 10,
        summary: "This app hasn't adopted the UIScene lifecycle. Per TN3187, apps built with the SDK after iOS 26 won't launch without it, and iPhone Duo's multiple windows depend on it.",
        fix: "Add a UIWindowSceneDelegate plus a UIApplicationSceneManifest (or implement application(_:configurationForConnecting:options:)), or use the SwiftUI App lifecycle.",
        reference: ref("scene-lifecycle")
    )

    public func check(_ facts: ProjectFacts) -> [Finding] {
        guard let appDelegate = facts.appDelegates.first,
              facts.sceneDelegates.isEmpty,
              facts.swiftUIApps.isEmpty,
              facts.sceneConfigurationProviders.isEmpty,
              !facts.plistDeclaresSceneManifest else { return [] }
        return [descriptor.finding(file: appDelegate.file, line: appDelegate.line, column: appDelegate.column)]
    }
}

// MARK: - Fact collection

enum FactCollector {
    static func collect(from file: SwiftFile, into facts: inout ProjectFacts) {
        func inherited(_ clause: InheritanceClauseSyntax?) -> [String] {
            clause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        }
        func record<Node: SyntaxProtocol>(_ types: [String], at node: Node, isMainApp: Bool) {
            let loc = file.location(of: node)
            let location = ProjectFacts.Location(file: file.path, line: loc.line, column: loc.column)
            if types.contains(where: { $0.hasSuffix("UIApplicationDelegate") }) {
                facts.appDelegates.append(location)
            }
            if types.contains(where: { $0.hasSuffix("UIWindowSceneDelegate") }) {
                facts.sceneDelegates.append(location)
            }
            if isMainApp, types.contains(where: { $0 == "App" || $0 == "SwiftUI.App" }) {
                facts.swiftUIApps.append(location)
            }
        }
        func hasMainAttribute(_ attributes: AttributeListSyntax) -> Bool {
            attributes.contains { element in
                if case .attribute(let attribute) = element {
                    return attribute.attributeName.trimmedDescription == "main"
                }
                return false
            }
        }

        for decl in file.nodes(ClassDeclSyntax.self) {
            record(inherited(decl.inheritanceClause), at: decl.name, isMainApp: false)
        }
        for decl in file.nodes(StructDeclSyntax.self) {
            record(inherited(decl.inheritanceClause), at: decl.name, isMainApp: hasMainAttribute(decl.attributes))
        }
        for decl in file.nodes(ExtensionDeclSyntax.self) {
            record(inherited(decl.inheritanceClause), at: decl.extendedType, isMainApp: false)
        }
        for function in file.nodes(FunctionDeclSyntax.self) where function.name.text == "application" {
            let labels = function.signature.parameterClause.parameters.map { $0.firstName.text }
            if labels.contains("configurationForConnecting") {
                let loc = file.location(of: function.name)
                facts.sceneConfigurationProviders.append(
                    ProjectFacts.Location(file: file.path, line: loc.line, column: loc.column)
                )
            }
        }
    }
}
