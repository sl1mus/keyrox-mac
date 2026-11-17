#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>
#include "keyrox_reset.h"
#include "keyrox_hid.h"
#include <stdio.h>
#include <unistd.h>

static io_service_t find_keyrox_usb_service(void) {
    @autoreleasepool {
        CFMutableDictionaryRef match = [IOUSBHostDevice
            createMatchingDictionaryWithVendorID:@(KEYROX_VID)
            productID:nil
            bcdDevice:nil
            deviceClass:nil
            deviceSubclass:nil
            deviceProtocol:nil
            speed:nil
            productIDArray:@[@(KEYROX_PID_V2), @(KEYROX_PID_V1)]];
        return match ? IOServiceGetMatchingService(kIOMainPortDefault, match) : IO_OBJECT_NULL;
    }
}

bool keyrox_usb_is_present(void) {
    io_service_t service = find_keyrox_usb_service();
    if (!service) return false;
    IOObjectRelease(service);
    return true;
}

int keyrox_usb_bus_reset(void) {
    @autoreleasepool {
        io_service_t service = find_keyrox_usb_service();
        if (!service) {
            fprintf(stderr, "[-] Keyrox keyboard (1a2c:2511 / 1a2c:1511) not found on USB bus for reset\n");
            return -1;
        }

        dispatch_queue_t queue = dispatch_queue_create("io.github.sl1mus.keyrox.usb-reset", DISPATCH_QUEUE_SERIAL);
        NSError *error = nil;
        IOUSBHostDevice *dev = [[IOUSBHostDevice alloc] initWithIOService:service
                                                                  options:IOUSBHostObjectInitOptionsNone
                                                                    queue:queue
                                                                    error:&error
                                                          interestHandler:nil];
        if (!dev) {
            fprintf(stderr, "[-] Could not create IOUSBHostDevice: %s\n",
                    error ? error.localizedDescription.UTF8String : "unknown error");
            IOObjectRelease(service);
            return -2;
        }

        BOOL ok = [dev resetWithError:&error];
        [dev destroy];
        IOObjectRelease(service);

        if (!ok) {
            fprintf(stderr, "[-] USB Bus Reset failed: %s\n",
                    error ? error.localizedDescription.UTF8String : "unknown error");
            return -3;
        }

        return 0;
    }
}

int keyrox_revive(void) {
    int result = keyrox_usb_bus_reset();
    if (result != 0) return result;

    for (int attempt = 0; attempt < 20; ++attempt) {
        usleep(150000);
        keyrox_device_t *dev = keyrox_open();
        if (!dev) continue;
        int status = keyrox_get_status(dev, NULL, NULL, NULL, NULL, NULL, 0);
        keyrox_close(dev);
        if (status == 0) return 0;
    }

    fprintf(stderr, "[-] USB reset completed, but the Keyrox HID interface did not respond\n");
    return -4;
}
