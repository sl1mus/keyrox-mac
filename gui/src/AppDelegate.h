#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "../../keyrox_hid.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>

@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) WKWebView *webView;

- (void)showAboutPanel:(id)sender;
- (void)checkForUpdates:(id)sender;
- (void)openSettingsTab:(id)sender;

- (void)setupWakeWatchdog;
- (void)checkWatchdogStatus;
- (void)installWatchdogDaemon;
- (void)uninstallWatchdogDaemon;

@end
