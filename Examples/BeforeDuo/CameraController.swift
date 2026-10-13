import AVFoundation

final class CameraController {
    let session = AVCaptureSession()

    func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInOuterUltraWideCamera, for: .video, position: .front) else { return }
        session.addInput(try AVCaptureDeviceInput(device: camera))
        let output = AVCaptureVideoDataOutput()
        session.addOutput(output)
        if camera.position == .front {
            output.connection(with: .video)?.isVideoMirrored = true
        }
    }
}
