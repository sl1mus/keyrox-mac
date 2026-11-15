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
static IOPMAssertionID gDisplayAssertionID = kIOPMNullAssertionID;
static dispatch_source_t gTimer = NULL;
static BOOL gKeyboardConnected = NO;

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
    if (gDisplayAssertionID == kIOPMNullAssertionID) {
        IOReturn kr = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep,
            kIOPMAssertionLevelOn,
            CFSTR("Keyrox TKL USB AutoSuspend Prevention"),
            &gDisplayAssertionID
        );
        if (kr == kIOReturnSuccess) {
            logMessage("Power assertion active: PreventUserIdleDisplaySleep (id: %u)", gDisplayAssertionID);
        } else {
            logMessage("[-] Failed to create PreventUserIdleDisplaySleep assertion: 0x%08x", kr);
        }
    }
}

static void releasePowerAssertions(void) {
    if (gDisplayAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gDisplayAssertionID);
        logMessage("Power assertion released: PreventUserIdleDisplaySleep (id: %u)", gDisplayAssertionID);
        gDisplayAssertionID = kIOPMNullAssertionID;
    }
    if (gSystemAssertionID != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gSystemAssertionID);
        logMessage("Power assertion released: PreventUserIdleSystemSleep (id: %u)", gSystemAssertionID);
        gSystemAssertionID = kIOPMNullAssertionID;
    }
}

static void reviveKeyboard(const char *reason) {
    logMessage("⚡ Auto-Revive triggered (reason: %s). Issuing USB Bus Reset...", reason);
    int rc = keyrox_usb_bus_reset();
    if (rc != 0) {
        logMessage("[-] Bus Reset returned %d (device might be unplugged / dropped from PHY)", rc);
        return;
    }
    logMessage("[+] USB Bus Reset sent successfully. Waiting 600ms for MCU boot...");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        keyrox_device_t *kdev = keyrox_open();
        if (kdev) {
            keyrox_set_mode(kdev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(kdev, 4);
            keyrox_close(kdev);
            gKeyboardConnected = YES;
            logMessage("[+] Keyboard revived and initialized to Wave mode (Brightness: 4)!");
        } else {
            logMessage("[!] USB Reset completed, waiting for kernel HID event driver.");
        }
    });
}

static void checkKeyboardHealth(void) {
    keyrox_device_t *dev = keyrox_open();
    if (!dev) {
        if (gKeyboardConnected) {
            logMessage("[!] Health check: Keyrox TKL became unresponsive, attempting auto-revive...");
            gKeyboardConnected = NO;
            reviveKeyboard("Health check failed");
        }
        return;
    }

    // Active heartbeat: query hardware status to ensure USB pipe is actively serviced
    keyrox_mode_t mode = KEYROX_MODE_CONST;
    uint8_t bright = 0, speed = 0, profile = 1;
    char fw[64] = {0};
    int rc = keyrox_get_status(dev, &mode, &bright, &speed, &profile, fw, sizeof(fw));
    keyrox_close(dev);

    if (rc != 0) {
        if (gKeyboardConnected) {
            logMessage("[!] Keyrox TKL opened but failed status query (rc=%d), reviving...", rc);
            gKeyboardConnected = NO;
            reviveKeyboard("Status query failed");
        }
        return;
    }

    if (!gKeyboardConnected) {
        logMessage("[+] Keyrox TKL connected! (FW: %s, Profile: %u, Mode: %s, Brightness: %u)",
                   fw[0] ? fw : "GK8911M",
                   profile,
                   keyrox_mode_to_string(mode),
                   bright);
        gKeyboardConnected = YES;

        // Auto-configure default lighting if freshly plugged in
        keyrox_device_t *init_dev = keyrox_open();
        if (init_dev) {
            keyrox_set_mode(init_dev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(init_dev, 4);
            keyrox_close(init_dev);
            logMessage("[+] Initialized reconnected keyboard to Wave mode (Brightness: 4)");
        }
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
            reviveKeyboard("CLI manual trigger");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.2]];
            return 0;
        }

        logMessage("Starting Keyrox USB Keep-Alive Watchdog v1.1 (AutoSuspend Prevention + Heartbeat)");
        logMessage("Target: VID 0x1A2C, PID 0x2511 / 0x1511 (Red Square Keyrox TKL)");

        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        createPowerAssertions();

        // Register for Display Sleep & Wake notifications
        NSNotificationCenter *wsCenter = [[NSWorkspace sharedWorkspace] notificationCenter];

        [wsCenter addObserverForName:NSWorkspaceScreensDidWakeNotification
                              object:nil
                               queue:[NSOperationQueue mainQueue]
                          usingBlock:^(NSNotification *note) {
            (void)note;
            logMessage("📺 Display woke up (NSWorkspaceScreensDidWakeNotification)");
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

        // 15-second periodic health check & USB heartbeat
        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            gTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
            (uint64_t)(15.0 * NSEC_PER_SEC),
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
