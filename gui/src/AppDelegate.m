#import "AppDelegate.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "keyrox_reset.h"

@interface TitleBarDragView : NSView
@end

@implementation TitleBarDragView
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount == 2) {
        [self.window zoom:nil];
    } else {
        [self.window performWindowDragWithEvent:event];
    }
}
- (BOOL)mouseDownCanMoveWindow {
    return YES;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}
@end

@interface AppDelegate () {
    keyrox_device_t *_dev;
    dispatch_queue_t _hidQueue;
    NSTimer *_pollTimer;
    BOOL _lastConnected;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _hidQueue = dispatch_queue_create("org.redsquare.keyrox.hid", DISPATCH_QUEUE_SERIAL);
    _lastConnected = NO;

    // Window Setup (1080x750 borderless, resizable with custom drag area)
    NSRect frame = NSMakeRect(0, 0, 1080, 750);
    NSUInteger styleMask = NSWindowStyleMaskTitled | 
                           NSWindowStyleMaskClosable | 
                           NSWindowStyleMaskMiniaturizable | 
                           NSWindowStyleMaskResizable |
                           NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];

    self.window.minSize = NSMakeSize(1000, 700);

    self.window.title = @"Red Square Keyrox TKL";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.movableByWindowBackground = YES;
    self.window.backgroundColor = [NSColor colorWithCalibratedRed:0.08 green:0.08 blue:0.09 alpha:1.0];
    [self.window setSharingType:NSWindowSharingReadOnly];
    [self.window center];

    // Hide default traffic light buttons to match original DirectUI design
    [[self.window standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[self.window standardWindowButton:NSWindowZoomButton] setHidden:YES];

    // WKWebView Configuration
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *userContent = [[WKUserContentController alloc] init];
    [userContent addScriptMessageHandler:self name:@"keyrox"];
    config.userContentController = userContent;
    [config.preferences setValue:@YES forKey:@"developerExtrasEnabled"];

    self.webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds configuration:config];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.navigationDelegate = self;
    [self.webView setValue:@NO forKey:@"drawsBackground"];

    [self.window.contentView addSubview:self.webView];

    // Add native titlebar drag overlay (leaving right 112px for minimize, maximize and close buttons)
    NSRect dragFrame = NSMakeRect(0, self.window.contentView.bounds.size.height - 34, self.window.contentView.bounds.size.width - 112, 34);
    TitleBarDragView *dragView = [[TitleBarDragView alloc] initWithFrame:dragFrame];
    dragView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.window.contentView addSubview:dragView positioned:NSWindowAbove relativeTo:self.webView];

    // Load UI HTML
    NSURL *uiURL = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html" subdirectory:@"ui"];
    if (uiURL) {
        [self.webView loadFileURL:uiURL allowingReadAccessToURL:[[NSBundle mainBundle] resourceURL]];
    } else {
        // Fallback to current working directory for development
        NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString *localPath = [cwd stringByAppendingPathComponent:@"gui/ui/index.html"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
            localPath = [cwd stringByAppendingPathComponent:@"ui/index.html"];
        }
        NSURL *localURL = [NSURL fileURLWithPath:localPath];
        [self.webView loadFileURL:localURL allowingReadAccessToURL:[localURL URLByDeletingLastPathComponent]];
    }

    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Start background status poller (every 2.5 seconds)
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.5
                                                  target:self
                                                selector:@selector(checkDeviceStatus)
                                                userInfo:nil
                                                 repeats:YES];
    
    // Initial check right away
    [self checkDeviceStatus];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [_pollTimer invalidate];
    if (_dev) {
        keyrox_close(_dev);
        _dev = NULL;
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[Keyrox] Web view loaded successfully.");
    NSString *snapName = [[[NSProcessInfo processInfo] environment] objectForKey:@"KEYROX_AUTO_SNAPSHOT"];
    if (snapName) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self captureSnapshot:snapName];
        });
    }

    if ([[[NSProcessInfo processInfo] environment] objectForKey:@"KEYROX_AUTO_SNAPSHOT_ALL"]) {
        NSArray *tabs = @[@"led", @"remap", @"custom", @"settings"];
        for (NSUInteger i = 0; i < tabs.count; i++) {
            NSString *tab = tabs[i];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1.0 + i * 0.8) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *js = [NSString stringWithFormat:@"document.querySelector('.tab-btn[data-tab=\"%@\"]').click();", tab];
                [self.webView evaluateJavaScript:js completionHandler:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self captureSnapshot:[NSString stringWithFormat:@"keyrox_tab_%@_v2_0.png", tab]];
                });
            });
        }
    }
}

