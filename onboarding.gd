# onboarding.gd — Godot 4.5
extends Control

# --- ONREADY VARIABLES ---
@onready var root_box: VBoxContainer = $MarginContainer/VBoxContainer
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var email_edit: LineEdit = $MarginContainer/VBoxContainer/EmailEdit
@onready var password_edit: LineEdit = $MarginContainer/VBoxContainer/PasswordEdit
@onready var referral_edit: LineEdit = $MarginContainer/VBoxContainer/ReferralEdit
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var existing_logo: TextureRect = $MarginContainer/VBoxContainer/Logo
@onready var deeplink := $Deeplink

# — Düğmeleri farklı isimlerle bulmak için yardımcı
func _ensure_onboarding_scroll() -> void:
	var margin := $MarginContainer as MarginContainer
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	if margin.get_node_or_null("OnboardingScroll"):
		var existing_center := margin.get_node_or_null("OnboardingScroll/OnboardingCenter")
		if existing_center is CenterContainer and root_box.get_parent() != existing_center:
			if root_box.get_parent():
				root_box.get_parent().remove_child(root_box)
			existing_center.add_child(root_box)
		return
	var scroll := ScrollContainer.new()
	scroll.name = "OnboardingScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.name = "OnboardingCenter"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	if root_box.get_parent() == margin:
		margin.remove_child(root_box)
	center.add_child(root_box)
	scroll.add_child(center)
	margin.add_child(scroll)


func _first_button(paths: Array) -> Button:
	for p in paths:
		var n := get_node_or_null(p)
		if n is Button:
			return n
	return null

@onready var login_buttonn: Button = _first_button([
	"MarginContainer/VBoxContainer/LoginButtonn",
	"MarginContainer/VBoxContainer/LoginButton",
	"MarginContainer/VBoxContainer/LoginBtn",
	"MarginContainer/VBoxContainer/LoginBut",
	"MarginContainer/VBoxContainer/Login",
])

@onready var forgot_button: Button = _first_button([
	"MarginContainer/VBoxContainer/ForgotPasswordButton",
	"MarginContainer/VBoxContainer/ForgotPassword",
	"MarginContainer/VBoxContainer/ForgotBtn",
	"MarginContainer/VBoxContainer/Forgot",
	"MarginContainer/VBoxContainer/SifremiUnuttum",
])

const MIN_TAP: int = 72
const MAX_TAP: int = 92
const MIN_WIDTH: int = 392
const MAX_WIDTH: int = 640

const GOOGLE_ICON: Texture2D = preload("res://assets/google_g.png")
const APPLE_ICON_PATH := "res://assets/apple_logo_white.png"

# runtime ui refs
var _tagline: Label
var _email_row: HBoxContainer
var _pass_row: HBoxContainer
var _ref_row: HBoxContainer
var _eye_btn: Button
var _glass_panel: PanelContainer
var _google_button: Button
var _apple_button: Button
var _auth_in_progress := false

# styles
var _style_input_normal: StyleBoxFlat
var _style_input_focus: StyleBoxFlat
var _style_input_error: StyleBoxFlat

# loading anim
var _loading_timer: Timer
var _loading_dots: int = 0
var _loading_btn: Button
var _loading_btn_text: String = ""

