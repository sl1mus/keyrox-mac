#import "AppDelegate.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>
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

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // 1. Application Menu (Keyrox)
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Keyrox"];
    
    // About
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"О программе Keyrox"
                                                       action:@selector(showAboutPanel:)
                                                keyEquivalent:@""];
    [aboutItem setTarget:self];
    [appMenu addItem:aboutItem];

    // Check for Updates
    NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"Проверить обновления..."
                                                        action:@selector(checkForUpdates:)
                                                 keyEquivalent:@""];
    [updateItem setTarget:self];
    [appMenu addItem:updateItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    // Preferences / Settings (Cmd+,)
    NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Настройки..."
                                                       action:@selector(openSettingsTab:)
                                                keyEquivalent:@","];
    [prefsItem setTarget:self];
    [appMenu addItem:prefsItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    // Services
    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Службы"
                                                          action:nil
                                                   keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Службы"];
    [servicesItem setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:servicesItem];

    [appMenu addItem:[NSMenuItem separatorItem]];

    // Hide / Show
    [appMenu addItemWithTitle:@"Скрыть Keyrox" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [[NSMenuItem alloc] initWithTitle:@"Скрыть остальные"
                                                        action:@selector(hideOtherApplications:)
                                                 keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [appMenu addItem:hideOthers];
    [appMenu addItemWithTitle:@"Показать все" action:@selector(unhideAllApplications:) keyEquivalent:@""];

    [appMenu addItem:[NSMenuItem separatorItem]];

    // Quit
    [appMenu addItemWithTitle:@"Завершить Keyrox" action:@selector(terminate:) keyEquivalent:@"q"];

    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];

    // 2. Device Menu (Устройство)
    NSMenuItem *deviceMenuItem = [[NSMenuItem alloc] init];
    NSMenu *deviceMenu = [[NSMenu alloc] initWithTitle:@"Устройство"];

    NSMenuItem *readSettingsItem = [[NSMenuItem alloc] initWithTitle:@"Считать настройки с клавиатуры"
                                                              action:@selector(menuReadSettings:)
                                                       keyEquivalent:@"r"];
    [readSettingsItem setTarget:self];
    [deviceMenu addItem:readSettingsItem];

    NSMenuItem *saveProfileItem = [[NSMenuItem alloc] initWithTitle:@"Сохранить профиль во Flash"
                                                             action:@selector(menuSaveProfile:)
                                                      keyEquivalent:@"s"];
    [saveProfileItem setTarget:self];
    [deviceMenu addItem:saveProfileItem];

    [deviceMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *reviveItem = [[NSMenuItem alloc] initWithTitle:@"⚡ Перезапуск шины USB (Revive)"
                                                        action:@selector(menuReviveUSB:)
                                                 keyEquivalent:@"R"];
    [reviveItem setTarget:self];
    [deviceMenu addItem:reviveItem];

    [deviceMenuItem setSubmenu:deviceMenu];
    [mainMenu addItem:deviceMenuItem];

    // 3. Window Menu (Окно)
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Окно"];
    [windowMenu addItemWithTitle:@"Свернуть" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Развернуть" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Закрыть окно" action:@selector(performClose:) keyEquivalent:@"w"];
    [windowMenu addItemWithTitle:@"Все окна — на передний план" action:@selector(arrangeInFront:) keyEquivalent:@""];

    [windowMenuItem setSubmenu:windowMenu];
    [mainMenu addItem:windowMenuItem];
    [NSApp setWindowsMenu:windowMenu];

    // 4. Help Menu (Справка)
    NSMenuItem *helpMenuItem = [[NSMenuItem alloc] init];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Справка"];

    NSMenuItem *githubItem = [[NSMenuItem alloc] initWithTitle:@"Репозиторий проекта на GitHub..."
                                                        action:@selector(openGitHubPage:)
                                                 keyEquivalent:@""];
    [githubItem setTarget:self];
    [helpMenu addItem:githubItem];

    NSMenuItem *issueItem = [[NSMenuItem alloc] initWithTitle:@"Сообщить об ошибке (GitHub Issues)..."
                                                       action:@selector(openGitHubIssues:)
                                                keyEquivalent:@""];
    [issueItem setTarget:self];
    [helpMenu addItem:issueItem];

    [helpMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *checkUpdatesHelpItem = [[NSMenuItem alloc] initWithTitle:@"Проверить обновления..."
                                                                  action:@selector(checkForUpdates:)
                                                           keyEquivalent:@""];
    [checkUpdatesHelpItem setTarget:self];
    [helpMenu addItem:checkUpdatesHelpItem];

    [helpMenuItem setSubmenu:helpMenu];
    [mainMenu addItem:helpMenuItem];
    [NSApp setHelpMenu:helpMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _hidQueue = dispatch_queue_create("org.redsquare.keyrox.hid", DISPATCH_QUEUE_SERIAL);
    _lastConnected = NO;

    [self setupMainMenu];

    // Window Setup (1080x810 borderless, resizable with custom drag area)
    NSRect frame = NSMakeRect(0, 0, 1080, 810);
    NSUInteger styleMask = NSWindowStyleMaskTitled | 
                           NSWindowStyleMaskClosable | 
                           NSWindowStyleMaskMiniaturizable | 
                           NSWindowStyleMaskResizable |
                           NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];

    self.window.minSize = NSMakeSize(1000, 750);

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
    [self setupWakeWatchdog];
    [self checkWatchdogStatus];
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
                    [self captureSnapshot:[NSString stringWithFormat:@"keyrox_tab_%@_v2_2.png", tab]];
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
    if ([action isEqualToString:@"showAbout"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAboutPanel:nil];
        });
        return;
    }
    if ([action isEqualToString:@"checkForUpdates"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkForUpdates:nil];
        });
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
    if ([action isEqualToString:@"getWatchdogStatus"]) {
        [self checkWatchdogStatus];
        return;
    }
    if ([action isEqualToString:@"installWatchdog"]) {
        [self installWatchdogDaemon];
        return;
    }
    if ([action isEqualToString:@"uninstallWatchdog"]) {
        [self uninstallWatchdogDaemon];
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

#pragma mark - Menu & App Actions

- (void)showAboutPanel:(id)sender {
    (void)sender;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    
    NSString *creditsText = @"Red Square Keyrox TKL Control for macOS\n\n"
                            @"Разработчик: keyrox-mac contributors\n"
                            @"Чистый реверс-инжиниринг USB HID протокола чипа ITE GK8911M.\n"
                            @"Открытый исходный код • MIT License (2026)\n\n"
                            @"GitHub: https://github.com/sl1mus/keyrox-mac";
    
    NSAttributedString *credits = [[NSAttributedString alloc] initWithString:creditsText
                                                                  attributes:@{
                                                                      NSFontAttributeName: [NSFont systemFontOfSize:11],
                                                                      NSParagraphStyleAttributeName: style,
                                                                      NSForegroundColorAttributeName: [NSColor labelColor]
                                                                  }];

    NSDictionary *options = @{
        NSAboutPanelOptionApplicationName: @"Red Square Keyrox TKL",
        NSAboutPanelOptionApplicationVersion: @"1.0.0",
        NSAboutPanelOptionVersion: @"v1.0.0 (macOS Universal)",
        @"Copyright": @"Copyright © 2026 keyrox-mac contributors. All rights reserved.",
        NSAboutPanelOptionCredits: credits
    };
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

- (void)checkForUpdates:(id)sender {
    (void)sender;
    [self sendJSEvent:@"onToastMessage" data:@{@"message": @"🔍 Проверка обновлений на GitHub..."}];

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/sl1mus/keyrox-mac/releases/latest"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"Keyrox-macOS-App" forHTTPHeaderField:@"User-Agent"];
    [req setTimeoutInterval:6.0];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            if (error || (httpResp && httpResp.statusCode == 404)) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Проверка обновлений Keyrox";
                alert.informativeText = @"Установлена актуальная версия: v1.0.0 (macOS Universal ARM64/x86_64).\n\n"
                                         @"Репозиторий проекта: github.com/sl1mus/keyrox-mac\n"
                                         @"Вы можете открыть страницу релизов на GitHub для просмотра истории и новостей.";
                [alert addButtonWithTitle:@"Открыть GitHub Релизы"];
                [alert addButtonWithTitle:@"Закрыть"];
                if ([alert runModal] == NSAlertFirstButtonReturn) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/sl1mus/keyrox-mac/releases"]];
                }
                return;
            }

            if (httpResp && httpResp.statusCode == 200 && data) {
                NSError *jsonErr = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                NSString *latestTag = json[@"tag_name"] ?: @"";
                NSString *htmlUrl = json[@"html_url"] ?: @"https://github.com/sl1mus/keyrox-mac/releases";
                NSString *releaseName = json[@"name"] ?: latestTag;

                NSString *currentVer = @"v1.0.0";
                if ([latestTag length] > 0 && ![latestTag isEqualToString:currentVer]) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = [NSString stringWithFormat:@"Доступно обновление: %@", latestTag];
                    alert.informativeText = [NSString stringWithFormat:@"Вышла новая версия Keyrox (%@).\nУстановленная версия: %@.\n\nХотите перейти на GitHub для загрузки?", releaseName, currentVer];
                    [alert addButtonWithTitle:@"Скачать обновление"];
                    [alert addButtonWithTitle:@"Позже"];
                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:htmlUrl]];
                    }
                } else {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"У вас актуальная версия";
                    alert.informativeText = [NSString stringWithFormat:@"Keyrox %@ — установлена самая последняя версия приложения.", currentVer];
                    [alert addButtonWithTitle:@"Отлично"];
                    [alert runModal];
                }
            } else {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Keyrox Control v1.0.0";
                alert.informativeText = @"Не удалось связаться с сервером обновлений. Проверьте подключение к сети.";
                [alert addButtonWithTitle:@"ОК"];
                [alert runModal];
            }
        });
    }];
    [task resume];
}

