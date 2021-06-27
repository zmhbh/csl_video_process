
import AVFoundation
import MobileCoreServices

class AvController: NSObject {
    /// landscape right means home button to the right
    final let orientations = [UIInterfaceOrientation.landscapeRight, UIInterfaceOrientation.portrait, UIInterfaceOrientation.landscapeLeft, UIInterfaceOrientation.portraitUpsideDown];
    
    public func getVideoAsset(_ url:URL)->AVURLAsset {
        return AVURLAsset(url: url)
    }
    
    public func getTrack(_ asset: AVURLAsset)->AVAssetTrack? {
        var track : AVAssetTrack? = nil
        let group = DispatchGroup()
        group.enter()
        asset.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: {
            var error: NSError? = nil;
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            if (status == .loaded) {
                track = asset.tracks(withMediaType: AVMediaType.video).first
            }
            group.leave()
        })
        group.wait()
        return track
    }
    
    public func getVideoOrientation(_ path:String)-> Int? {
        let url = Utility.getPathUrl(path)
        let asset = getVideoAsset(url)
        guard let track = getTrack(asset) else {
            return nil
        }
        let size = track.naturalSize
        let txf = track.preferredTransform
        if size.width == txf.tx && size.height == txf.ty {
            return 0
        } else if txf.tx == 0 && txf.ty == 0 {
            return 90
        } else if txf.tx == 0 && txf.ty == size.width {
            return 180
        } else {
            return 270
        }
    }
    ///     case 0: return .right
    ///     case 90: return .up
    ///     case 180: return .left
    ///     case -90: return .down
    public func getVideoRotation(_ videoTrack: AVAssetTrack) -> Int {
        let transform = videoTrack.preferredTransform
        func radiansToDegrees(_ radians: Float) -> CGFloat {
                    return CGFloat(radians * 180.0 / Float.pi)
                }
        let videoAngleInDegree = Int(radiansToDegrees(atan2f(Float(transform.b), Float(transform.a))))
        return videoAngleInDegree
    }
    
    public func getCurrentOrientation(_ videoTrack: AVAssetTrack) -> UIInterfaceOrientation {
        var orientation = UIInterfaceOrientation.portrait
        let t = videoTrack.preferredTransform
        // Portrait
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0) {
            orientation = UIInterfaceOrientation.portrait
        }
        // PortraitUpsideDown
        if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0) {
            orientation = UIInterfaceOrientation.portraitUpsideDown
        }
        // LandscapeRight
        if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0) {
            orientation = UIInterfaceOrientation.landscapeRight;
        }
        // LandscapeLeft
        if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0) {
            orientation = UIInterfaceOrientation.landscapeLeft;
        }
        return orientation
    }
    
    ///[rotation] is clockwise
    public func getTargetOrientation(_ currentOrientation: UIInterfaceOrientation, _ rotation: Int) -> UIInterfaceOrientation{
        let currentIdx = orientations.firstIndex(of: currentOrientation)
        var targetIdx = currentIdx! + Int(rotation / 90)
        targetIdx = targetIdx % 4
        return orientations[targetIdx]
    }
    
    public func getTransform(_ orientation: UIInterfaceOrientation, _ size: CGSize) -> CGAffineTransform{
        switch (orientation) {
        case UIInterfaceOrientation.landscapeLeft:
            return CGAffineTransform(a: -1, b: 0,c: 0, d: -1, tx: size.width, ty: size.height)
        case UIInterfaceOrientation.landscapeRight:
            return CGAffineTransform(a: 1, b: 0,c: 0, d: 1, tx: 0, ty: 0)
        case UIInterfaceOrientation.portrait:
            return CGAffineTransform(a: 0, b: 1,c: -1, d: 0, tx: size.height, ty: 0)
        case UIInterfaceOrientation.portraitUpsideDown:
            return CGAffineTransform(a: 0, b: -1,c: 1, d: 0, tx: 0, ty: size.width)
        default:
            return CGAffineTransform(a: 0, b: 1,c: -1, d: 0, tx: size.height, ty: 0)
        }
    }
    
    public func getMetaDataByTag(_ asset:AVAsset,key:String)->String {
        for item in asset.commonMetadata {
            if item.commonKey?.rawValue == key {
                return item.stringValue ?? "";
            }
        }
        return ""
    }
}