func _ready() -> void:
	Global.analytics_page("Onboarding", "app://candar/onboarding")
	Global.analytics_event("app_screen_view", {"screen": "onboarding"})
	_ensure_onboarding_scroll()
	_apply_premium_style()
	_build_tagline_and_glass_logo()
	_build_language_selector()
	_build_input_rows()
	root_box.mouse_filter = Control.MOUSE_FILTER_PASS

	# Google hem Android hem iOS'ta her zaman görünür olsun.
	_build_google_button()

	# Apple zaten _build_apple_button içinde iOS kontrolü yapıyor.
	_build_apple_button()
	_ensure_social_buttons_order()

	_add_privacy_row()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	await Global.apply_safe_area(self)

	# placeholders – çeviri ile (CSV’deki key’ler)
	email_edit.placeholder_text = tr("email_placeholder")
	password_edit.placeholder_text = tr("password_placeholder")
	referral_edit.placeholder_text = tr("referral_placeholder")
	password_edit.secret = true
	password_edit.secret_character = "•"

	# mobil klavye + clear
	email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	password_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	referral_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	email_edit.clear_button_enabled = true
	password_edit.clear_button_enabled = false
	referral_edit.clear_button_enabled = true
	# butonlar – çeviri ile
	if login_buttonn != null:
		login_buttonn.text = tr("login_button")          # EN: "Sign in / Sign up"
	if forgot_button != null:
		forgot_button.text = tr("forgot_password")       # EN: "Forgot Password?"

	for btn in [login_buttonn, forgot_button]:
		if btn != null:
			_connect_press_anim(btn)

	# enter ile akış
	email_edit.text_submitted.connect(func(_t): password_edit.grab_focus())
	if login_buttonn != null:
		password_edit.text_submitted.connect(func(_t): login_buttonn.emit_signal("pressed"))

	# buton aksiyonları
	if login_buttonn != null:
		login_buttonn.pressed.connect(func() -> void: _on_login_pressed_common(false, false))
	if forgot_button != null:
		forgot_button.pressed.connect(_on_forgot_password_pressed)

	if _supports_google_login() and _google_button != null:
		_connect_press_anim(_google_button)
		_google_button.pressed.connect(_on_google_login_pressed)

	# Apple connect (iOS'ta oluşuyor zaten)
	if _apple_button != null:
		_connect_press_anim(_apple_button)
		if not _apple_button.pressed.is_connected(_on_apple_button_pressed):
			_apple_button.pressed.connect(_on_apple_button_pressed)

	_loading_timer = Timer.new()
	_loading_timer.wait_time = 0.4
	_loading_timer.timeout.connect(_on_loading_tick)
	add_child(_loading_timer)
	call_deferred("_prefill_referral_from_launch_context")


# A language switcher is available before sign-in, rather than requiring
# users to navigate a foreign-language profile screen first.
func _build_language_selector() -> void:
	var codes := ["en", "tr", "de", "fr", "es", "pt", "ru", "zh", "ja", "ko", "ar", "hi"]
	var names := [
		"English", "Türkçe", "Deutsch", "Français", "Español", "Português",
		"Русский", "简体中文", "日本語", "한국어", "العربية", "हिन्दी"
	]
	var existing := root_box.get_node_or_null("LanguageSelect")
	if existing:
		return
	var selector := OptionButton.new()
	selector.name = "LanguageSelect"
	selector.tooltip_text = tr("select_language")
	selector.custom_minimum_size = Vector2(170, 46)
	selector.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	selector.add_theme_font_size_override("font_size", 17)
	for i in range(codes.size()):
		selector.add_item(names[i], i)
	var current := TranslationServer.get_locale().replace("-", "_").get_slice("_", 0).to_lower()
	var index := codes.find(current)
	if index >= 0:
		selector.select(index)
	selector.item_selected.connect(func(chosen: int) -> void:
		var next_locale: String = codes[chosen]
		if next_locale != current:
			Global.set_language(next_locale)
			# New onboarding scene also reapplies all tr() placeholders.
			get_tree().call_deferred("reload_current_scene")
	)
	root_box.add_child(selector)
	root_box.move_child(selector, mini(2, root_box.get_child_count() - 1))

# Yardımcılar
func _event_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return event.position
	if event is InputEventScreenTouch:
		return event.position
	return Vector2.ZERO

func _point_in_control(ctrl: Control, p: Vector2) -> bool:
	return ctrl.get_global_rect().has_point(p)

func _is_ios_runtime() -> bool:
	return OS.has_feature("ios") or OS.get_name() == "iOS"

func _is_android_runtime() -> bool:
	return OS.has_feature("android") or OS.get_name() == "Android"

func _supports_google_login() -> bool:
	return _is_ios_runtime() or _is_android_runtime()

