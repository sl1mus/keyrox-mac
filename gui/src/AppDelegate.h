#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "../../keyrox_hid.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) WKWebView *webView;

@end
