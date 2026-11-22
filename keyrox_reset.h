#ifndef KEYROX_RESET_H
#define KEYROX_RESET_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Request a reset of the matching Keyrox USB device.
 * Returns 0 if macOS accepted the reset, -1 for an absent device,
 * -2 for client creation failure, or -3 if the reset failed.
 */
int keyrox_usb_bus_reset(void);
int keyrox_usb_reenumerate(void);
bool keyrox_usb_is_present(void);

/* Reset, fall back to USB re-enumeration, and wait for HID. Returns -4 for no HID response. */
int keyrox_revive(void);

#ifdef __cplusplus
}
#endif

#endif /* KEYROX_RESET_H */
