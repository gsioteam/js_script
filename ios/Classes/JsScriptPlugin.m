#import "JsScriptPlugin.h"

void jsContextSetup();

@implementation JsScriptPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"js_script"
            binaryMessenger:[registrar messenger]];
  JsScriptPlugin* instance = [[[JsScriptPlugin alloc] init] autorelease];
  [registrar addMethodCallDelegate:instance channel:channel];
    jsContextSetup();
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
