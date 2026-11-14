#include "keyrox_hid.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void print_usage(const char *prog) {
    printf("keyrox-ctl — Native macOS Utility for Red Square Keyrox TKL (1a2c:2511)\n\n");
    printf("Usage:\n");
    printf("  %s status                    Query keyboard status, firmware version, and settings\n", prog);
    printf("  %s mode <name|0..19>         Set lighting mode\n", prog);
    printf("  %s brightness <0..4>         Set backlight brightness level\n", prog);
    printf("  %s speed <0..4>              Set lighting animation speed\n", prog);
    printf("  %s color <#RRGGBB|R,G,B>     Set custom/static RGB color\n", prog);
    printf("  %s profile <1..5>            Switch active profile\n", prog);
    printf("  %s on                        Turn backlight on (const mode)\n", prog);
    printf("  %s off                       Turn backlight off\n", prog);
    printf("  %s save                      Commit current configuration to Flash/EEPROM\n", prog);
    printf("  %s watchdog                  Run watchdog keepalive loop (prevents sleep dropout)\n", prog);
    printf("  %s modes                     List all supported lighting modes\n\n", prog);
    printf("Examples:\n");
    printf("  %s mode wave                 Set rainbow wave mode\n", prog);
    printf("  %s mode breathe              Set breathing mode\n", prog);
    printf("  %s color '#00FF88'           Set turquoise backlight\n", prog);
    printf("  %s brightness 3              Set brightness to 3\n", prog);
}

static void print_modes(void) {
    printf("Supported Lighting Modes:\n");
    for (int i = 0; i < KEYROX_MODE_COUNT; ++i) {
        printf("  %2d: %s\n", i, keyrox_mode_to_string((keyrox_mode_t)i));
    }
}

