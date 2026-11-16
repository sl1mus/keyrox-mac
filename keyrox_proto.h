#ifndef KEYROX_PROTO_H
#define KEYROX_PROTO_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#define KEYROX_VID             0x1a2c
#define KEYROX_PID             0x2511  /* Keyrox TKL V2 (default) */
#define KEYROX_PID_V2          0x2511  /* Keyrox TKL V2 (G3ms Sapphire) */
#define KEYROX_PID_V1          0x1511  /* Keyrox TKL V1 (Gateron / Outemu) */
#define KEYROX_USAGE_PAGE      0xff00
#define KEYROX_USAGE           0x0002
#define KEYROX_REPORT_SIZE     520
#define KEYROX_PAYLOAD_MAX     512

/* Command Opcodes */
#define KEYROX_CMD_DEV_INFO      0x01
#define KEYROX_CMD_CONFIG        0x02
#define KEYROX_CMD_CAPS          0x03
#define KEYROX_CMD_PROFILE       0x04
#define KEYROX_CMD_CUSTOM_LED    0x05
#define KEYROX_CMD_SPEED_BRIGHT  0x06
#define KEYROX_CMD_REMAP         0x07
#define KEYROX_CMD_MODE          0x08
#define KEYROX_CMD_SAVE          0x09
#define KEYROX_CMD_MACRO         0x0A
#define KEYROX_CMD_MATRIX_STREAM 0xB0

/* Read mask */
#define KEYROX_CMD_READ_FLAG    0x80

/* Lighting Modes (from kbpanel.xml) */
typedef enum {
    KEYROX_MODE_CONST            = 0,
    KEYROX_MODE_WAVE             = 1,
    KEYROX_MODE_CROSS            = 2,
    KEYROX_MODE_POINT            = 3,
    KEYROX_MODE_CUSTOM           = 4,
    KEYROX_MODE_STARS            = 5,
    KEYROX_MODE_SNOW             = 6,
    KEYROX_MODE_RAIN             = 7,
    KEYROX_MODE_SPECTRUM         = 8,
    KEYROX_MODE_BREATHE          = 9,
    KEYROX_MODE_LINE_DIFFUSION   = 10,
    KEYROX_MODE_PLUMFLOWER       = 11,
    KEYROX_MODE_HEARTRATE        = 12,
    KEYROX_MODE_SHOOT            = 13,
    KEYROX_MODE_ROTATE           = 14,
    KEYROX_MODE_RECT_CONE        = 15,
    KEYROX_MODE_CIRCLE_DIFFUSION = 16,
    KEYROX_MODE_OFF              = 17,
    KEYROX_MODE_MULTILAYER       = 18,
    KEYROX_MODE_MULTIZONE        = 19,
    KEYROX_MODE_COUNT            = 20
} keyrox_mode_t;

/* Directions */
typedef enum {
    KEYROX_DIR_LEFT              = 0,
    KEYROX_DIR_RIGHT             = 1,
    KEYROX_DIR_TOP               = 2,
    KEYROX_DIR_BOTTOM            = 3,
    KEYROX_DIR_CLOCKWISE         = 0,
    KEYROX_DIR_ANTICLOCKWISE     = 1
} keyrox_direction_t;

/* Packet Layout (520 bytes total wire format) */
#pragma pack(push, 1)
typedef struct {
    uint32_t offset;     /* Bytes 0..3: Param / Offset (LE) */
    uint16_t len;        /* Bytes 4..5: Payload length in bytes (LE) */
    uint8_t  cmd;        /* Byte 6: Command ID */
    uint8_t  subcmd;     /* Byte 7: Subcommand / Index */
    uint8_t  data[KEYROX_PAYLOAD_MAX]; /* Bytes 8..519: Payload buffer */
} keyrox_packet_t;
#pragma pack(pop)

/* RGB color struct */
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} keyrox_rgb_t;

/* Per-key color with alpha brightness struct */
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t brightness; /* 0x00..0xFF (Alpha) */
} keyrox_color_t;

/* Helper functions */
void keyrox_packet_init(keyrox_packet_t *pkt, uint8_t cmd, uint8_t subcmd, uint32_t offset, const void *data, uint16_t len);
void keyrox_matrix_packet_init(keyrox_packet_t *pkt, const keyrox_color_t *colors, size_t count);
const char *keyrox_mode_to_string(keyrox_mode_t mode);
int keyrox_string_to_mode(const char *str);

#endif /* KEYROX_PROTO_H */
