import ReplayKit
import VideoToolbox
import Network

class SampleHandler: RPBroadcastSampleHandler {
    
    private var connection: NWConnection?
    private var compressionSession: VTCompressionSession?
    private var width: Int32 = 0
    private var height: Int32 = 0
    
    private let sharedDefaults = UserDefaults(suiteName: "group.com.hdhvxud.ScreenMirror")
    
    private var androidIP: String {
        sharedDefaults?.string(forKey: "android_ip") ?? "192.168.42.100"
    }
    private var port: UInt16 {
        UInt16(sharedDefaults?.string(forKey: "android_port") ?? "12345") ?? 12345
    }
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        setupConnection()
    }
    
    override func broadcastPaused() {}
    override func broadcastResumed() {}
    
    override func broadcastFinished() {
        connection?.cancel()
        connection = nil
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, kCMTimeInvalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        switch type {
        case .video:
            processVideo(sampleBuffer)
        default:
            break
        }
    }
    
    private func processVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let connection = connection, connection.state == .ready else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if compressionSession == nil {
            width = Int32(CVPixelBufferGetWidth(pixelBuffer))
            height = Int32(CVPixelBufferGetHeight(pixelBuffer))
            setupCompressionSession(width: width, height: height)
        }
        guard let session = compressionSession else { return }
        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }
    
    private func setupCompressionSession(width: Int32, height: Int32) {
        VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] as CFDictionary, compressedDataAllocator: nil, outputCallback: compressionCallback, refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), compressionSessionOut: &compressionSession)
        
        guard let session = compressionSession else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
        VTSessionSetProperty.(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    private let compressionCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
        guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else { return }
        let handler = Unmanaged<SampleHandler>.fromOpaque(refcon).takeUnretainedValue()
        handler.sendFrame(sampleBuffer)
    }
    
    private func sendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer), let connection = connection else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard let ptr = dataPointer else { return }
        let data = Data(bytes: ptr, count: totalLength)
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error { print("Send error: \(error)") }
        }))
    }
    
    private func setupConnection() {
        let host = NWEndpoint.Host(androidIP)
        let port = NWEndpoint.Port(integerLiteral: port)
        connection = NWConnection(host: host, port: port, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.connection?.cancel()
                self?.connection = nil
            }
        }
        connection?.start(queue: .global())
    }
}