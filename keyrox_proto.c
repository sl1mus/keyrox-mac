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
    if (len > KEYROX_PAYLOAD_MAX) {
        len = KEYROX_PAYLOAD_MAX;
    }
    pkt->offset = offset;
    pkt->len = len;
    pkt->cmd = cmd;
    pkt->subcmd = subcmd;
    if (data && len > 0) {
        memcpy(pkt->data, data, len);
    }
}

/* Hardware selector values for 1a2c:1511 and 1a2c:2511.
 * The CLI and GUI keep their existing mode IDs. */
static const keyrox_mode_t effects_by_wire[] = {
    KEYROX_MODE_WAVE, KEYROX_MODE_CONST, KEYROX_MODE_BREATHE,
    KEYROX_MODE_HEARTRATE, KEYROX_MODE_POINT, KEYROX_MODE_RAIN,
    KEYROX_MODE_STARS, KEYROX_MODE_SPECTRUM, KEYROX_MODE_PLUMFLOWER,
    KEYROX_MODE_SHOOT, KEYROX_MODE_ROTATE, KEYROX_MODE_CIRCLE_DIFFUSION,
    KEYROX_MODE_CUSTOM
};

int keyrox_mode_to_wire(keyrox_mode_t mode) {
    for (size_t i = 0; i < sizeof(effects_by_wire) / sizeof(effects_by_wire[0]); ++i) {
        if (effects_by_wire[i] == mode) return (int)i;
    }
    return -1;
}

int keyrox_mode_from_wire(uint8_t wire) {
    if (wire >= sizeof(effects_by_wire) / sizeof(effects_by_wire[0])) return -1;
    return effects_by_wire[wire];
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
    pkt->cmd = KEYROX_CMD_REMAP;
    pkt->len = KEYROX_MATRIX_FRAME_LENGTH;

    if (!colors || count == 0) return;

    size_t n = count > KEYROX_TKL_KEY_COUNT ? KEYROX_TKL_KEY_COUNT : count;
    for (size_t i = 0; i < n; i++) {
        uint8_t pos = KEYROX_LED_POSITIONS[i];
        size_t off = (size_t)pos * 4;
        if (off + 3 < KEYROX_PAYLOAD_MAX) {
            pkt->data[off + 0] = colors[i].r;
            pkt->data[off + 1] = colors[i].g;
            pkt->data[off + 2] = colors[i].b;
            pkt->data[off + 3] = colors[i].brightness;
        }
    }
}
