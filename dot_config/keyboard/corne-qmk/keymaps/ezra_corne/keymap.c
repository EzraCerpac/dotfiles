#include QMK_KEYBOARD_H

enum layer_names {
    _BASE = 0,
    _NUM_SYM,
    _NAV_FN,
    _GAME,
};

enum custom_keycodes {
    M_LOCK = SAFE_RANGE,
    M_AREA,
    M_FULL,
    TH_HUD_MEH,
    TH_HYP_NUM,
    TH_NUM_BSPC,
    NUM_LOCK_SWITCH,
    TH_NAV_S,
    TH_NAV_E,
    TH_NAV_BACK_GUI,
    TH_NAV_FWD_ALT,
    TH_NAV_TAB_CTL,
    TH_DEL_NAV,
    GAME_EXIT,
};

#define HRM_A LGUI_T(KC_A)
#define HRM_R LALT_T(KC_R)
#define HRM_T LCTL_T(KC_T)
#define HRM_N RCTL_T(KC_N)
#define HRM_I RALT_T(KC_I)
#define HRM_O RGUI_T(KC_O)

#define MEH_MASK (MOD_BIT(KC_LCTL) | MOD_BIT(KC_LALT) | MOD_BIT(KC_LGUI))

enum combos {
    GAME_MODE_COMBO_BASE,
    GAME_MODE_COMBO_GAME,
};

const uint16_t PROGMEM game_mode_combo_base[] = {TH_HUD_MEH, TH_DEL_NAV, COMBO_END};
const uint16_t PROGMEM game_mode_combo_game[] = {KC_LCTL, KC_RALT, COMBO_END};

combo_t key_combos[] = {
    [GAME_MODE_COMBO_BASE] = COMBO_ACTION(game_mode_combo_base),
    [GAME_MODE_COMBO_GAME] = COMBO_ACTION(game_mode_combo_game),
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [_BASE] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,            KC_W,            KC_F,            KC_P,            KC_B,            KC_J,            KC_L,            KC_U,            KC_Y,            KC_SCLN,         KC_PGUP,
        HYPR_T(KC_ESC), HRM_A,           HRM_R,           TH_NAV_S,         HRM_T,           KC_G,            KC_M,            HRM_N,           TH_NAV_E,        HRM_I,           HRM_O,           KC_QUOT,
        KC_NUBS, KC_Z,            KC_X,            KC_C,            KC_D,            KC_V,            KC_K,            KC_H,            KC_COMM,         KC_DOT,          KC_SLSH,         KC_PGDN,
                                            TH_HUD_MEH,      LSFT_T(KC_ENT),      TH_HYP_NUM,          TH_NUM_BSPC,        LSFT_T(KC_SPC), TH_DEL_NAV
    ),

    [_NUM_SYM] = LAYOUT_split_3x6_3(
        KC_LPRN, KC_RPRN, KC_LBRC, KC_RBRC, KC_LCBR, KC_RCBR, KC_ASTR, KC_7,         KC_8,         KC_9,          KC_EQL,          NUM_LOCK_SWITCH,
        KC_TRNS, LGUI_T(KC_AT), LALT_T(KC_HASH), KC_DLR,  LCTL_T(KC_PERC), KC_CIRC, KC_SLSH, RCTL_T(KC_4), KC_5, RALT_T(KC_6), RGUI_T(KC_MINS), KC_PLUS,
        KC_UNDS, KC_PIPE, KC_BSLS, KC_GRV,  KC_TILD, KC_AMPR, KC_0,    KC_1,         KC_2,         KC_3,          KC_COMM,         KC_DOT,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_NAV_FN] = LAYOUT_split_3x6_3(
        KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,
        KC_TRNS, TH_NAV_BACK_GUI, TH_NAV_FWD_ALT, C(S(KC_TAB)), TH_NAV_TAB_CTL, KC_WREF, KC_LEFT, KC_DOWN,  KC_UP,   KC_RGHT, KC_BRID, KC_BRIU,
        QK_BOOT, S(G(KC_1)), S(G(KC_4)), KC_MCTL, G(KC_MCTL), C(G(KC_Q)), KC_MPRV, KC_MPLY, KC_MNXT, KC_MUTE, KC_VOLD, KC_VOLU,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_GAME] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,    KC_W,    KC_E,    KC_R,    KC_T,    KC_Y,    KC_U,    KC_I,    KC_O,    KC_P,    KC_ENT,
        KC_ESC,  KC_A,    KC_S,    KC_D,    KC_F,    KC_G,    KC_H,    KC_J,    KC_K,    KC_L,    KC_SCLN, KC_QUOT,
        KC_NUBS, KC_Z,    KC_X,    KC_C,    KC_V,    KC_B,    KC_N,    KC_M,    KC_COMM, KC_DOT,  KC_SLSH, GAME_EXIT,
                                   KC_LCTL, KC_LSFT, KC_LGUI, MO(_NUM_SYM), KC_SPC, KC_RALT
    )
};