- (void)captureSnapshot:(NSString *)filename {
    WKSnapshotConfiguration *snapConfig = [[WKSnapshotConfiguration alloc] init];
    [self.webView takeSnapshotWithConfiguration:snapConfig completionHandler:^(NSImage *snapshot, NSError *error) {
        if (snapshot) {
            CGImageRef cgImage = [snapshot CGImageForProposedRect:NULL context:nil hints:nil];
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
            NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *customDir = [[[NSProcessInfo processInfo] environment] objectForKey:@"KEYROX_SNAPSHOT_DIR"];
            NSString *targetDir = customDir;
            if (!targetDir || ![[NSFileManager defaultManager] fileExistsAtPath:targetDir]) {
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
                targetDir = paths.firstObject ?: NSTemporaryDirectory();
            }
            NSString *path = [targetDir stringByAppendingPathComponent:filename];
            [pngData writeToFile:path atomically:YES];
            NSLog(@"[Keyrox] Successfully saved UI snapshot to %@", path);
        } else {
            NSLog(@"[Keyrox] Snapshot failed: %@", error);
        }
    }];
}

#pragma mark - Device Helpers

- (keyrox_device_t *)ensureDevice {
    if (!_dev) {
        _dev = keyrox_open();
    }
    return _dev;
}

- (void)checkDeviceStatus {
    dispatch_async(_hidQueue, ^{
        keyrox_device_t *dev = [self ensureDevice];
        if (!dev) {
            if (self->_lastConnected) {
                self->_lastConnected = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self sendJSEvent:@"onDeviceStatus" data:@{@"connected": @NO}];
                });
            }
            return;
        }

        keyrox_mode_t mode = 0;
        uint8_t bright = 0, speed = 0, profile = 0;
        char fw[32] = {0};

        int ret = keyrox_get_status(dev, &mode, &bright, &speed, &profile, fw, sizeof(fw));
        if (ret == 0) {
            self->_lastConnected = YES;
            NSDictionary *status = @{
                @"connected": @YES,
                @"mode": @((int)mode),
                @"modeName": [NSString stringWithUTF8String:keyrox_mode_to_string(mode)],
                @"brightness": @(bright),
                @"speed": @(speed),
                @"profile": @(profile),
                @"fw": [NSString stringWithUTF8String:fw]
            };
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendJSEvent:@"onDeviceStatus" data:status];
            });
        } else {
            // Read failed, device might have disconnected
            keyrox_close(dev);
            self->_dev = NULL;
            self->_lastConnected = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendJSEvent:@"onDeviceStatus" data:@{@"connected": @NO}];
            });
        }
    });
}

- (void)sendJSEvent:(NSString *)eventName data:(NSDictionary *)data {
    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&err];
    if (!jsonData) return;
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.%@ && window.%@(%@);", eventName, eventName, jsonStr];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

