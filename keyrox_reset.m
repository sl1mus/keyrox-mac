#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOUSBHost/IOUSBHost.h>
#include "keyrox_reset.h"
#include <stdio.h>

int keyrox_usb_bus_reset(void) {
    @autoreleasepool {
        CFMutableDictionaryRef match = [IOUSBHostDevice
            createMatchingDictionaryWithVendorID:@(0x1a2c)
            productID:@(0x2511)
            bcdDevice:nil
            deviceClass:nil
            deviceSubclass:nil
            deviceProtocol:nil
            speed:nil
            productIDArray:nil];
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
        if (!service) {
            fprintf(stderr, "[-] Keyboard 1a2c:2511 not found on USB bus for reset\n");
            return -1;
        }

        NSError *error = nil;
        IOUSBHostDevice *dev = [[IOUSBHostDevice alloc] initWithIOService:service
                                                                  options:IOUSBHostObjectInitOptionsNone
                                                                    queue:nil
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
