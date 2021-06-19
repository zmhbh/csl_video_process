import Flutter
import AVFoundation

public class SwiftCslVideoProcessPlugin: NSObject, FlutterPlugin {
    private let channelName = "csl_video_process"
    private var exporter: AVAssetExportSession? = nil
    private var stopCommand = false
    private let channel: FlutterMethodChannel
    private let avController = AvController()
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "csl_video_process", binaryMessenger: registrar.messenger())
        let instance = SwiftCslVideoProcessPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, Any>
        switch call.method {
        case "getByteThumbnail":
            let path = args!["path"] as! String
            let quality = args!["quality"] as! NSNumber
            let position = args!["position"] as! NSNumber
            getByteThumbnail(path, quality, position, result)
        case "getFileThumbnail":
            let path = args!["path"] as! String
            let quality = args!["quality"] as! NSNumber
            let position = args!["position"] as! NSNumber
            getFileThumbnail(path, quality, position, result)
        case "getMediaInfo":
            let path = args!["path"] as! String
            getMediaInfo(path, result)
        case "compressVideo":
            let path = args!["path"] as! String
            let quality = args!["quality"] as! NSNumber
            let deleteOrigin = args!["deleteOrigin"] as! Bool
            let startTime = args!["startTime"] as? Double
            let duration = args!["duration"] as? Double
            let includeAudio = args!["includeAudio"] as? Bool
            let frameRate = args!["frameRate"] as? Int
            compressVideoV2(path, quality, deleteOrigin, startTime, duration, includeAudio,
                          frameRate, result)
        case "cancelCompression":
            cancelCompression(result)
        case "deleteAllCache":
            Utility.deleteFile(Utility.basePath(), clear: true)
            result(true)
        case "setLogLevel":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func getBitMap(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult)-> Data?  {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return nil }
        
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        
        let timeScale = CMTimeScale(track.nominalFrameRate)
        let timeMs = CMTimeMakeWithSeconds(Float64(truncating: position) * 0.001, preferredTimescale: timeScale * 1000)
        guard let img = try? assetImgGenerate.copyCGImage(at:timeMs, actualTime: nil) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: img)
        let compressionQuality = CGFloat(0.01 * Double(truncating: quality))
        return thumbnail.jpegData(compressionQuality: compressionQuality)
    }
    
    private func getByteThumbnail(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        if let bitmap = getBitMap(path,quality,position,result) {
            result(bitmap)
        }
    }
    
    private func getFileThumbnail(_ path: String,_ quality: NSNumber,_ position: NSNumber,_ result: FlutterResult) {
        let fileName = Utility.getFileName(path)
        let url = Utility.getPathUrl("\(Utility.basePath())/\(fileName).jpg")
        Utility.deleteFile(path)
        if let bitmap = getBitMap(path,quality,position,result) {
            guard (try? bitmap.write(to: url)) != nil else {
                return result(FlutterError(code: channelName,message: "getFileThumbnail error",details: "getFileThumbnail error"))
            }
            result(Utility.excludeFileProtocol(url.absoluteString))
        }
    }
    
    public func getMediaInfoJson(_ path: String)->[String : Any?] {
        let url = Utility.getPathUrl(path)
        let asset = avController.getVideoAsset(url)
        guard let track = avController.getTrack(asset) else { return [:] }
        
        let playerItem = AVPlayerItem(url: url)
        let metadataAsset = playerItem.asset
        
        let orientation = avController.getVideoOrientation(path)
        
        let title = avController.getMetaDataByTag(metadataAsset,key: "title")
        let author = avController.getMetaDataByTag(metadataAsset,key: "author")
        
        let duration = asset.duration.seconds * 1000
        let filesize = track.totalSampleDataLength
        
        let size = track.naturalSize.applying(track.preferredTransform)
        
        let width = abs(size.width)
        let height = abs(size.height)
        
        let dictionary = [
            "path":Utility.excludeFileProtocol(path),
            "title":title,
            "author":author,
            "width":width,
            "height":height,
            "duration":duration,
            "filesize":filesize,
            "orientation":orientation
            ] as [String : Any?]
        return dictionary
    }
    
    private func getMediaInfo(_ path: String,_ result: FlutterResult) {
        let json = getMediaInfoJson(path)
        let string = Utility.keyValueToJson(json)
        result(string)
    }
    
    
    @objc private func updateProgress(timer:Timer) {
        let asset = timer.userInfo as! AVAssetExportSession
        if(!stopCommand) {
            channel.invokeMethod("updateProgress", arguments: "\(String(describing: asset.progress * 100))")
        }
    }
    
    private func getExportPreset(_ quality: NSNumber)->String {
        switch(quality) {
        case 1:
            return AVAssetExportPresetLowQuality    
        case 2:
            return AVAssetExportPresetMediumQuality
        case 3:
            return AVAssetExportPreset1280x720
        default:
            return AVAssetExportPresetMediumQuality
        }
    }
    
    private func getComposition(_ isIncludeAudio: Bool,_ timeRange: CMTimeRange, _ sourceVideoTrack: AVAssetTrack)->AVAsset {
        let composition = AVMutableComposition()
        if !isIncludeAudio {
            let compressionVideoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
            compressionVideoTrack!.preferredTransform = sourceVideoTrack.preferredTransform
            try? compressionVideoTrack!.insertTimeRange(timeRange, of: sourceVideoTrack, at: CMTime.zero)
        } else {
            return sourceVideoTrack.asset!
        }
        
        return composition    
    }
    
    private func compressVideo(_ path: String,_ quality: NSNumber,_ deleteOrigin: Bool,_ startTime: Double?,
                               _ duration: Double?,_ includeAudio: Bool?,_ frameRate: Int?,
                               _ result: @escaping FlutterResult) {
        let sourceVideoUrl = Utility.getPathUrl(path)
        let sourceVideoType = "mp4"
        
        let sourceVideoAsset = avController.getVideoAsset(sourceVideoUrl)
        let sourceVideoTrack = avController.getTrack(sourceVideoAsset)
        
        let compressionUrl =
            Utility.getPathUrl("\(Utility.basePath())/\(Utility.getFileName(path)).\(sourceVideoType)")
        
        let timescale = sourceVideoAsset.duration.timescale
        let minStartTime = Double(startTime ?? 0)
        
        let videoDuration = sourceVideoAsset.duration.seconds
        let minDuration = Double(duration ?? videoDuration)
        let maxDurationTime = minStartTime + minDuration < videoDuration ? minDuration : videoDuration
        
        let cmStartTime = CMTimeMakeWithSeconds(minStartTime, preferredTimescale: timescale)
        let cmDurationTime = CMTimeMakeWithSeconds(maxDurationTime, preferredTimescale: timescale)
        let timeRange: CMTimeRange = CMTimeRangeMake(start: cmStartTime, duration: cmDurationTime)
        
        let isIncludeAudio = includeAudio != nil ? includeAudio! : true
        
        let session = getComposition(isIncludeAudio, timeRange, sourceVideoTrack!)
        
        let exporter = AVAssetExportSession(asset: session, presetName: getExportPreset(quality))!
        _ = try? FileManager.default.removeItem(at: compressionUrl)
        
        exporter.outputURL = compressionUrl
        exporter.outputFileType = AVFileType.mov
        exporter.shouldOptimizeForNetworkUse = true
        
        if frameRate != nil {
            let videoComposition = AVMutableVideoComposition(propertiesOf: sourceVideoAsset)
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate!))
            exporter.videoComposition = videoComposition
        }
        
        //if !isIncludeAudio {
            exporter.timeRange = timeRange
        //}
        
        Utility.deleteFile(compressionUrl.absoluteString)
        
        let timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updateProgress),
                                         userInfo: exporter, repeats: true)
        
        exporter.exportAsynchronously(completionHandler: {
            if(self.stopCommand) {
                timer.invalidate()
                self.stopCommand = false
                var json = self.getMediaInfoJson(path)
                json["isCancel"] = true
                let jsonString = Utility.keyValueToJson(json)
                return result(jsonString)
            }
            if deleteOrigin {
                timer.invalidate()
                let fileManager = FileManager.default
                do {
                    if fileManager.fileExists(atPath: path) {
                        try fileManager.removeItem(atPath: path)
                    }
                    self.exporter = nil
                    self.stopCommand = false
                }
                catch let error as NSError {
                    print(error)
                }
            }
            var json = self.getMediaInfoJson(compressionUrl.absoluteString)
            json["isCancel"] = false
            let jsonString = Utility.keyValueToJson(json)
            result(jsonString)
        })
    }
    
    private func compressVideoV2(_ path: String,_ quality: NSNumber,_ deleteOrigin: Bool,_ startTime: Double?,
                               _ duration: Double?,_ includeAudio: Bool?,_ frameRate: Int?,
                               _ result: @escaping FlutterResult) {
        //video file to make the asset
        var assetWriter:AVAssetWriter?
        var assetReader:AVAssetReader?
        let bitrate:NSNumber = NSNumber(value:1024 * 1024 * 2.0)
        
        var audioFinished = false
        var videoFinished = false
        
        let sourceVideoUrl = Utility.getPathUrl(path)
        
        print("sourceVideoUrl: ", sourceVideoUrl)
        
        let sourceVideoType = "mp4"
        
        let asset = AVAsset(url: sourceVideoUrl)
        
        let timescale = asset.duration.timescale
        let cmStartTime = CMTimeMakeWithSeconds(5, preferredTimescale: timescale)
        let cmEndTime = CMTimeMakeWithSeconds(15, preferredTimescale: timescale)


        //create asset reader
        do{
            assetReader = try AVAssetReader(asset: asset)
        } catch{
            assetReader = nil
        }
        
        guard let reader = assetReader else{
               fatalError("Could not initalize asset reader probably failed its try catch")
           }
        
        //reader.timeRange = CMTimeRangeFromTimeToTime(start: cmStartTime, end: cmEndTime)
        
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first!
        let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first!
        
        let videoReaderSettings: [String:Any] =  [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB ]

        let compressionUrl =
            Utility.getPathUrl("\(Utility.basePath())/\(Utility.getFileName(path)).\(sourceVideoType)")
        
        print("compressionUrl: ", compressionUrl)
        _ = try? FileManager.default.removeItem(at: compressionUrl)

        
        // ADJUST BIT RATE OF VIDEO HERE
                
        // Video Output Configuration
        let videoCompressionProps: Dictionary<String, Any> = [
            AVVideoAverageBitRateKey : bitrate,
            AVVideoMaxKeyFrameIntervalKey : 15,
            AVVideoProfileLevelKey : AVVideoProfileLevelH264High41
        ]
        
        
        //resize
        // Rect to fit that size within. In this case you don't care about fitting
        // inside a rect, so pass (0, 0) for the origin.
        
        let frameRate = videoTrack.nominalFrameRate
        let bitRate = videoTrack.estimatedDataRate
        
        print("videoTrack.naturalSize: ",videoTrack.naturalSize)
        print("frameRate: ",frameRate)
        print("bitRate: ",bitRate)
        
        let transform = videoTrack.preferredTransform
        func radiansToDegrees(_ radians: Float) -> CGFloat {
                    return CGFloat(radians * 180.0 / Float.pi)
                }
        let videoAngleInDegree = Int(radiansToDegrees(atan2f(Float(transform.b), Float(transform.a))))
        print("videoAngleInDegree: ", videoAngleInDegree)
        
        var constraint = CGRect(x: 0, y: 0, width: 720, height: 1080)
        if (abs(videoAngleInDegree) == 90){
            constraint = CGRect(x: 0, y: 0, width: 1080, height: 720)
        }
        let compressedSize = AVMakeRect(aspectRatio: videoTrack.naturalSize, insideRect: constraint).size
        
        let videoSettings:[String:Any] = [
            AVVideoCompressionPropertiesKey: videoCompressionProps,
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoHeightKey: compressedSize.height,
            AVVideoWidthKey: compressedSize.width
        ]
        
        // Audio Output Configuration
        var acl = AudioChannelLayout()
        acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        acl.mChannelBitmap = AudioChannelBitmap(rawValue: UInt32(0))
        acl.mNumberChannelDescriptions = UInt32(0)
        
        let acll = MemoryLayout<AudioChannelLayout>.size
        
        let audioOutputSettings: Dictionary<String, Any> = [
            AVFormatIDKey : UInt(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey : UInt(2),
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey : 128000,
            AVChannelLayoutKey : NSData(bytes:&acl, length: acll)
        ]
 
        // Audio Input Configuration
        let decompressionAudioSettings: Dictionary<String, Any> = [
            AVFormatIDKey: UInt(kAudioFormatLinearPCM)
        ]
        
        let assetReaderVideoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
        let assetReaderAudioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: decompressionAudioSettings)
        assetReaderVideoOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(assetReaderVideoOutput){
            reader.add(assetReaderVideoOutput)
        }else{
            fatalError("Couldn't add video output reader")
        }
        
        if reader.canAdd(assetReaderAudioOutput){
            reader.add(assetReaderAudioOutput)
        }else{
            fatalError("Couldn't add audio output reader")
        }
                
        let audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
        let videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        videoInput.transform = videoTrack.preferredTransform
        //we need to add samples to the video input
        
        let videoInputQueue = DispatchQueue(label: "videoQueue")
        let audioInputQueue = DispatchQueue(label: "audioQueue")
        
        do{
            assetWriter = try AVAssetWriter(outputURL: compressionUrl, fileType: AVFileType.mp4)
        }catch{
            assetWriter = nil
        }
        guard let writer = assetWriter else{
            fatalError("assetWriter was nil")
        }
        
        writer.shouldOptimizeForNetworkUse = true
        writer.add(videoInput)
        writer.add(audioInput)
        
        
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: CMTime.zero)
        
        let closeWriter:()->Void = {
                    if (audioFinished && videoFinished){
                        assetWriter?.finishWriting(completionHandler: {
                            
                            self.checkFileSize(sizeUrl: (assetWriter?.outputURL)!, message: "The file size of the compressed file is: ")
                            
                            var json = self.getMediaInfoJson(compressionUrl.absoluteString)
                            json["isCancel"] = false
                            let jsonString = Utility.keyValueToJson(json)
                            result(jsonString)
                            
                            //completion((self.assetWriter?.outputURL)!)
                            
                        })
                        
                        assetReader?.cancelReading()
         
                    }
                }
         
        let duration = asset.duration
        let durationTime = CMTimeGetSeconds(duration)
                
                audioInput.requestMediaDataWhenReady(on: audioInputQueue) {
                    while(audioInput.isReadyForMoreMediaData){
                        let sample = assetReaderAudioOutput.copyNextSampleBuffer()
                        if (sample != nil){
                            audioInput.append(sample!)
                        }else{
                            audioInput.markAsFinished()
                            DispatchQueue.main.async {
                                audioFinished = true
                                closeWriter()
                            }
                            break;
                        }
                    }
                }
        

                
                videoInput.requestMediaDataWhenReady(on: videoInputQueue) {
                    //request data here
                    
                    while(videoInput.isReadyForMoreMediaData){
                        let sample = assetReaderVideoOutput.copyNextSampleBuffer()
                        if (sample != nil){
                            videoInput.append(sample!)
                            let timeStamp = CMSampleBufferGetPresentationTimeStamp(sample!)
                            let timeSecond = CMTimeGetSeconds(timeStamp)
                            let per = timeSecond / durationTime
                            print("video progress --- \(per)")
                        }else{
                            videoInput.markAsFinished()
                            DispatchQueue.main.async {
                                videoFinished = true
                                closeWriter()
                            }
                            break;
                        }
                    }
         
                }
    }
    
    private func cancelCompression(_ result: FlutterResult) {
        exporter?.cancelExport()
        stopCommand = true
        result("")
    }
    
    
    func checkFileSize(sizeUrl: URL, message:String){
        let data = NSData(contentsOf: sizeUrl)!
        print(message, (Double(data.length) / 1048576.0), " mb")
    }
    
}
