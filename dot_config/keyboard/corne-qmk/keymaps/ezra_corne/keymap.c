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
    TH_HUD_ALT,
    TH_HYP_NUM,
    TH_NAV_S,
    TH_NAV_BSPC,
    HRM_R_MEH,
    NS_A_GUI,
    NS_R_ALT,
    NS_T_CTL,
    NS_N_CTL,
    NS_I_ALT,
    NS_O_GUI,
    NV_A_GUI,
    NV_R_ALT,
    NV_T_CTL,
};

#define HRM_A MT(MOD_LGUI, KC_A)
#define HRM_R HRM_R_MEH
#define HRM_T MT(MOD_LCTL, KC_T)
#define HRM_N MT(MOD_RCTL, KC_N)
#define HRM_I MT(MOD_RALT, KC_I)
#define HRM_O MT(MOD_RGUI, KC_O)

enum combos {
    GAME_MODE_COMBO,
};

const uint16_t PROGMEM game_mode_combo[] = {TH_HYP_NUM, TH_NAV_BSPC, COMBO_END};

combo_t key_combos[] = {
    [GAME_MODE_COMBO] = COMBO_ACTION(game_mode_combo),
};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [_BASE] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,            KC_W,            KC_F,            KC_P,            KC_B,            KC_J,            KC_L,            KC_U,            KC_Y,            KC_SCLN,         KC_PGUP,
        HYPR_T(KC_ESC), HRM_A,           HRM_R,           TH_NAV_S,         HRM_T,           KC_G,            KC_M,            HRM_N,           KC_E,            HRM_I,           HRM_O,           KC_QUOT,
        KC_NUBS, KC_Z,            KC_X,            KC_C,            KC_D,            KC_V,            KC_K,            KC_H,            KC_COMM,         KC_DOT,          KC_SLSH,         KC_PGDN,
                                            TH_HUD_ALT,      CTL_T(KC_ENT),       TH_HYP_NUM,          TH_NAV_BSPC,         LSFT_T(KC_SPC), MT(MOD_RGUI, KC_DEL)
    ),

    [_NUM_SYM] = LAYOUT_split_3x6_3(
        KC_EXLM, KC_AT,   KC_HASH, KC_DLR,  KC_PERC, KC_CIRC, KC_AMPR, KC_ASTR, KC_LPRN, KC_RPRN, KC_UNDS, KC_PLUS,
        KC_1,    NS_A_GUI, NS_R_ALT, KC_4,  NS_T_CTL, KC_6,   KC_7,    NS_N_CTL, KC_9,   NS_I_ALT, NS_O_GUI, KC_EQL,
        KC_LBRC, KC_RBRC, KC_LCBR, KC_RCBR, KC_PIPE, KC_UNDS, KC_PLUS, KC_SLSH, KC_QUES, KC_COLN, LSFT(KC_QUOT), KC_TILD,
                                   KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_NAV_FN] = LAYOUT_split_3x6_3(
        KC_F1,   KC_F2,   KC_F3,   KC_F4,   KC_F5,   KC_F6,   KC_F7,   KC_F8,   KC_F9,   KC_F10,  KC_F11,  KC_F12,
        KC_ESC,  NV_A_GUI, NV_R_ALT, C(S(KC_TAB)), NV_T_CTL, KC_WREF, KC_LEFT, KC_DOWN,  KC_UP,   KC_RGHT, KC_BRID, KC_BRIU,
        QK_BOOT, KC_MPRV, KC_MPLY, KC_MNXT, KC_MUTE, KC_WBAK, KC_WFWD, KC_WREF, KC_WSTP, KC_VOLD, KC_VOLU, KC_MUTE,
                                   KC_TRNS, KC_TRNS, KC_LSFT, KC_TRNS, KC_TRNS, KC_TRNS
    ),

    [_GAME] = LAYOUT_split_3x6_3(
        KC_TAB,  KC_Q,    KC_W,    KC_E,    KC_R,    KC_T,    KC_Y,    KC_U,    KC_I,    KC_O,    KC_P,    KC_PGUP,
        KC_ESC,  KC_A,    KC_S,    KC_D,    KC_F,    KC_G,    KC_H,    KC_J,    KC_K,    KC_L,    KC_SCLN, KC_QUOT,
        KC_NUBS, KC_Z,    KC_X,    KC_C,    KC_V,    KC_B,    KC_N,    KC_M,    KC_COMM, KC_DOT,  KC_SLSH, KC_PGDN,
                                   KC_LCTL, KC_LSFT, KC_SPC,  TH_NAV_BSPC, KC_RALT, MT(MOD_RGUI, KC_DEL)
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

static bool nav_pressed = false;
static bool nav_interrupted = false;
static uint16_t nav_timer = 0;
static bool nav_bspc_pressed = false;
static bool nav_bspc_interrupted = false;
static uint16_t nav_bspc_timer = 0;
static uint8_t nav_hold_refs = 0;
static uint8_t previous_hud_layer = _BASE;

typedef struct {
    uint16_t keycode;
    uint8_t hold_mod;
    uint16_t tap_code;
    bool pressed;
    bool hold;
    bool interrupted;
    uint16_t timer;
} custom_modtap_t;

static custom_modtap_t custom_modtaps[] = {
    {HRM_R_MEH, MOD_BIT(KC_LGUI) | MOD_BIT(KC_LCTL) | MOD_BIT(KC_LALT), KC_R, false, false, false, 0},
    {NS_A_GUI, MOD_BIT(KC_LGUI), KC_2, false, false, false, 0},
    {NS_R_ALT, MOD_BIT(KC_LALT), KC_3, false, false, false, 0},
    {NS_T_CTL, MOD_BIT(KC_LCTL), KC_5, false, false, false, 0},
    {NS_N_CTL, MOD_BIT(KC_RCTL), KC_8, false, false, false, 0},
    {NS_I_ALT, MOD_BIT(KC_RALT), KC_0, false, false, false, 0},
    {NS_O_GUI, MOD_BIT(KC_RGUI), KC_MINS, false, false, false, 0},
    {NV_A_GUI, MOD_BIT(KC_LGUI), KC_WBAK, false, false, false, 0},
    {NV_R_ALT, MOD_BIT(KC_LALT), KC_WFWD, false, false, false, 0},
    {NV_T_CTL, MOD_BIT(KC_LCTL), C(KC_TAB), false, false, false, 0},
};

static custom_modtap_t *find_custom_modtap(uint16_t keycode) {
    for (uint8_t i = 0; i < ARRAY_SIZE(custom_modtaps); i++) {
        if (custom_modtaps[i].keycode == keycode) {
            return &custom_modtaps[i];
        }
    }
    return NULL;
}

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

static void activate_custom_modtap_hold(custom_modtap_t *mt) {
    if (!mt->hold) {
        register_mods(mt->hold_mod);
        mt->hold = true;
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
    if (hud_pressed && !hud_hold && keycode != TH_HUD_ALT) {
        hud_interrupted = true;
        activate_hud_hold();
    }

    if (num_pressed && !num_hold && keycode != TH_HYP_NUM) {
        num_interrupted = true;
        activate_num_hold();
    }

    if (nav_pressed && keycode != TH_NAV_S) {
        nav_interrupted = true;
    }
    if (nav_bspc_pressed && keycode != TH_NAV_BSPC) {
        nav_bspc_interrupted = true;
    }

    for (uint8_t i = 0; i < ARRAY_SIZE(custom_modtaps); i++) {
        custom_modtap_t *mt = &custom_modtaps[i];
        if (mt->pressed && !mt->hold && keycode != mt->keycode) {
            mt->interrupted = true;
            activate_custom_modtap_hold(mt);
        }
    }
}

static void toggle_game_mode(void) {
    if (current_base_layer(default_layer_state) == _GAME) {
        set_single_persistent_default_layer(_BASE);
    } else {
        set_single_persistent_default_layer(_GAME);
    }
}

static bool handle_custom_modtap(custom_modtap_t *mt, keyrecord_t *record) {
    if (record->event.pressed) {
        mt->pressed = true;
        mt->hold = false;
        mt->interrupted = false;
        mt->timer = timer_read();
    } else {
        mt->pressed = false;
        if (mt->hold) {
            unregister_mods(mt->hold_mod);
        } else if (!mt->interrupted && timer_elapsed(mt->timer) < TAPPING_TERM) {
            tap_code16(mt->tap_code);
        }
    }
    return false;
}

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    custom_modtap_t *mt = find_custom_modtap(keycode);
    if (mt != NULL) {
        return handle_custom_modtap(mt, record);
    }

    switch (keycode) {
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
        case TH_NAV_S:
            if (record->event.pressed) {
                nav_pressed = true;
                nav_interrupted = false;
                nav_timer = timer_read();
                nav_layer_ref_inc();
            } else {
                nav_pressed = false;
                nav_layer_ref_dec();
                if (!nav_interrupted && timer_elapsed(nav_timer) < TAPPING_TERM) {
                    tap_code(KC_S);
                }
            }
            return false;
        case TH_NAV_BSPC:
            if (record->event.pressed) {
                nav_bspc_pressed = true;
                nav_bspc_interrupted = false;
                nav_bspc_timer = timer_read();
                nav_layer_ref_inc();
            } else {
                nav_bspc_pressed = false;
                nav_layer_ref_dec();
                if (!nav_bspc_interrupted && timer_elapsed(nav_bspc_timer) < TAPPING_TERM) {
                    tap_code(KC_BSPC);
                }
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

    if (num_pressed && !num_hold && timer_elapsed(num_timer) >= TAPPING_TERM) {
        activate_num_hold();
    }

    for (uint8_t i = 0; i < ARRAY_SIZE(custom_modtaps); i++) {
        custom_modtap_t *mt = &custom_modtaps[i];
        if (mt->pressed && !mt->hold && timer_elapsed(mt->timer) >= TAPPING_TERM) {
            activate_custom_modtap_hold(mt);
        }
    }
}

void process_combo_event(uint16_t combo_index, bool pressed) {
    if (!pressed) {
        return;
    }

    switch (combo_index) {
        case GAME_MODE_COMBO:
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
