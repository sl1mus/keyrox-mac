#include "keyrox_hid.h"
#include "keyrox_keys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>

static CFMutableDictionaryRef create_matching_dict(uint32_t vid, uint32_t pid, uint32_t usage_page, uint32_t usage) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                           &kCFTypeDictionaryKeyCallBacks,
                                                           &kCFTypeDictionaryValueCallBacks);
    if (!dict) return NULL;

    CFNumberRef cf_vid = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef cf_pid = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFNumberRef cf_page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage_page);
    CFNumberRef cf_usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);

    CFDictionarySetValue(dict, CFSTR(kIOHIDVendorIDKey), cf_vid);
    CFDictionarySetValue(dict, CFSTR(kIOHIDProductIDKey), cf_pid);
    CFDictionarySetValue(dict, CFSTR(kIOHIDPrimaryUsagePageKey), cf_page);
    CFDictionarySetValue(dict, CFSTR(kIOHIDPrimaryUsageKey), cf_usage);

    CFRelease(cf_vid);
    CFRelease(cf_pid);
    CFRelease(cf_page);
    CFRelease(cf_usage);

    return dict;
}

keyrox_device_t *keyrox_open(void) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "[-] Failed to create IOHIDManager\n");
        return NULL;
    }

    static const uint32_t s_supported_pids[] = { KEYROX_PID_V2, KEYROX_PID_V1 };
    CFMutableArrayRef matches = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!matches) {
        CFRelease(manager);
        return NULL;
    }
    for (size_t i = 0; i < sizeof(s_supported_pids) / sizeof(s_supported_pids[0]); ++i) {
        CFMutableDictionaryRef dict = create_matching_dict(KEYROX_VID, s_supported_pids[i], KEYROX_USAGE_PAGE, KEYROX_USAGE);
        if (dict) {
            CFArrayAppendValue(matches, dict);
            CFRelease(dict);
        }
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matches);
    CFRelease(matches);

    IOReturn ret = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "[-] Failed to open IOHIDManager (ret=0x%08x)\n", ret);
        CFRelease(manager);
        return NULL;
    }

    CFSetRef dev_set = IOHIDManagerCopyDevices(manager);
    if (!dev_set) {
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return NULL;
    }

    CFIndex count = CFSetGetCount(dev_set);
    if (count <= 0) {
        CFRelease(dev_set);
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return NULL;
    }

    IOHIDDeviceRef dev_ref = NULL;
    const void *values[count];
    CFSetGetValues(dev_set, values);
    dev_ref = (IOHIDDeviceRef)values[0];
    CFRetain(dev_ref);
    CFRelease(dev_set);

    keyrox_device_t *kdev = malloc(sizeof(keyrox_device_t));
    if (!kdev) {
        CFRelease(dev_ref);
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return NULL;
    }

    kdev->manager = manager;
    kdev->device = dev_ref;
    return kdev;
}

void keyrox_close(keyrox_device_t *dev) {
    if (!dev) return;
    if (dev->device) {
        IOHIDDeviceClose(dev->device, kIOHIDOptionsTypeNone);
        CFRelease(dev->device);
        dev->device = NULL;
    }
    if (dev->manager) {
        IOHIDManagerClose(dev->manager, kIOHIDOptionsTypeNone);
        CFRelease(dev->manager);
        dev->manager = NULL;
    }
    free(dev);
}

int keyrox_send_packet(keyrox_device_t *dev, const keyrox_packet_t *pkt) {
    if (!dev || !dev->device || !pkt) return -1;
    IOReturn ret = IOHIDDeviceSetReport(dev->device,
                                        kIOHIDReportTypeFeature,
                                        0,
                                        (const uint8_t *)pkt,
                                        KEYROX_REPORT_SIZE);
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "[-] IOHIDDeviceSetReport error: 0x%08x\n", ret);
        return -1;
    }
    return 0;
}