# ---------- STYLE HELPERS ----------
func _mk_input_style(base_col: Color, border_col: Color, radius: int = 20, pad: int = 18, shadow: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = base_col
	s.border_color = border_col
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.shadow_size = shadow
	s.shadow_color = Color(0,0,0,0.25)
	return s

func _mk_button_style(bg: Color, radius: int = 999, pad_h: int = 18, pad_v: int = 16, shadow: int = 26, shadow_col: Color = Color(0,0,0,0.28)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.expand_margin_left = 0
	sb.expand_margin_right = 0
	sb.expand_margin_top = 0
	sb.expand_margin_bottom = 0
	sb.shadow_size = shadow
	sb.shadow_color = shadow_col
	return sb

func _mix(a: Color, b: Color, t: float) -> Color:
	# Not: Orijinal kodun alfa hesabı aynı kalacak şekilde bırakıldı
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (a.a - a.a) * t)

# ---------- APPLY STYLE ----------
func _apply_premium_style() -> void:
	if has_node("ColorRect"):
		$ColorRect.visible = false
	CandarUI.add_gradient_bg(self, "OnboardingGradient")
	root_box.add_theme_constant_override("separation", 20)

	title_label.text = "Candar Network"
	title_label.add_theme_color_override("font_color", Color("#FFA51B"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	status_label.add_theme_color_override("font_color", Color("#FFBE4D"))
	status_label.add_theme_color_override("font_outline_color", Color("#1F2745"))
	status_label.add_theme_constant_override("outline_size", 1)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var base: Color = Color("#0f172a")
	var border: Color = Color("#FFA51B")
	var focusb: Color = Color("#FFD074")
	_style_input_normal = _mk_input_style(base, border, 20, 18, 18)
	_style_input_focus = _mk_input_style(base, focusb, 20, 18, 24)
	_style_input_focus.shadow_color = Color(1,0.72,0.22,0.38)
	_style_input_error = _mk_input_style(_mix(base, Color(1,0,0,0.12), 0.5), Color8(230,80,80), 20, 18, 22)

	for le in [email_edit, password_edit, referral_edit]:
		if le != null:
			var style_n = _style_input_normal.duplicate() as StyleBoxFlat
			style_n.content_margin_left = 24
			if le == password_edit:
				style_n.content_margin_right = 92
			var style_f = _style_input_focus.duplicate() as StyleBoxFlat
			style_f.content_margin_left = 24
			if le == password_edit:
				style_f.content_margin_right = 92
			var style_e = _style_input_error.duplicate() as StyleBoxFlat
			style_e.content_margin_left = 24
			if le == password_edit:
				style_e.content_margin_right = 92

			le.size_flags_vertical = Control.SIZE_EXPAND_FILL
			le.add_theme_stylebox_override("normal", style_n)
			le.add_theme_stylebox_override("focus", style_f)
			le.add_theme_stylebox_override("error", style_e)
			le.add_theme_color_override("font_color", Color("#F6F7FB"))
			le.add_theme_color_override("placeholder_color", Color8(246,247,251,150))
			le.caret_blink = true
			le.caret_blink_interval = 0.75

	# --- Birincil buton paleti (GİRİŞ & ŞİFREMİ UNUTTUM aynı) ---
	var amber         := Color8(255,194,77)
	var amber_hover   := Color8(255,210,120)
	var amber_pressed := Color8(255,158,27)
	var font_dark     := Color("#1C223B")

	var st_n: StyleBoxFlat = _mk_button_style(amber,         999, 18, 16, 26, Color(0, 0, 0, 0.28))
	var st_h: StyleBoxFlat = _mk_button_style(amber_hover,   999, 18, 16, 30, Color(0, 0, 0, 0.32))
	var st_p: StyleBoxFlat = _mk_button_style(amber_pressed, 999, 18, 16, 18, Color(0, 0, 0, 0.24))

	for btn in [login_buttonn, forgot_button]:
		if btn != null:
			btn.add_theme_stylebox_override("normal",  st_n)
			btn.add_theme_stylebox_override("hover",   st_h)
			btn.add_theme_stylebox_override("pressed", st_p)
			btn.add_theme_color_override("font_color", font_dark)

func _apply_background_gradient() -> void:
	if get_node_or_null("OnboardingGradient") != null:
		return
	var tex_rect := TextureRect.new()
	tex_rect.name = "OnboardingGradient"
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#0f172a"), Color("#111827"), Color("#1e293b")])
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	var gtex := GradientTexture2D.new()
	gtex.gradient = gradient
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 64
	gtex.height = 64
	tex_rect.texture = gtex
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tex_rect)
	move_child(tex_rect, 1)

# ---------- GLASS CARD + TAGLINE ----------
func _make_glass_panel() -> PanelContainer:
	var glass := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(24)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.shadow_size = 24
	sb.shadow_color = Color(0,0,0,0.28)
	glass.add_theme_stylebox_override("panel", sb)
	glass.custom_minimum_size = Vector2(0, 112)
	return glass

func _build_tagline_and_glass_logo() -> void:
	if _tagline == null:
		_tagline = Label.new()
		_tagline.name = "Tagline"
		_tagline.text = tr("onboarding_first_step")
		_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tagline.add_theme_color_override("font_color", Color8(255, 222, 170, 220))
		root_box.add_child(_tagline)
		var idx: int = root_box.get_children().find(title_label)
		if idx != -1:
			root_box.move_child(_tagline, idx + 1)

	if _glass_panel == null:
		_glass_panel = _make_glass_panel()
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 18)
		m.add_theme_constant_override("margin_right", 18)
		m.add_theme_constant_override("margin_top", 18)
		m.add_theme_constant_override("margin_bottom", 18)
		_glass_panel.add_child(m)

		if existing_logo != null and existing_logo.get_parent() != null:
			existing_logo.get_parent().remove_child(existing_logo)
			m.add_child(existing_logo)
			existing_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			existing_logo.custom_minimum_size = Vector2(0, 76)
			existing_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			existing_logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			existing_logo.size_flags_vertical = Control.SIZE_EXPAND_FILL

		root_box.add_child(_glass_panel)
		var tag_idx: int = root_box.get_children().find(_tagline)
		var insert_at: int = tag_idx + 1
		root_box.move_child(_glass_panel, insert_at)

# ---------- INPUT ROWS ----------
func _wrap_input(le: LineEdit) -> HBoxContainer:
	var parent := le.get_parent()
	var idx: int = le.get_index()
	parent.remove_child(le)
	var row := HBoxContainer.new()
	row.name = le.name + "_Row"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	parent.move_child(row, idx)
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	return row

func _build_input_rows() -> void:
	# Full-width fields line up with the social and email sign-in buttons.
	# Emoji gutters were blank on iOS and shifted the fields to the right.
	_email_row = _wrap_input(email_edit)
	_pass_row = _wrap_input(password_edit)
	_ref_row = _wrap_input(referral_edit)
	_eye_btn = Button.new()
	_eye_btn.name = "PasswordVisibility"
	_eye_btn.icon = preload("res://assets/onboarding_eye.svg")
	_eye_btn.expand_icon = true
	_eye_btn.add_theme_constant_override("icon_max_width", 36)
	_eye_btn.focus_mode = Control.FOCUS_NONE
	_eye_btn.tooltip_text = Global.localized_ui_text("Şifreyi göster/gizle", "Show/hide password")
	for state in ["normal", "hover", "pressed", "focus"]:
		_eye_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	password_edit.add_child(_eye_btn)
	_eye_btn.anchor_left = 1.0
	_eye_btn.anchor_right = 1.0
	_eye_btn.anchor_top = 0.0
	_eye_btn.anchor_bottom = 1.0
	_eye_btn.offset_left = -84
	_eye_btn.offset_right = -4
	_eye_btn.offset_top = 8
	_eye_btn.offset_bottom = -8
	_eye_btn.pressed.connect(func() -> void:
		password_edit.secret = not password_edit.secret
		_eye_btn.icon = preload("res://assets/onboarding_eye.svg") if password_edit.secret else preload("res://assets/onboarding_eye_hidden.svg")
	)

func _set_input_error(le: LineEdit, invalid: bool) -> void:
	var style := (_style_input_error if invalid else _style_input_normal).duplicate() as StyleBoxFlat
	style.content_margin_left = 24
	if le == password_edit:
		style.content_margin_right = 92
	le.add_theme_stylebox_override("normal", style)

func _on_google_login_pressed():
	Global.analytics_event("login_google_tap", {"screen": "onboarding"})
	# Eski GoogleAuthInApp yerine Global.google_sign_in() akışını kullanıyoruz.
	await _on_login_pressed_common(true, false)

func _on_apple_button_pressed() -> void:
	Global.analytics_event("login_apple_tap", {"screen": "onboarding"})
	await _on_login_pressed_common(false, true)

# ---------- GOOGLE BUTTON ----------
func _build_google_button() -> void:
	if not _supports_google_login():
		return

	if _google_button != null:
		_google_button.visible = true
		_google_button.disabled = false
		return

	_google_button = Button.new()
	_google_button.name = "GoogleButton"
	_google_button.text = tr("google_button")
	_google_button.custom_minimum_size = Vector2(0, MIN_TAP)
	_google_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var base_col = Color("#F7F8FB")
	var hover_col = Color("#F2F4F7")
	var pressed_col = Color("#EBEEF2")
	var border_col = Color("#D9DEE6")
	var font_col = Color("#1C223B")

	var st = _mk_button_style(base_col, 999, 20, 16, 18, Color(0,0,0,0.18))
	st.set_border_width_all(1)
	st.border_color = border_col
	_google_button.add_theme_stylebox_override("normal", st)

	var st_h := st.duplicate() as StyleBoxFlat
	st_h.bg_color = hover_col
	_google_button.add_theme_stylebox_override("hover", st_h)

	var st_p := st.duplicate() as StyleBoxFlat
	st_p.bg_color = pressed_col
	st_p.shadow_size = 12
	_google_button.add_theme_stylebox_override("pressed", st_p)

	_google_button.add_theme_color_override("font_color", font_col)

	if GOOGLE_ICON != null:
		_google_button.icon = GOOGLE_ICON
	_google_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_google_button.expand_icon = false
	_google_button.add_theme_constant_override("icon_max_width", 24)
	_google_button.add_theme_constant_override("icon_separation", 12)

	for sb in ["normal", "hover", "pressed"]:
		var b := _google_button.get_theme_stylebox(sb)
		if b is StyleBoxFlat:
			b.content_margin_left = 22
			b.content_margin_right = 22
			b.content_margin_top = 16
			b.content_margin_bottom = 16

	root_box.add_child(_google_button)
	_ensure_social_buttons_order()

func _build_apple_button() -> void:
	# SADECE iOS’TA BUTON OLUŞTUR
	if not _is_ios_runtime():
		return

	if _apple_button != null:
		return

	_apple_button = Button.new()
	_apple_button.name = "AppleButton"
	_apple_button.text = tr("apple_button")
	_apple_button.custom_minimum_size = Vector2(0, MIN_TAP)
	_apple_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var base_col = Color("#111111")
	var hover_col = Color("#1a1a1a")
	var pressed_col = Color("#000000")
	var font_col = Color("#F7F7F7")

	var st = _mk_button_style(base_col, 999, 20, 16, 22, Color(0,0,0,0.42))
	_apple_button.add_theme_stylebox_override("normal", st)

	var st_h := st.duplicate() as StyleBoxFlat
	st_h.bg_color = hover_col
	_apple_button.add_theme_stylebox_override("hover", st_h)

	var st_p := st.duplicate() as StyleBoxFlat
	st_p.bg_color = pressed_col
	st_p.shadow_size = 14
	_apple_button.add_theme_stylebox_override("pressed", st_p)

	_apple_button.add_theme_color_override("font_color", font_col)

	# ---- APPLE LOGOSU ----
	if ResourceLoader.exists(APPLE_ICON_PATH):
		var tex: Texture2D = load(APPLE_ICON_PATH)
		if tex:
			_apple_button.icon = tex

	_apple_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apple_button.expand_icon = false
	_apple_button.add_theme_constant_override("icon_max_width", 24)
	_apple_button.add_theme_constant_override("icon_separation", 12)

	for sb in ["normal", "hover", "pressed"]:
		var b := _apple_button.get_theme_stylebox(sb)
		if b is StyleBoxFlat:
			b.content_margin_left = 22
			b.content_margin_right = 22
			b.content_margin_top = 16
			b.content_margin_bottom = 16

	# Apple ve Google, e-posta giriş düğmesinin ardından gelir.
	root_box.add_child(_apple_button)
	_ensure_social_buttons_order()

func _ensure_social_buttons_order() -> void:
	if root_box == null or login_buttonn == null or login_buttonn.get_parent() != root_box:
		return
	var anchor: Control = login_buttonn
	for button in [_apple_button, _google_button]:
		if button != null and button.get_parent() == root_box:
			button.visible = true
			var target_index: int = anchor.get_index() + 1
			if button.get_index() < target_index:
				target_index -= 1
			root_box.move_child(button, target_index)
			anchor = button


# ---------- LEGAL/PRIVACY ROW ----------
func _add_privacy_row() -> void:
	if root_box.get_node_or_null("LegalRow") != null:
		return
	var legal_box := VBoxContainer.new()
	legal_box.name = "LegalRow"
	legal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color8(200, 206, 224, 180))
	lbl.text = tr("legal_text")
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legal_box.add_child(lbl)
	var links := HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 18)
	for item in [
		{"text": tr("privacy_policy"), "url": "https://candarnetwork.com/privacy.html"},
		{"text": tr("terms_of_service"), "url": "https://candarnetwork.com/terms.html"}
	]:
		var link := Button.new()
		link.text = str(item["text"])
		link.flat = true
		link.focus_mode = Control.FOCUS_NONE
		link.add_theme_color_override("font_color", Color8(255, 184, 77))
		link.add_theme_font_size_override("font_size", 13)
		link.pressed.connect(_open_legal_url.bind(str(item["url"])))
		links.add_child(link)
	legal_box.add_child(links)
	root_box.add_child(legal_box)
	if forgot_button != null:
		var idx: int = root_box.get_children().find(forgot_button)
		if idx != -1:
			root_box.move_child(legal_box, idx + 1)


