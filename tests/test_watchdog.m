#define main keyrox_watchdog_main
#define keyrox_usb_is_present forbidden_parent_usb_lookup
#include "../daemon/keyrox-watchdog.m"
#undef keyrox_usb_is_present
#undef main
#include <stdlib.h>

bool forbidden_parent_usb_lookup(void) {
    fputs("FAIL: watchdog parent called the blocking USB registry lookup\n", stderr);
    exit(90);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1) {
            if (strcmp(argv[1], "--probe") == 0) {
                const char *scenario = getenv("KEYROX_TEST_SCENARIO");
                if (scenario && strcmp(scenario, "hang") == 0) {
                    sleep(5);
                    return 1;
                }
                if (scenario && strcmp(scenario, "absent") == 0) return 2;
                if (scenario && strcmp(scenario, "failure") == 0) return 1;
            }
            return 0;
        }
        setenv("KEYROX_TEST_SCENARIO","hang",1);
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        if (runWorker(@"--probe",0.15) != -1 || NSProcessInfo.processInfo.systemUptime-started>2) return 1;
        puts("PASS: stuck USB worker is terminated within its deadline");

        setenv("KEYROX_TEST_SCENARIO","absent",1);
        checkKeyboardHealth();
        if (gKeyboardConnected) return 2;
        setenv("KEYROX_TEST_SCENARIO","healthy",1);
        checkKeyboardHealth();
        if (!gKeyboardConnected) return 3;
        puts("PASS: absence and reconnection are recognized");

        setenv("KEYROX_TEST_SCENARIO","failure",1);
        checkKeyboardHealth();
        if (gKeyboardConnected) return 4;
        checkKeyboardHealth();
        if (gKeyboardConnected) return 5;
        checkKeyboardHealth();
        if (!gKeyboardConnected) return 6;
        puts("PASS: recovery starts after three HID failures");

        gBrightnessSynchronized = YES;
        displaySleepChanged(YES);
        syncDisplayBrightness();
        if (gBrightnessSynchronized) return 7;
        displaySleepChanged(NO);
        syncDisplayBrightness();
        if (gBrightnessSynchronized) return 8;
        usleep(1100000);
        syncDisplayBrightness();
        if (!gBrightnessSynchronized || gDisplayIsSleeping) return 9;
        puts("PASS: rapid screen transitions settle before brightness is applied");
        return 0;
    }
}