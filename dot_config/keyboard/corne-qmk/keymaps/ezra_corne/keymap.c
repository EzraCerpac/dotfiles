#include QMK_KEYBOARD_H

enum layer_names {
    _BASE = 0,
    _NUM_SYM,
    _NAV_FN,
};

enum custom_keycodes {
    M_LOCK = SAFE_RANGE,
    M_AREA,
    M_FULL,
    TH_HUD_ALT,
    TH_HYP_NUM,
};

#define HRM_A MT(MOD_LGUI, KC_A)
#define HRM_R MT(MOD_LALT, KC_R)
#define HRM_T MT(MOD_LCTL, KC_T)
#define HRM_N MT(MOD_RCTL, KC_N)
#define HRM_I MT(MOD_RALT, KC_I)
#define HRM_O MT(MOD_RGUI, KC_O)

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [_BASE] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,            KC_W,            KC_F,            KC_P,            KC_B,            KC_J,            KC_L,            KC_U,            KC_Y,            KC_SCLN,         KC_PGUP,
        HYPR_T(KC_ESC), HRM_A,           HRM_R,           LT(_NAV_FN, KC_S), HRM_T,           KC_G,            KC_M,            HRM_N,           KC_E,            HRM_I,           HRM_O,           KC_QUOT,
        KC_GRV,  KC_Z,            KC_X,            KC_C,            KC_D,            KC_V,            KC_K,            KC_H,            KC_COMM,         KC_DOT,          KC_SLSH,         KC_PGDN,
                                            TH_HUD_ALT,      TH_HYP_NUM,          CTL_T(KC_ENT),       LSFT_T(KC_SPC), LT(_NAV_FN, KC_BSPC), MT(MOD_RGUI, KC_DEL)
    ),

    [_NUM_SYM] = LAYOUT_split_3x6_3(
        KC_EXLM, KC_AT,   KC_HASH, KC_DLR,  KC_PERC, KC_CIRC, KC_AMPR, KC_ASTR, KC_LPRN, KC_RPRN, KC_BSLS, KC_GRV,
        KC_1,    HRM_A,   HRM_R,   KC_4,    HRM_T,   KC_6,    KC_7,    HRM_N,   KC_9,    HRM_I,   HRM_O,   KC_EQL,
        KC_LBRC, KC_RBRC, KC_LCBR, KC_RCBR, KC_PIPE, KC_UNDS, KC_PLUS, KC_SLSH, KC_QUES, KC_COLN, LSFT(KC_QUOT), KC_TILD,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_NAV_FN] = LAYOUT_split_3x6_3(
        KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,
        KC_ESC,  HRM_A,   HRM_R,   C(S(KC_TAB)), HRM_T, KC_WREF, KC_LEFT, HRM_N, KC_UP,   HRM_I,   HRM_O,   KC_BRIU,
        QK_BOOT, KC_MPRV, KC_MPLY, KC_MNXT, KC_MUTE, KC_WBAK, KC_WFWD, KC_WREF, KC_WSTP, KC_VOLD, KC_VOLU, KC_MUTE,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    )
};

static bool hud_pressed = false;
static bool hud_hold    = false;
static bool hud_interrupted = false;
static uint16_t hud_timer = 0;

static bool num_pressed = false;
static bool num_hold    = false;
static bool num_interrupted = false;
static uint16_t num_timer = 0;

static void activate_hud_hold(void) {
    if (!hud_hold) {
        register_code(KC_LALT);
        hud_hold = true;
    }
}

static void activate_num_hold(void) {
    if (!num_hold) {
        layer_on(_NUM_SYM);
        num_hold = true;
    }
}

static bool handle_home_row_mod_taps(uint16_t keycode, keyrecord_t *record) {
    uint16_t tapped = KC_NO;
    uint8_t layer = get_highest_layer(layer_state | default_layer_state);

    if (!(record->tap.count && record->event.pressed)) {
        return true;
    }

    switch (layer) {
        case _NUM_SYM:
            switch (keycode) {
                case HRM_A: tapped = KC_2; break;
                case HRM_R: tapped = KC_3; break;
                case HRM_T: tapped = KC_5; break;
                case HRM_N: tapped = KC_8; break;
                case HRM_I: tapped = KC_0; break;
                case HRM_O: tapped = KC_MINS; break;
            }
            break;
        case _NAV_FN:
            switch (keycode) {
                case HRM_A: tapped = KC_WBAK; break;
                case HRM_R: tapped = KC_WFWD; break;
                case HRM_T: tapped = C(KC_TAB); break;
                case HRM_N: tapped = KC_DOWN; break;
                case HRM_I: tapped = KC_RGHT; break;
                case HRM_O: tapped = KC_BRID; break;
            }
            break;
    }

    if (tapped == KC_NO) {
        return true;
    }

    tap_code16(tapped);
    return false;
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    switch (keycode) {
        case HRM_A:
        case HRM_R:
        case HRM_T:
        case HRM_N:
        case HRM_I:
        case HRM_O:
            return handle_home_row_mod_taps(keycode, record);
        case TH_HUD_ALT:
            if (record->event.pressed) {
                hud_pressed = true;
                hud_hold    = false;
                hud_interrupted = false;
                hud_timer = timer_read();
            } else {
                hud_pressed = false;
                if (hud_hold) {
                    unregister_code(KC_LALT);
                } else if (!hud_interrupted && timer_elapsed(hud_timer) < TAPPING_TERM) {
                    tap_code16(LCTL(LGUI(KC_O)));
                }
            }
            return false;
        case TH_HYP_NUM:
            if (record->event.pressed) {
                num_pressed = true;
                num_hold    = false;
                num_interrupted = false;
                num_timer = timer_read();
            } else {
                num_pressed = false;
                if (num_hold) {
                    layer_off(_NUM_SYM);
                } else if (!num_interrupted && timer_elapsed(num_timer) < TAPPING_TERM) {
                    tap_code16(HYPR(KC_R));
                }
            }
            return false;
    }

    if (record->event.pressed) {
        if (hud_pressed && !hud_hold) {
            hud_interrupted = true;
            activate_hud_hold();
        }
        if (num_pressed && !num_hold) {
            num_interrupted = true;
            activate_num_hold();
        }
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

    if (num_pressed && !num_hold && timer_elapsed(num_timer) >= TAPPING_TERM) {
        activate_num_hold();
    }
}

layer_state_t layer_state_set_user(layer_state_t state) {
    static uint8_t previous_layer = _BASE;
    uint8_t current_layer         = get_highest_layer(state);

    if (!is_keyboard_master()) {
        return state;
    }

    if (current_layer != previous_layer) {
        switch (current_layer) {
            case _BASE:
                tap_code(KC_F14);
                break;
            case _NUM_SYM:
                tap_code(KC_F15);
                break;
            case _NAV_FN:
                tap_code(KC_F16);
                break;
        }
        previous_layer = current_layer;
    }

    return state;
}
