#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "../keyrox_proto.h"

static int g_tests_run = 0;
static int g_tests_passed = 0;

#define TEST(name) static void name(void)
#define RUN_TEST(name) do { \
    printf("  [RUN] %s...", #name); \
    name(); \
    g_tests_run++; \
    g_tests_passed++; \
    printf(" \033[32mPASS\033[0m\n"); \
} while(0)

TEST(test_packet_struct_size) {
    /* Keyrox HID packet must be exactly 520 bytes (offset:4, len:2, cmd:1, subcmd:1, data:512) */
    assert(sizeof(keyrox_packet_t) == KEYROX_REPORT_SIZE);
    assert(sizeof(keyrox_packet_t) == 520);
}

TEST(test_packet_init_basic) {
    keyrox_packet_t pkt;
    uint8_t payload[4] = {0x01, 0x02, 0x03, 0x04};
    keyrox_packet_init(&pkt, KEYROX_CMD_MODE, 0x01, 0x12345678, payload, sizeof(payload));

    assert(pkt.cmd == KEYROX_CMD_MODE);
    assert(pkt.subcmd == 0x01);
    assert(pkt.offset == 0x12345678);
    assert(pkt.len == 4);
    assert(memcmp(pkt.data, payload, 4) == 0);
    assert(pkt.data[4] == 0x00); /* Rest should be zeroed */

    /* Verify wire layout offsets */
    uint8_t *raw = (uint8_t *)&pkt;
    assert(raw[0] == 0x78 && raw[1] == 0x56 && raw[2] == 0x34 && raw[3] == 0x12); /* offset */
    assert(raw[4] == 0x04 && raw[5] == 0x00); /* len */
    assert(raw[6] == KEYROX_CMD_MODE); /* cmd */
    assert(raw[7] == 0x01); /* subcmd */
    assert(raw[8] == 0x01 && raw[9] == 0x02 && raw[10] == 0x03 && raw[11] == 0x04); /* data */
}

TEST(test_packet_init_payload_clamp) {
    keyrox_packet_t pkt;
    uint8_t large_payload[600];
    memset(large_payload, 0xAA, sizeof(large_payload));

    keyrox_packet_init(&pkt, KEYROX_CMD_CUSTOM_LED, 0, 0, large_payload, 600);
    assert(pkt.len == KEYROX_PAYLOAD_MAX);
    assert(pkt.data[0] == 0xAA);
    assert(pkt.data[KEYROX_PAYLOAD_MAX - 1] == 0xAA);
}

TEST(test_packet_init_null_data) {
    keyrox_packet_t pkt;
    keyrox_packet_init(&pkt, KEYROX_CMD_DEV_INFO, 0, 0, NULL, 0);

    assert(pkt.cmd == KEYROX_CMD_DEV_INFO);
    assert(pkt.len == 0);
}

TEST(test_mode_to_string_all_modes) {
    for (int m = 0; m < KEYROX_MODE_COUNT; ++m) {
        const char *name = keyrox_mode_to_string((keyrox_mode_t)m);
        assert(name != NULL);
        assert(strcmp(name, "unknown") != 0);
    }
    assert(strcmp(keyrox_mode_to_string((keyrox_mode_t)-1), "unknown") == 0);
    assert(strcmp(keyrox_mode_to_string((keyrox_mode_t)KEYROX_MODE_COUNT), "unknown") == 0);
    assert(strcmp(keyrox_mode_to_string((keyrox_mode_t)999), "unknown") == 0);
}

TEST(test_string_to_mode_names_and_numeric) {
    assert(keyrox_string_to_mode("const") == KEYROX_MODE_CONST);
    assert(keyrox_string_to_mode("wave") == KEYROX_MODE_WAVE);
    assert(keyrox_string_to_mode("spectrum") == KEYROX_MODE_SPECTRUM);
    assert(keyrox_string_to_mode("off") == KEYROX_MODE_OFF);
    assert(keyrox_string_to_mode("multizone") == KEYROX_MODE_MULTIZONE);

    /* Numeric string parsing */
    assert(keyrox_string_to_mode("0") == KEYROX_MODE_CONST);
    assert(keyrox_string_to_mode("1") == KEYROX_MODE_WAVE);
    assert(keyrox_string_to_mode("19") == KEYROX_MODE_MULTIZONE);
    assert(keyrox_string_to_mode("20") == -1);
    assert(keyrox_string_to_mode("-1") == -1);
}

