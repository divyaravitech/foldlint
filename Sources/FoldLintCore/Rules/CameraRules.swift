import Foundation
import SwiftSyntax

private func ref(_ id: String) -> String { "\(RuleRegistry.docsBase)#\(id)" }

/// The elements of an unfolded `SequenceExprSyntax` (`a = b`, `a == b`).
private func elements(of sequence: SequenceExprSyntax) -> [ExprSyntax] {
    Array(sequence.elements)
}

// MARK: - video-mirroring

/// Assigning `isVideoMirrored` raises an exception while `automaticallyAdjustsVideoMirroring` is true.
///
/// Source: Apple, "Choosing a camera by the direction it faces" — "Set automaticallyAdjustsVideoMirroring
/// to false before you assign isVideoMirrored, because assigning it while the connection adjusts
/// mirroring on its own raises an exception."
public struct VideoMirroringRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "video-mirroring",
        name: "Unsafe video mirroring",
        severity: .error,
        weight: 8,
        summary: "Assigning isVideoMirrored raises an exception while automaticallyAdjustsVideoMirroring is true. On iPhone Duo, apps override mirroring whenever a camera's position and direction disagree.",
        fix: "Check connection.isVideoMirroringSupported, set automaticallyAdjustsVideoMirroring = false, then assign isVideoMirrored.",
        reference: ref("video-mirroring")
    )

    public func check(_ file: SwiftFile) -> [Finding] {
        var assignments: [ExprSyntax] = []
        var disablesAutomatic = false
        for sequence in file.nodes(SequenceExprSyntax.self) {
            let parts = elements(of: sequence)
            guard parts.count >= 3 else { continue }
            for index in 0..<(parts.count - 2) where parts[index + 1].is(AssignmentExprSyntax.self) {
                let lhs = parts[index].trimmedDescription
                let rhs = parts[index + 2].trimmedDescription
                if lhs.hasSuffix("isVideoMirrored") {
                    assignments.append(parts[index])
                } else if lhs.hasSuffix("automaticallyAdjustsVideoMirroring"), rhs == "false" {
                    disablesAutomatic = true
                }
            }
        }
        guard !disablesAutomatic else { return [] }
        return assignments.map { node in
            let loc = file.location(of: node)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}

// MARK: - front-camera-assumption

/// `AVCaptureDevice.position` says where a camera sits, not which way it faces.
///
/// Discovering the front camera with `position: .front` is still correct (it returns the
/// virtual front camera on iPhone Duo), so this rule only flags *comparisons* against
/// `.front`, which apps use to decide "is this a selfie camera?" (mirroring, UI, filters).
public struct FrontCameraAssumptionRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "front-camera-assumption",
        name: "Camera direction from position",
        severity: .warning,
        weight: 5,
        summary: "position == .front says where a camera sits, not which way it faces. On iPhone Duo a front camera can face away from the user, and a rear camera can face them.",
        fix: "Ask AVCaptureDeviceDirectionCoordinator (AVKit) which cameras face forward, and decide mirroring and selfie UI from its direction map.",
        reference: ref("front-camera-assumption")
    )

    private static func isFront(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        return compact == ".front" || compact.hasSuffix("Position.front")
    }

    private static func isPosition(_ text: String) -> Bool {
        text.filter { !$0.isWhitespace }.hasSuffix("position")
    }

    public func check(_ file: SwiftFile) -> [Finding] {
        var findings: [Finding] = []
        for sequence in file.nodes(SequenceExprSyntax.self) {
            let parts = elements(of: sequence)
            guard parts.count >= 3 else { continue }
            for index in 1..<(parts.count - 1) {
                let op = parts[index].trimmedDescription
                guard op == "==" || op == "!=" else { continue }
                let lhs = parts[index - 1].trimmedDescription
                let rhs = parts[index + 1].trimmedDescription
                if (Self.isPosition(lhs) && Self.isFront(rhs)) || (Self.isPosition(rhs) && Self.isFront(lhs)) {
                    let loc = file.location(of: parts[index - 1])
                    findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
                }
            }
        }
        // `switch device.position { case .front: … }`
        for caseItem in file.nodes(SwitchCaseItemSyntax.self) where Self.isFront(caseItem.pattern.trimmedDescription) {
            let enclosingSwitch = caseItem.ancestors().lazy.compactMap { $0.as(SwitchExprSyntax.self) }.first
            guard let enclosingSwitch, Self.isPosition(enclosingSwitch.subject.trimmedDescription) else { continue }
            let loc = file.location(of: caseItem)
            findings.append(descriptor.finding(file: file.path, line: loc.line, column: loc.column))
        }
        return findings
    }
}

// MARK: - camera-discovery

/// The individual iPhone Duo front cameras are only discoverable through a discovery session.
///
/// Source: `AVCaptureDevice.DeviceType.builtInOuterUltraWideCamera` — "devices of this type may
/// only be discovered using an AVCaptureDeviceDiscoverySession."
public struct CameraDiscoveryRule: SwiftRule {
    public init() {}
    public let descriptor = RuleDescriptor(
        id: "camera-discovery",
        name: "Duo camera via default(_:for:position:)",
        severity: .error,
        weight: 6,
        summary: "The inner and outer ultra wide cameras can only be discovered with AVCaptureDevice.DiscoverySession; AVCaptureDevice.default(_:for:position:) won't return them.",
        fix: "Use AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera], mediaType: .video, position: .unspecified).",
        reference: ref("camera-discovery")
    )

    private static let duoDeviceTypes = ["builtInOuterUltraWideCamera", "builtInInnerUltraWideCamera"]

    public func check(_ file: SwiftFile) -> [Finding] {
        file.nodes(FunctionCallExprSyntax.self).compactMap { call in
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.memberName == "default",
                  member.normalizedBase?.hasSuffix("AVCaptureDevice") == true,
                  let first = call.arguments.first,
                  Self.duoDeviceTypes.contains(where: { first.expression.trimmedDescription.hasSuffix($0) })
            else { return nil }
            let loc = file.location(of: call)
            return descriptor.finding(file: file.path, line: loc.line, column: loc.column)
        }
    }
}