- (void)openSettingsTab:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.webView evaluateJavaScript:@"document.querySelector('.tab-btn[data-tab=\"settings\"]')?.click();" completionHandler:nil];
}

- (void)menuReadSettings:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.webView evaluateJavaScript:@"document.getElementById('btn-load-current-profile')?.click();" completionHandler:nil];
}

- (void)menuSaveProfile:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.webView evaluateJavaScript:@"document.getElementById('btn-save-current-profile')?.click();" completionHandler:nil];
}

- (void)menuReviveUSB:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.webView evaluateJavaScript:@"document.getElementById('btn-status-revive')?.click();" completionHandler:nil];
}

- (void)openGitHubPage:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/sl1mus/keyrox-mac"]];
}

- (void)openGitHubIssues:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/sl1mus/keyrox-mac/issues"]];
}

#pragma mark - Automatic Wake Watchdog & Daemon Manager

- (void)setupWakeWatchdog {
    NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

    [wsCenter addObserverForName:NSWorkspaceScreensDidWakeNotification
                          object:nil
                           queue:[NSOperationQueue mainQueue]
                      usingBlock:^(NSNotification *note) {
        (void)note;
        NSLog(@"[Keyrox Watchdog] Display woke up (NSWorkspaceScreensDidWakeNotification)!");
        [self autoReviveOnWake:@"Пробуждение дисплея"];
    }];

    [wsCenter addObserverForName:NSWorkspaceDidWakeNotification
                          object:nil
                           queue:[NSOperationQueue mainQueue]
                      usingBlock:^(NSNotification *note) {
        (void)note;
        NSLog(@"[Keyrox Watchdog] System woke up (NSWorkspaceDidWakeNotification)!");
        [self autoReviveOnWake:@"Выход Mac из сна"];
    }];
}

