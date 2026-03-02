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
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [_BASE] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,            KC_W,            KC_F,            KC_P,            KC_B,            KC_J,            KC_L,            KC_U,            KC_Y,            KC_SCLN,         KC_BSPC,
        HYPR_T(KC_ESC), MT(MOD_LGUI,KC_A), MT(MOD_LALT,KC_R), KC_S, MT(MOD_LCTL,KC_T), KC_G,            KC_M,            MT(MOD_RCTL,KC_N), KC_E,            MT(MOD_RALT,KC_I), KC_O,            KC_QUOT,
        KC_LSFT, KC_Z,            KC_X,            KC_C,            KC_D,            KC_V,            KC_K,            KC_H,            KC_COMM,         KC_DOT,          KC_SLSH,         KC_ENT,
                                            ALT_T(KC_ENT),   LT(_NUM_SYM, KC_NO), MT(MOD_LCTL, KC_NO), LSFT_T(KC_SPC), LT(_NAV_FN, KC_BSPC), MT(MOD_RGUI, KC_DEL)
    ),

    [_NUM_SYM] = LAYOUT_split_3x6_3(
        KC_1,    KC_2,    KC_3,    KC_4,    KC_5,    KC_6,    KC_7,    KC_8,    KC_9,    KC_0,    KC_MINS, KC_EQL,
        KC_EXLM, KC_AT,   KC_HASH, KC_DLR,  KC_PERC, KC_CIRC, KC_AMPR, KC_ASTR, KC_LPRN, KC_RPRN, KC_BSLS, KC_GRV,
        KC_LBRC, KC_RBRC, KC_LCBR, KC_RCBR, KC_PIPE, KC_UNDS, KC_PLUS, KC_SLSH, KC_QUES, KC_COLN, LSFT(KC_QUOT), KC_TILD,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_NAV_FN] = LAYOUT_split_3x6_3(
        KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,
        KC_ESC,  KC_TAB,  KC_HOME, KC_PGDN, KC_PGUP, KC_END,  KC_LEFT, KC_DOWN, KC_UP,   KC_RGHT, KC_BRID, KC_BRIU,
        QK_BOOT, RGB_TOG, RGB_MOD, RGB_HUI, RGB_SAI, RGB_VAI, RGB_HUD, RGB_SAD, RGB_VAD, KC_VOLD, KC_VOLU, KC_MUTE,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    )
};

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
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
