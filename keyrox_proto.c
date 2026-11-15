#include "keyrox_proto.h"
#include "keyrox_keys.h"
#include <string.h>
#include <strings.h>
#include <stdlib.h>

static const char *s_mode_names[KEYROX_MODE_COUNT] = {
    [KEYROX_MODE_CONST]            = "const",
    [KEYROX_MODE_WAVE]             = "wave",
    [KEYROX_MODE_CROSS]            = "cross",
    [KEYROX_MODE_POINT]            = "point",
    [KEYROX_MODE_CUSTOM]           = "custom",
    [KEYROX_MODE_STARS]            = "stars",
    [KEYROX_MODE_SNOW]             = "snow",
    [KEYROX_MODE_RAIN]             = "rain",
    [KEYROX_MODE_SPECTRUM]         = "spectrum",
    [KEYROX_MODE_BREATHE]          = "breathe",
    [KEYROX_MODE_LINE_DIFFUSION]   = "line_diff",
    [KEYROX_MODE_PLUMFLOWER]       = "plumflower",
    [KEYROX_MODE_HEARTRATE]        = "heartrate",
    [KEYROX_MODE_SHOOT]            = "shoot",
    [KEYROX_MODE_ROTATE]           = "rotate",
    [KEYROX_MODE_RECT_CONE]        = "rect_cone",
    [KEYROX_MODE_CIRCLE_DIFFUSION] = "circle_diff",
    [KEYROX_MODE_OFF]              = "off",
    [KEYROX_MODE_MULTILAYER]       = "multilayer",
    [KEYROX_MODE_MULTIZONE]        = "multizone"
};

void keyrox_packet_init(keyrox_packet_t *pkt, uint8_t cmd, uint8_t subcmd, uint32_t offset, const void *data, uint16_t len) {
    if (!pkt) return;
    memset(pkt, 0, sizeof(keyrox_packet_t));
    pkt->report_id = 0x00;
    if (len > KEYROX_PAYLOAD_MAX) {
        len = KEYROX_PAYLOAD_MAX;
    }
    pkt->len = len;
    pkt->cmd = cmd;
    pkt->subcmd = subcmd;
    pkt->offset = offset;
    if (data && len > 0) {
        memcpy(pkt->data, data, len);
    }
}

const char *keyrox_mode_to_string(keyrox_mode_t mode) {
    if ((int)mode >= 0 && (int)mode < KEYROX_MODE_COUNT) {
        return s_mode_names[mode];
    }
    return "unknown";
}

int keyrox_string_to_mode(const char *str) {
    if (!str) return -1;
    char *endptr = NULL;
    long val = strtol(str, &endptr, 10);
    if (endptr != str && *endptr == '\0') {
        if (val >= 0 && val < KEYROX_MODE_COUNT) {
            return (int)val;
        }
        return -1;
    }

    for (int i = 0; i < KEYROX_MODE_COUNT; ++i) {
        if (s_mode_names[i] && strcasecmp(str, s_mode_names[i]) == 0) {
            return i;
        }
    }

    /* Aliases */
    if (strcasecmp(str, "static") == 0) return KEYROX_MODE_CONST;
    if (strcasecmp(str, "rainbow") == 0) return KEYROX_MODE_WAVE;
    if (strcasecmp(str, "cycle") == 0) return KEYROX_MODE_SPECTRUM;
    if (strcasecmp(str, "close") == 0) return KEYROX_MODE_OFF;
    if (strcasecmp(str, "radar") == 0) return KEYROX_MODE_RECT_CONE;
    if (strcasecmp(str, "ripple") == 0) return KEYROX_MODE_CIRCLE_DIFFUSION;

    return -1;
}

void keyrox_matrix_packet_init(keyrox_packet_t *pkt, const keyrox_color_t *colors, size_t count) {
    if (!pkt) return;
    memset(pkt, 0, sizeof(keyrox_packet_t));
    uint8_t *raw = (uint8_t *)pkt;
    raw[0] = 0x00; /* Report ID */
    raw[5] = KEYROX_CMD_MATRIX_STREAM; /* 0xB0 */
    raw[6] = 0x01;
    raw[7] = 0x07;

    if (!colors || count == 0) return;

    size_t n = count > KEYROX_TKL_KEY_COUNT ? KEYROX_TKL_KEY_COUNT : count;
    for (size_t i = 0; i < n; i++) {
        uint8_t pos = KEYROX_LED_POSITIONS[i];
        size_t off = 8 + (size_t)pos * 4;
        if (off + 3 < KEYROX_REPORT_SIZE) {
            raw[off + 0] = colors[i].r;
            raw[off + 1] = colors[i].g;
            raw[off + 2] = colors[i].b;
            raw[off + 3] = colors[i].brightness;
        }
    }
}