static bool hud_pressed = false;
static bool hud_hold    = false;
static bool hud_interrupted = false;
static uint16_t hud_timer = 0;

static bool num_l_pressed = false;
static bool num_l_hold    = false;
static bool num_l_interrupted = false;
static uint16_t num_l_timer = 0;

static bool num_r_pressed = false;
static bool num_r_hold    = false;
static bool num_r_interrupted = false;
static uint16_t num_r_timer = 0;

static bool nav_s_pressed = false;
static bool nav_s_interrupted = false;
static uint16_t nav_s_timer = 0;

static bool nav_e_pressed = false;
static bool nav_e_interrupted = false;
static uint16_t nav_e_timer = 0;

static bool nav_back_gui_pressed = false;
static bool nav_back_gui_hold = false;
static bool nav_back_gui_interrupted = false;
static uint16_t nav_back_gui_timer = 0;

static bool nav_fwd_alt_pressed = false;
static bool nav_fwd_alt_hold = false;
static bool nav_fwd_alt_interrupted = false;
static uint16_t nav_fwd_alt_timer = 0;

static bool nav_tab_ctl_pressed = false;
static bool nav_tab_ctl_hold = false;
static bool nav_tab_ctl_interrupted = false;
static uint16_t nav_tab_ctl_timer = 0;

static bool del_nav_pressed = false;
static bool del_nav_hold = false;
static bool del_nav_interrupted = false;
static uint16_t del_nav_timer = 0;

static uint8_t nav_hold_refs = 0;
static uint8_t num_hold_refs = 0;
static bool num_locked = false;
static uint8_t previous_hud_layer = _BASE;

static void activate_hud_hold(void) {
    if (!hud_hold) {
        register_mods(MEH_MASK);
        hud_hold = true;
    }
}

static void activate_nav_back_gui_hold(void) {
    if (!nav_back_gui_hold) {
        register_mods(MOD_BIT(KC_LGUI));
        nav_back_gui_hold = true;
    }
}

static void activate_nav_fwd_alt_hold(void) {
    if (!nav_fwd_alt_hold) {
        register_mods(MOD_BIT(KC_LALT));
        nav_fwd_alt_hold = true;
    }
}

static void activate_nav_tab_ctl_hold(void) {
    if (!nav_tab_ctl_hold) {
        register_mods(MOD_BIT(KC_LCTL));
        nav_tab_ctl_hold = true;
    }
}

static void num_layer_ref_inc(void) {
    if (num_hold_refs == 0) {
        layer_on(_NUM_SYM);
    }
    num_hold_refs++;
}

static void num_layer_ref_dec(void) {
    if (num_hold_refs == 0) {
        return;
    }
    num_hold_refs--;
    if (num_hold_refs == 0 && !num_locked) {
        layer_off(_NUM_SYM);
    }
}

