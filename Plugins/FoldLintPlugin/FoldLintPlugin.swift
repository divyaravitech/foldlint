import Foundation
import PackagePlugin

/// `swift package foldlint [options]` — runs FoldLint on the current package.
///
/// If no existing path is passed, the package directory is linted. All other arguments
/// are forwarded to the `foldlint` CLI unchanged.
@main
struct FoldLintPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "foldlint")
        var arguments = arguments
        let passesPath = arguments.contains { FileManager.default.fileExists(atPath: $0) }
        if !passesPath {
            arguments.insert(context.package.directory.string, at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path.string)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        if process.terminationReason == .exit && process.terminationStatus == 0 {
            return
        }
        Diagnostics.error("foldlint exited with status \(process.terminationStatus)")
        throw FoldLintPluginError.failed(status: process.terminationStatus)
    }
}

enum FoldLintPluginError: Error, CustomStringConvertible {
    case failed(status: Int32)

    var description: String {
        switch self {
        case .failed(let status): return "foldlint exited with status \(status)"
        }
    }
}
