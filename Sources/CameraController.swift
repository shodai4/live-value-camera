import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import QuartzCore
import UIKit

/// 背面カメラの映像を CIImage として配信する。
/// 画面側は最新の 1 枚だけを描画し、停止中はその 1 枚を保つ。
final class CameraController: NSObject, ObservableObject {
    enum Permission: Equatable {
        case checking
        case authorized
        case denied
        case unavailable
    }

    @Published private(set) var frame: CIImage?
    @Published private(set) var frameID: Int = 0
    @Published private(set) var permission: Permission = .checking
    @Published private(set) var isPreviewRunning = false

    /// 停止中は新しい映像を取り込まない（最後の 1 枚を保つ）。
    @Published private(set) var isPaused = false

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.shodai4.livevaluecamera.session")
    private let videoQueue = DispatchQueue(label: "com.shodai4.livevaluecamera.video",
                                           qos: .userInitiated)
    private let stateLock = NSLock()
    private var pausedFlag = false
    private var lastFrameTime: CFTimeInterval = 0
    private var isConfigured = false
    private var configurationFailed = false
    private let minimumFrameInterval: CFTimeInterval = 1.0 / 30.0

    // MARK: 起動

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
            configureAndRun()
        case .notDetermined:
            permission = .checking
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.permission = .authorized
                        self.configureAndRun()
                    } else {
                        self.permission = .denied
                    }
                }
            }
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            permission = .denied
        }
    }

    /// 設定アプリから戻ってきたときなど、権限の変化を拾い直す。
    func refreshPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            if permission != .authorized {
                permission = .authorized
            }
            configureAndRun()
        case .denied, .restricted:
            if permission != .denied {
                permission = .denied
            }
            stopSession()
        case .notDetermined:
            start()
        @unknown default:
            break
        }
    }

    // MARK: 停止と再開

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        stateLock.lock()
        pausedFlag = paused
        stateLock.unlock()
        isPaused = paused
        if paused {
            Haptics.shared.tick()
        }
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    /// 写真を保存できる状態か（停止中か、映像が届いていれば可）。
    var hasFrame: Bool { frame != nil }

    // MARK: セッション

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard !self.configurationFailed else { return }
                guard self.configureSession() else {
                    self.configurationFailed = true
                    DispatchQueue.main.async {
                        self.permission = .unavailable
                    }
                    return
                }
                self.isConfigured = true
            }
            self.startRunning()
        }
    }

    private func startRunning() {
        guard !session.isRunning else { return }
        session.startRunning()
        DispatchQueue.main.async {
            self.isPreviewRunning = self.session.isRunning
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isPreviewRunning = false
            }
        }
    }

    func suspend() {
        stopSession()
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return false }
            session.addInput(input)
        } catch {
            return false
        }

        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            // 縦持ちの画面に合わせて、映像をあらかじめ回して受け取る。
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }

        applyDefaultDeviceSettings(device)
        return true
    }

    private func applyDefaultDeviceSettings(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            // 設定できなくても撮影自体は続けられる。
        }
    }
}

// MARK: - フレームの受け取り

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        stateLock.lock()
        let paused = pausedFlag
        stateLock.unlock()
        guard !paused else { return }

        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= minimumFrameInterval else { return }
        lastFrameTime = now

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        DispatchQueue.main.async {
            self.frame = image
            self.frameID &+= 1
        }
    }
}

// MARK: - 触覚

final class Haptics {
    static let shared = Haptics()

    func tick() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}
