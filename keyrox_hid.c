#include "keyrox_hid.h"
#include "keyrox_keys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
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

    /* Specifically select Vendor Control Interface (UsagePage 0xFF00 / 65280).
     * Picking values[0] at random could select mouse (usage 1:2) or standard keyboard (usage 1:6),
     * which reject vendor 64-byte feature reports with 0xe00002d6.
     */
    for (CFIndex i = 0; i < count; i++) {
        IOHIDDeviceRef candidate = (IOHIDDeviceRef)values[i];
        long page = 0;
        CFNumberRef np = (CFNumberRef)IOHIDDeviceGetProperty(candidate, CFSTR(kIOHIDPrimaryUsagePageKey));
        if (np) CFNumberGetValue(np, kCFNumberLongType, &page);
        if (page == KEYROX_USAGE_PAGE) {
            dev_ref = candidate;
            break;
        }
    }
    if (!dev_ref) {
        CFRelease(dev_set);
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
        return NULL;
    }
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

/* Keep SetReport/GetReport pairs indivisible across GUI, CLI and watchdog. */
static int lock_transport(void) {
    char path[128];
    snprintf(path, sizeof(path), "/tmp/keyrox-hid-%u.lock", (unsigned)getuid());
    int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;
    struct stat info;
    if (fstat(fd, &info) != 0 || info.st_uid != getuid() || !S_ISREG(info.st_mode)) {
        close(fd);
        return -1;
    }
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) return fd;
        usleep(10000);
    }
    close(fd);
    return -1;
}

static int send_packet_unlocked(keyrox_device_t *dev, const keyrox_packet_t *pkt) {
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
    usleep(30000); /* 30 ms delay for GK8911M MCU command pacing */
    return 0;
}

int keyrox_send_packet(keyrox_device_t *dev, const keyrox_packet_t *pkt) {
    int fd = lock_transport();
    if (fd < 0) return -1;
    int result = send_packet_unlocked(dev, pkt);
    close(fd);
    return result;
}

static int read_packet_unlocked(keyrox_device_t *dev, uint8_t cmd, uint8_t subcmd, uint32_t offset, void *out_buf, uint16_t req_len) {
    if (!dev || !dev->device || req_len > KEYROX_PAYLOAD_MAX) return -1;

    keyrox_packet_t req;
    keyrox_packet_init(&req, cmd | KEYROX_CMD_READ_FLAG, subcmd, offset, NULL, req_len);
    if (send_packet_unlocked(dev, &req) != 0) {
        return -1;
    }

    usleep(25000); /* 25 ms delay for MCU processing */

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

    const size_t header_size = offsetof(keyrox_packet_t, data);
    if (in_len < (CFIndex)(header_size + req_len)) {
        fprintf(stderr, "[-] Short response received: %ld bytes\n", (long)in_len);
        return -1;
    }

    uint8_t resp_cmd = resp_buf[6];
    if (resp_cmd != (cmd | KEYROX_CMD_READ_FLAG)) {
        fprintf(stderr, "[-] Response opcode mismatch: got 0x%02x, expected 0x%02x\n",
                resp_cmd, (uint8_t)(cmd | KEYROX_CMD_READ_FLAG));
        return -1;
    }

    if (out_buf && req_len > 0) {
        memcpy(out_buf, &resp_buf[header_size], req_len);
    }

    return 0;
}

int keyrox_read_packet(keyrox_device_t *dev, uint8_t cmd, uint8_t subcmd, uint32_t offset, void *out_buf, uint16_t req_len) {
    int fd = lock_transport();
    if (fd < 0) return -1;
    int result = read_packet_unlocked(dev, cmd, subcmd, offset, out_buf, req_len);
    close(fd);
    return result;
}

static int read_effect(keyrox_device_t *dev, uint8_t *effect) {
    if (keyrox_read_packet(dev, KEYROX_CMD_EFFECT, 0, 0, effect, 1) != 0) return -1;
    return keyrox_mode_from_wire(*effect) < 0 ? -1 : 0;
}

static int select_effect(keyrox_device_t *dev, uint8_t effect) {
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_EFFECT, 0, 0, &effect, 1);
    if (keyrox_send_packet(dev, &pkt) != 0) return -1;
    uint8_t active;
    return read_effect(dev, &active) == 0 && active == effect ? 0 : -1;
}

