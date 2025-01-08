//
//  MFRController.swift
//  MFRFramework
//
//  Created by Maniganda Saravanan on 05/01/2025.
//

import AVFoundation
import Vision
import UIKit

public enum ExpressionType {
    case smile
    case blink
    case zoomIn
    case zoomOut
    case leftTurn
    case rightTurn
    case upTurn
    case downTurn
    case none
}

public enum LivenessDetectionResult {
    case success
    case failed
    case spoofingDetected
    case timeOut
    case none
}

public class MFRController: UIViewController, @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    private var sequenceRequestHandler = VNSequenceRequestHandler()
    private var previousFaceSize: CGFloat = 0.0
    private var currentFaceSize: CGFloat = 0.0
    
    private var captureSession: AVCaptureSession!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    private var selectedExpression = ExpressionType.leftTurn
    private var strokeLayer = CAShapeLayer()
    private var expressionLabel: UILabel!
    private var zoomDetectionTimer: Timer? // Timer for delayed detection
    private var mfrTimer: Timer?
    private var mfrTimerCount = 0
    private var isFaceDetected = false
    private var detectionTimeCount = 0
    private var currentDetection: ExpressionType?
    private var initializeCounter = 0
    
    // Public callbacks for various detections
    public var onLivenessDetection: ((LivenessDetectionResult) -> Void)?
    
    private var expressions = [ExpressionType.smile, ExpressionType.blink, ExpressionType.zoomIn, ExpressionType.zoomOut, ExpressionType.leftTurn, ExpressionType.rightTurn]
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        selectedExpression = expressions.randomElement() ?? .leftTurn
//        if selectedExpression == .zoomIn || selectedExpression == .zoomOut {
            startZoomDetectionTimer()
//        }
        startMFRTimer()
    }
    
    private func startMFRTimer() {
        mfrTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                self.mfrTimerCount += 1
                if self.mfrTimerCount >= 30 {
                    self.mfrTimer?.invalidate()
                    self.mfrTimerCount = 0
                    self.onLivenessDetection?(.timeOut)
                }
            }
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            print("Failed to set up camera.")
            return
        }
        captureSession.addInput(videoDeviceInput)

        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        guard captureSession.canAddOutput(videoDataOutput) else { return }
        captureSession.addOutput(videoDataOutput)

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

