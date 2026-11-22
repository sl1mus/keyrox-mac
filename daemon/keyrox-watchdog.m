#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOUSBHost/IOUSBHost.h>

#include <signal.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include "../keyrox_reset.h"
#include "../keyrox_hid.h"
#include "../keyrox_proto.h"

static IOPMAssertionID gSystemAssertionID = kIOPMNullAssertionID;
static dispatch_source_t gTimer = NULL;
static BOOL gKeyboardConnected = NO;
static BOOL gDisplayIsSleeping = NO;
static BOOL gBrightnessSynchronized = NO;
static NSTimeInterval gDisplaySettleUntil = 0;

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

/* Run USB calls in a child so a stuck driver cannot stop the watchdog timer. */
static int runWorker(NSString *argument, NSTimeInterval timeout) {
    char executable[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0) return -1;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:executable]];
    task.arguments = @[argument];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        logMessage("Worker launch failed: %s", error.localizedDescription.UTF8String);
        return -1;
    }
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + timeout;
    while (task.running && NSProcessInfo.processInfo.systemUptime < deadline) usleep(20000);
    if (task.running) {
        kill(task.processIdentifier, SIGKILL);
        logMessage("Worker %s timed out after %.0f seconds", argument.UTF8String, timeout);
        return -1;
    }
    return task.terminationStatus;
}

static void syncDisplayBrightness(void) {
    if (gBrightnessSynchronized || NSProcessInfo.processInfo.systemUptime < gDisplaySettleUntil) return;
    NSString *argument = gDisplayIsSleeping ? @"--dim" : @"--restore-brightness";
    if (runWorker(argument, 3) == 0) {
        gBrightnessSynchronized = YES;
        logMessage("%s", gDisplayIsSleeping ? "Display asleep: effect brightness set to minimum" :
                   "Display awake: saved effect brightness synchronized");
    }
}

static BOOL displaysAreAsleep(void) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) return NO;
    CGDirectDisplayID *displays = calloc(count, sizeof(*displays));
    if (!displays) return NO;
    BOOL sleeping = NO;
    if (CGGetOnlineDisplayList(count, displays, &count) == kCGErrorSuccess && count > 0) {
        sleeping = YES;
        for (uint32_t i = 0; i < count; ++i) {
            if (!CGDisplayIsAsleep(displays[i])) {
                sleeping = NO;
                break;
            }
        }
    }
    free(displays);
    return sleeping;
}

static void displaySleepChanged(BOOL sleeping) {
    if (gDisplayIsSleeping == sleeping) return;
    gDisplayIsSleeping = sleeping;
    gBrightnessSynchronized = NO;
    gDisplaySettleUntil = NSProcessInfo.processInfo.systemUptime + 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        syncDisplayBrightness();
    });
}

static void checkKeyboardHealth(void) {
    static unsigned consecutiveFailures = 0;
    static NSTimeInterval lastRecovery = -30;
    static NSTimeInterval lastHeartbeat = -60;
    static int previousStatus = -99;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;

    /* Even registry matching can block during removal. Keep it inside the worker. */
    int status = runWorker(@"--probe", 3);
    if (status == 2) {
        if (previousStatus != 2) logMessage("Keyboard absent from USB; waiting for reconnection");
        previousStatus = status;
        gKeyboardConnected = NO;
        gBrightnessSynchronized = NO;
        consecutiveFailures = 0;
        return;
    }
    previousStatus = status;
    if (status != 0) {
        gKeyboardConnected = NO;
        if (consecutiveFailures < 3) consecutiveFailures++;
        logMessage("HID heartbeat failed (%u consecutive failures)", consecutiveFailures);
        if (consecutiveFailures >= 3 && now - lastRecovery >= 30) {
            lastRecovery = now;
            int recovered = runWorker(@"--revive", 8);
            logMessage("Automatic recovery finished (result %d)", recovered);
            if (recovered == 0) {
                consecutiveFailures = 0;
                gKeyboardConnected = YES;
                gBrightnessSynchronized = NO;
            }
        }
        return;
    }
    consecutiveFailures = 0;
    if (!gKeyboardConnected || now - lastHeartbeat >= 60) {
        logMessage("HID heartbeat OK; automatic recovery armed");
        lastHeartbeat = now;
    }
    gKeyboardConnected = YES;
    syncDisplayBrightness();
}

static void signalHandler(int sig) {
    logMessage("Received signal %d; terminating cleanly...", sig);
    if (gTimer) dispatch_source_cancel(gTimer);
    releasePowerAssertions();
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && (strcmp(argv[1], "--dim") == 0 ||
                         strcmp(argv[1], "--restore-brightness") == 0)) {
            keyrox_device_t *dev = keyrox_open();
            int result = keyrox_sync_display_brightness(dev, strcmp(argv[1], "--dim") == 0);
            keyrox_close(dev);
            return result == 0 ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--probe") == 0) {
            if (!keyrox_usb_is_present()) return 2;
            keyrox_device_t *dev = keyrox_open();
            int result = keyrox_get_status(dev, NULL, NULL, NULL, NULL, NULL, 0);
            keyrox_close(dev);
            return result == 0 ? 0 : 1;
        }
        if (argc > 1 && (strcmp(argv[1], "--revive") == 0 || strcmp(argv[1], "-r") == 0)) {
            return reviveKeyboard("CLI manual trigger") == 0 ? 0 : 1;
        }

        // Initialize NSApplication for Cocoa/WindowServer event delivery
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

        logMessage("Starting Keyrox USB Keep-Alive Watchdog v1.0.7 (bounded heartbeat and automatic USB recovery)");
        logMessage("Target: VID 0x1A2C, PID 0x2511 / 0x1511 (Red Square Keyrox TKL)");
        logMessage("Heartbeat every 5 seconds; recovery after 3 failures; retry cooldown 30 seconds");

        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        createPowerAssertions();

        // Use actual screen sleep/wake notifications. Generic power transitions
        // also occur while a display is awake and must not drive keyboard dimming.
        gDisplayIsSleeping = displaysAreAsleep();

        NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

        [wsCenter addObserverForName:NSWorkspaceScreensDidSleepNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            displaySleepChanged(YES);
        }];

        [wsCenter addObserverForName:NSWorkspaceScreensDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            displaySleepChanged(NO);
            createPowerAssertions();
            checkKeyboardHealth();
        }];

        [wsCenter addObserverForName:NSWorkspaceDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            logMessage("System woke up (NSWorkspaceDidWakeNotification)");
            displaySleepChanged(displaysAreAsleep());
            createPowerAssertions();
            checkKeyboardHealth();
        }];

        // Initial health check
        checkKeyboardHealth();

        // Five-second health check and retry of pending brightness synchronization
        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            gTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
            (uint64_t)(5.0 * NSEC_PER_SEC),
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