enum { MODE_BRIGHTNESS = 0, MODE_FLAGS = 1, MODE_SPEED = 2, MODE_COLORS = 3, MODE_PARAM_SIZE = 9 };

static int read_mode_params(keyrox_device_t *dev, uint8_t effect, uint8_t params[MODE_PARAM_SIZE]) {
    return keyrox_read_packet(dev, KEYROX_CMD_CUSTOM_LED, effect, 0, params, MODE_PARAM_SIZE);
}

static int write_mode_params(keyrox_device_t *dev, uint8_t effect, const uint8_t params[MODE_PARAM_SIZE]) {
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_CUSTOM_LED, effect, 0, params, MODE_PARAM_SIZE);
    if (keyrox_send_packet(dev, &pkt) != 0) return -1;

    uint8_t actual[MODE_PARAM_SIZE];
    if (read_mode_params(dev, effect, actual) != 0) return -1;
    return memcmp(actual, params, sizeof(actual)) == 0 ? 0 : -1;
}

int keyrox_set_mode(keyrox_device_t *dev, keyrox_mode_t mode, keyrox_direction_t dir) {
    (void)dir;
    if (mode == KEYROX_MODE_OFF) return keyrox_set_brightness(dev, 0);

    int effect = keyrox_mode_to_wire(mode);
    if (effect < 0) return -1;
    return select_effect(dev, (uint8_t)effect);
}

int keyrox_set_brightness(keyrox_device_t *dev, uint8_t level) {
    static const uint8_t levels[] = {0, 32, 64, 96, 127};
    if (level > 4) return -1;
    uint8_t effect, params[MODE_PARAM_SIZE];
    if (read_effect(dev, &effect) != 0 || keyrox_mode_from_wire(effect) == KEYROX_MODE_CUSTOM ||
        read_mode_params(dev, effect, params) != 0) return -1;
    params[MODE_BRIGHTNESS] = levels[level];
    params[MODE_FLAGS] = 0xff;
    return write_mode_params(dev, effect, params);
}

int keyrox_set_speed(keyrox_device_t *dev, uint8_t speed) {
    if (speed > 4) return -1;
    uint8_t effect, params[MODE_PARAM_SIZE];
    if (read_effect(dev, &effect) != 0 || keyrox_mode_from_wire(effect) == KEYROX_MODE_CUSTOM ||
        read_mode_params(dev, effect, params) != 0) return -1;
    params[MODE_SPEED] = (params[MODE_SPEED] & 0xf0) | speed;
    params[MODE_FLAGS] = 0xff;
    return write_mode_params(dev, effect, params);
}

int keyrox_set_direction(keyrox_device_t *dev, keyrox_direction_t dir) {
    static const uint8_t wave_directions[] = {0x10, 0x00, 0x20, 0x30};
    uint8_t effect, params[MODE_PARAM_SIZE];
    if ((unsigned)dir >= sizeof(wave_directions) || read_effect(dev, &effect) != 0) return -1;

    uint8_t direction;
    switch (keyrox_mode_from_wire(effect)) {
        case KEYROX_MODE_WAVE:
            direction = wave_directions[dir];
            break;
        case KEYROX_MODE_RAIN:
        case KEYROX_MODE_ROTATE:
            if (dir != KEYROX_DIR_TOP && dir != KEYROX_DIR_BOTTOM) return -1;
            direction = dir == KEYROX_DIR_TOP ? 0xa0 : 0xb0;
            break;
        default:
            return -1;
    }
    if (read_mode_params(dev, effect, params) != 0) return -1;
    params[MODE_SPEED] = (params[MODE_SPEED] & 0x0f) | direction;
    params[MODE_FLAGS] = 0xff;
    return write_mode_params(dev, effect, params);
}