//        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
//        }
    }
    
    private func setupOverlay() {
        
        let width: CGFloat = view.frame.size.width
        let height: CGFloat = view.frame.size.height
        
        // Define the full screen path
        let path = UIBezierPath(rect: view.bounds)
        
        // Define the rounded rectangle in the center
        let rect = CGRect(x: width / 2 - 175, y: height / 2.5 - 200, width: 350, height: 600)
        let rectPath = UIBezierPath(roundedRect: rect, cornerRadius: 20)
        
        path.append(rectPath)
        path.usesEvenOddFillRule = true
        
        // Create the overlay layer for the dimmed background
        let overlayLayer = CAShapeLayer()
        overlayLayer.path = path.cgPath
        overlayLayer.fillRule = .evenOdd
        overlayLayer.fillColor = UIColor.black.cgColor
        overlayLayer.opacity = 0.5 // Adjust for transparency
        view.layer.addSublayer(overlayLayer)
        
        // Create a separate layer for the rectangle's stroke
        strokeLayer = CAShapeLayer()
        strokeLayer.path = rectPath.cgPath
        strokeLayer.strokeColor = isFaceDetected ? UIColor.green.cgColor : UIColor.red.cgColor // Stroke color for the rectangle
        strokeLayer.lineWidth = 3.0 // Adjust as needed
        strokeLayer.fillColor = UIColor.clear.cgColor // Ensure the inner rectangle remains transparent
        strokeLayer.cornerRadius = 20 // Add explicit corner radius (redundant if path is correct)
        view.layer.addSublayer(strokeLayer)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
    
    private func setupUI() {
        expressionLabel = UILabel()
        expressionLabel.translatesAutoresizingMaskIntoConstraints = false
        expressionLabel.text = ""
        expressionLabel.textColor = .white
        expressionLabel.font = .systemFont(ofSize: 18, weight: .bold)
        expressionLabel.textAlignment = .center
        expressionLabel.numberOfLines = 0
//        expressionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(expressionLabel)
        view.bringSubviewToFront(expressionLabel)
        
        NSLayoutConstraint.activate([
            expressionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expressionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            expressionLabel.widthAnchor.constraint(equalToConstant: 300),
            expressionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50) // Ensure space for multiple lines
        ])
    }
    
    private func updateExpressionLabel() {
        switch selectedExpression {
        case .smile:
            expressionLabel.text = "SMILE\nPlease Smile"
        case .blink:
            expressionLabel.text = "BLINK\nPerform Blink"
        case .zoomIn:
            expressionLabel.text = "ZOOM IN\nBring phone towards your face"
        case .zoomOut:
            expressionLabel.text = "ZOOM OUT\nPerform a zoom out from your phone"
        case .leftTurn:
            expressionLabel.text = "LEFT TURN\nPerform a left turn"
        case .rightTurn:
            expressionLabel.text = "RIGHT TURN\nPerform a right turn"
        case .upTurn:
            expressionLabel.text = "HEAD UP\nMove the head upwards"
        case .downTurn:
            expressionLabel.text = "HEAD DOWN\nMove the head downwards"
        case .none:
            break
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let observations = request.results as? [VNFaceObservation], let self = self else {
                return
            }
            
            DispatchQueue.main.async {
                if observations.count > 1 {
                    self.detectionTimeCount = 0
                    self.zoomDetectionTimer?.invalidate()
                    self.mfrTimer?.invalidate()
                    self.mfrTimerCount = 0
                    self.onLivenessDetection?(.spoofingDetected)
                    return
                } else {
                    if observations.first != nil {
                        self.isFaceDetected = true
                        for observation in observations {
                            switch self.selectedExpression {
                            case .smile:
                                self.detectSmile(in: observation)
                            case .blink:
                                self.detectBlink(in: observation)
                            case .zoomIn, .zoomOut:
                                self.detectFaceZoom(with: observation)
                            case .leftTurn, .rightTurn, .upTurn, .downTurn:
                                self.detectHeadTurns(in: observation)
                            case .none:
                                break
                            }
                        }
                    } else {
                        self.currentDetection = ExpressionType.none
                        self.isFaceDetected = false
                    }
                    self.updateOverlayBorder()
                }
            }
        }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try requestHandler.perform([request])
        } catch {
            print("Error performing face detection: \(error)")
        }
    }

    
    private func updateOverlayBorder() {
        if isFaceDetected {
            strokeLayer.strokeColor = isFaceDetected ? UIColor.green.cgColor : UIColor.red.cgColor // Stroke color for the rectangle
            updateExpressionLabel()
        } else {
            strokeLayer.strokeColor = UIColor.red.cgColor
            expressionLabel.text = "Keep your face inside the frame"
        }
    }
    
    //MARK: - BLINK DETECTION
    private func detectBlink(in faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else { return }
        
        let leftEAR = calculateEAR(for: leftEye)
        let rightEAR = calculateEAR(for: rightEye)
        
        let blinkThreshold: CGFloat = 0.2
        
        if leftEAR < blinkThreshold && rightEAR < blinkThreshold {
            currentDetection = .blink
//            DispatchQueue.main.async {
//                self.onLivenessDetection?()
//            }
        }
    }
    
    private func calculateEAR(for eye: VNFaceLandmarkRegion2D) -> CGFloat {
        guard eye.pointCount >= 6 else { return 1.0 } // Ensure we have enough points
        
        let points = eye.normalizedPoints
        let vertical1 = distanceBetween(points[1], points[5])
        let vertical2 = distanceBetween(points[2], points[4])
        let horizontal = distanceBetween(points[0], points[3])
        
        // EAR formula
        return (vertical1 + vertical2) / (2.0 * horizontal)
    }
    
    private func distanceBetween(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - SMILE DETECTION
    private func detectSmile(in faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks,
              let mouth = landmarks.outerLips else { return }
        let points = mouth.normalizedPoints

        // Left and right corners of the outer lips
        let leftCorner = points.first ?? CGPoint.zero
        let rightCorner = points.last ?? CGPoint.zero

        // Middle point of the outer lips (around the top of the curve)
        let middlePoint = points[points.count / 2]

        // Calculate the distance between the corners and middle of the mouth
//        let mouthWidth = leftCorner.x - rightCorner.x
        let mouthHeight = middlePoint.y - min(leftCorner.y, rightCorner.y)

        // A basic check if the mouth width is enough (indicating a wide mouth) and height is greater than a threshold
        let smileThreshold: CGFloat = 0.32 // Tune this threshold based on your requirements
        
        print(mouthHeight)
        // Smile detection: if the mouth is wide enough and the middle point is sufficiently lower than the corners
        if mouthHeight > smileThreshold {
            currentDetection = .smile
//            DispatchQueue.main.async {
//                self.onLivenessDetection?()
//            }
        } else {
            currentDetection = ExpressionType.none
        }
    }
    
    // MARK: - FACE ZOOM DETECTION
    private func detectFaceZoom(with faceObservation: VNFaceObservation) {
        // Get the size of the face bounding box
        let boundingBox = faceObservation.boundingBox
        let faceWidth = boundingBox.width
        let faceHeight = boundingBox.height
        currentFaceSize = faceWidth * faceHeight
    }
    
    private func startZoomDetectionTimer() {
        zoomDetectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.selectedExpression == .zoomIn || self?.selectedExpression == .zoomOut {
                    self?.detectZoom()
                }
                self?.initializeCamera()
                print("selectedExpression \(String(describing: self?.selectedExpression))")
                print("currentDetection \(String(describing: self?.currentDetection))")
                print("detectionTimeCount \(String(describing: self?.detectionTimeCount))")
                
                if self?.selectedExpression == self?.currentDetection {
                    if self?.selectedExpression == .blink {
                        DispatchQueue.main.async {
                            self?.detectionTimeCount = 0
                            self?.zoomDetectionTimer?.invalidate()
                            self?.mfrTimer?.invalidate()
                            self?.mfrTimerCount = 0
                            self?.onLivenessDetection?(.success)
                        }
                    } else {
                        self?.detectionTimeCount += 1
                        if self?.detectionTimeCount == 1 {
                            DispatchQueue.main.async {
                                self?.detectionTimeCount = 0
                                self?.zoomDetectionTimer?.invalidate()
                                self?.mfrTimer?.invalidate()
                                self?.mfrTimerCount = 0
                                self?.onLivenessDetection?(.success)
                            }
                        }
                    }
                } else {
                    self?.detectionTimeCount = 0
                }
            }
        }
    }
    
    private func initializeCamera() {
        initializeCounter += 1
        if initializeCounter == 2 {
            setupCamera()
            setupOverlay()
            setupUI()
            updateExpressionLabel()
        }
    }
    
    private func detectZoom() {
        guard previousFaceSize != 0 else {
            previousFaceSize = currentFaceSize
            return
        }
        if selectedExpression == .zoomIn {
            if currentFaceSize > previousFaceSize {
                currentDetection = .zoomIn
//                DispatchQueue.main.async {
//                    self.zoomDetectionTimer?.invalidate()
//                    self.onLivenessDetection?()
//                }
            } else {
                currentDetection = ExpressionType.none
            }
        } else if selectedExpression == .zoomOut {
            if currentFaceSize < previousFaceSize {
                currentDetection = .zoomOut
//                DispatchQueue.main.async {
//                    self.zoomDetectionTimer?.invalidate()
//                    self.onLivenessDetection?()
//                }
            } else {
                currentDetection = ExpressionType.none
            }
        } else {
            currentDetection = ExpressionType.none
        }
        print("CurretFaceSize \(currentFaceSize)")
        // Update the previous face size
        previousFaceSize = currentFaceSize
        print("PreviousFaceSize \(previousFaceSize)")
    }
    
    // MARK: - LEFT RIGHT TURN
    private func detectHeadTurns(in faceObservation: VNFaceObservation) {
        guard let landmarks = faceObservation.landmarks else { return }
        
        guard let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye, let nose = landmarks.nose else {
            return
        }
        
        // Find the center points of left and right eyes and nose
        let leftEyeCenter = CGPoint(
            x: leftEye.normalizedPoints.reduce(0) { $0 + $1.x } / CGFloat(leftEye.normalizedPoints.count),
            y: leftEye.normalizedPoints.reduce(0) { $0 + $1.y } / CGFloat(leftEye.normalizedPoints.count)
        )
        let rightEyeCenter = CGPoint(
            x: rightEye.normalizedPoints.reduce(0) { $0 + $1.x } / CGFloat(rightEye.normalizedPoints.count),
            y: rightEye.normalizedPoints.reduce(0) { $0 + $1.y } / CGFloat(rightEye.normalizedPoints.count)
        )

        let noseCenter = CGPoint(
            x: nose.normalizedPoints.reduce(0) { $0 + $1.x } / CGFloat(nose.normalizedPoints.count),
            y: nose.normalizedPoints.reduce(0) { $0 + $1.y } / CGFloat(nose.normalizedPoints.count)
        )
        
        // Detect head turn by calculating the angle between the nose and the midpoint of the eyes
        let eyeMidPoint = CGPoint(x: (leftEyeCenter.x + rightEyeCenter.x) / 2,
                                  y: (leftEyeCenter.y + rightEyeCenter.y) / 2)
        
        let dx = noseCenter.x - eyeMidPoint.x
        let dy = noseCenter.y - eyeMidPoint.y
        if self.selectedExpression == .leftTurn || self.selectedExpression == .rightTurn {
            let angle = atan2(dy, dx) * 180 / .pi
            // Determine turn direction based on the angle
            if angle < -10 {
                currentDetection = .rightTurn
                //            DispatchQueue.main.async {
                //                self.onLivenessDetection?()
                //            }
            } else if angle > 10 {
                currentDetection = .leftTurn
                //            DispatchQueue.main.async {
                //                self.onLivenessDetection?()
                //            }
            } else {
                currentDetection = ExpressionType.none
            }
        }
        
        if self.selectedExpression == .upTurn || self.selectedExpression == .downTurn {
            // Detect vertical tilt (up/down)
            let verticalDifference = noseCenter.y - eyeMidPoint.y
            print("verticalDifference \(verticalDifference)")
            if verticalDifference > 0.05 { // Adjust threshold as needed
                currentDetection = .downTurn
            } else if verticalDifference < -0.05 { // Adjust threshold as needed
                currentDetection = .upTurn
            } else {
                currentDetection = ExpressionType.none
            }
        }
    }
}
