#import "CslVideoProcessPlugin.h"
#import <csl_video_process/csl_video_process-Swift.h>

@implementation CslVideoProcessPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftCslVideoProcessPlugin registerWithRegistrar:registrar];
}
@end