- (void)autoReviveOnWake:(NSString *)reason {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int rc = keyrox_usb_bus_reset();
        NSLog(@"[Keyrox Watchdog] Auto-Revive triggered (%@), reset result = %d", reason, rc);
        usleep(600000);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkDeviceStatus];
            [self sendJSEvent:@"onToastMessage" data:@{
                @"message": [NSString stringWithFormat:@"⚡ Клавиатура автоматически реанимирована (%@)!", reason]
            }];
        });
    });
}

- (void)checkWatchdogStatus {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *home = NSHomeDirectory();
        NSString *plistPath = [home stringByAppendingPathComponent:@"Library/LaunchAgents/io.github.sl1mus.keyrox-watchdog.plist"];
        BOOL plistExists = [[NSFileManager defaultManager] fileExistsAtPath:plistPath];

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/bin/sh";
        task.arguments = @[@"-c", @"launchctl list | grep -E '(keyrox-watchdog|juchen-keepalive)' || true"];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        [task launch];
        [task waitUntilExit];

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        BOOL isRunning = NO;
        int pid = 0;
        if (output && output.length > 0) {
            NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            for (NSString *line in lines) {
                if (line.length > 0) {
                    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSMutableArray *cleanParts = [NSMutableArray array];
                    for (NSString *p in parts) {
                        if (p.length > 0) [cleanParts addObject:p];
                    }
                    if (cleanParts.count >= 3) {
                        NSString *pidStr = cleanParts[0];
                        if (![pidStr isEqualToString:@"-"]) {
                            pid = [pidStr intValue];
                            isRunning = YES;
                            break;
                        }
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendJSEvent:@"onWatchdogStatus" data:@{
                @"installed": @(plistExists),
                @"running": @(isRunning),
                @"pid": @(pid)
            }];
        });
    });
}

