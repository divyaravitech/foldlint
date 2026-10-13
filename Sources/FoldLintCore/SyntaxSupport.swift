import Foundation
import SwiftParser
import SwiftSyntax

/// A parsed Swift source file.
public final class SwiftFile {
    public let path: String
    public let source: String
    public let tree: SourceFileSyntax
    let converter: SourceLocationConverter
    /// Every node in the tree, in source order, collected in a single walk.
    private lazy var allNodes: [Syntax] = {
        var result: [Syntax] = []
        let walker = AnyNodeWalker { result.append($0) }
        walker.walk(tree)
        return result
    }()
    private var cache: [ObjectIdentifier: [Any]] = [:]

    public init(path: String, source: String) {
        self.path = path
        self.source = source
        self.tree = Parser.parse(source: source)
        self.converter = SourceLocationConverter(fileName: path, tree: tree)
    }

    func location(of node: some SyntaxProtocol) -> (line: Int, column: Int) {
        let loc = node.startLocation(converter: converter)
        return (loc.line, loc.column)
    }

    /// All nodes of the given type in source order.
    ///
    /// The tree is walked once per file; each node type is then filtered from that list
    /// once and cached, so rules can query freely. A `SwiftFile` is not thread-safe: the
    /// linter gives each file to a single thread.
    func nodes<T: SyntaxProtocol>(_ type: T.Type) -> [T] {
        let key = ObjectIdentifier(type)
        if let cached = cache[key] as? [T] {
            return cached
        }
        let result = allNodes.compactMap { $0.as(T.self) }
        cache[key] = result
        return result
    }
}

final class AnyNodeWalker: SyntaxAnyVisitor {
    private let body: (Syntax) -> Void

    init(_ body: @escaping (Syntax) -> Void) {
        self.body = body
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        body(node)
        return .visitChildren
    }
}

extension SyntaxProtocol {
    /// Ancestors from nearest to farthest. When `stopAtDeclaration` is true, the walk
    /// stops at the first enclosing declaration (`var body`, a `func`, a type, ...).
    func ancestors(stopAtDeclaration: Bool = true) -> [Syntax] {
        var result: [Syntax] = []
        var current = parent
        while let node = current {
            if stopAtDeclaration, node.is(DeclSyntax.self) {
                break
            }
            result.append(node)
            current = node.parent
        }
        return result
    }

    /// Enclosing function calls, nearest first, within the current declaration.
    func enclosingCalls() -> [FunctionCallExprSyntax] {
        ancestors().compactMap { $0.as(FunctionCallExprSyntax.self) }
    }
}

extension FunctionCallExprSyntax {
    /// The simple name being called: `List`, `toolbar`, `UIToolbar`, `ArrangementView`, ...
    var calleeName: String? {
        Self.name(of: calledExpression)
    }

    private static func name(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            // `UIToolbar.init(...)` should report `UIToolbar`.
            if member.declName.baseName.text == "init", let base = member.base {
                return name(of: base)
            }
            return member.declName.baseName.text
        }
        if let generic = expr.as(GenericSpecializationExprSyntax.self) {
            return name(of: generic.expression)
        }
        return nil
    }

    func hasArgument(label: String) -> Bool {
        arguments.contains { $0.label?.text == label }
    }

    /// True if the call has a closure argument (trailing or labelled).
    var hasClosure: Bool {
        trailingClosure != nil || arguments.contains { $0.expression.is(ClosureExprSyntax.self) }
    }
}

extension MemberAccessExprSyntax {
    var memberName: String { declName.baseName.text }

    /// Base expression text with optional-chaining and force-unwrap marks removed,
    /// e.g. `view.window?.windowScene?.screen` becomes `view.window.windowScene.screen`.
    var normalizedBase: String? {
        guard let base else { return nil }
        return base.trimmedDescription
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .filter { !$0.isWhitespace }
    }
}

extension String {
    var lastPathComponentOfMemberChain: Substring {
        split(separator: ".").last ?? Substring(self)
    }
}