static void activate_num_l_hold(void) {
    if (!num_l_hold) {
        num_layer_ref_inc();
        num_l_hold = true;
    }
}

static void activate_num_r_hold(void) {
    if (!num_r_hold) {
        num_layer_ref_inc();
        num_r_hold = true;
    }
}

static void nav_layer_ref_inc(void) {
    if (nav_hold_refs == 0) {
        layer_on(_NAV_FN);
    }
    nav_hold_refs++;
}

static void nav_layer_ref_dec(void) {
    if (nav_hold_refs == 0) {
        return;
    }
    nav_hold_refs--;
    if (nav_hold_refs == 0) {
        layer_off(_NAV_FN);
    }
}

static void activate_del_nav_hold(void) {
    if (!del_nav_hold) {
        nav_layer_ref_inc();
        del_nav_hold = true;
    }
}

static uint8_t current_base_layer(layer_state_t default_layer_state_value) {
    uint8_t base_layer = get_highest_layer(default_layer_state_value);
    return base_layer == _GAME ? _GAME : _BASE;
}

static uint8_t current_hud_layer(layer_state_t layer_state_value, layer_state_t default_layer_state_value) {
    uint8_t active_layer = get_highest_layer(layer_state_value);
    if (active_layer == _NUM_SYM || active_layer == _NAV_FN) {
        return active_layer;
    }
    return current_base_layer(default_layer_state_value);
}

static void emit_layer_signal(uint8_t layer) {
    switch (layer) {
        case _BASE:
            tap_code(KC_F17);
            break;
        case _NUM_SYM:
            tap_code(KC_F18);
            break;
        case _NAV_FN:
            tap_code(KC_F19);
            break;
        case _GAME:
            tap_code(KC_F23);
            break;
    }
}

static void sync_hud_layer(layer_state_t layer_state_value, layer_state_t default_layer_state_value) {
    uint8_t current_layer = current_hud_layer(layer_state_value, default_layer_state_value);

    if (!is_keyboard_master()) {
        return;
    }

    if (current_layer != previous_hud_layer) {
        emit_layer_signal(current_layer);
        previous_hud_layer = current_layer;
    }
}

static void activate_pending_holds(uint16_t keycode) {
    if (hud_pressed && !hud_hold && keycode != TH_HUD_MEH) {
        hud_interrupted = true;
        activate_hud_hold();
    }

    if (num_l_pressed && !num_l_hold && keycode != TH_HYP_NUM) {
        num_l_interrupted = true;
        activate_num_l_hold();
    }

    if (num_r_pressed && !num_r_hold && keycode != TH_NUM_BSPC) {
        num_r_interrupted = true;
        activate_num_r_hold();
    }

    if (nav_s_pressed && keycode != TH_NAV_S) {
        nav_s_interrupted = true;
    }

    if (nav_e_pressed && keycode != TH_NAV_E) {
        nav_e_interrupted = true;
    }

    if (nav_back_gui_pressed && !nav_back_gui_hold && keycode != TH_NAV_BACK_GUI) {
        nav_back_gui_interrupted = true;
        activate_nav_back_gui_hold();
    }

    if (nav_fwd_alt_pressed && !nav_fwd_alt_hold && keycode != TH_NAV_FWD_ALT) {
        nav_fwd_alt_interrupted = true;
        activate_nav_fwd_alt_hold();
    }

    if (nav_tab_ctl_pressed && !nav_tab_ctl_hold && keycode != TH_NAV_TAB_CTL) {
        nav_tab_ctl_interrupted = true;
        activate_nav_tab_ctl_hold();
    }

    if (del_nav_pressed && !del_nav_hold && keycode != TH_DEL_NAV) {
        del_nav_interrupted = true;
        activate_del_nav_hold();
    }
}