#pragma mark - Script Message Handler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"keyrox"]) return;
    if (![message.body isKindOfClass:[NSDictionary class]]) return;

    NSDictionary *dict = (NSDictionary *)message.body;
    NSString *action = dict[@"action"];
    if (!action) return;

    if ([action isEqualToString:@"closeWindow"]) {
        [NSApp terminate:nil];
        return;
    }
    if ([action isEqualToString:@"minimizeWindow"]) {
        [self.window miniaturize:nil];
        return;
    }
    if ([action isEqualToString:@"maximizeWindow"] || [action isEqualToString:@"zoomWindow"]) {
        [self.window zoom:nil];
        return;
    }
    if ([action isEqualToString:@"openUrl"]) {
        NSString *urlStr = dict[@"url"];
        if (urlStr) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlStr]];
        }
        return;
    }
    if ([action isEqualToString:@"reviveDevice"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            keyrox_usb_bus_reset();
            usleep(600000);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self checkDeviceStatus];
                [self sendJSEvent:@"onToastMessage" data:@{@"message": @"⚡ Шина USB перезапущена, клавиатура реанимирована!"}];
            });
        });
        return;
    }
    if ([action isEqualToString:@"takeSnapshot"]) {
        NSString *name = dict[@"name"] ?: @"keyrox_tab_snapshot.png";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self captureSnapshot:name];
        });
        return;
    }
    if ([action isEqualToString:@"saveProfileToFile"]) {
        NSDictionary *data = dict[@"data"];
        if (data) {
            NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
            NSString *dir = [appSupport stringByAppendingPathComponent:@"Keyrox"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *filePath = [dir stringByAppendingPathComponent:@"profiles.json"];
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
            [jsonData writeToFile:filePath atomically:YES];
            NSLog(@"[Keyrox] Saved profiles to %@", filePath);
        }
        return;
    }
    if ([action isEqualToString:@"loadProfilesFromFile"]) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filePath = [[appSupport stringByAppendingPathComponent:@"Keyrox"] stringByAppendingPathComponent:@"profiles.json"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSData *jsonData = [NSData dataWithContentsOfFile:filePath];
            if (jsonData) {
                NSDictionary *profilesData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                if (profilesData) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self sendJSEvent:@"onProfilesLoaded" data:profilesData];
                    });
                }
            }
        }
        return;
    }
    if ([action isEqualToString:@"exportProfilesToFile"]) {
        NSDictionary *data = dict[@"data"];
        if (!data) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSSavePanel *savePanel = [NSSavePanel savePanel];
            savePanel.title = @"Экспорт настроек Keyrox";
            savePanel.nameFieldStringValue = @"keyrox_profiles_backup.json";
            savePanel.allowedContentTypes = @[UTTypeJSON];
            [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
                if (result == NSModalResponseOK) {
                    NSURL *url = savePanel.URL;
                    if (url) {
                        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:nil];
                        [jsonData writeToURL:url atomically:YES];
                        NSLog(@"[Keyrox] Exported profiles to %@", url.path);
                        [self sendJSEvent:@"onToastMessage" data:@{@"message": [NSString stringWithFormat:@"Настройки экспортированы: %@", [url lastPathComponent]]}];
                    }
                }
            }];
        });
        return;
    }
    if ([action isEqualToString:@"importProfilesFromFile"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSOpenPanel *openPanel = [NSOpenPanel openPanel];
            openPanel.title = @"Импорт настроек Keyrox";
            openPanel.allowedContentTypes = @[UTTypeJSON];
            openPanel.allowsMultipleSelection = NO;
            openPanel.canChooseDirectories = NO;
            openPanel.canChooseFiles = YES;
            [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
                if (result == NSModalResponseOK) {
                    NSURL *url = openPanel.URL;
                    if (url) {
                        NSData *jsonData = [NSData dataWithContentsOfURL:url];
                        if (jsonData) {
                            NSDictionary *profilesData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                            if (profilesData) {
                                [self sendJSEvent:@"onProfilesLoaded" data:profilesData];
                                [self sendJSEvent:@"onToastMessage" data:@{@"message": [NSString stringWithFormat:@"Импортированы настройки из %@", [url lastPathComponent]]}];
                            }
                        }
                    }
                }
            }];
        });
        return;
    }
    if ([action isEqualToString:@"revealProfilesInFinder"]) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *dir = [appSupport stringByAppendingPathComponent:@"Keyrox"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *filePath = [dir stringByAppendingPathComponent:@"profiles.json"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [@"{}" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [[NSWorkspace sharedWorkspace] selectFile:filePath inFileViewerRootedAtPath:@""];
        return;
    }

    // All hardware actions dispatched to HID queue
    dispatch_async(_hidQueue, ^{
        keyrox_device_t *dev = [self ensureDevice];
        if (!dev) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendJSEvent:@"onDeviceStatus" data:@{@"connected": @NO}];
            });
            return;
        }

        if ([action isEqualToString:@"getStatus"]) {
            [self checkDeviceStatus];
        }
        else if ([action isEqualToString:@"setMode"]) {
            int modeVal = [dict[@"mode"] intValue];
            int dirVal = dict[@"dir"] ? [dict[@"dir"] intValue] : 0;
            keyrox_set_mode(dev, (keyrox_mode_t)modeVal, (keyrox_direction_t)dirVal);
        }
        else if ([action isEqualToString:@"setBrightness"]) {
            int val = [dict[@"value"] intValue];
            keyrox_set_brightness(dev, (uint8_t)val);
        }
        else if ([action isEqualToString:@"setSpeed"]) {
            int val = [dict[@"value"] intValue];
            keyrox_set_speed(dev, (uint8_t)val);
        }
        else if ([action isEqualToString:@"setProfile"]) {
            int val = [dict[@"profile"] intValue];
            keyrox_set_profile(dev, (uint8_t)val);
        }
        else if ([action isEqualToString:@"setColor"]) {
            int r = [dict[@"r"] intValue];
            int g = [dict[@"g"] intValue];
            int b = [dict[@"b"] intValue];
            keyrox_set_color(dev, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        }
        else if ([action isEqualToString:@"setKeyColor"]) {
            int keyIdx = [dict[@"keyIndex"] intValue];
            int r = [dict[@"r"] intValue];
            int g = [dict[@"g"] intValue];
            int b = [dict[@"b"] intValue];
            keyrox_set_key_color(dev, (uint8_t)keyIdx, (uint8_t)r, (uint8_t)g, (uint8_t)b);
        }
        else if ([action isEqualToString:@"setMultipleKeysColor"]) {
            NSArray *keys = dict[@"keys"];
            int r = [dict[@"r"] intValue];
            int g = [dict[@"g"] intValue];
            int b = [dict[@"b"] intValue];
            for (NSNumber *num in keys) {
                keyrox_set_key_color(dev, (uint8_t)[num intValue], (uint8_t)r, (uint8_t)g, (uint8_t)b);
                usleep(1500);
            }
        }
        else if ([action isEqualToString:@"setKeyRemap"]) {
            int keyIdx = [dict[@"keyIndex"] intValue];
            int targetCode = [dict[@"targetCode"] intValue];
            keyrox_set_key_remap(dev, (uint8_t)keyIdx, (uint16_t)targetCode);
        }
        else if ([action isEqualToString:@"resetRemap"]) {
            keyrox_reset_remap(dev);
        }
        else if ([action isEqualToString:@"resetMacro"]) {
            keyrox_reset_macro(dev);
        }
        else if ([action isEqualToString:@"resetLed"]) {
            keyrox_set_mode(dev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(dev, 4);
            keyrox_set_speed(dev, 2);
        }
        else if ([action isEqualToString:@"resetLedCustom"]) {
            for (int i = 0; i < 87; i++) {
                keyrox_set_key_color(dev, (uint8_t)i, 0, 0, 0);
                usleep(1000);
            }
        }
        else if ([action isEqualToString:@"saveSettings"]) {
            keyrox_save_settings(dev);
        }
        else if ([action isEqualToString:@"turnOff"]) {
            keyrox_set_mode(dev, KEYROX_MODE_OFF, KEYROX_DIR_LEFT);
        }
        else if ([action isEqualToString:@"turnOn"]) {
            keyrox_set_mode(dev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
        }
        else if ([action isEqualToString:@"restoreDefaults"]) {
            keyrox_set_profile(dev, 0);
            keyrox_set_mode(dev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(dev, 4);
            keyrox_set_speed(dev, 2);
            keyrox_reset_remap(dev);
            keyrox_reset_macro(dev);
            keyrox_save_settings(dev);
        }
    });
}

@end