func _open_legal_url(url: String) -> void:
	OS.shell_open(url)


# ---------- LAYOUT ----------
func _apply_responsive_layout() -> void:
	var vs: Vector2 = get_viewport_rect().size

	# 1. Tablet Tespiti
	var is_tablet: bool = vs.x > 800 or (vs.y / vs.x) < 1.5

	# 2. Genişlik Hesaplama
	var target_w: float
	if is_tablet:
		target_w = clampf(vs.x * 0.42, 420.0, 560.0)
	else:
		target_w = minf(clampf(vs.x * 0.92, 280.0, float(MAX_WIDTH)), maxf(0.0, vs.x - 32.0))
	# Leave room for the vertical scrollbar without widening the full-screen margin.
	var scroll := $MarginContainer/OnboardingScroll as ScrollContainer
	var scrollbar_w := scroll.get_v_scroll_bar().get_combined_minimum_size().x
	target_w = minf(target_w, maxf(0.0, vs.x - 32.0 - scrollbar_w))

	root_box.custom_minimum_size.x = target_w
	root_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var margin := $MarginContainer as MarginContainer
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.scale = Vector2.ONE
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	var center := margin.get_node_or_null("OnboardingScroll/OnboardingCenter") as CenterContainer
	if center:
		# Containers settle their minimum sizes after the initial style/reparent pass.
		# Caching that transient height here pushes the first screen below the fold.
		center.custom_minimum_size = Vector2.ZERO
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 3. Yükseklik Hesaplama
	var tap_h: int = clampi(int(vs.y / 16.0), MIN_TAP, 100)

	# Buton ve satır boylarını güncelle
	for n in [_email_row, _pass_row, _ref_row, login_buttonn, _apple_button, _google_button, forgot_button]:
		if n != null:
			n.custom_minimum_size.y = tap_h

	# 4. Dinamik Font ve Ara Boşluk
	var t: float = clampf(inverse_lerp(float(MIN_WIDTH), 1100.0, target_w), 0.0, 1.0)

	var title_fs: int = int(round(lerpf(36.0, 56.0, t)))
	var field_fs: int = int(round(lerpf(20.0, 32.0, t)))
	var status_fs: int = int(round(lerpf(18.0, 26.0, t)))
	var tag_fs: int = int(round(lerpf(16.0, 22.0, t)))

	title_label.add_theme_font_size_override("font_size", title_fs)
	status_label.add_theme_font_size_override("font_size", status_fs)

	if _tagline != null:
		_tagline.add_theme_font_size_override("font_size", tag_fs)

	for le in [email_edit, password_edit, referral_edit]:
		if le != null:
			le.add_theme_font_size_override("font_size", field_fs)

	for btn in [login_buttonn, _google_button, _apple_button, forgot_button, _eye_btn]:
		if btn != null:
			btn.add_theme_font_size_override("font_size", field_fs)

	var sep := int(round(lerpf(16.0, 28.0, t)))
	root_box.add_theme_constant_override("separation", sep)

	# Keep the full-screen root at 1:1. Scaling it from the top-left shifts the
	# centered form and clips its right edge on high-DPI iPhones.
	scale = Vector2.ONE
	_reset_button_scales()

