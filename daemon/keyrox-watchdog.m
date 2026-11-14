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

static IOPMAssertionID gPowerAssertionID = kIOPMNullAssertionID;
static dispatch_source_t gTimer = NULL;

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

static void createPowerAssertion(void) {
    if (gPowerAssertionID != kIOPMNullAssertionID) return;
    IOReturn kr = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep,
        kIOPMAssertionLevelOn,
        CFSTR("Keyrox TKL USB Keep-Alive"),
        &gPowerAssertionID
    );
    if (kr == kIOReturnSuccess) {
        logMessage("Power assertion active: PreventUserIdleSystemSleep (id: %u)", gPowerAssertionID);
    }
}

static void releasePowerAssertion(void) {
    if (gPowerAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gPowerAssertionID);
        logMessage("Power assertion released (id: %u)", gPowerAssertionID);
        gPowerAssertionID = kIOPMNullAssertionID;
    }
}

static void reviveKeyboard(const char *reason) {
    logMessage("⚡ Auto-Revive triggered (reason: %s). Issuing USB Bus Reset...", reason);
    int rc = keyrox_usb_bus_reset();
    if (rc != 0) {
        logMessage("[-] Bus Reset returned %d (device might be unplugged)", rc);
        return;
    }
    logMessage("[+] USB Bus Reset sent successfully. Waiting 600ms for MCU boot...");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        keyrox_device_t *kdev = keyrox_open();
        if (kdev) {
            keyrox_set_mode(kdev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(kdev, 4);
            keyrox_close(kdev);
            logMessage("[+] Keyboard revived and initialized to Wave mode (Brightness: 4)!");
        } else {
            logMessage("[!] USB Reset completed, waiting for kernel HID event driver.");
        }
    });
}

static void checkKeyboardHealth(void) {
    keyrox_device_t *dev = keyrox_open();
    if (!dev) {
        logMessage("[!] Health check: keyboard not responding, attempting auto-revive...");
        reviveKeyboard("Health check failed");
    } else {
        keyrox_close(dev);
        logMessage("Health check OK: Keyrox TKL responsive.");
    }
}

static void signalHandler(int sig) {
    logMessage("Received signal %d; terminating cleanly...", sig);
    if (gTimer) dispatch_source_cancel(gTimer);
    releasePowerAssertion();
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && (strcmp(argv[1], "--revive") == 0 || strcmp(argv[1], "-r") == 0)) {
            reviveKeyboard("CLI manual trigger");
            sleep(1);
            return 0;
        }

        logMessage("Starting Keyrox USB Keep-Alive Watchdog v1.0 (Smart Screen-Wake Revive)");
        logMessage("Target: VID 0x1A2C, PID 0x2511 (Red Square Keyrox TKL)");

        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        createPowerAssertion();

        // Register for Display Sleep & Wake notifications
        NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

        [wsCenter addObserverForName:NSWorkspaceScreensDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            logMessage("📺 Display woke up (NSWorkspaceScreensDidWakeNotification)!");
            reviveKeyboard("Display woke up");
        }];

        [wsCenter addObserverForName:NSWorkspaceDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            logMessage("💻 System woke up (NSWorkspaceDidWakeNotification)!");
            reviveKeyboard("System woke up");
        }];

        // Initial health check
        checkKeyboardHealth();

        // 60-second periodic health check
        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            gTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)),
            (uint64_t)(60.0 * NSEC_PER_SEC),
            1 * NSEC_PER_SEC
        );
        dispatch_source_set_event_handler(gTimer, ^{
            checkKeyboardHealth();
        });
        dispatch_resume(gTimer);

        // Run Cocoa runloop for NSWorkspace notifications
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