TEST(test_string_to_mode_case_insensitive) {
    assert(keyrox_string_to_mode("WAVE") == KEYROX_MODE_WAVE);
    assert(keyrox_string_to_mode("Wave") == KEYROX_MODE_WAVE);
    assert(keyrox_string_to_mode("SpEcTrUm") == KEYROX_MODE_SPECTRUM);
}

TEST(test_string_to_mode_aliases) {
    assert(keyrox_string_to_mode("static") == KEYROX_MODE_CONST);
    assert(keyrox_string_to_mode("STATIC") == KEYROX_MODE_CONST);
    assert(keyrox_string_to_mode("rainbow") == KEYROX_MODE_WAVE);
    assert(keyrox_string_to_mode("cycle") == KEYROX_MODE_SPECTRUM);
    assert(keyrox_string_to_mode("close") == KEYROX_MODE_OFF);
    assert(keyrox_string_to_mode("radar") == KEYROX_MODE_RECT_CONE);
    assert(keyrox_string_to_mode("ripple") == KEYROX_MODE_CIRCLE_DIFFUSION);
}

TEST(test_string_to_mode_invalid) {
    assert(keyrox_string_to_mode(NULL) == -1);
    assert(keyrox_string_to_mode("") == -1);
    assert(keyrox_string_to_mode("not_a_mode") == -1);
    assert(keyrox_string_to_mode("123bad") == -1);
}

TEST(test_multi_pid_definitions) {
    assert(KEYROX_VID == 0x1a2c);
    assert(KEYROX_PID_V2 == 0x2511);
    assert(KEYROX_PID_V1 == 0x1511);
    assert(KEYROX_PID == KEYROX_PID_V2);
}

TEST(test_matrix_stream_packet) {
    keyrox_packet_t pkt;
    keyrox_color_t colors[87];
    for (int i = 0; i < 87; i++) {
        colors[i].r = (uint8_t)(i + 1);
        colors[i].g = (uint8_t)(i + 2);
        colors[i].b = (uint8_t)(i + 3);
        colors[i].brightness = 0x80;
    }

    keyrox_matrix_packet_init(&pkt, colors, 87);

    assert(pkt.cmd == KEYROX_CMD_MATRIX_STREAM);
    assert(pkt.cmd == 0xB0);
    assert(pkt.subcmd == 0x01);
    assert(pkt.len == KEYROX_PAYLOAD_MAX);

    /* First key (Esc, pos = 0) -> pkt.data[0..3] */
    assert(pkt.data[0] == 1);
    assert(pkt.data[1] == 2);
    assert(pkt.data[2] == 3);
    assert(pkt.data[3] == 0x80);

    /* Null pointer safety */
    keyrox_matrix_packet_init(&pkt, NULL, 0);
    assert(pkt.cmd == 0xB0);
}

int main(void) {
    printf("\n=== Running Keyrox Protocol Unit Tests ===\n");
    RUN_TEST(test_packet_struct_size);
    RUN_TEST(test_packet_init_basic);
    RUN_TEST(test_packet_init_payload_clamp);
    RUN_TEST(test_packet_init_null_data);
    RUN_TEST(test_mode_to_string_all_modes);
    RUN_TEST(test_string_to_mode_names_and_numeric);
    RUN_TEST(test_string_to_mode_case_insensitive);
    RUN_TEST(test_string_to_mode_aliases);
    RUN_TEST(test_string_to_mode_invalid);
    RUN_TEST(test_multi_pid_definitions);
    RUN_TEST(test_matrix_stream_packet);

    printf("\n\033[32m✔ All %d tests passed successfully!\033[0m\n\n", g_tests_passed);
    return 0;
}
