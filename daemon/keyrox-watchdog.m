#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOUSBHost/IOUSBHost.h>

#include <signal.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include "../keyrox_reset.h"
#include "../keyrox_hid.h"
#include "../keyrox_proto.h"

static IOPMAssertionID gSystemAssertionID = kIOPMNullAssertionID;
static dispatch_source_t gTimer = NULL;
static BOOL gKeyboardConnected = NO;
static BOOL gDisplayIsSleeping = NO;
static uint8_t gSavedBrightness = 4;
static BOOL gBacklightTurnedOffForSleep = NO;
static io_object_t gDisplayWranglerNotifier = 0;

static void logMessage(const char *format, ...) {
    char timestamp[32] = {0};
    time_t now = time(NULL);
    struct tm localTime;
    localtime_r(&now, &localTime);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &localTime);

    printf("[%s] ", timestamp);
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
    fflush(stdout);
}

static void createPowerAssertions(void) {
    if (gSystemAssertionID == kIOPMNullAssertionID) {
        IOReturn kr = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionLevelOn,
            CFSTR("Keyrox TKL USB System Keep-Alive"),
            &gSystemAssertionID
        );
        if (kr == kIOReturnSuccess) {
            logMessage("Power assertion active: PreventUserIdleSystemSleep (id: %u)", gSystemAssertionID);
        } else {
            logMessage("[-] Failed to create PreventUserIdleSystemSleep assertion: 0x%08x", kr);
        }
    }
}

static void releasePowerAssertions(void) {
    if (gSystemAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gSystemAssertionID);
        logMessage("Power assertion released: PreventUserIdleSystemSleep (id: %u)", gSystemAssertionID);
        gSystemAssertionID = kIOPMNullAssertionID;
    }
}

static void turnOffBacklightForSleep(void) {
    if (gBacklightTurnedOffForSleep) return;
    keyrox_device_t *dev = keyrox_open();
    if (!dev) return;

    uint8_t brightness;
    if (keyrox_get_status(dev, NULL, &brightness, NULL, NULL, NULL, 0) == 0 &&
        brightness > 0 && keyrox_set_brightness(dev, 0) == 0) {
        gSavedBrightness = brightness;
        gBacklightTurnedOffForSleep = YES;
        logMessage("Backlight dimmed for sleep (saved brightness: %u/4)", brightness);
    }
    keyrox_close(dev);
}

static void restoreBacklightAfterWake(void) {
    if (!gBacklightTurnedOffForSleep) return;
    keyrox_device_t *dev = keyrox_open();
    if (!dev) return;

    if (keyrox_set_brightness(dev, gSavedBrightness) == 0) {
        gBacklightTurnedOffForSleep = NO;
        logMessage("Backlight brightness restored to %u/4", gSavedBrightness);
    }
    keyrox_close(dev);
}

static void DisplayWranglerCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument);

static int reviveKeyboard(const char *reason) {
    logMessage("USB reset requested (%s)", reason);
    int result = keyrox_revive();
    if (result == 0) {
        logMessage("Keyrox HID responded after USB reset");
    } else {
        logMessage("Keyrox recovery failed (result %d)", result);
    }
    return result;
}

static void checkKeyboardHealth(void) {
    static unsigned consecutiveFailures = 0;
    static BOOL recoveryAttempted = NO;
    keyrox_device_t *dev = keyrox_open();
    int status = keyrox_get_status(dev, NULL, NULL, NULL, NULL, NULL, 0);
    keyrox_close(dev);

    if (status != 0) {
        gKeyboardConnected = NO;
        if (consecutiveFailures < 3) consecutiveFailures++;
        if (consecutiveFailures >= 3 && !recoveryAttempted && keyrox_usb_is_present()) {
            recoveryAttempted = YES;
            if (reviveKeyboard("consecutive HID failures") == 0) {
                consecutiveFailures = 0;
                recoveryAttempted = NO;
                gKeyboardConnected = YES;
                if (!gDisplayIsSleeping) restoreBacklightAfterWake();
            }
        }
        return;
    }

    consecutiveFailures = 0;
    recoveryAttempted = NO;
    if (!gKeyboardConnected) logMessage("Keyrox HID is responding");
    gKeyboardConnected = YES;
    if (!gDisplayIsSleeping) restoreBacklightAfterWake();
}

static void DisplayWranglerCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument) {
    (void)refcon; (void)service; (void)messageArgument;
    if (messageType == 0xe0000280 /* kIOMessageDeviceWillPowerOff */ ||
        messageType == 0xe0000270 /* kIOMessageCanDevicePowerOff */) {
        gDisplayIsSleeping = YES;
        turnOffBacklightForSleep();
    } else if (messageType == 0xe0000250 /* kIOMessageDeviceHasPoweredOn */) {
        gDisplayIsSleeping = NO;
        restoreBacklightAfterWake();
        checkKeyboardHealth();
    }
}

static void signalHandler(int sig) {
    logMessage("Received signal %d; terminating cleanly...", sig);
    if (gTimer) dispatch_source_cancel(gTimer);
    releasePowerAssertions();
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && (strcmp(argv[1], "--revive") == 0 || strcmp(argv[1], "-r") == 0)) {
            return reviveKeyboard("CLI manual trigger") == 0 ? 0 : 1;
        }

        // Initialize NSApplication for Cocoa/WindowServer event delivery
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

        logMessage("Starting Keyrox USB Keep-Alive Watchdog v1.3 (Smart Backlight Sleep Sync + 10s Heartbeat)");
        logMessage("Target: VID 0x1A2C, PID 0x2511 / 0x1511 (Red Square Keyrox TKL)");
        logMessage("Mode: Display Sleep allowed (Backlight dims to 0 on sleep, restores on wake)");

        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        createPowerAssertions();

        // Register for IODisplayWrangler hardware power notifications (kernel-level)
        IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMainPortDefault);
        if (notifyPort) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPort), kCFRunLoopDefaultMode);
        }

        io_service_t wrangler = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayWrangler"));
        if (wrangler) {
            if (notifyPort && IOServiceAddInterestNotification(notifyPort, wrangler, kIOGeneralInterest,
                                                              DisplayWranglerCallback, NULL, &gDisplayWranglerNotifier) == kIOReturnSuccess) {
                logMessage("IODisplayWrangler kernel power listener registered");
            }
            IOObjectRelease(wrangler);
        }

        // Also register Cocoa NSWorkspace notifications
        NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

        [wsCenter addObserverForName:NSWorkspaceScreensDidSleepNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            gDisplayIsSleeping = YES;
            turnOffBacklightForSleep();
        }];

        [wsCenter addObserverForName:NSWorkspaceScreensDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            gDisplayIsSleeping = NO;
            restoreBacklightAfterWake();
            createPowerAssertions();
            checkKeyboardHealth();
        }];

        [wsCenter addObserverForName:NSWorkspaceDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            logMessage("💻 System woke up (NSWorkspaceDidWakeNotification)");
            createPowerAssertions();
            checkKeyboardHealth();
        }];

        // Initial health check
        checkKeyboardHealth();

        // 10-second periodic health check & USB heartbeat
        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            gTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
            (uint64_t)(10.0 * NSEC_PER_SEC),
            1 * NSEC_PER_SEC
        );
        dispatch_source_set_event_handler(gTimer, ^{
            checkKeyboardHealth();
        });
        dispatch_resume(gTimer);

        // Run Cocoa runloop for notifications
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