func _reset_button_scales() -> void:
	for btn in [login_buttonn, forgot_button, _google_button, _apple_button, _eye_btn]:
		if btn != null:
			btn.scale = Vector2.ONE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		call_deferred("_apply_responsive_layout")

# ---------- UTILS ve LOGIC ----------
func _connect_press_anim(btn: Button) -> void:
	btn.button_down.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(0.98, 0.98), 0.06)
	)
	btn.button_up.connect(func():
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1, 1), 0.06)
	)

func _shake(node: Control) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(1.03, 0.98), 0.05)
	tw.tween_property(node, "scale", Vector2(0.97, 1.02), 0.08)
	tw.tween_property(node, "scale", Vector2(1, 1), 0.05)

func _set_loading(btn: Button, base_text: String, active: bool) -> void:
	_auth_in_progress = active
	# Prevent simultaneous Apple, Google, email, and reset requests sharing auth state.
	for action in [login_buttonn, _google_button, _apple_button, forgot_button]:
		if action != null:
			action.disabled = active
	for field in [email_edit, password_edit, referral_edit]:
		field.editable = not active
	if active:
		_loading_btn = btn
		_loading_btn_text = base_text
		_loading_dots = 0
		if btn != null:
			btn.disabled = true
		_loading_timer.start()
	else:
		_loading_timer.stop()
		if _loading_btn != null:
			_loading_btn.text = _loading_btn_text
			_loading_btn.disabled = false
		_loading_btn = null
		_loading_btn_text = ""

