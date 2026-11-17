#ifndef KEYROX_RESET_H
#define KEYROX_RESET_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Sends an electrical USB Bus Reset signal to the Keyrox TKL keyboard (1a2c:2511).
 * Forces the GK8911M microcontroller to reboot, clear endpoint stalls,
 * and re-enumerate with macOS kernel without physically unplugging the cable.
 *
 * Returns:
 *   0 on success
 *  -1 if device not found on USB bus
 *  -2 if IOUSBHostDevice initialization failed
 *  -3 if resetWithError returned failure
 */
int keyrox_usb_bus_reset(void);
bool keyrox_usb_is_present(void);

/* Reset and wait for a valid HID response. Returns -4 if the controller stays unresponsive. */
int keyrox_revive(void);

#ifdef __cplusplus
}
#endif

#endif /* KEYROX_RESET_H */