int keyrox_set_profile(keyrox_device_t *dev, uint8_t profile) {
    if (profile > 4) return -1;
    return select_effect(dev, profile);
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

static const CFStringRef backlight_domain = CFSTR("io.github.sl1mus.keyrox.backlight");

static int save_backlight_data(CFStringRef key, CFDataRef data) {
    CFPreferencesSetAppValue(key, data, backlight_domain);
    return CFPreferencesAppSynchronize(backlight_domain) ? 0 : -1;
}

static CFDataRef copy_backlight_data(CFStringRef key) {
    CFPreferencesAppSynchronize(backlight_domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, backlight_domain);
    if (value && CFGetTypeID(value) != CFDataGetTypeID()) {
        CFRelease(value);
        return NULL;
    }
    return (CFDataRef)value;
}

/* Called under the transport lock so the saved state matches the dimmed frame. */
static int sync_display_brightness_unlocked(keyrox_device_t *dev, bool sleeping) {
    const CFStringRef state_key = CFSTR("DisplaySleepState");
    uint8_t effect;
    if (read_packet_unlocked(dev, KEYROX_CMD_EFFECT, 0, 0, &effect, 1) != 0 ||
        keyrox_mode_from_wire(effect) < 0) return -1;

    CFDataRef state = copy_backlight_data(state_key);
    if (sleeping && state) {
        CFRelease(state);
        return 0;
    }
    if (!sleeping && !state) return 0;

    bool custom = keyrox_mode_from_wire(effect) == KEYROX_MODE_CUSTOM;
    size_t payload_size = custom ? sizeof(keyrox_packet_t) : MODE_PARAM_SIZE;
    uint8_t saved[1 + sizeof(keyrox_packet_t)] = {effect};
    keyrox_packet_t packet;

    if (sleeping) {
        if (custom) {
            CFDataRef matrix = copy_backlight_data(CFSTR("LastMatrixFrame"));
            if (!matrix || CFDataGetLength(matrix) != sizeof(packet)) {
                if (matrix) CFRelease(matrix);
                return -1;
            }
            memcpy(&packet, CFDataGetBytePtr(matrix), sizeof(packet));
            CFRelease(matrix);
            if (packet.cmd != KEYROX_CMD_REMAP || packet.len != KEYROX_MATRIX_FRAME_LENGTH) return -1;
            memcpy(saved + 1, &packet, sizeof(packet));
            for (size_t i = 3; i < KEYROX_MATRIX_FRAME_LENGTH; i += 4) {
                if (packet.data[i] > 32) packet.data[i] = 32;
            }
        } else {
            uint8_t params[MODE_PARAM_SIZE];
            if (read_packet_unlocked(dev, KEYROX_CMD_CUSTOM_LED, effect, 0, params, sizeof(params)) != 0) return -1;
            if (params[MODE_BRIGHTNESS] <= 32) return 0;
            memcpy(saved + 1, params, sizeof(params));
            params[MODE_BRIGHTNESS] = 32;
            keyrox_packet_init(&packet, KEYROX_CMD_CUSTOM_LED, effect, 0, params, sizeof(params));
        }
        state = CFDataCreate(kCFAllocatorDefault, saved, 1 + payload_size);
        if (!state) return -1;
        int persisted = save_backlight_data(state_key, state);
        CFRelease(state);
        if (persisted != 0) return -1;
    } else {
        CFIndex length = CFDataGetLength(state);
        if (length != (CFIndex)(1 + payload_size) || CFDataGetBytePtr(state)[0] != effect) {
            CFRelease(state);
            return save_backlight_data(state_key, NULL);
        }
        memcpy(saved, CFDataGetBytePtr(state), (size_t)length);
        CFRelease(state);
        if (custom) {
            CFDataRef current = copy_backlight_data(CFSTR("LastMatrixFrame"));
            bool changed = !current || CFDataGetLength(current) != sizeof(packet) ||
                memcmp(CFDataGetBytePtr(current), saved + 1, sizeof(packet)) != 0;
            if (current) CFRelease(current);
            if (changed) return save_backlight_data(state_key, NULL);
            memcpy(&packet, saved + 1, sizeof(packet));
        } else {
            uint8_t params[MODE_PARAM_SIZE];
            if (read_packet_unlocked(dev, KEYROX_CMD_CUSTOM_LED, effect, 0, params, sizeof(params)) != 0) return -1;
            /* Keep changes made to the effect while the screen was asleep. */
            if (params[MODE_BRIGHTNESS] != 32) return save_backlight_data(state_key, NULL);
            params[MODE_BRIGHTNESS] = saved[1 + MODE_BRIGHTNESS];
            keyrox_packet_init(&packet, KEYROX_CMD_CUSTOM_LED, effect, 0, params, sizeof(params));
        }
    }

    if (send_packet_unlocked(dev, &packet) != 0) return -1;
    if (!custom) {
        uint8_t actual[MODE_PARAM_SIZE];
        if (read_packet_unlocked(dev, KEYROX_CMD_CUSTOM_LED, effect, 0, actual, sizeof(actual)) != 0 ||
            memcmp(actual, packet.data, sizeof(actual)) != 0) return -1;
    }
    return sleeping ? 0 : save_backlight_data(state_key, NULL);
}

int keyrox_sync_display_brightness(keyrox_device_t *dev, bool sleeping) {
    if (!dev || !dev->device) return -1;
    int fd = lock_transport();
    if (fd < 0) return -1;
    int result = sync_display_brightness_unlocked(dev, sleeping);
    close(fd);
    return result;
}

int keyrox_stream_matrix(keyrox_device_t *dev, const keyrox_color_t *colors, size_t count) {
    if (!dev || !colors || count != KEYROX_TKL_KEY_COUNT) return -1;
    if (select_effect(dev, (uint8_t)keyrox_mode_to_wire(KEYROX_MODE_CUSTOM)) != 0) return -1;
    keyrox_packet_t pkt;
    keyrox_matrix_packet_init(&pkt, colors, count);
    int fd = lock_transport();
    if (fd < 0) return -1;
    int result = send_packet_unlocked(dev, &pkt);
    if (result == 0) {
        CFDataRef frame = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)&pkt, sizeof(pkt));
        if (frame) {
            result = save_backlight_data(CFSTR("LastMatrixFrame"), frame);
            CFRelease(frame);
        } else result = -1;
    }
    close(fd);
    return result;
}