func _on_loading_tick() -> void:
	_loading_dots = (_loading_dots + 1) % 4
	if _loading_btn != null:
		var dots := ".".repeat(_loading_dots)
		_loading_btn.text = _loading_btn_text + dots

func _extract_referral_from_text(text: String) -> String:
	var re := RegEx.new()
	if re.compile("(?i)(?:candar_ref|ref|referral)(?:=|%3D)([A-Za-z0-9_-]{4,32})") != OK:
		return ""
	var found := re.search(text)
	return found.get_string(1) if found != null else ""

func _current_referral_code() -> String:
	var typed := referral_edit.text.strip_edges() if referral_edit != null else ""
	if typed != "":
		var extracted := _extract_referral_from_text(typed)
		if extracted != "":
			return extracted.to_upper()
		var direct := typed.replace(" ", "").to_upper()
		var valid_code := RegEx.new()
		if valid_code.compile("^[A-Z0-9_-]{4,32}$") == OK and valid_code.search(direct) != null:
			return direct
		return ""
	return Global.get_pending_referral_code() if Global.has_method("get_pending_referral_code") else ""

func _prefill_referral_from_launch_context() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.75).timeout
	if _auth_in_progress or referral_edit == null or referral_edit.text.strip_edges() != "":
		return
	var code := Global.get_pending_referral_code() if Global.has_method("get_pending_referral_code") else ""
	if code == "":
		return
	referral_edit.text = code.to_upper()
	_ref_row.visible = true
	call_deferred("_apply_responsive_layout")
	# A delayed launch-context update must not replace a login/reset error.
	if status_label.text.strip_edges() == "":
		status_label.text = tr("referral_detected") % code.to_upper()

