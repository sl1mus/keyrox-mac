#ifndef KEYROX_KEYS_H
#define KEYROX_KEYS_H

#include <stdint.h>

/* Key definition extracted from keyboardpos.xml */
typedef struct {
    uint16_t id;         /* Scan code / LED index */
    uint16_t vk;         /* Windows VK code */
    const char *name;    /* Key name */
} keyrox_key_info_t;

static const keyrox_key_info_t KEYROX_TKL_KEYS[] = {
    { 1, 27, "Esc" }, { 59, 112, "F1" }, { 60, 113, "F2" }, { 61, 114, "F3" }, { 62, 115, "F4" },
    { 63, 116, "F5" }, { 64, 117, "F6" }, { 65, 118, "F7" }, { 66, 119, "F8" },
    { 67, 120, "F9" }, { 68, 121, "F10" }, { 87, 122, "F11" }, { 88, 123, "F12" },
    { 311, 44, "PrintScreen" }, { 70, 145, "ScrollLock" }, { 69, 19, "Pause" },

    { 41, 192, "`" }, { 2, 49, "1" }, { 3, 50, "2" }, { 4, 51, "3" }, { 5, 52, "4" },
    { 6, 53, "5" }, { 7, 54, "6" }, { 8, 55, "7" }, { 9, 56, "8" }, { 10, 57, "9" },
    { 11, 48, "0" }, { 12, 189, "-" }, { 13, 187, "=" }, { 14, 8, "Backspace" },
    { 338, 45, "Insert" }, { 327, 36, "Home" }, { 329, 33, "PageUp" },

    { 15, 9, "Tab" }, { 16, 81, "Q" }, { 17, 87, "W" }, { 18, 69, "E" }, { 19, 82, "R" },
    { 20, 84, "T" }, { 21, 89, "Y" }, { 22, 85, "U" }, { 23, 73, "I" }, { 24, 79, "O" },
    { 25, 80, "P" }, { 26, 219, "[" }, { 27, 221, "]" }, { 43, 220, "\\" },
    { 339, 46, "Del" }, { 335, 35, "End" }, { 337, 34, "PageDown" },

    { 58, 20, "CapsLock" }, { 30, 65, "A" }, { 31, 83, "S" }, { 32, 68, "D" }, { 33, 70, "F" },
    { 34, 71, "G" }, { 35, 72, "H" }, { 36, 74, "J" }, { 37, 75, "K" }, { 38, 76, "L" },
    { 39, 186, ";" }, { 40, 222, "'" }, { 28, 13, "Enter" },

    { 42, 160, "LeftShift" }, { 44, 90, "Z" }, { 45, 88, "X" }, { 46, 67, "C" }, { 47, 86, "V" },
    { 48, 66, "B" }, { 49, 78, "N" }, { 50, 77, "M" }, { 51, 188, "," }, { 52, 190, "." },
    { 53, 191, "/" }, { 310, 161, "RightShift" }, { 328, 38, "ArrowUp" },

    { 29, 162, "LeftCtrl" }, { 347, 91, "LeftWin" }, { 56, 164, "LeftAlt" },
    { 57, 32, "Spacebar" }, { 312, 165, "RightAlt" }, { 349, 93, "App" },
    { 285, 163, "RightCtrl" }, { 331, 37, "ArrowLeft" }, { 336, 40, "ArrowDown" }, { 333, 39, "ArrowRight" }
};

#define KEYROX_TKL_KEY_COUNT (sizeof(KEYROX_TKL_KEYS) / sizeof(KEYROX_TKL_KEYS[0]))

#endif /* KEYROX_KEYS_H */
