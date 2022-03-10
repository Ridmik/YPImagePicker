//
//  YPPhotoCaptureHelper.swift
//  YPImagePicker
//
//  Created by Sacha DSO on 08/03/2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation

internal final class YPPhotoCaptureHelper: NSObject {
    var currentFlashMode: YPFlashMode {
        return YPFlashMode(torchMode: device?.torchMode)
    }
    var device: AVCaptureDevice? {
        return deviceInput?.device
    }
    var hasFlash: Bool {
        let isFrontCamera = device?.position == .front
        let deviceHasFlash = device?.hasFlash ?? false
        return !isFrontCamera && deviceHasFlash
    }
    
    private let sessionQueue = DispatchQueue(label: "YPPhotoCaptureHelperQueue", qos: .background)
    private let session = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private var isCaptureSessionSetup: Bool = false
    private var isPreviewSetup: Bool = false
    private var previewView: UIView!
    private var videoLayer: AVCaptureVideoPreviewLayer!
    private var block: ((Data) -> Void)?
    private var initVideoZoomFactor: CGFloat = 1.0
}

// MARK: - Public

extension YPPhotoCaptureHelper {
    func shoot(completion: @escaping (Data) -> Void) {
        guard let device = device, device.isConnected else { return }
        
        block = completion
        
        // Set current device orientation
        setCurrentOrienation()
        
        let settings = photoCaptureSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func start(with previewView: UIView, completion: @escaping () -> Void) {
        self.previewView = previewView
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isCaptureSessionSetup {
                self.setupCaptureSession()
            }
            self.startCamera {
                completion()
            }
        }
    }
    
    func stopCamera() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }
    
    func zoom(began: Bool, scale: CGFloat) {
        guard let device = device else {
            return
        }
        
        if began {
            initVideoZoomFactor = device.videoZoomFactor
            return
        }
        
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            var minAvailableVideoZoomFactor: CGFloat = 1.0
            if #available(iOS 11.0, *) {
                minAvailableVideoZoomFactor = device.minAvailableVideoZoomFactor
            }
            var maxAvailableVideoZoomFactor: CGFloat = device.activeFormat.videoMaxZoomFactor
            if #available(iOS 11.0, *) {
                maxAvailableVideoZoomFactor = device.maxAvailableVideoZoomFactor
            }
            maxAvailableVideoZoomFactor = min(maxAvailableVideoZoomFactor, YPConfig.maxCameraZoomFactor)
            
            let desiredZoomFactor = initVideoZoomFactor * scale
            device.videoZoomFactor = max(minAvailableVideoZoomFactor,
                                         min(desiredZoomFactor, maxAvailableVideoZoomFactor))
        } catch let error {
            ypLog("Error: \(error)")
        }
    }
    
    func flipCamera(completion: @escaping () -> Void) {
        sessionQueue.async { [weak self] in
            self?.flip()
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func focus(on point: CGPoint) {
        guard let device = device else {
            return
        }
        
        setFocusPointOnDevice(device: device, point: point)
    }
}

extension YPPhotoCaptureHelper: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        block?(data)
    }
}

// MARK: - Private
private extension YPPhotoCaptureHelper {
    
    // MARK: Setup
    
    private func photoCaptureSettings() -> AVCapturePhotoSettings {
        var settings = AVCapturePhotoSettings()
        
        // Catpure Heif when available.
        if #available(iOS 11.0, *) {
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
        }
        
        // Set flash mode.
        if let deviceInput = deviceInput {
            if deviceInput.device.position == .back {
                // Catpure Highest Quality possible.
                settings.isHighResolutionPhotoEnabled = true
            }
            if deviceInput.device.isFlashAvailable {
                let supportedFlashModes = photoOutput.__supportedFlashModes
                switch currentFlashMode {
                case .auto:
                    if supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.auto.rawValue)) {
                        settings.flashMode = .auto
                    }
                case .off:
                    if supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.off.rawValue)) {
                        settings.flashMode = .off
                    }
                case .on:
                    if supportedFlashModes.contains(NSNumber(value: AVCaptureDevice.FlashMode.on.rawValue)) {
                        settings.flashMode = .on
                    }
                }
            }
        }
        
        return settings
    }
    
    private func setupCaptureSessionInputOutput() {
        guard let videoInput = deviceInput else { return }
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            if videoInput.device.position == .back {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            // Improve capture time by preparing output with the desired settings.
            photoOutput.setPreparedPhotoSettingsArray([photoCaptureSettings()], completionHandler: nil)
        }
    }
    
    private func setupCaptureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        let cameraPosition: AVCaptureDevice.Position = YPConfig.usesFrontCamera ? .front : .back
        let aDevice = AVCaptureDevice.deviceForPosition(cameraPosition)
        if let d = aDevice {
            deviceInput = try? AVCaptureDeviceInput(device: d)
        }
        setupCaptureSessionInputOutput()
        session.commitConfiguration()
        isCaptureSessionSetup = true
    }
    
    private func tryToSetupPreview() {
        if !isPreviewSetup {
            setupPreview()
            isPreviewSetup = true
        }
    }
    
    private func setupPreview() {
        videoLayer = AVCaptureVideoPreviewLayer(session: session)
        DispatchQueue.main.async {
            self.videoLayer.frame = self.previewView.bounds
            self.videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            self.previewView.layer.addSublayer(self.videoLayer)
        }
    }
    
    // MARK: Other
    
    private func startCamera(completion: @escaping (() -> Void)) {
        if !session.isRunning {
            sessionQueue.async { [weak self] in
                // Re-apply session preset
                self?.session.sessionPreset = .photo
                let status = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
                switch status {
                case .notDetermined, .restricted, .denied:
                    self?.session.stopRunning()
                case .authorized:
                    self?.session.startRunning()
                    completion()
                    self?.tryToSetupPreview()
                @unknown default:
                    ypLog("unknown default reached. Check code.")
                }
            }
        }
    }
    
    private func flip() {
        session.beginConfiguration()
        session.resetInputs()
        deviceInput = flippedDeviceInputForInput(deviceInput)
        setupCaptureSessionInputOutput()
        session.commitConfiguration()
    }
    
    private func setCurrentOrienation() {
        let connection = photoOutput.connection(with: .video)
        let orientation = YPDeviceOrientationHelper.shared.currentDeviceOrientation
        switch orientation {
        case .portrait:
            connection?.videoOrientation = .portrait
        case .portraitUpsideDown:
            connection?.videoOrientation = .portraitUpsideDown
        case .landscapeRight:
            connection?.videoOrientation = .landscapeLeft
        case .landscapeLeft:
            connection?.videoOrientation = .landscapeRight
        default:
            connection?.videoOrientation = .portrait
        }
    }
}
