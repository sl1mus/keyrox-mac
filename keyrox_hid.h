#ifndef KEYROX_HID_H
#define KEYROX_HID_H

#include "keyrox_proto.h"
#include <IOKit/hid/IOHIDManager.h>

typedef struct {
    IOHIDManagerRef manager;
    IOHIDDeviceRef  device;
} keyrox_device_t;

/* Lifecycle */
keyrox_device_t *keyrox_open(void);
void keyrox_close(keyrox_device_t *dev);

/* Low-level HID transfer */
int keyrox_send_packet(keyrox_device_t *dev, const keyrox_packet_t *pkt);
int keyrox_read_packet(keyrox_device_t *dev, uint8_t cmd, uint8_t subcmd, uint32_t offset, void *out_buf, uint16_t req_len);

/* High-level control commands */
int keyrox_set_mode(keyrox_device_t *dev, keyrox_mode_t mode, keyrox_direction_t dir);
int keyrox_set_brightness(keyrox_device_t *dev, uint8_t level);
int keyrox_set_speed(keyrox_device_t *dev, uint8_t speed);
int keyrox_set_color(keyrox_device_t *dev, uint8_t r, uint8_t g, uint8_t b);
int keyrox_set_mode_color(keyrox_device_t *dev, keyrox_mode_t mode, uint8_t r, uint8_t g, uint8_t b);
int keyrox_set_mode_colors(keyrox_device_t *dev, keyrox_mode_t mode, uint8_t fg_r, uint8_t fg_g, uint8_t fg_b, uint8_t bg_r, uint8_t bg_g, uint8_t bg_b);
int keyrox_set_key_color(keyrox_device_t *dev, uint8_t key_index, uint8_t r, uint8_t g, uint8_t b);
int keyrox_stream_matrix(keyrox_device_t *dev, const keyrox_color_t *colors, size_t count);
uint32_t keyrox_get_pid(keyrox_device_t *dev);
int keyrox_set_profile(keyrox_device_t *dev, uint8_t profile);
int keyrox_set_key_remap(keyrox_device_t *dev, uint8_t key_index, uint16_t target_code);
int keyrox_reset_remap(keyrox_device_t *dev);
int keyrox_reset_macro(keyrox_device_t *dev);
int keyrox_save_settings(keyrox_device_t *dev);
int keyrox_restore_default_modes(keyrox_device_t *dev);
int keyrox_get_status(keyrox_device_t *dev, keyrox_mode_t *out_mode, uint8_t *out_bright, uint8_t *out_speed, uint8_t *out_profile, char *fw_version, size_t fw_ver_len);

#endif /* KEYROX_HID_H */