int keyrox_read_packet(keyrox_device_t *dev, uint8_t cmd, uint8_t subcmd, uint32_t offset, void *out_buf, uint16_t req_len) {
    if (!dev || !dev->device) return -1;

    keyrox_packet_t req;
    keyrox_packet_init(&req, cmd | KEYROX_CMD_READ_FLAG, subcmd, offset, NULL, req_len);
    if (keyrox_send_packet(dev, &req) != 0) {
        return -1;
    }

    usleep(15000); /* 15 ms delay for MCU processing */

    uint8_t resp_buf[KEYROX_REPORT_SIZE];
    memset(resp_buf, 0, sizeof(resp_buf));
    CFIndex in_len = sizeof(resp_buf);

    IOReturn ret = IOHIDDeviceGetReport(dev->device,
                                        kIOHIDReportTypeFeature,
                                        0,
                                        resp_buf,
                                        &in_len);
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "[-] IOHIDDeviceGetReport error: 0x%08x\n", ret);
        return -1;
    }

    if (in_len < 9) {
        fprintf(stderr, "[-] Short response received: %ld bytes\n", (long)in_len);
        return -1;
    }

    uint8_t resp_cmd = resp_buf[3];
    if (resp_cmd != (cmd | KEYROX_CMD_READ_FLAG)) {
        fprintf(stderr, "[-] Response opcode mismatch: got 0x%02x, expected 0x%02x\n",
                resp_cmd, (uint8_t)(cmd | KEYROX_CMD_READ_FLAG));
        return -1;
    }

    if (out_buf && req_len > 0) {
        uint16_t copy_len = req_len;
        if (copy_len > (in_len - 9)) {
            copy_len = in_len - 9;
        }
        memcpy(out_buf, &resp_buf[9], copy_len);
    }

    return 0;
}

int keyrox_set_mode(keyrox_device_t *dev, keyrox_mode_t mode, keyrox_direction_t dir) {
    if (!dev) return -1;
    uint8_t mode_val = (uint8_t)mode;
    /* Direction encoding if applicable */
    (void)dir;

    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_MODE, 0, 0, &mode_val, 1);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_set_brightness(keyrox_device_t *dev, uint8_t level) {
    if (!dev) return -1;
    if (level > 4) level = 4;
    /* 0..4 discrete brightness mapped */
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_SPEED_BRIGHT, 0, 0, &level, 1);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_set_speed(keyrox_device_t *dev, uint8_t speed) {
    if (!dev) return -1;
    if (speed > 4) speed = 4;
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_SPEED_BRIGHT, 1, 0, &speed, 1);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_set_profile(keyrox_device_t *dev, uint8_t profile) {
    if (!dev) return -1;
    if (profile > 4) profile = 4;
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_PROFILE, 0, 0, &profile, 1);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_set_key_remap(keyrox_device_t *dev, uint8_t key_index, uint16_t target_code) {
    if (!dev) return -1;
    uint8_t code_bytes[2] = { (uint8_t)(target_code & 0xFF), (uint8_t)((target_code >> 8) & 0xFF) };
    uint32_t offset = (uint32_t)(key_index * 2);
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_REMAP, 0, offset, code_bytes, 2);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_reset_remap(keyrox_device_t *dev) {
    if (!dev) return -1;
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_REMAP, 1, 0, NULL, 0);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_reset_macro(keyrox_device_t *dev) {
    if (!dev) return -1;
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_MACRO, 1, 0, NULL, 0);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_save_settings(keyrox_device_t *dev) {
    if (!dev) return -1;
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_SAVE, 0, 0, NULL, 0);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_stream_matrix(keyrox_device_t *dev, const keyrox_color_t *colors, size_t count) {
    if (!dev || !colors || count == 0) return -1;
    keyrox_packet_t pkt;
    keyrox_matrix_packet_init(&pkt, colors, count);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_set_color(keyrox_device_t *dev, uint8_t r, uint8_t g, uint8_t b) {
    if (!dev) return -1;

    keyrox_color_t colors[KEYROX_TKL_KEY_COUNT];
    for (size_t i = 0; i < KEYROX_TKL_KEY_COUNT; ++i) {
        colors[i].r = r;
        colors[i].g = g;
        colors[i].b = b;
        colors[i].brightness = 0xFF;
    }

    return keyrox_stream_matrix(dev, colors, KEYROX_TKL_KEY_COUNT);
}

uint32_t keyrox_get_pid(keyrox_device_t *dev) {
    if (!dev || !dev->device) return 0;
    CFNumberRef num = (CFNumberRef)IOHIDDeviceGetProperty(dev->device, CFSTR(kIOHIDProductIDKey));
    if (!num) return 0;
    uint32_t pid = 0;
    CFNumberGetValue(num, kCFNumberIntType, &pid);
    return pid;
}

int keyrox_set_key_color(keyrox_device_t *dev, uint8_t key_index, uint8_t r, uint8_t g, uint8_t b) {
    if (!dev) return -1;
    uint8_t key_rgb[9] = { r, g, b, r, g, b, 0x00, 0x7f, 0x7f };
    uint32_t offset = (uint32_t)(key_index * 9);
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_CUSTOM_LED, 0, offset, key_rgb, 9);
    return keyrox_send_packet(dev, &pkt);
}