int keyrox_set_mode_colors(keyrox_device_t *dev, keyrox_mode_t mode, uint8_t fg_r, uint8_t fg_g, uint8_t fg_b, uint8_t bg_r, uint8_t bg_g, uint8_t bg_b) {
    int effect = keyrox_mode_to_wire(mode);
    if (effect < 0 || mode == KEYROX_MODE_CUSTOM) return -1;
    uint8_t params[MODE_PARAM_SIZE];
    if (read_mode_params(dev, (uint8_t)effect, params) != 0) return -1;

    const uint8_t colors[] = {fg_r, fg_g, fg_b, bg_r, bg_g, bg_b};
    memcpy(&params[MODE_COLORS], colors, sizeof(colors));
    params[MODE_FLAGS] = 0xff;
    params[MODE_SPEED] &= 0x7f;
    if (select_effect(dev, (uint8_t)effect) != 0) return -1;
    return write_mode_params(dev, (uint8_t)effect, params);
}

int keyrox_set_mode_color(keyrox_device_t *dev, keyrox_mode_t mode, uint8_t r, uint8_t g, uint8_t b) {
    return keyrox_set_mode_colors(dev, mode, r, g, b, 0, 0, 0);
}

int keyrox_set_color(keyrox_device_t *dev, uint8_t r, uint8_t g, uint8_t b) {
    if (keyrox_set_mode_color(dev, KEYROX_MODE_CONST, r, g, b) != 0) return -1;
    return keyrox_set_brightness(dev, 4);
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
    (void)dev; (void)key_index; (void)r; (void)g; (void)b;
    /* GK8911M hardware does not support per-key USB streaming registers.
     * Custom per-key backlight zones are recorded on hardware via Fn + Pause.
     * Do NOT send CMD_05 with key offsets as it corrupts mode table in EEPROM.
     */
    return 0;
}

