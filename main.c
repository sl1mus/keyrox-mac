#include "keyrox_hid.h"
#include "keyrox_reset.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void print_usage(const char *prog) {
    printf("keyrox-ctl — Native macOS Utility for Red Square Keyrox TKL (1a2c:2511)\n\n");
    printf("Usage:\n");
    printf("  %s revive                    Send USB Bus Reset to revive frozen keyboard without unplugging\n", prog);
    printf("  %s status                    Query keyboard status, firmware version, and settings\n", prog);
    printf("  %s mode <name|0..19>         Set lighting mode\n", prog);
    printf("  %s brightness <0..4>         Set backlight brightness level\n", prog);
    printf("  %s speed <0..4>              Set lighting animation speed\n", prog);
    printf("  %s color <#RRGGBB|R,G,B>     Set static single color (const mode 0)\n", prog);
    printf("  %s mode-color <mode> <#RGB>  Set foreground color for specific mode\n", prog);
    printf("  %s reset-modes               Restore factory default colors for all 18 modes\n", prog);
    printf("  %s profile <1..5>            Switch active profile\n", prog);
    printf("  %s on                        Turn backlight on (restore PWM, mode preserved)\n", prog);
    printf("  %s off                       Turn backlight off (0%% PWM, mode preserved)\n", prog);
    printf("  %s save                      Commit current configuration to Flash/EEPROM\n", prog);
    printf("  %s watchdog                  Run foreground watchdog loop\n", prog);
    printf("  %s install-daemon            Install 24/7 background sleep protection LaunchAgent\n", prog);
    printf("  %s uninstall-daemon          Uninstall background sleep protection LaunchAgent\n", prog);
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

    if (strcmp(cmd, "revive") == 0 || strcmp(cmd, "reset-usb") == 0) {
        printf("[*] Sending hardware USB Bus Reset to Keyrox TKL (1a2c:2511)...\n");
        if (keyrox_usb_bus_reset() != 0) {
            fprintf(stderr, "[-] USB Bus Reset failed. Ensure keyboard is physically connected.\n");
            return 1;
        }
        printf("[+] Electrical USB Bus Reset successful! Re-enumerating controller...\n");
        usleep(600000); /* 600ms for MCU reboot and re-enumeration */

        keyrox_device_t *kdev = keyrox_open();
        if (kdev) {
            keyrox_set_mode(kdev, KEYROX_MODE_WAVE, KEYROX_DIR_LEFT);
            keyrox_set_brightness(kdev, 4);
            keyrox_close(kdev);
            printf("[+] Keyboard successfully revived and initialized to Wave mode (Brightness: 4/4)!\n");
        } else {
            printf("[!] USB Bus Reset issued. macOS HID driver re-enumerating (test typing now).\n");
        }
        return 0;
    }

    if (strcmp(cmd, "install-daemon") == 0) {
        printf("[*] Installing Keyrox Watchdog LaunchAgent (24/7 background sleep protection)...\n");
        const char *home = getenv("HOME");
        if (!home) return 1;

        char app_support[512];
        snprintf(app_support, sizeof(app_support), "%s/Library/Application Support/Keyrox", home);
        char cmd_mkdir[1024];
        snprintf(cmd_mkdir, sizeof(cmd_mkdir), "mkdir -p '%s' '%s/Library/LaunchAgents' '%s/Library/Logs'", app_support, home, home);
        system(cmd_mkdir);

        char target_bin[512];
        snprintf(target_bin, sizeof(target_bin), "%s/keyrox-watchdog", app_support);
        
        char cp_cmd[1024];
        snprintf(cp_cmd, sizeof(cp_cmd),
            "if [ -f '/Applications/Keyrox.app/Contents/MacOS/keyrox-watchdog' ]; then "
            "  cp '/Applications/Keyrox.app/Contents/MacOS/keyrox-watchdog' '%s'; "
            "elif [ -f '%s/.local/bin/keyrox-watchdog' ]; then "
            "  cp '%s/.local/bin/keyrox-watchdog' '%s'; "
            "elif [ -f 'daemon/keyrox-watchdog' ]; then "
            "  cp 'daemon/keyrox-watchdog' '%s'; "
            "fi; chmod +x '%s'",
            target_bin, home, home, target_bin, target_bin, target_bin);
        system(cp_cmd);

        if (access(target_bin, X_OK) != 0) {
            fprintf(stderr, "[-] Could not find executable keyrox-watchdog to install.\n");
            return 1;
        }

        char plist_path[512];
        snprintf(plist_path, sizeof(plist_path), "%s/Library/LaunchAgents/io.github.sl1mus.keyrox-watchdog.plist", home);
        char log_path[512];
        snprintf(log_path, sizeof(log_path), "%s/Library/Logs/keyrox-watchdog.log", home);

        FILE *f = fopen(plist_path, "w");
        if (!f) {
            perror("[-] Failed to create plist file");
            return 1;
        }
        fprintf(f,
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            "<plist version=\"1.0\">\n"
            "<dict>\n"
            "    <key>Label</key>\n"
            "    <string>io.github.sl1mus.keyrox-watchdog</string>\n"
            "    <key>ProgramArguments</key>\n"
            "    <array>\n"
            "        <string>%s</string>\n"
            "    </array>\n"
            "    <key>RunAtLoad</key>\n"
            "    <true/>\n"
            "    <key>KeepAlive</key>\n"
            "    <true/>\n"
            "    <key>ProcessType</key>\n"
            "    <string>Background</string>\n"
            "    <key>StandardOutPath</key>\n"
            "    <string>%s</string>\n"
            "    <key>StandardErrorPath</key>\n"
            "    <string>%s</string>\n"
            "</dict>\n"
            "</plist>\n",
            target_bin, log_path, log_path);
        fclose(f);

        char load_cmd[2048];
        snprintf(load_cmd, sizeof(load_cmd),
            "launchctl unload '%s/Library/LaunchAgents/com.kistenev.juchen-keepalive.plist' 2>/dev/null; "
            "rm -f '%s/Library/LaunchAgents/com.kistenev.juchen-keepalive.plist'; "
            "launchctl unload '%s' 2>/dev/null; "
            "launchctl load -w '%s'",
            home, home, plist_path, plist_path);
        int ret = system(load_cmd);
        if (ret == 0) {
            printf("[+] Keyrox Watchdog LaunchAgent installed and loaded successfully!\n");
            printf("    Binary:   %s\n", target_bin);
            printf("    Log file: %s\n", log_path);
        } else {
            fprintf(stderr, "[-] Failed to load LaunchAgent via launchctl.\n");
        }
        return ret;
    }

    if (strcmp(cmd, "uninstall-daemon") == 0) {
        printf("[*] Uninstalling Keyrox Watchdog LaunchAgent...\n");
        const char *home = getenv("HOME");
        if (!home) return 1;
        char cmd_buf[1024];
        snprintf(cmd_buf, sizeof(cmd_buf),
            "launchctl unload -w '%s/Library/LaunchAgents/io.github.sl1mus.keyrox-watchdog.plist' 2>/dev/null; "
            "rm -f '%s/Library/LaunchAgents/io.github.sl1mus.keyrox-watchdog.plist'; "
            "launchctl unload -w '%s/Library/LaunchAgents/com.kistenev.juchen-keepalive.plist' 2>/dev/null; "
            "rm -f '%s/Library/LaunchAgents/com.kistenev.juchen-keepalive.plist'",
            home, home, home, home);
        system(cmd_buf);
        printf("[+] Keyrox Watchdog LaunchAgent removed from system startup.\n");
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
                printf("[*] Setting static color (mode 0) to #%02X%02X%02X...\n", r, g, b);
                if (keyrox_set_color(dev, r, g, b) == 0) {
                    printf("[+] Color applied to keyboard matrix (Mode Const)\n");
                } else {
                    fprintf(stderr, "[-] Failed to apply color\n");
                    rc = 1;
                }
            }
        }
    } else if (strcmp(cmd, "mode-color") == 0) {
        if (argc < 4) {
            fprintf(stderr, "[-] Usage: %s mode-color <mode_name|0..17> <#RRGGBB> [bg_#RRGGBB]\n", argv[0]);
            rc = 1;
        } else {
            int mode_idx = keyrox_string_to_mode(argv[2]);
            if (mode_idx < 0) {
                fprintf(stderr, "[-] Unknown mode: '%s'\n", argv[2]);
                rc = 1;
            } else {
                uint8_t fg_r, fg_g, fg_b, bg_r = 0, bg_g = 0, bg_b = 0;
                if (parse_color(argv[3], &fg_r, &fg_g, &fg_b) != 0) {
                    fprintf(stderr, "[-] Invalid foreground color: '%s'\n", argv[3]);
                    rc = 1;
                } else {
                    if (argc >= 5) {
                        parse_color(argv[4], &bg_r, &bg_g, &bg_b);
                    }
                    printf("[*] Setting color for mode %s (%d) to #%02X%02X%02X...\n",
                           keyrox_mode_to_string((keyrox_mode_t)mode_idx), mode_idx, fg_r, fg_g, fg_b);
                    if (keyrox_set_mode_colors(dev, (keyrox_mode_t)mode_idx, fg_r, fg_g, fg_b, bg_r, bg_g, bg_b) == 0) {
                        printf("[+] Mode color updated and saved\n");
                    } else {
                        fprintf(stderr, "[-] Failed to set mode color\n");
                        rc = 1;
                    }
                }
            }
        }
    } else if (strcmp(cmd, "reset-modes") == 0) {
        printf("[*] Restoring factory default colors for all 18 modes in EEPROM...\n");
        if (keyrox_restore_default_modes(dev) == 0) {
            printf("[+] All 18 modes restored to factory defaults and saved to Flash!\n");
        } else {
            fprintf(stderr, "[-] Failed to restore default modes\n");
            rc = 1;
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
        printf("[*] Turning backlight on (PWM restore)...\n");
        if (keyrox_set_brightness(dev, 4) == 0) {
            printf("[+] Backlight turned ON (Brightness: 4/4, active mode and colors preserved)\n");
        } else {
            fprintf(stderr, "[-] Failed to turn on backlight\n");
            rc = 1;
        }
    } else if (strcmp(cmd, "off") == 0) {
        printf("[*] Turning backlight off (PWM 0%%)...\n");
        if (keyrox_set_brightness(dev, 0) == 0) {
            printf("[+] Backlight turned OFF (Brightness: 0/4, active mode and colors preserved)\n");
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