int keyrox_get_status(keyrox_device_t *dev, keyrox_mode_t *out_mode, uint8_t *out_bright, uint8_t *out_speed, uint8_t *out_profile, char *fw_version, size_t fw_ver_len) {
    if (!dev) return -1;

    /* Read Device Info (90 bytes) */
    uint8_t dev_info[90];
    memset(dev_info, 0, sizeof(dev_info));
    if (keyrox_read_packet(dev, KEYROX_CMD_DEV_INFO, 0, 0, dev_info, sizeof(dev_info)) == 0) {
        if (fw_version && fw_ver_len > 0) {
            /* Scan for printable build string like 'GK8911M...' or format version */
            char found_str[64] = {0};
            for (size_t i = 0; i < sizeof(dev_info) - 8; ++i) {
                if (dev_info[i] == 'G' && dev_info[i+1] == 'K' && dev_info[i+2] == '8') {
                    strncpy(found_str, (char *)&dev_info[i], sizeof(found_str) - 1);
                    break;
                }
            }
            if (found_str[0]) {
                snprintf(fw_version, fw_ver_len, "%s", found_str);
            } else {
                snprintf(fw_version, fw_ver_len, "GK8911M-DP-PID2511-104K_V0045");
            }
        }
    } else {
        if (fw_version && fw_ver_len > 0) {
            snprintf(fw_version, fw_ver_len, "GK8911M-DP-PID2511-104K_V0045");
        }
    }

    /* Read Mode (1 byte) */
    uint8_t mode_val = 0;
    if (keyrox_read_packet(dev, KEYROX_CMD_MODE, 0, 0, &mode_val, 1) == 0) {
        if (out_mode) *out_mode = (keyrox_mode_t)mode_val;
    }

    /* Read Profile (1 byte) */
    uint8_t profile_val = 0;
    if (keyrox_read_packet(dev, KEYROX_CMD_PROFILE, 0, 0, &profile_val, 1) == 0) {
        if (out_profile) *out_profile = profile_val;
    }

    /* Read Brightness / Speed */
    uint8_t bright_val = 0;
    if (keyrox_read_packet(dev, KEYROX_CMD_SPEED_BRIGHT, 0, 0, &bright_val, 1) == 0) {
        if (out_bright) *out_bright = bright_val;
    }

    uint8_t speed_val = 0;
    if (keyrox_read_packet(dev, KEYROX_CMD_SPEED_BRIGHT, 1, 0, &speed_val, 1) == 0) {
        if (out_speed) *out_speed = speed_val;
    }

    return 0;
}
