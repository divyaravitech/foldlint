import AVFoundation
import AVKit
import UIKit

/// Owns the capture session. All AVFoundation work happens on this actor.
actor CaptureService {
    private let session = AVCaptureSession()
    private var activeInput: AVCaptureDeviceInput?

    func selectCamera(with descriptor: AVCaptureDeviceDescriptor) throws {
        guard let device = AVCaptureDevice(uniqueID: descriptor.uniqueID) else { return }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let activeInput { session.removeInput(activeInput) }
        if session.canAddInput(input) {
            session.addInput(input)
            activeInput = input
        }
    }

    func applyMirroring(_ mirrored: Bool, to connection: AVCaptureConnection) {
        guard connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}

/// Watches which cameras face the user and hands the forward-facing one to the capture actor.
@MainActor
final class DirectionObserver {
    private let captureService: CaptureService
    private var coordinator: AVCaptureDeviceDirectionCoordinator?

    init(captureService: CaptureService) {
        self.captureService = captureService
    }

    func startObserving(previewView: UIView) {
        coordinator = AVCaptureDeviceDirectionCoordinator(
            view: previewView,
            deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera]
        ) { [weak self] directions in
            guard let self, let forward = directions.forwardFacingDeviceDescriptors.first else { return }
            Task { try await self.captureService.selectCamera(with: forward) }
        }
    }
}