static void toggle_game_mode(void) {
    if (current_base_layer(default_layer_state) == _GAME) {
        set_single_persistent_default_layer(_BASE);
    } else {
        set_single_persistent_default_layer(_GAME);
    }
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    switch (keycode) {
        case TH_HUD_MEH:
            if (record->event.pressed) {
                hud_pressed = true;
                hud_hold    = false;
                hud_interrupted = false;
                hud_timer = timer_read();
            } else {
                hud_pressed = false;
                if (hud_hold) {
                    unregister_mods(MEH_MASK);
                } else if (!hud_interrupted && timer_elapsed(hud_timer) < TAPPING_TERM) {
                    tap_code16(LCTL(LGUI(KC_O)));
                }
            }
            return false;
        case TH_HYP_NUM:
            if (record->event.pressed) {
                num_l_pressed = true;
                num_l_hold    = false;
                num_l_interrupted = false;
                num_l_timer = timer_read();
            } else {
                num_l_pressed = false;
                if (num_l_hold) {
                    num_layer_ref_dec();
                } else if (!num_l_interrupted && timer_elapsed(num_l_timer) < TAPPING_TERM) {
                    tap_code16(HYPR(KC_R));
                }
            }
            return false;
        case TH_NUM_BSPC:
            if (record->event.pressed) {
                num_r_pressed = true;
                num_r_hold = false;
                num_r_interrupted = false;
                num_r_timer = timer_read();
            } else {
                num_r_pressed = false;
                if (num_r_hold) {
                    num_layer_ref_dec();
                } else if (!num_r_interrupted && timer_elapsed(num_r_timer) < TAPPING_TERM) {
                    tap_code(KC_BSPC);
                }
            }
            return false;
        case NUM_LOCK_SWITCH:
            if (!record->event.pressed) {
                return false;
            }
            if (num_locked) {
                num_locked = false;
                if (num_hold_refs == 0) {
                    layer_off(_NUM_SYM);
                }
            } else {
                num_locked = true;
                layer_on(_NUM_SYM);
            }
            return false;
        case TH_NAV_S:
            if (record->event.pressed) {
                nav_s_pressed = true;
                nav_s_interrupted = false;
                nav_s_timer = timer_read();
                nav_layer_ref_inc();
            } else {
                nav_s_pressed = false;
                nav_layer_ref_dec();
                if (!nav_s_interrupted && timer_elapsed(nav_s_timer) < TAPPING_TERM) {
                    tap_code(KC_S);
                }
            }
            return false;
        case TH_NAV_E:
            if (record->event.pressed) {
                nav_e_pressed = true;
                nav_e_interrupted = false;
                nav_e_timer = timer_read();
                nav_layer_ref_inc();
            } else {
                nav_e_pressed = false;
                nav_layer_ref_dec();
                if (!nav_e_interrupted && timer_elapsed(nav_e_timer) < TAPPING_TERM) {
                    tap_code(KC_E);
                }
            }
            return false;
        case TH_NAV_BACK_GUI:
            if (record->event.pressed) {
                nav_back_gui_pressed = true;
                nav_back_gui_hold = false;
                nav_back_gui_interrupted = false;
                nav_back_gui_timer = timer_read();
            } else {
                nav_back_gui_pressed = false;
                if (nav_back_gui_hold) {
                    unregister_mods(MOD_BIT(KC_LGUI));
                } else if (!nav_back_gui_interrupted && timer_elapsed(nav_back_gui_timer) < TAPPING_TERM) {
                    tap_code(KC_WBAK);
                }
            }
            return false;
        case TH_NAV_FWD_ALT:
            if (record->event.pressed) {
                nav_fwd_alt_pressed = true;
                nav_fwd_alt_hold = false;
                nav_fwd_alt_interrupted = false;
                nav_fwd_alt_timer = timer_read();
            } else {
                nav_fwd_alt_pressed = false;
                if (nav_fwd_alt_hold) {
                    unregister_mods(MOD_BIT(KC_LALT));
                } else if (!nav_fwd_alt_interrupted && timer_elapsed(nav_fwd_alt_timer) < TAPPING_TERM) {
                    tap_code(KC_WFWD);
                }
            }
            return false;
        case TH_NAV_TAB_CTL:
            if (record->event.pressed) {
                nav_tab_ctl_pressed = true;
                nav_tab_ctl_hold = false;
                nav_tab_ctl_interrupted = false;
                nav_tab_ctl_timer = timer_read();
            } else {
                nav_tab_ctl_pressed = false;
                if (nav_tab_ctl_hold) {
                    unregister_mods(MOD_BIT(KC_LCTL));
                } else if (!nav_tab_ctl_interrupted && timer_elapsed(nav_tab_ctl_timer) < TAPPING_TERM) {
                    tap_code16(C(KC_TAB));
                }
            }
            return false;
        case TH_DEL_NAV:
            if (record->event.pressed) {
                del_nav_pressed = true;
                del_nav_hold = false;
                del_nav_interrupted = false;
                del_nav_timer = timer_read();
            } else {
                del_nav_pressed = false;
                if (del_nav_hold) {
                    nav_layer_ref_dec();
                } else if (!del_nav_interrupted && timer_elapsed(del_nav_timer) < TAPPING_TERM) {
                    tap_code(KC_DEL);
                }
            }
            return false;
        case GAME_EXIT:
            if (record->event.pressed) {
                set_single_persistent_default_layer(_BASE);
            }
            return false;
    }

    if (record->event.pressed) {
        activate_pending_holds(keycode);
    }

    if (!record->event.pressed) {
        return true;
    }

    switch (keycode) {
        case M_LOCK:
            tap_code16(LCTL(LGUI(KC_Q)));
            return false;
        case M_AREA:
            tap_code16(LSFT(LGUI(KC_4)));
            return false;
        case M_FULL:
            tap_code16(LSFT(LGUI(KC_3)));
            return false;
    }

    return true;
}