- (void)installWatchdogDaemon {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *home = NSHomeDirectory();
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *keyroxDir = [appSupport stringByAppendingPathComponent:@"Keyrox"];
        [[NSFileManager defaultManager] createDirectoryAtPath:keyroxDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSString *targetBinary = [keyroxDir stringByAppendingPathComponent:@"keyrox-watchdog"];

        // Look for bundled keyrox-watchdog inside app bundle
        NSString *bundledBinary = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"keyrox-watchdog"];
        if (!bundledBinary || ![[NSFileManager defaultManager] fileExistsAtPath:bundledBinary]) {
            bundledBinary = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/MacOS/keyrox-watchdog"];
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:bundledBinary]) {
            [[NSFileManager defaultManager] removeItemAtPath:targetBinary error:nil];
            [[NSFileManager defaultManager] copyItemAtPath:bundledBinary toPath:targetBinary error:nil];
        }

        chmod(targetBinary.UTF8String, 0755);

        NSString *launchAgentsDir = [home stringByAppendingPathComponent:@"Library/LaunchAgents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:launchAgentsDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSString *plistPath = [launchAgentsDir stringByAppendingPathComponent:@"io.github.sl1mus.keyrox-watchdog.plist"];
        NSString *logPath = [home stringByAppendingPathComponent:@"Library/Logs/keyrox-watchdog.log"];

        NSString *plistContent = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            @"<plist version=\"1.0\">\n"
            @"<dict>\n"
            @"    <key>Label</key>\n"
            @"    <string>io.github.sl1mus.keyrox-watchdog</string>\n"
            @"    <key>ProgramArguments</key>\n"
            @"    <array>\n"
            @"        <string>%@</string>\n"
            @"    </array>\n"
            @"    <key>RunAtLoad</key>\n"
            @"    <true/>\n"
            @"    <key>KeepAlive</key>\n"
            @"    <true/>\n"
            @"    <key>ProcessType</key>\n"
            @"    <string>Background</string>\n"
            @"    <key>StandardOutPath</key>\n"
            @"    <string>%@</string>\n"
            @"    <key>StandardErrorPath</key>\n"
            @"    <string>%@</string>\n"
            @"</dict>\n"
            @"</plist>\n", targetBinary, logPath, logPath];

        [plistContent writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        // Clean up legacy prototype
        NSString *oldPlist = [launchAgentsDir stringByAppendingPathComponent:@"com.kistenev.juchen-keepalive.plist"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:oldPlist]) {
            NSString *unloadOldCmd = [NSString stringWithFormat:@"launchctl unload \"%@\" 2>/dev/null; rm -f \"%@\"", oldPlist, oldPlist];
            system(unloadOldCmd.UTF8String);
        }

        // Load new watchdog daemon
        NSString *loadCmd = [NSString stringWithFormat:@"launchctl unload \"%@\" 2>/dev/null; launchctl load -w \"%@\"", plistPath, plistPath];
        system(loadCmd.UTF8String);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendJSEvent:@"onToastMessage" data:@{
                @"message": @"🛡️ Фоновый Watchdog (24/7) успешно установлен и запущен!"
            }];
            [self checkWatchdogStatus];
        });
    });
}

- (void)uninstallWatchdogDaemon {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *home = NSHomeDirectory();
        NSString *plistPath = [home stringByAppendingPathComponent:@"Library/LaunchAgents/io.github.sl1mus.keyrox-watchdog.plist"];
        NSString *oldPlist = [home stringByAppendingPathComponent:@"Library/LaunchAgents/com.kistenev.juchen-keepalive.plist"];

        NSString *cmd = [NSString stringWithFormat:
            @"launchctl unload -w \"%@\" 2>/dev/null; rm -f \"%@\"; "
            @"launchctl unload -w \"%@\" 2>/dev/null; rm -f \"%@\"",
            plistPath, plistPath, oldPlist, oldPlist];
        system(cmd.UTF8String);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendJSEvent:@"onToastMessage" data:@{
                @"message": @"⏹️ Фоновый Watchdog остановлен и удален из автозагрузки"
            }];
            [self checkWatchdogStatus];
        });
    });
}

@end