# ---------- LOGIC ----------
func _on_login_pressed_common(use_google: bool, use_apple: bool = false) -> void:
	if _auth_in_progress:
		return
	var email: String = email_edit.text.strip_edges()
	# Passwords are opaque credentials; spaces can be part of a valid password.
	var password: String = password_edit.text
	var referral: String = _current_referral_code()

	# --- APPLE İLE GİRİŞ (NATIVE - WEB YOK) ---
	if use_apple:
		if not OS.has_feature("ios") and OS.get_name() != "iOS":
			status_label.text = Global.localized_ui_text("Apple ile giriş sadece iOS cihazlarda kullanılabilir.", "Apple sign-in is only available on iOS devices.")
			return

		Global.analytics_event("signup_start", {"method": "apple"})
		status_label.text = tr("status_apple_start")
		if _apple_button != null:
			_set_loading(_apple_button, _apple_button.text, true)

		# 🔥 Native Apple Sign-In + Firebase (global.gd içinde hazır)
		var ares: Array = await Global.apple_sign_in(referral)

		if _apple_button != null:
			_set_loading(_apple_button, _apple_button.text, false)

		var ok_a := false
		var err_a := ""
		if typeof(ares) == TYPE_ARRAY and ares.size() >= 2:
			ok_a = bool(ares[0])
			if not ok_a:
				err_a = str(ares[1])
		else:
			err_a = "Apple girişinden beklenmeyen cevap"

		if ok_a:
			_auth_in_progress = true
			var apple_auth: Dictionary = ares[1] if ares.size() > 1 and typeof(ares[1]) == TYPE_DICTIONARY else {}
			Global.analytics_event(
				"signup_complete" if bool(apple_auth.get("isNewUser", false)) else "login_complete",
				{"screen": "onboarding", "method": "apple"}
			)
			status_label.text = tr("status_login_success")
			await get_tree().create_timer(0.35).timeout
			get_tree().change_scene_to_file("res://home.tscn")
		else:
			if err_a == "":
				err_a = "Apple ile giriş başarısız"
			Global.analytics_event("signup_error", {"method": "apple", "reason": "auth_failed"})
			status_label.text = tr("status_apple_failed") + " " + err_a
			_shake(_email_row)
			_shake(_pass_row)
		return

	# --- GOOGLE İLE GİRİŞ ---
	if use_google:
		Global.analytics_event("signup_start", {"method": "google"})
		status_label.text = tr("status_google_start")
		_set_loading(_google_button, _google_button.text, true)

		var ok_g := false
		var err_g := ""

		if Global != null and Global.has_method("google_sign_in"):
			var gres: Array = await Global.google_sign_in(referral)
			if gres.size() >= 1 and bool(gres[0]):
				ok_g = true
				var google_auth: Dictionary = gres[1] if gres.size() > 1 and typeof(gres[1]) == TYPE_DICTIONARY else {}
				Global.analytics_event(
					"signup_complete" if bool(google_auth.get("isNewUser", false)) else "login_complete",
					{"screen": "onboarding", "method": "google"}
				)
			elif gres.size() >= 2:
				err_g = str(gres[1])
			else:
				err_g = "Beklenmeyen cevap"
		else:
			err_g = "Google oturumu için 'google_sign_in' metodu tanımlı değil."

		_set_loading(_google_button, _google_button.text, false)

		if ok_g:
			_auth_in_progress = true
			status_label.text = tr("status_login_success")
			await get_tree().create_timer(0.45).timeout
			get_tree().change_scene_to_file("res://home.tscn")
		else:
			Global.analytics_event("signup_error", {"method": "google", "reason": "auth_failed"})
			status_label.text = tr("status_google_failed") + " " + err_g
			_shake(_email_row)
			_shake(_pass_row)
		return

	# --- E-POSTA / ŞİFRE İLE GİRİŞ ---
	if email == "" or password == "":
		status_label.text = tr("status_email_password_required")
		_set_input_error(email_edit, true)
		_set_input_error(password_edit, true)
		_shake(_email_row)
		_shake(_pass_row)
		if OS.has_feature("Android"):
			Input.vibrate_handheld(30)
		await get_tree().create_timer(0.5).timeout
		_set_input_error(email_edit, false)
		_set_input_error(password_edit, false)
		return

	status_label.text = tr("status_login_try")
	if login_buttonn != null:
		_set_loading(login_buttonn, login_buttonn.text, true)

	var result: Array = await Global.login_or_register(email, password, referral)

	if login_buttonn != null:
		_set_loading(login_buttonn, login_buttonn.text, false)

	# result beklenen: [bool success, auth_info ya da error_string]
	if typeof(result) == TYPE_ARRAY and result.size() >= 2:
		var success := bool(result[0])

		if success:
			_auth_in_progress = true
			var auth_info: Variant = result[1]

			var id_token := ""
			var refresh_token := ""
			var uid := ""

			if typeof(auth_info) == TYPE_DICTIONARY:
				id_token      = str(auth_info.get("idToken", ""))
				refresh_token = str(auth_info.get("refreshToken", ""))
				uid           = str(auth_info.get("localId", ""))

			# Chat/premium için tokenları FirebaseClient’a gönder
			if id_token != "" and uid != "":
				Firebase.set_tokens(id_token, refresh_token, uid)
				if Global.has_method("save_uid"):
					Global.save_uid(uid)

			status_label.text = tr("status_login_success")
			await get_tree().create_timer(0.45).timeout
			get_tree().change_scene_to_file("res://home.tscn")
		else:
			var err_msg: String = str(result[1])
			match err_msg:
				"Bu e-posta zaten kayıtlı. Şifreni doğru yazıp tekrar dene":
					status_label.text = tr("account_exists_password")
				"Şifre yanlış!":
					status_label.text = tr("wrong_password")
				_:
					if err_msg.begins_with("Geçerli bir"):
						status_label.text = tr("invalid_email")
					elif err_msg.contains("doğrulama"):
						status_label.text = tr("login_failed")
					else:
						# Backend errors may be Turkish-only; do not leak them to
						# users in any other locale. Keep details in Turkish UI.
						status_label.text = ("%s %s" % [tr("login_failed"), err_msg]) if TranslationServer.get_locale().begins_with("tr") else tr("login_failed")
			_shake(_email_row)
			_shake(_pass_row)
	else:
		status_label.text = tr("unexpected_error")

func _on_forgot_password_pressed() -> void:
	if _auth_in_progress:
		return
	var email: String = email_edit.text.strip_edges()
	if email == "":
		status_label.text = tr("status_forgot_email_required")
		_shake(_email_row)
		return

	status_label.text = tr("status_forgot_sending")
	if forgot_button != null:
		_set_loading(forgot_button, forgot_button.text, true)

	var result: Array = await Global.send_password_reset(email)

	if forgot_button != null:
		_set_loading(forgot_button, forgot_button.text, false)

	var ok := false
	var err_txt := ""
	if typeof(result) == TYPE_ARRAY:
		if result.size() >= 1:
			ok = bool(result[0])
		if result.size() >= 2:
			err_txt = str(result[1])

	if ok:
		status_label.text = tr("status_forgot_success")
	else:
		if err_txt != "":
			status_label.text = err_txt
		else:
			status_label.text = tr("status_forgot_failed")

# ---------- BOŞLUĞA TIKLAYINCA KLAVYE KAPATMA ----------
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		var current_focus = get_viewport().gui_get_focus_owner()
		if current_focus:
			current_focus.release_focus()
