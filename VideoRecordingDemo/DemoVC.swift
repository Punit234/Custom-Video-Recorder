//
//  ViewController.swift
//  VideoRecordingDemo
//
//  Created by Jay Mehta on 1/11/17.
//  Copyright © 2017 Jay Mehta. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}

class DemoVC: UIViewController , AVCaptureFileOutputRecordingDelegate{
    @IBOutlet weak var PreviewView: PreviewView!
    @IBOutlet weak var OverlayView: OverlayView!
    
    
    @IBOutlet weak var btnRecording: UIButton!
    @IBOutlet weak var btnCamera: UIButton!
    
    @IBOutlet weak var btnFlash: UIButton!
    
    @IBOutlet weak var btnVolume: UIButton!
    
    let maximumVideoLength : Float64 = 30.0; //Whatever value you wish to set as the maximum, in seconds
    let prefferedTimeScale : Int32 = 30 //Frames per second
    
    
    private let session = AVCaptureSession()
    private var backgroundRecordingID: UIBackgroundTaskIdentifier? = nil
    private var isSessionRunning = false
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil) // Communicate with the session and other session objects on this queue.
    private var setupResult: SessionSetupResult = .success
    var videoDeviceInput: AVCaptureDeviceInput!
    private var movieFileOutput: AVCaptureMovieFileOutput? = nil //Recording Movies
    
    @IBOutlet weak var resumeButton: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.btnRecording.addTarget(self, action: #selector(btnRecordingPress), for: .touchUpInside);
        self.btnCamera.addTarget(self, action: #selector(changeCamera), for: .touchUpInside);
        self.btnFlash.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        self.btnVolume.addTarget(self, action: #selector(volumePressed), for: .touchUpInside)
      
        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
                })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }

        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async { [unowned self] in
            self.configureSession()
            self.setUpForRecording();
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("App doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "App", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        if #available(iOS 10.0, *) {
                            UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                        } else {
                            // Fallback on earlier versions
                            UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                        }
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }


    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    func setInputGain(gain: Float) {
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.isInputGainSettable {
            do{
                
               // var error : NSErrorPointer = nil
                if (audioSession.isInputGainSettable) {
                    
                    let success = audioSession.isInputAvailable//audioSession.setInputGain(gain, error: error)
                    if success {
                        print("Volume Input gain Available")
                    }
                    _ = try audioSession.setInputGain(gain)
               
                }
            }catch{
                print("ERROR MSG!! AUDIO SESSION");
            }
            
        }
        else {
            print("Cannot set input gain")
        }
    }
    
    //MARK: DELEGATE
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        // Enable the Record button to let the user stop the recording.
        DispatchQueue.main.async { [unowned self] in
           
            self.btnRecording.isEnabled = true;
            self.btnRecording.setTitle("Stop", for: .normal)
            self.showButtons();
        }
    }
    
     func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        
        /*
         Note that currentBackgroundRecordingID is used to end the background task
         associated with this recording. This allows a new recording to be started,
         associated with a new UIBackgroundTaskIdentifier, once the movie file output's
         `isRecording` property is back to false — which happens sometime after this method
         returns.
         
         Note: Since we use a unique file path for each recording, a new recording will
         not overwrite a recording currently being saved.
         */
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                }
                catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskInvalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(error)")
            success = (((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as! Bool))
        }
        
        if success {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    if #available(iOS 9.0, *) {
                        
                        PHPhotoLibrary.shared().performChanges({
                            
                            let  options = PHAssetResourceCreationOptions()
                            options.shouldMoveFile = true
                            let creationRequest = PHAssetCreationRequest.forAsset()
                            
                            creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                            }, completionHandler: { success, error in
                                if !success {
                                    print("Could not save movie to photo library: \(error)")
                                }
                                cleanup()
                            }
                        )
                    }
                    else {
                        // Fallback on earlier versions
                    }
                }
                else {
                    cleanup()
                }
            }
        }
        else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async { [unowned self] in
            // Only enable the ability to change camera if the device has more than one camera.
            self.btnRecording.isEnabled = true
            self.btnRecording.setTitle(NSLocalizedString("Record", comment: "Recording button record title"), for: [])
            self.showButtons();
        }
        
    }
    //MARK: BUTTON 
    func btnRecordingPress()
    {
        self.startRecording();
        self.btnRecording.setTitle("Start", for: .normal)
    }
    func volumePressed()
    {
        // your code to initialize output
        
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        let audioConnection :AVCaptureConnection? = movieFileOutput.connection(withMediaType:AVMediaTypeAudio)
        
        if(self.btnVolume.isSelected == false)
        {
            self.btnVolume.isSelected = true
            //self.setInputGain(gain: 0.0); // Disable microphone
            self.btnVolume.setTitle("Muted", for: .normal)
            if let connection = audioConnection {
                connection.isEnabled = false;
            }
        }
        else
        {
            self.btnVolume.isSelected = false;
            //self.setInputGain(gain: 1.0); // Enable microphone
            self.btnVolume.setTitle("Volume", for: .normal)
            if let connection = audioConnection {
                connection.isEnabled = true;
            }
        }
    }
       
    //MARK: FLASH
    func toggleFlash() {
        var device : AVCaptureDevice!
        
        if #available(iOS 10.0, *) {
            let videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDuoCamera], mediaType: AVMediaTypeVideo, position: .unspecified)!
            let devices = videoDeviceDiscoverySession.devices!
            device = devices.first!
            
        } else {
            // Fallback on earlier versions
            device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        }
        
        if ((device as AnyObject).hasMediaType(AVMediaTypeVideo))
        {
            if (device.hasTorch)
            {
                self.session.beginConfiguration()
                if device.isTorchActive == false {
                    self.flashOn(device: device)
                } else {
                    self.flashOff(device: device);
                }
                self.session.commitConfiguration()
            }
        }
    }
    private func flashOn(device:AVCaptureDevice)
    {
        do{
            if (device.hasTorch)
            {
                try device.lockForConfiguration()
                device.torchMode = .on
                device.unlockForConfiguration()
            }
        }catch{
            print("Device tourch Flash Error ");
        }
    }
    
    private func flashOff(device:AVCaptureDevice)
    {
        do{
            if (device.hasTorch){
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
           }
        }catch{
            print("Device tourch Flash Error ");
        }
    }
    
    //MARK: CONFIGRATION
    // Call this on the session queue.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        session.beginConfiguration()
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            if #available(iOS 10, *) {
                
                // Choose the back dual camera if available, otherwise default to a wide angle camera.
                if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDuoCamera, mediaType: AVMediaTypeVideo, position: .back) {
                    defaultVideoDevice = dualCameraDevice
                }
                else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
                    // If the back dual camera is not available, default to the back wide angle camera.
                    defaultVideoDevice = backCameraDevice
                }
                else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
                    // In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
                    defaultVideoDevice = frontCameraDevice
                }
            }
            else{
                for device in AVCaptureDevice.devices()
                {
                    
                    if (device as AnyObject).hasMediaType( AVMediaTypeVideo )
                    {
                        if (device as AnyObject).position == AVCaptureDevicePosition.back
                        {
                            defaultVideoDevice = device as? AVCaptureDevice
                            break;
                        }
                        else
                        {
                            defaultVideoDevice = device as? AVCaptureDevice
                            break;
                        }
                    }
                }
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Why are we dispatching this to the main queue?
                     Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                     can only be manipulated on the main thread.
                     Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    //let statusBarOrientation = UIApplication.shared.statusBarOrientation
             
                    /*if statusBarOrientation != .unknown {
                        if let videoOrientation = statusBarOrientation.videoOrientation {
                            initialVideoOrientation = videoOrientation
                        }
                    }*/
                    
                   /* if(self.PreviewView.videoPreviewLayer.connection.isVideoOrientationSupported)
                    {
                        self.PreviewView.videoPreviewLayer.connection.videoOrientation = .portrait
                    }*/
                    let initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    self.PreviewView.videoPreviewLayer.session = self.session
                    self.PreviewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation
                    print("\(self.PreviewView.videoPreviewLayer.connection)")
                }
                
                // Add audio input.
                do {
                    let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
                    let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                    
                    if session.canAddInput(audioDeviceInput) {
                        session.addInput(audioDeviceInput)
                    }
                    else {
                        print("Could not add audio device input to the session")
                    }
                }
                catch {
                    print("Could not create audio device input: \(error)")
                }
                
                // Add photo output.
                /*if session.canAddOutput(photoOutput)
                {
                    session.addOutput(photoOutput)
                    
                    photoOutput.isHighResolutionCaptureEnabled = true
                    photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
                    livePhotoMode = photoOutput.isLivePhotoCaptureSupported ? .on : .off
                }
                else {
                    print("Could not add photo output to the session")
                    setupResult = .configurationFailed
                    session.commitConfiguration()
                    return
                }*/
                
                session.commitConfiguration()
            }
            else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        }
        catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    private func setUpForRecording()
    {
        sessionQueue.async { [unowned self] in
            let movieFileOutput = AVCaptureMovieFileOutput()
            
            if self.session.canAddOutput(movieFileOutput) {
                self.session.beginConfiguration()
                self.session.addOutput(movieFileOutput)
                self.session.sessionPreset = AVCaptureSessionPresetHigh
                if let connection = movieFileOutput.connection(withMediaType: AVMediaTypeVideo) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
                self.session.commitConfiguration()
                self.movieFileOutput = movieFileOutput
                
                //SET MAX DURATION
                let maxDuration : CMTime = CMTimeMakeWithSeconds(self.maximumVideoLength,self.prefferedTimeScale)
                self.movieFileOutput?.maxRecordedDuration = maxDuration;
                //
                
                DispatchQueue.main.async { [unowned self] in
                    self.btnRecording.isEnabled = true;
                }
            }
        }
    }
    
    private func startRecording()
    {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.
         
         See the AVCaptureFileOutputRecordingDelegate methods.
         */
        self.btnRecording.isEnabled = false
        
        /*
         Retrieve the video preview layer's video orientation on the main queue
         before entering the session queue. We do this to ensure UI elements are
         accessed on the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = PreviewView.videoPreviewLayer.connection.videoOrientation
        
        sessionQueue.async { [unowned self] in
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    /*
                     Setup background task.
                     This is needed because the `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)`
                     callback is not received until AVCam returns to the foreground unless you request background execution time.
                     This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                     To conclude this background execution, endBackgroundTask(_:) is called in
                     `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)` after the recorded file has been saved.
                     */
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation
                
                // Start recording to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                self.hideButtons()
            }
            else {
                movieFileOutput.stopRecording()
                self.showButtons();
            }
        }
    }
    
    private func hideButtons()
    {
        self.btnCamera.isHidden = true
        self.btnFlash.isHidden = true
    }
    
    private func showButtons()
    {
        self.btnCamera.isHidden = false
        self.btnFlash.isHidden = false
    }
    
    //FOR CHANGE CAMERA
    func changeCamera() {
        
        self.btnRecording.isEnabled = false
        self.btnCamera.isEnabled = false
        self.btnFlash.isEnabled = false;
        
        sessionQueue.async { [unowned self] in
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice!.position
            var newVideoDevice: AVCaptureDevice? = nil
            let preferredPosition: AVCaptureDevicePosition
            if #available(iOS 10, *) {
                let videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDuoCamera], mediaType: AVMediaTypeVideo, position: .unspecified)!
                let devices = videoDeviceDiscoverySession.devices!
               
                let preferredDeviceType: AVCaptureDeviceType
                
                switch currentPosition {
                case .unspecified, .front:
                    preferredPosition = .back
                    preferredDeviceType = .builtInDuoCamera
                    
                    
                case .back:
                    preferredPosition = .front
                    preferredDeviceType = .builtInWideAngleCamera
                    
                }
                
                // First, look for a device with both the preferred position and device type. Otherwise, look for a device with only the preferred position.
                if let device = devices.filter({ $0.position == preferredPosition && $0.deviceType == preferredDeviceType }).first {
                    newVideoDevice = device
                }
                else if let device = devices.filter({ $0.position == preferredPosition }).first {
                    newVideoDevice = device
                }
            }
            else
            {
                switch currentPosition {
                case .unspecified, .front:
                    preferredPosition = .back
                    
                case .back:
                    preferredPosition = .front
                }
                let devicesOld = AVCaptureDevice.devices()
                //let videoCaptureDevice: AVCaptureDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
                if let device  = devicesOld?.filter({ ($0 as AnyObject).position == preferredPosition }).first {
                    
                    if ((device as AnyObject).hasMediaType(AVMediaTypeVideo)) {
                        newVideoDevice = device as? AVCaptureDevice
                    }
                    
                }
            }
            self.flashOff(device: newVideoDevice!)
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: currentVideoDevice!)
                        
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: videoDeviceInput.device)
                        
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    }
                    else {
                        self.session.addInput(self.videoDeviceInput);
                    }
                    
                    if let connection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                }
                catch {
                    print("Error occured while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async { [unowned self] in
                
                if(preferredPosition == .front)
                {
                    self.btnFlash.isHidden = true;
                }
                else
                {
                    self.btnFlash.isHidden = false;
                }
                self.btnCamera.isEnabled = true;
                self.btnFlash.isEnabled = true;
                self.btnRecording.isEnabled = self.movieFileOutput != nil
            }
        }
    }
    
  
    
    private func focus(with focusMode: AVCaptureFocusMode, exposureMode: AVCaptureExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async { [unowned self] in
            if let device = self.videoDeviceInput.device {
                do {
                    try device.lockForConfiguration()
                    
                    /*
                     Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                     Call set(Focus/Exposure)Mode() to apply the new point of interest.
                     */
                    if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                        device.focusPointOfInterest = devicePoint
                        device.focusMode = focusMode
                    }
                    
                    if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                        device.exposurePointOfInterest = devicePoint
                        device.exposureMode = exposureMode
                    }
                    
                    device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                    device.unlockForConfiguration()
                }
                catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        }
    }
    
    // MARK: KVO and Notifications
    
    private var sessionRunningObserveContext = 0
    
    private func addObservers() {
        session.addObserver(self, forKeyPath: "running", options: .new, context: &sessionRunningObserveContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification"), object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningObserveContext)
    }
    
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .autoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunningObserveContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
           // let isLivePhotoCaptureSupported = photoOutput.isLivePhotoCaptureSupported
           // let isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureEnabled
            
            DispatchQueue.main.async { [unowned self] in
                // Only enable the ability to change camera if the device has more than one camera.
                //self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount() > 1
                self.btnRecording.isEnabled = isSessionRunning && self.movieFileOutput != nil
                //self.photoButton.isEnabled = isSessionRunning
               // self.captureModeControl.isEnabled = isSessionRunning
               // self.livePhotoModeButton.isEnabled = isSessionRunning && isLivePhotoCaptureEnabled
                //self.livePhotoModeButton.isHidden = !(isSessionRunning && isLivePhotoCaptureSupported)
            }
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
        
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async { [unowned self] in
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
                else {
                    DispatchQueue.main.async { [unowned self] in
                        self.resumeButton.isHidden = false
                    }
                }
            }
        }
        else {
            resumeButton.isHidden = false
        }
    }
    
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios we want to enable the user to resume the session running.
         For example, if music playback is initiated via control center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if #available(iOS 9.0, *) {
            if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSessionInterruptionReason(rawValue: reasonIntegerValue) {
                print("Capture session was interrupted with reason \(reason)")
                
                var showResumeButton = false
                
                if reason == AVCaptureSessionInterruptionReason.audioDeviceInUseByAnotherClient || reason == AVCaptureSessionInterruptionReason.videoDeviceInUseByAnotherClient {
                    showResumeButton = true
                }
                else if reason == AVCaptureSessionInterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps {
                    // Simply fade-in a label to inform the user that the camera is unavailable.
                   
                }
                
                if showResumeButton {
                    // Simply fade-in a button to enable the user to try to resume the session running.
                    resumeButton.alpha = 0
                    resumeButton.isHidden = false
                    UIView.animate(withDuration: 0.25) { [unowned self] in
                        self.resumeButton.alpha = 1
                    }
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: { [unowned self] in
                            self.resumeButton.alpha = 0
                }, completion: { [unowned self] finished in
                    self.resumeButton.isHidden = true
                }
            )
        }
    }
}

@available(iOS 10.0, *)
extension AVCaptureDeviceDiscoverySession {
    func uniqueDevicePositionsCount() -> Int {
        var uniqueDevicePositions = [AVCaptureDevicePosition]()
        
        for device in devices {
            if !uniqueDevicePositions.contains(device.position) {
                uniqueDevicePositions.append(device.position)
            }
        }
        
        return uniqueDevicePositions.count
    }
}