void matrix_scan_user(void) {
    if (hud_pressed && !hud_hold && timer_elapsed(hud_timer) >= TAPPING_TERM) {
        activate_hud_hold();
    }

    if (num_l_pressed && !num_l_hold && timer_elapsed(num_l_timer) >= TAPPING_TERM) {
        activate_num_l_hold();
    }

    if (num_r_pressed && !num_r_hold && timer_elapsed(num_r_timer) >= TAPPING_TERM) {
        activate_num_r_hold();
    }

    if (nav_back_gui_pressed && !nav_back_gui_hold && timer_elapsed(nav_back_gui_timer) >= TAPPING_TERM) {
        activate_nav_back_gui_hold();
    }

    if (nav_fwd_alt_pressed && !nav_fwd_alt_hold && timer_elapsed(nav_fwd_alt_timer) >= TAPPING_TERM) {
        activate_nav_fwd_alt_hold();
    }

    if (nav_tab_ctl_pressed && !nav_tab_ctl_hold && timer_elapsed(nav_tab_ctl_timer) >= TAPPING_TERM) {
        activate_nav_tab_ctl_hold();
    }

    if (del_nav_pressed && !del_nav_hold && timer_elapsed(del_nav_timer) >= TAPPING_TERM) {
        activate_del_nav_hold();
    }
}

void process_combo_event(uint16_t combo_index, bool pressed) {
    if (!pressed) {
        return;
    }

    switch (combo_index) {
        case GAME_MODE_COMBO_BASE:
        case GAME_MODE_COMBO_GAME:
            toggle_game_mode();
            break;
    }
}

layer_state_t layer_state_set_user(layer_state_t state) {
    sync_hud_layer(state, default_layer_state);
    return state;
}

layer_state_t default_layer_state_set_user(layer_state_t state) {
    sync_hud_layer(layer_state, state);
    return state;
}