static int parse_color(const char *str, uint8_t *r, uint8_t *g, uint8_t *b) {
    if (!str || !r || !g || !b) return -1;
    if (str[0] == '#') str++;

    if (strlen(str) == 6) {
        unsigned int ri, gi, bi;
        if (sscanf(str, "%02x%02x%02x", &ri, &gi, &bi) == 3) {
            *r = (uint8_t)ri;
            *g = (uint8_t)gi;
            *b = (uint8_t)bi;
            return 0;
        }
    }

    int ri, gi, bi;
    if (sscanf(str, "%d,%d,%d", &ri, &gi, &bi) == 3) {
        if (ri >= 0 && ri <= 255 && gi >= 0 && gi <= 255 && bi >= 0 && bi <= 255) {
            *r = (uint8_t)ri;
            *g = (uint8_t)gi;
            *b = (uint8_t)bi;
            return 0;
        }
    }

    return -1;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "help") == 0 || strcmp(cmd, "-h") == 0 || strcmp(cmd, "--help") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    if (strcmp(cmd, "modes") == 0) {
        print_modes();
        return 0;
    }

    keyrox_device_t *dev = keyrox_open();
    if (!dev) {
        fprintf(stderr, "[-] Red Square Keyrox TKL keyboard (1a2c:2511) not found!\n");
        fprintf(stderr, "    Ensure keyboard is plugged in and recognized by macOS.\n");
        return 1;
    }

    int rc = 0;

    if (strcmp(cmd, "status") == 0) {
        keyrox_mode_t mode = KEYROX_MODE_OFF;
        uint8_t bright = 0, speed = 0, profile = 0;
        char fw[128] = {0};

        if (keyrox_get_status(dev, &mode, &bright, &speed, &profile, fw, sizeof(fw)) == 0) {
            printf("[+] Keyboard connected:\n");
            printf("    Firmware:   %s\n", fw[0] ? fw : "Unknown (GK8911M)");
            printf("    Profile:    %d\n", profile + 1);
            printf("    Mode:       %s (%d)\n", keyrox_mode_to_string(mode), (int)mode);
            printf("    Brightness: %d / 4\n", bright);
            printf("    Speed:      %d / 4\n", speed);
        } else {
            fprintf(stderr, "[-] Failed to retrieve keyboard status\n");
            rc = 1;
        }
    } else if (strcmp(cmd, "mode") == 0) {
        if (argc < 3) {
            fprintf(stderr, "[-] Missing mode name or index\n");
            rc = 1;
        } else {
            int mode_idx = keyrox_string_to_mode(argv[2]);
            if (mode_idx < 0) {
                fprintf(stderr, "[-] Unknown mode: '%s'. Run '%s modes' to see list.\n", argv[2], argv[0]);
                rc = 1;
            } else {
                printf("[*] Setting lighting mode to %s (%d)...\n", keyrox_mode_to_string((keyrox_mode_t)mode_idx), mode_idx);
                if (keyrox_set_mode(dev, (keyrox_mode_t)mode_idx, KEYROX_DIR_LEFT) == 0) {
                    printf("[+] Mode set successfully\n");
                } else {
                    fprintf(stderr, "[-] Failed to set mode\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "brightness") == 0) {
        if (argc < 3) {
            fprintf(stderr, "[-] Missing brightness level (0..4)\n");
            rc = 1;
        } else {
            int level = atoi(argv[2]);
            if (level < 0 || level > 4) {
                fprintf(stderr, "[-] Invalid brightness level (must be 0..4)\n");
                rc = 1;
            } else {
                printf("[*] Setting brightness to %d...\n", level);
                if (keyrox_set_brightness(dev, (uint8_t)level) == 0) {
                    printf("[+] Brightness set successfully\n");
                } else {
                    fprintf(stderr, "[-] Failed to set brightness\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "speed") == 0) {
        if (argc < 3) {
            fprintf(stderr, "[-] Missing speed level (0..4)\n");
            rc = 1;
        } else {
            int spd = atoi(argv[2]);
            if (spd < 0 || spd > 4) {
                fprintf(stderr, "[-] Invalid speed level (must be 0..4)\n");
                rc = 1;
            } else {
                printf("[*] Setting animation speed to %d...\n", spd);
                if (keyrox_set_speed(dev, (uint8_t)spd) == 0) {
                    printf("[+] Speed set successfully\n");
                } else {
                    fprintf(stderr, "[-] Failed to set speed\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "color") == 0) {
        if (argc < 3) {
            fprintf(stderr, "[-] Missing color (#RRGGBB or R,G,B)\n");
            rc = 1;
        } else {
            uint8_t r, g, b;
            if (parse_color(argv[2], &r, &g, &b) != 0) {
                fprintf(stderr, "[-] Invalid color format: '%s'. Use #RRGGBB or R,G,B\n", argv[2]);
                rc = 1;
            } else {
                printf("[*] Setting matrix color to #%02X%02X%02X...\n", r, g, b);
                if (keyrox_set_color(dev, r, g, b) == 0) {
                    printf("[+] Color applied to keyboard matrix\n");
                } else {
                    fprintf(stderr, "[-] Failed to apply color\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "profile") == 0) {
        if (argc < 3) {
            fprintf(stderr, "[-] Missing profile number (1..5)\n");
            rc = 1;
        } else {
            int prof = atoi(argv[2]);
            if (prof < 1 || prof > 5) {
                fprintf(stderr, "[-] Invalid profile number (must be 1..5)\n");
                rc = 1;
            } else {
                printf("[*] Switching to profile %d...\n", prof);
                if (keyrox_set_profile(dev, (uint8_t)(prof - 1)) == 0) {
                    printf("[+] Profile switched successfully\n");
                } else {
                    fprintf(stderr, "[-] Failed to switch profile\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "on") == 0) {
        printf("[*] Turning backlight on (Const mode)...\n");
        if (keyrox_set_mode(dev, KEYROX_MODE_CONST, KEYROX_DIR_LEFT) == 0) {
            printf("[+] Backlight turned ON\n");
        } else {
            fprintf(stderr, "[-] Failed to turn on backlight\n");
            rc = 1;
        }
    } else if (strcmp(cmd, "off") == 0) {
        printf("[*] Turning backlight off...\n");
        if (keyrox_set_mode(dev, KEYROX_MODE_OFF, KEYROX_DIR_LEFT) == 0) {
            printf("[+] Backlight turned OFF\n");
        } else {
            fprintf(stderr, "[-] Failed to turn off backlight\n");
            rc = 1;
        }
    } else if (strcmp(cmd, "save") == 0) {
        printf("[*] Committing settings to keyboard Flash/EEPROM...\n");
        if (keyrox_save_settings(dev) == 0) {
            printf("[+] Settings committed to persistent memory\n");
        } else {
            fprintf(stderr, "[-] Failed to commit settings\n");
            rc = 1;
        }
    } else if (strcmp(cmd, "watchdog") == 0) {
        printf("[+] Running keyrox-ctl watchdog (press Ctrl+C to exit)...\n");
        while (1) {
            uint8_t mode = 0;
            keyrox_read_packet(dev, KEYROX_CMD_MODE, 0, 0, &mode, 1);
            sleep(30);
        }
    } else {
        fprintf(stderr, "[-] Unknown command: '%s'\n", cmd);
        print_usage(argv[0]);
        rc = 1;
    }

    keyrox_close(dev);
    return rc;
}