int keyrox_restore_default_modes(keyrox_device_t *dev) {
    if (!dev) return -1;

    /* Factory default mode parameters for all 18 GK8911M modes */
    static const uint8_t default_table[18][9] = {
        { 0x7f, 0x40, 0x34, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 0: Const (Cyan) */
        { 0x7f, 0xff, 0x34, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* 1: Wave (Rainbow) */
        { 0x7f, 0x40, 0x34, 0x00, 0x80, 0xff, 0x00, 0x00, 0x00 }, /* 2: Cross (Sky Blue) */
        { 0x7f, 0x40, 0x34, 0x00, 0xff, 0x80, 0x00, 0x00, 0x00 }, /* 3: Point (Mint) */
        { 0x7f, 0x40, 0x34, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 4: Custom (White) */
        { 0x7f, 0xff, 0x34, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 }, /* 5: Stars (Yellow) */
        { 0x7f, 0xff, 0x34, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 6: Snow (White) */
        { 0x7f, 0xff, 0x34, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 7: Rain (Cyan) */
        { 0x7f, 0xff, 0x34, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* 8: Spectrum (Cycle) */
        { 0x7f, 0x40, 0x34, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 9: Breathe (Cyan) */
        { 0x7f, 0x40, 0x34, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00 }, /* 10: Line (Green) */
        { 0x7f, 0x40, 0x34, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00 }, /* 11: Plumflower (Magenta) */
        { 0x7f, 0x40, 0x34, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* 12: Heartrate (Red) */
        { 0x7f, 0x40, 0x34, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00 }, /* 13: Shoot (Yellow) */
        { 0x7f, 0xff, 0x34, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* 14: Rotate (Dynamic) */
        { 0x7f, 0xff, 0x34, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00 }, /* 15: Cone (Dynamic) */
        { 0x7f, 0x40, 0x34, 0x00, 0xff, 0xff, 0x00, 0x00, 0x00 }, /* 16: Diffusion (Cyan) */
        { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }  /* 17: Close (Off) */
    };

    for (uint8_t m = 0; m < 18; ++m) {
        int effect = keyrox_mode_to_wire((keyrox_mode_t)m);
        if (effect >= 0 && m != KEYROX_MODE_CUSTOM &&
            write_mode_params(dev, (uint8_t)effect, default_table[m]) != 0) return -1;
    }

    if (keyrox_set_mode(dev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT) != 0 ||
        keyrox_set_brightness(dev, 4) != 0 || keyrox_set_speed(dev, 2) != 0) return -1;
    return keyrox_save_settings(dev);
}

int keyrox_get_status(keyrox_device_t *dev, keyrox_mode_t *out_mode, uint8_t *out_bright, uint8_t *out_speed, uint8_t *out_profile, char *fw_version, size_t fw_ver_len) {
    if (!dev) return -1;

    uint8_t effect;
    if (read_effect(dev, &effect) != 0) return -1;
    keyrox_mode_t mode = (keyrox_mode_t)keyrox_mode_from_wire(effect);

    uint8_t params[MODE_PARAM_SIZE] = {0};
    if ((out_bright || out_speed) && mode != KEYROX_MODE_CUSTOM &&
        read_mode_params(dev, effect, params) != 0) return -1;

    if (out_mode) *out_mode = mode;
    if (out_profile) *out_profile = effect < 4 ? effect : KEYROX_NO_PRESET;
    if (out_bright) {
        const uint8_t raw = params[MODE_BRIGHTNESS];
        if (mode == KEYROX_MODE_CUSTOM) *out_bright = 4;
        else if (raw == 0) *out_bright = 0;
        else if (raw < 48) *out_bright = 1;
        else if (raw < 80) *out_bright = 2;
        else if (raw < 112) *out_bright = 3;
        else *out_bright = 4;
    }
    if (out_speed) {
        const uint8_t raw = params[MODE_SPEED] & 0x0f;
        *out_speed = raw > 4 ? 4 : raw;
    }

    /* 4. Read Device Info (FW version) */
    if (fw_version && fw_ver_len > 0) {
        uint8_t dev_info[90] = {0};
        if (keyrox_read_packet(dev, KEYROX_CMD_DEV_INFO, 0, 0, dev_info, sizeof(dev_info)) == 0) {
            char found_str[64] = {0};
            for (size_t i = 0; i < sizeof(dev_info) - 8; ++i) {
                if (dev_info[i] == 'G' && dev_info[i+1] == 'K' && dev_info[i+2] == '8') {
                    size_t available = sizeof(dev_info) - i;
                    size_t copied = available < sizeof(found_str) - 1 ? available : sizeof(found_str) - 1;
                    memcpy(found_str, &dev_info[i], copied);
                    break;
                }
            }
            if (found_str[0]) {
                snprintf(fw_version, fw_ver_len, "%s", found_str);
            } else {
                snprintf(fw_version, fw_ver_len, "GK8911M");
            }
        } else {
            snprintf(fw_version, fw_ver_len, "GK8911M");
        }
    }

    return 0;
}
