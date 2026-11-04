# profile.gd — Godot 4.5 (Sadeleştirilmiş Profil Ekranı)

extends Control

# ---------- RENK PALETİ (HOME / MARKET İLE AYNI) ----------
const COL_BG_TOP        = CandarUI.COL_BG_TOP
const COL_BG_BOT        = CandarUI.COL_BG_BOT
const COL_ACCENT_BOOST  = CandarUI.COL_ACCENT
const COL_ACCENT_PREM   = CandarUI.COL_ACCENT_PREM
const COL_TEXT_MAIN     = CandarUI.COL_TEXT
const COL_TEXT_SUB      = CandarUI.COL_TEXT_SUB
const COL_HEADER_BG     = Color(0.06, 0.09, 0.16, 0.95)
const COL_CARD_BG       = Color(0.12, 0.15, 0.25, 0.95)
const COL_CARD_BORDER   = Color(0.18, 0.22, 0.35, 0.9)

const HEADER_HEIGHT: float = 70.0
const PROFILE_TOP_MARGIN: float = 18.0
const APP_LINK_ANDROID := "https://play.google.com/store/apps/details?id=com.candarnetwork.app"
const APP_LINK_IOS     := "https://apps.apple.com/app/id6756212781"
const APP_DOWNLOAD_LINK := "https://candarnetwork.com/download"
const RATE_PER_REF     := 0.05
const ACHIEVEMENT_CATALOG := [
	{"id": "first_mining", "name": "ach_first_mining"},
	{"id": "100_points", "name": "ach_100_points"},
	{"id": "1000_points", "name": "ach_1000_points"},
	{"id": "10000_points", "name": "ach_10000_points"},
	{"id": "first_referral", "name": "ach_first_referral"},
	{"id": "10_referrals", "name": "ach_10_referrals"},
	{"id": "7_day_streak", "name": "ach_7_day_streak"},
	{"id": "30_day_streak", "name": "ach_30_day_streak"},
	{"id": "premium_member", "name": "ach_premium_member"},
]

const MARGIN_CARD      := 22
const PADDING_CARD     := 16
const GAP_SECTION      := 8
const GAP_BUTTONS      := 14

# ---------- SAHNEDEN GELEN NODES ----------
@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var vbox: VBoxContainer       = $MarginContainer/ScrollContainer/VBoxContainer
@onready var email_label: Label       = $MarginContainer/ScrollContainer/VBoxContainer/EmailLabel
@onready var puan_label: Label        = $MarginContainer/ScrollContainer/VBoxContainer/PuanLabel
@onready var referral_label: Label    = $MarginContainer/ScrollContainer/VBoxContainer/ReferralLabel
@onready var back_button: Button      = $MarginContainer/ScrollContainer/VBoxContainer/BackButton
@onready var delete_btn: Button = $MarginContainer/ScrollContainer/VBoxContainer/DeleteAccountButton
@onready var confirm_dialog: ConfirmationDialog = $MarginContainer/ScrollContainer/VBoxContainer/ConfirmDeleteDialog
@onready var status_label: Label = $MarginContainer/ScrollContainer/VBoxContainer/StatusLabel

# ---------- RUNTIME OLARAK OLUŞAN NODES ----------
var title_label: Label
var header_back_button: Button

var card_user: PanelContainer
var stats_grid: GridContainer
var stat_candar_v: Label
var stat_rate_v: Label
var stat_refs_v: Label
var progress_box: VBoxContainer
var progress_text: Label
var progress_bar: ProgressBar
var membership_card: PanelContainer
var membership_premium_label: Label
var membership_boost_label: Label
var membership_note_label: Label

var actions_box: VBoxContainer
var btn_leader: Button
var btn_achievements: Button
var btn_share: Button
var btn_reset: Button
var btn_language: Button
var btn_logout: Button
var btn_back: Button
var footer: Label
var badge_label: Label
var avatar_view: TextureRect

# Toast
var _toast_panel: PanelContainer
var _toast_label: Label
var _invite_overlay: ColorRect
var _active_sheet: Control
var _account_busy := false
var _retry_button: Button
var _scroll_pointer := -2
var _scroll_start := Vector2.ZERO
var _scroll_start_value := 0
var _scroll_dragging := false
var _drag_disabled_buttons: Array[BaseButton] = []

# ---------- VERİ ----------
var current_user_id: String = ""
var user_data: Dictionary   = {}
var referans_sayisi: int    = 0
var kazim_orani: float      = 1.0

# ================= READY =================
func _ready() -> void:
	Global.analytics_page("Profile", "app://candar/profile")
	Global.analytics_event("app_screen_view", {"screen": "profile"})
	_create_background()
	_create_header()
	_build_ui()
	_apply_style()
	_configure_profile_scroll_behavior()
	_apply_profile_responsive_layout()
	if not get_viewport().size_changed.is_connected(_apply_profile_responsive_layout):
		get_viewport().size_changed.connect(_apply_profile_responsive_layout)
	_build_toast()
	await Global.apply_safe_area(self)
	_apply_profile_responsive_layout()
	if scroll_container:
		if (OS.has_feature("android") or OS.has_feature("ios")) and not Global.is_ad_free_user():
			CandarUI.apply_banner_bottom_inset(scroll_container)
		else:
			scroll_container.offset_bottom = 0

	# Eski sahne geri butonu görünmesin
	if is_instance_valid(back_button):
		back_button.visible = false

	# Eventler
	btn_leader.pressed.connect(_open_leaderboard)
	btn_achievements.pressed.connect(_open_achievements)
	btn_share.pressed.connect(_on_share_pressed)
	btn_reset.pressed.connect(_on_reset_pressed)
	btn_language.pressed.connect(_show_language_dialog)
	btn_back.pressed.connect(_go_home)
	btn_logout.pressed.connect(_on_logout_pressed)
	delete_btn.text = tr("delete_account_button")
	delete_btn.pressed.connect(_on_delete_pressed)

	if is_instance_valid(btn_back):
		btn_back.visible = false
	if is_instance_valid(header_back_button):
		header_back_button.visible = true

	current_user_id = _get_uid()
	if current_user_id == "":
		get_tree().call_deferred("change_scene_to_file", "res://onboarding.tscn")
		return

	await _load_user(current_user_id)
	if user_data.is_empty():
		return
	var achievement_sync: Array = await Global.check_and_unlock_achievements(current_user_id)
	if achievement_sync.size() > 1 and bool(achievement_sync[0]) and achievement_sync[1] is Array and not achievement_sync[1].is_empty():
		await _load_user(current_user_id)
	await _compute_rate_and_update_ui()

func _configure_profile_scroll_behavior() -> void:
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.follow_focus = true
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_pass_profile_pointer_events(vbox)

func _pass_profile_pointer_events(node: Node) -> void:
	# Cards and their contents must not swallow a drag before it reaches the scroll.
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_pass_profile_pointer_events(child)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(scroll_container) or is_instance_valid(_active_sheet) or is_instance_valid(_invite_overlay):
		return
	var pointer := -2
	var point := Vector2.ZERO
	var pressed := false
	var released := false
	var moved := false
	if event is InputEventScreenTouch:
		pointer = event.index
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		pointer = event.index
		point = event.position
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _scroll_pointer < 0:
		pointer = -1
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and _scroll_pointer == -1:
		pointer = -1
		point = event.position
		moved = true
	else:
		return
	if pressed and _scroll_pointer == -2 and scroll_container.get_global_rect().has_point(point):
		_scroll_pointer = pointer
		_scroll_start = point
		_scroll_start_value = scroll_container.scroll_vertical
		_scroll_dragging = false
	elif pointer == _scroll_pointer and moved:
		var delta := point.y - _scroll_start.y
		var bar := scroll_container.get_v_scroll_bar()
		if absf(delta) > 12.0 and bar.max_value > bar.page:
			if not _scroll_dragging:
				_scroll_dragging = true
				# Prevent releasing a drag over a button from activating that action.
				for button in [btn_share, btn_achievements, btn_leader, btn_reset, btn_logout, delete_btn, _retry_button]:
					if is_instance_valid(button) and not button.disabled:
						button.disabled = true
						_drag_disabled_buttons.append(button)
			scroll_container.scroll_vertical = _scroll_start_value - roundi(delta)
			get_viewport().set_input_as_handled()
	elif pointer == _scroll_pointer and released:
		if _scroll_dragging:
			# Let ScrollContainer finish its own gesture; buttons stay disabled
			# until release propagation has completed.
			_restore_drag_buttons.call_deferred()
		_scroll_pointer = -2
		_scroll_dragging = false

func _restore_drag_buttons() -> void:
	for button in _drag_disabled_buttons:
		if is_instance_valid(button):
			button.disabled = _account_busy and button in [btn_reset, btn_logout, delete_btn]
	_drag_disabled_buttons.clear()

func _on_delete_pressed() -> void:
	if _account_busy:
		return
	var dialog := _create_glass_dialog(tr("delete_account_title"), Vector2(520, 360), true)
	var rt := dialog.find_child("rt", true, false) as RichTextLabel
	if rt:
		rt.text = tr("delete_account_body")
	var actions := dialog.find_child("actions", true, false) as GridContainer
	if actions:
		var cancel_btn := CandarUI.make_secondary_button(tr("delete_account_cancel"), 80)
		cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel_btn.add_theme_font_size_override("font_size", 26)
		cancel_btn.pressed.connect(_close_profile_sheet.bind(dialog))
		actions.add_child(cancel_btn)
		var delete_confirm := Button.new()
		delete_confirm.text = tr("delete_account_confirm")
		delete_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		delete_confirm.custom_minimum_size.y = 80
		delete_confirm.add_theme_font_size_override("font_size", 26)
		delete_confirm.add_theme_color_override("font_color", Color.WHITE)
		var danger := StyleBoxFlat.new()
		danger.bg_color = Color("#b91c1c")
		danger.set_corner_radius_all(16)
		var danger_hover := danger.duplicate() as StyleBoxFlat
		danger_hover.bg_color = Color("#dc2626")
		var danger_pressed := danger.duplicate() as StyleBoxFlat
		danger_pressed.bg_color = Color("#991b1b")
		delete_confirm.add_theme_stylebox_override("normal", danger)
		delete_confirm.add_theme_stylebox_override("hover", danger_hover)
		delete_confirm.add_theme_stylebox_override("pressed", danger_pressed)
		delete_confirm.pressed.connect(func():
			_close_profile_sheet(dialog)
			_on_delete_confirmed()
		)
		actions.add_child(delete_confirm)


func _on_delete_confirmed() -> void:
	await _do_delete_account()

func _safe_set_status(msg: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = msg
		status_label.visible = not msg.is_empty()
	else:
		print("PROFILE STATUS:", msg) # yedek

func _set_account_busy(busy: bool) -> void:
	_account_busy = busy
	for button in [btn_reset, btn_logout, delete_btn, header_back_button]:
		if is_instance_valid(button):
			button.disabled = busy

func _do_delete_account() -> void:
	if _account_busy:
		return
	_set_account_busy(true)
	_safe_set_status(tr("delete_account_in_progress"))
	delete_btn.text = tr("delete_account_in_progress")
	var res: Array = await Global.delete_my_account()
	var ok := res.size() > 0 and bool(res[0])
	if ok:
		# delete_my_account already awaits the native secure logout.
		if FileAccess.file_exists("user://uid.txt"):
			var d := DirAccess.open("user://")
			if d:
				d.remove("uid.txt")
		get_tree().change_scene_to_file("res://onboarding.tscn")
	else:
		_set_account_busy(false)
		delete_btn.text = tr("delete_account_button")
		_safe_set_status(tr("delete_account_error"))
		_show_info_dialog(tr("delete_account_error"))

# ----------------------------------------------------------
# BACKGROUND + HEADER
# ----------------------------------------------------------
func _create_background() -> void:
	var tex_rect = TextureRect.new()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([COL_BG_TOP, COL_BG_BOT])
	var gtex = GradientTexture2D.new()
	gtex.gradient = gradient
	gtex.fill_from = Vector2(0.5, 0)
	gtex.fill_to = Vector2(0.5, 1)
	gtex.width = 64
	gtex.height = 64
	tex_rect.texture = gtex
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tex_rect)
	move_child(tex_rect, 0)

func _create_header() -> void:
	var hdr := CandarUI.create_header(self, tr("profile_header_title"), true)
	if hdr.get("header") and hdr["header"]:
		(hdr["header"] as Panel).z_index = 40
		(hdr["header"] as Panel).offset_bottom = CandarUI.header_total_height() + 24
	if hdr.get("title"):
		hdr["title"].add_theme_font_size_override("font_size", 32)
		hdr["title"].offset_bottom = CandarUI.header_total_height() + 24
	if hdr.get("back") and hdr["back"]:
		header_back_button = hdr["back"]
		header_back_button.size = Vector2(80, 80)
		header_back_button.position.y = CandarUI.top_safe_inset() + 4
		header_back_button.pressed.connect(_go_home)

# ================= UI BUILD =================
func _build_ui() -> void:
	# İçerik iOS güvenli alanına sıkışmadan, sayfa içinde başlasın.
	vbox.offset_top = PROFILE_TOP_MARGIN
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 18)

	# Sahnede önceden duran çocukları temizle (node’ları silmeden)
	# NOT: remove_child parent’sız bırakır, aşağıda güvenli ekliyoruz
	for c in vbox.get_children():
		vbox.remove_child(c)
		if c == puan_label or c == back_button:
			add_child(c)
			c.hide()
		elif c not in [email_label, referral_label, delete_btn, confirm_dialog, status_label]:
			c.queue_free()

	# Confirm dialog root'ta dursun (popup için en stabil yer)
	if is_instance_valid(confirm_dialog) and confirm_dialog.get_parent() != self:
		add_child(confirm_dialog)

	# ---- ANA KART ----
	card_user = _mk_card()
	vbox.add_child(card_user)

	var wrapper := card_user.get_child(0) as MarginContainer
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	wrapper.add_child(body)

	# Avatar + rozet
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	avatar_view = TextureRect.new()
	avatar_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_view.custom_minimum_size = Vector2(58, 58)
	row.add_child(avatar_view)

	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_theme_constant_override("separation", 4)

	badge_label = Label.new()
	badge_label.name = "BadgeLabel"
	badge_label.text = tr("profile_badge_label") % tr("badge_bronze")
	badge_label.add_theme_color_override("font_color", COL_TEXT_MAIN)
	badge_label.add_theme_font_size_override("font_size", 20)

	var info_note := Label.new()
	info_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_note.text = tr("profile_info_note") % RATE_PER_REF
	info_note.add_theme_font_size_override("font_size", 24)
	info_note.add_theme_color_override("font_color", COL_TEXT_SUB)

	meta.add_child(badge_label)
	meta.add_child(info_note)
	row.add_child(meta)
	body.add_child(row)

	# Email (parent’sızsa direkt ekle, parent’lıysa reparent)
	if is_instance_valid(email_label):
		if email_label.get_parent() == null:
			body.add_child(email_label)
		else:
			email_label.reparent(body)
		email_label.add_theme_font_size_override("font_size", 24)
		email_label.add_theme_color_override("font_color", COL_TEXT_MAIN)

	# Stats grid
	stats_grid = GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 16)
	stats_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(stats_grid)

	stat_candar_v = _mk_stat_cell(tr("profile_stat_candar"))
	stat_rate_v   = _mk_stat_cell(tr("profile_stat_rate"))
	stat_refs_v   = _mk_stat_cell(tr("profile_stat_refs"))

	# Referral satırı + Copy
# Referral satırı (Copy butonu KALDIRILDI)
	if is_instance_valid(referral_label):
		if referral_label.get_parent() == null:
			body.add_child(referral_label)
		else:
			referral_label.reparent(body)

		referral_label.add_theme_font_size_override("font_size", 24)
		referral_label.add_theme_color_override("font_color", COL_TEXT_MAIN)

	# Progress
	progress_box = VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 6)
	body.add_child(progress_box)

	progress_text = Label.new()
	progress_text.add_theme_font_size_override("font_size", 28)
	progress_text.add_theme_color_override("font_color", COL_TEXT_MAIN)
	progress_box.add_child(progress_text)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.step = 0.01
	progress_bar.show_percentage = true
	progress_bar.custom_minimum_size = Vector2(0, 14)

	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color("#192135")
	sb_bg.set_corner_radius_all(999)

	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = COL_ACCENT_BOOST
	sb_fill.set_corner_radius_all(999)

	progress_bar.add_theme_stylebox_override("background", sb_bg)
	progress_bar.add_theme_stylebox_override("fill", sb_fill)
	progress_box.add_child(progress_bar)

	membership_card = _mk_card()
	vbox.add_child(membership_card)
	var member_wrap := membership_card.get_child(0) as MarginContainer
	var member_box := VBoxContainer.new()
	member_box.add_theme_constant_override("separation", 4)
	member_wrap.add_child(member_box)

	var member_title := Label.new()
	member_title.text = _ui_text("Üyelik ve Boost", "Membership and Boost")
	member_title.add_theme_color_override("font_color", COL_ACCENT_BOOST.lightened(0.1))
	member_title.add_theme_font_size_override("font_size", 28)
	member_box.add_child(member_title)

	membership_premium_label = Label.new()
	membership_boost_label = Label.new()
	membership_note_label = Label.new()
	for l in [membership_premium_label, membership_boost_label, membership_note_label]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", COL_TEXT_MAIN)
		l.add_theme_font_size_override("font_size", 19)
		member_box.add_child(l)
	membership_note_label.add_theme_color_override("font_color", COL_TEXT_SUB)
	_update_membership_card()

	# Action buttons — gruplu
	actions_box = VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", GAP_SECTION)
	vbox.add_child(actions_box)

	btn_back   = _mk_dark_btn(_ui_text("← Ana Sayfaya Dön", "← Back to Home"), true)
	btn_leader = _mk_dark_btn(tr("btn_leaderboard"), true)
	btn_achievements = _mk_dark_btn(_ui_text("Başarılarım", "My Achievements"), true)
	btn_share  = _mk_dark_btn(tr("invite_action"), true)
	btn_reset  = _mk_dark_btn(_ui_text("Şifre Sıfırlama E-postası", "Password Reset Email"), true)
	btn_language = _mk_dark_btn(_ui_text("🌐 Dil / Language", "🌐 App Language"), true)
	btn_logout = _mk_dark_btn(tr("btn_logout"), false)

	_add_action_group(actions_box, _ui_text("Topluluk", "Community"), [btn_share, btn_achievements, btn_leader])
	var all_btns: Array = [btn_language, btn_reset, btn_logout]
	if is_instance_valid(delete_btn):
		if delete_btn.get_parent() != null:
			delete_btn.get_parent().remove_child(delete_btn)
		_style_delete_button()
		all_btns.append(delete_btn)
	_add_action_group(actions_box, _ui_text("Hesap Ayarları", "Account Settings"), all_btns)
	add_child(btn_back)
	btn_back.hide()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.add_theme_color_override("font_color", Color("#fca5a5"))
	vbox.add_child(status_label)
	status_label.hide()
	_retry_button = _mk_dark_btn(_ui_text("Yeniden Dene", "Try Again"), true)
	_retry_button.pressed.connect(_retry_profile_load)
	vbox.add_child(_retry_button)
	_retry_button.hide()

	# Footer
	footer = Label.new()
	var app_version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	footer.text = "Candar Network • v%s • 2026" % app_version if app_version != "" else "Candar Network • 2026"
	footer.modulate = COL_TEXT_SUB
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 14)
	vbox.add_child(footer)


func _add_action_group(parent: VBoxContainer, title: String, buttons: Array) -> void:
	var card := CandarUI.make_card(COL_ACCENT_BOOST, 16, COL_CARD_BG, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var title_lbl := CandarUI.make_section_title(title)
	title_lbl.add_theme_font_size_override("font_size", 28)
	box.add_child(title_lbl)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	box.add_child(button_row)
	for b in buttons:
		if b is Button:
			(b as Button).custom_minimum_size.y = 80
			(b as Button).add_theme_font_size_override("font_size", 24)
			(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(b as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if b == btn_reset:
				box.add_child(b)
				box.move_child(b, 1)
			else:
				button_row.add_child(b)
	parent.add_child(card)


func _apply_profile_responsive_layout() -> void:
	var margin := $MarginContainer as MarginContainer
	var vs := get_viewport_rect().size
	var is_tablet := vs.x >= 900.0 or (vs.x > 700.0 and vs.y / maxf(vs.x, 1.0) < 1.55)
	var content_w := minf(vs.x - 40.0, 680.0 if is_tablet else 640.0)
	content_w = maxf(content_w, minf(vs.x - 24.0, 360.0))
	var side_margin := maxf((vs.x - content_w) / 2.0, 14.0)

	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.scale = Vector2.ONE
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", int(side_margin))
	margin.add_theme_constant_override("margin_right", int(side_margin))
	var top_margin := CandarUI.header_total_height() + 24.0 + 12.0
	margin.add_theme_constant_override("margin_top", int(top_margin))
	var bottom_margin := 18
	if (OS.has_feature("android") or OS.has_feature("ios")) and not Global.is_ad_free_user():
		bottom_margin += int(CandarUI.AD_BANNER_INSET)
	margin.add_theme_constant_override("margin_bottom", bottom_margin)

	vbox.custom_minimum_size = Vector2(0, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", 10)

	if stats_grid:
		stats_grid.columns = 3

	var label_font := 24
	var value_font := 26
	for n in [email_label, referral_label, progress_text, badge_label]:
		if n and n is Label:
			n.add_theme_font_size_override("font_size", value_font)
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for n in [membership_premium_label, membership_boost_label, membership_note_label]:
		if n and n is Label:
			n.add_theme_font_size_override("font_size", label_font)
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for b in [btn_leader, btn_achievements, btn_share, btn_reset, btn_back, btn_logout, delete_btn]:
		if b and b is Button:
			b.add_theme_font_size_override("font_size", label_font)
			b.custom_minimum_size.y = 80
	if btn_back:
		btn_back.custom_minimum_size.y = 60 if is_tablet else 56
	# Keep equivalent readable sizes when a viewport uses points instead of 720 units.
	var ui_scale := clampf(vs.x / 720.0, 0.5, 1.0)
	_scale_profile_content(vbox, ui_scale)
	avatar_view.custom_minimum_size = Vector2(48, 48) * ui_scale
	footer.add_theme_font_size_override("font_size", roundi(20 * ui_scale))
	for card in [card_user, membership_card]:
		var wrapper := card.get_child(0) as MarginContainer
		for side in ["left", "right", "top", "bottom"]:
			wrapper.add_theme_constant_override("margin_" + side, roundi(PADDING_CARD * ui_scale))

func _scale_profile_content(node: Node, factor: float) -> void:
	if node is Label or node is Button:
		if not node.has_meta("profile_base_font"):
			node.set_meta("profile_base_font", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("profile_base_font")) * factor))
	if node is Button:
		node.custom_minimum_size.y = 80 * factor
	if node is BoxContainer:
		if not node.has_meta("profile_base_gap"):
			node.set_meta("profile_base_gap", node.get_theme_constant("separation"))
		node.add_theme_constant_override("separation", roundi(float(node.get_meta("profile_base_gap")) * factor))
	for child in node.get_children():
		_scale_profile_content(child, factor)
# ================= HELPERS (GENEL) =================
func _get_uid() -> String:
	var p := "user://uid.txt"
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var s: String = f.get_as_text().strip_edges()
		f.close()
		return s
	return ""

func _fmt_points(v: float) -> String: return "%.2f" % v
func _fmt_rate(v: float) -> String: return "x%.2f" % v

func _is_tr() -> bool:
	var locale := TranslationServer.get_locale()
	return locale.begins_with("tr") if locale != "" else OS.get_locale().begins_with("tr")

func _ui_text(tr_text: String, en_text: String) -> String:
	return Global.localized_ui_text(tr_text, en_text)

func _go_home() -> void:
	Global.analytics_event("profile_back", {"screen": "profile"})
	get_tree().change_scene_to_file("res://home.tscn")

func _referral_rate_for_count(ref_count: int) -> float:
	return snapped(1.0 + float(maxi(ref_count, 0)) * RATE_PER_REF, 0.01)

func _badge_name_for_ref_count(ref_count: int) -> String:
	if ref_count < 10: return "badge_bronze"
	if ref_count < 20: return "badge_silver"
	if ref_count < 30: return "badge_gold"
	return "badge_diamond"

func _badge_colors(name: String) -> Dictionary:
	match name:
		"badge_bronze":
			return {"ring": Color8(205,135, 95), "glow": Color8(255,170,120,140)}
		"badge_silver":
			return {"ring": COL_ACCENT_PREM.lightened(0.2), "glow": COL_ACCENT_PREM.lightened(0.4)}
		"badge_gold":
			return {"ring": COL_ACCENT_BOOST.lightened(0.1), "glow": COL_ACCENT_BOOST.lightened(0.3)}
		"badge_diamond":
			return {"ring": Color8(130,205,255), "glow": Color8(140,230,255,170)}
		_:
			return {"ring": Color8(200,200,200), "glow": Color8(220,220,220,140)}

func _add_section_gap() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = GAP_SECTION
	vbox.add_child(gap)

func _mk_card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_CARD_BG
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = COL_CARD_BORDER
	card.add_theme_stylebox_override("panel", sb)

	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", PADDING_CARD)
	wrapper.add_theme_constant_override("margin_right", PADDING_CARD)
	wrapper.add_theme_constant_override("margin_top", PADDING_CARD)
	wrapper.add_theme_constant_override("margin_bottom", PADDING_CARD)
	card.add_child(wrapper)

	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card

func _mk_stat_cell(title: String) -> Label:
	if not is_instance_valid(stats_grid):
		return Label.new()
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	var t := Label.new()
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.text = title
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", COL_TEXT_SUB)
	var v := Label.new()
	v.text = "-"
	v.add_theme_font_size_override("font_size", 28)
	v.add_theme_color_override("font_color", COL_TEXT_MAIN)
	cell.add_child(t)
	cell.add_child(v)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 24)
	v.add_theme_font_size_override("font_size", 30)
	stats_grid.add_child(cell)
	return v

func _mk_pill_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 32)
	var base := StyleBoxFlat.new()
	base.bg_color = COL_ACCENT_BOOST
	base.set_corner_radius_all(16)
	var hover := base.duplicate()
	hover.bg_color = COL_ACCENT_BOOST.lightened(0.1)
	var pressed := base.duplicate()
	pressed.bg_color = COL_ACCENT_BOOST.darkened(0.1)
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color("#232c3b"))
	btn.add_theme_font_size_override("font_size", 28)
	return btn
	
func _mk_dark_btn(text: String, is_premium: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 60)
	btn.add_theme_font_size_override("font_size", 28)

	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_CARD_BG.darkened(0.1)
	normal.set_corner_radius_all(14)
	normal.shadow_size = 12
	normal.shadow_color = Color(0, 0, 0, 0.2)

	var hover := normal.duplicate()
	hover.bg_color = COL_CARD_BG.lightened(0.05)
	var pressed := normal.duplicate()
	pressed.bg_color = COL_CARD_BG.darkened(0.2)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

	if is_premium:
		btn.add_theme_color_override("font_color", COL_ACCENT_BOOST)
	else:
		btn.add_theme_color_override("font_color", COL_TEXT_MAIN)

	return btn
func _style_delete_button() -> void:
	if not is_instance_valid(delete_btn):
		return

	delete_btn.custom_minimum_size = Vector2(0, 60)
	delete_btn.add_theme_font_size_override("font_size", 28)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#301b28")
	normal.border_color = Color("#b94a60")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	normal.shadow_size = 16
	normal.shadow_color = Color(0, 0, 0, 0.4)

	var hover := normal.duplicate()
	hover.bg_color = Color("#482432")

	var pressed := normal.duplicate()
	pressed.bg_color = Color("#25131c")

	delete_btn.add_theme_stylebox_override("normal", normal)
	delete_btn.add_theme_stylebox_override("hover", hover)
	delete_btn.add_theme_stylebox_override("pressed", pressed)
	delete_btn.add_theme_color_override("font_color", Color("#FDF2F5"))

# ================= STYLE =================
func _apply_style() -> void:
	var cr := get_node_or_null("ColorRect")
	if cr and cr is ColorRect:
		cr.queue_free()

	# Puan label’ı artık kart içinde gösterdiğimiz için görünmesine gerek yok
	if is_instance_valid(puan_label):
		puan_label.visible = false

# ================= DATA LOAD =================
func _retry_profile_load() -> void:
	_retry_button.disabled = true
	await _load_user(current_user_id)
	if not user_data.is_empty():
		await _compute_rate_and_update_ui()
	_retry_button.disabled = false

func _load_user(uid: String) -> void:
	_safe_set_status("")
	_retry_button.hide()
	if email_label:
		email_label.text = tr("profile_email_loading")
	if puan_label:
		puan_label.text = tr("profile_points_loading")
	if referral_label:
		referral_label.text = tr("profile_refcode_loading")

	var doc: Variant = await Global.get_user_doc(uid)
	if typeof(doc) == TYPE_DICTIONARY and (doc as Dictionary).has("fields"):
		user_data = (doc as Dictionary)["fields"]
		Global.sync_point_entitlements(user_data)
		if Global.is_ad_free_user():
			Global.ads_hide_banner()
			scroll_container.offset_bottom = 0
			_apply_profile_responsive_layout()
		var mail := _get_field_string(user_data, "email")

		# Candar coin ana points alanından gelir; eski mining.points sadece fallback.
		var mining: Dictionary = user_data.get("mining", {}).get("mapValue", {})
		var mining_fields: Dictionary = mining.get("fields", {})
		var pts := _get_field_double(user_data, "points", _get_field_double(mining_fields, "points", 0.0))
		var refc := _get_field_string(user_data, "referralCode")

		if email_label:
			email_label.text = tr("profile_email_prefix") + (mail if mail != "" else "-")
		if puan_label:
			puan_label.text = tr("profile_points_prefix") + _fmt_points(pts)
		if referral_label:
			referral_label.text = tr("profile_refcode_prefix") + (refc if refc != "" else "-")
			if stat_candar_v:
				stat_candar_v.text = _fmt_points(pts)
			_update_membership_card()
	else:
		user_data = {}
		_safe_set_status(_ui_text("Profil yüklenemedi. Bağlantını kontrol edip tekrar dene.", "Could not load your profile. Check your connection and try again."))
		_retry_button.show()
		if email_label:
			email_label.text = tr("profile_email_failed")
		if puan_label:
			puan_label.text = tr("profile_points_failed")
		if referral_label:
			referral_label.text = tr("profile_refcode_failed")
		_update_membership_card()

func _get_field_string(fields: Dictionary, key: String) -> String:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("stringValue"):
		return String((v as Dictionary)["stringValue"])
	return ""

func _get_field_double(fields: Dictionary, key: String, default_value: float = 0.0) -> float:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY:
		# Önce ondalıklı sayı mı diye bak
		if (v as Dictionary).has("doubleValue"):
			return float((v as Dictionary)["doubleValue"])
		# YOKSA tam sayı mı diye bak (Çok önemli!)
		elif (v as Dictionary).has("integerValue"):
				return float((v as Dictionary)["integerValue"])
	return default_value

func _update_membership_card() -> void:
	if not membership_premium_label or not membership_boost_label or not membership_note_label:
		return
	if user_data.is_empty():
		membership_premium_label.text = _ui_text("Üyelik bilgisi henüz yüklenmedi.", "Membership information is not loaded yet.")
		membership_boost_label.text = ""
		membership_note_label.text = ""
		return
	var premium_active := false
	if user_data.has("isPremium") and typeof(user_data["isPremium"]) == TYPE_DICTIONARY and user_data["isPremium"].has("booleanValue"):
		premium_active = bool(user_data["isPremium"]["booleanValue"])
	var premium_map: Dictionary = user_data.get("premium", {}).get("mapValue", {}).get("fields", {})
	if premium_map.has("is_active") and typeof(premium_map["is_active"]) == TYPE_DICTIONARY and premium_map["is_active"].has("booleanValue"):
		premium_active = bool(premium_map["is_active"]["booleanValue"])

	var multiplier := 1.0
	if user_data.has("currentMultiplier") and typeof(user_data["currentMultiplier"]) == TYPE_DICTIONARY:
		multiplier = _num_from_field(user_data["currentMultiplier"], 1.0)
	var mining_fields: Dictionary = user_data.get("mining", {}).get("mapValue", {}).get("fields", {})
	if mining_fields.has("active_multiplier") and typeof(mining_fields["active_multiplier"]) == TYPE_DICTIONARY:
		multiplier = _num_from_field(mining_fields["active_multiplier"], multiplier)

	var boost_exp := _timestamp_from_field(user_data.get("boostExpiresAt", {}))
	if boost_exp == "" and mining_fields.has("boost_expires_at"):
		boost_exp = _timestamp_from_field(mining_fields["boost_expires_at"])
	var premium_exp := _timestamp_from_field(user_data.get("premiumExpiresAt", {}))
	if premium_exp == "" and premium_map.has("expires_at"):
		premium_exp = _timestamp_from_field(premium_map["expires_at"])

	if premium_exp != "" and not _is_active_until(premium_exp):
		premium_active = false
	if boost_exp != "" and not _is_active_until(boost_exp):
		multiplier = 1.0

	var premium_txt := _ui_text("Aktif", "Active") if premium_active else _ui_text("Kapalı", "Off")
	if premium_exp != "" and not _is_active_until(premium_exp):
		premium_txt = _ui_text("Süresi doldu", "Expired")
	if premium_exp != "":
		premium_txt += " · " + _short_date(premium_exp)
	membership_premium_label.text = "%s: %s" % [_ui_text("Premium", "Premium"), premium_txt]

	var point_multiplier := _get_field_double(user_data, "pointsBoostMultiplier", 1.0)
	var point_boost_exp := _timestamp_from_field(user_data.get("pointsBoostUntil", {}))
	var point_boost_active := _is_active_until(point_boost_exp)
	var combined_multiplier := multiplier * (point_multiplier if point_boost_active else 1.0)
	var boost_txt := "x%.2f" % combined_multiplier if combined_multiplier > 1.0 else _ui_text("Aktif değil", "Not active")
	if boost_exp != "" and multiplier > 1.0:
		boost_txt += " · " + _short_date(boost_exp)
	elif point_boost_active:
		boost_txt += " · " + _short_date(point_boost_exp)
	membership_boost_label.text = "%s: %s" % [_ui_text("Boost", "Boost"), boost_txt]
	var profile_gold := _get_field_string(user_data, "profilePrivilege") == "gold"
	var ad_free_exp := _timestamp_from_field(user_data.get("pointsAdFreeUntil", {}))
	var ai_credits := _get_field_int(user_data, "aiBonusCredits", 0)
	membership_note_label.text = _ui_text(
		"Puan avantajları: %s profil · %d AI hakkı%s",
		"Point benefits: %s profile · %d AI credits%s"
	) % [
		_ui_text("Altın", "Gold") if profile_gold else _ui_text("Standart", "Standard"),
		ai_credits,
		(_ui_text(" · Reklamsız: ", " · Ad-free until: ") + _short_date(ad_free_exp)) if _is_active_until(ad_free_exp) else ""
	]

func _get_field_int(fields: Dictionary, key: String, default_value := 0) -> int:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY:
		if (v as Dictionary).has("integerValue"):
			return int(str((v as Dictionary)["integerValue"]))
		if (v as Dictionary).has("doubleValue"):
			return int(float((v as Dictionary)["doubleValue"]))
	return default_value

func _num_from_field(field: Dictionary, default_value: float) -> float:
	if field.has("doubleValue"):
		return float(field["doubleValue"])
	if field.has("integerValue"):
		return float(field["integerValue"])
	if field.has("stringValue") and String(field["stringValue"]).is_valid_float():
		return float(String(field["stringValue"]))
	return default_value

func _timestamp_from_field(field: Variant) -> String:
	if typeof(field) == TYPE_DICTIONARY and (field as Dictionary).has("timestampValue"):
		return String((field as Dictionary)["timestampValue"])
	return ""

func _is_active_until(ts: String) -> bool:
	return not ts.is_empty() and Time.get_unix_time_from_datetime_string(ts) > Time.get_unix_time_from_system()

func _short_date(ts: String) -> String:
	if ts.length() >= 10:
		return ts.substr(0, 10)
	return ts

# ======== RATE & PROGRESS ========
func _compute_rate_and_update_ui() -> void:
	var rate_components: Dictionary = await Global.get_user_mining_rate_components(current_user_id, user_data)
	referans_sayisi = maxi(int(rate_components.get("ref_count", 0)), 0)
	kazim_orani = float(rate_components.get("total_rate", snapped(1.0 + float(referans_sayisi) * RATE_PER_REF, 0.01)))
	Global.mining_rate = kazim_orani

	if stat_rate_v:
		stat_rate_v.text = _fmt_rate(kazim_orani)
	if stat_refs_v:
		stat_refs_v.text = str(referans_sayisi)

	_update_progress_ui()
	_update_badge_and_avatar()

func _update_badge_and_avatar() -> void:
	var badge_key := _badge_name_for_ref_count(referans_sayisi)
	if is_instance_valid(badge_label):
		var base_badge: String = tr("profile_badge_label") % tr(badge_key)
		if _get_field_string(user_data, "profilePrivilege") == "gold":
			badge_label.text = _ui_text("⭐ Altın Profil · ", "⭐ Gold Profile · ") + base_badge
		else:
			badge_label.text = base_badge

	var colors := _badge_colors(badge_key)
	avatar_view.texture = _make_badge_avatar(colors["ring"], colors["glow"])

func _update_progress_ui() -> void:
	var current_ref_rate := _referral_rate_for_count(referans_sayisi)
	var next_ref_target := 30
	var lower_ref_target := 20
	var is_max := referans_sayisi >= 30
	if referans_sayisi < 10:
		next_ref_target = 10
		lower_ref_target = 0
	elif referans_sayisi < 20:
		next_ref_target = 20
		lower_ref_target = 10

	if progress_bar:
		if is_max:
			progress_bar.value = 1.0
		else:
			var target_span := maxi(next_ref_target - lower_ref_target, 1)
			progress_bar.value = clampf(
				float(referans_sayisi - lower_ref_target) / float(target_span),
				0.0,
				1.0
			)

	if progress_text:
		if is_max:
			progress_text.text = tr("profile_progress_max") % _fmt_rate(current_ref_rate)
		else:
			var next_label_key := _badge_name_for_ref_count(next_ref_target)
			var next_ref_rate := _referral_rate_for_count(next_ref_target)
			var need_refs := next_ref_target - referans_sayisi
			progress_text.text = tr("profile_progress_to_next") % [tr(next_label_key), _fmt_rate(next_ref_rate), need_refs]

func _set_rate_and_refs(rate: float, refs: int) -> void:
	kazim_orani = rate
	referans_sayisi = refs
	Global.mining_rate = rate
	if stat_rate_v:
		stat_rate_v.text = _fmt_rate(rate)
	if stat_refs_v:
		stat_refs_v.text = str(refs)

func _store_link_for_platform() -> String:
	if OS.has_feature("android"):
		return APP_LINK_ANDROID
	elif OS.has_feature("ios"):
		return APP_LINK_IOS
	return "Android: %s\niOS: %s" % [APP_LINK_ANDROID, APP_LINK_IOS]

func _referral_download_link(ref_code: String) -> String:
	return "%s?ref=%s&src=app_invite&utm_source=app&utm_medium=referral&utm_campaign=member_invite" % [
		APP_DOWNLOAD_LINK,
		ref_code.uri_encode()
	]

func _on_share_pressed() -> void:
	Global.analytics_event("share_referral_tap", {"screen": "profile"})
	var ref_code := _get_field_string(user_data, "referralCode")
	if ref_code == "":
		_toast(_ui_text("Referans kodu henüz yüklenmedi.", "Referral code is not loaded yet."))
		return
	
	_show_share_dialog(ref_code)

func _show_share_dialog(ref_code: String) -> void:
	if is_instance_valid(_active_sheet):
		_close_profile_sheet(_active_sheet)
	_close_invite_sheet()
	var profile_link := _referral_download_link(ref_code)

	# Sistem dialogu yerine uygulamayla aynı palette, çerçevesiz bir alt panel.
	_invite_overlay = ColorRect.new()
	_invite_overlay.color = Color(0.01, 0.02, 0.04, 0.78)
	_invite_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_invite_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_invite_overlay.z_index = 100
	add_child(_invite_overlay)

	var stage := VBoxContainer.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_theme_constant_override("separation", 0)
	_invite_overlay.add_child(stage)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(air)

	var sheet := PanelContainer.new()
	sheet.custom_minimum_size.y = minf(720.0, get_viewport_rect().size.y * 0.75)
	var sheet_style := StyleBoxFlat.new()
	sheet_style.bg_color = Color("#0b1220")
	sheet_style.corner_radius_top_left = 28
	sheet_style.corner_radius_top_right = 28
	sheet_style.content_margin_left = 22
	sheet_style.content_margin_right = 22
	sheet_style.content_margin_top = 18
	sheet_style.content_margin_bottom = 28
	sheet.add_theme_stylebox_override("panel", sheet_style)
	stage.add_child(sheet)
	# Native reklam katmanı Godot arayüzünün üstünde çizilir. Paneli banner ve
	# iPhone home indicator alanının tamamen üzerinde tut.
	var banner_clearance := Control.new()
	banner_clearance.custom_minimum_size.y = CandarUI.MODAL_BANNER_CLEARANCE if not Global.is_ad_free_user() else 18.0
	banner_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(banner_clearance)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	sheet.add_child(content)

	var handle := ColorRect.new()
	handle.color = Color("#f59e0b")
	handle.custom_minimum_size = Vector2(46, 4)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(handle)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	var heading := Label.new()
	heading.text = tr("share_title")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 32)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color("#f8fafc"))
	header.add_child(heading)
	var close_btn := CandarUI.make_ghost_icon_button("×", 80)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", Color("#f8fafc"))
	close_btn.pressed.connect(_close_invite_sheet)
	header.add_child(close_btn)

	var details_scroll := ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(details_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	details_scroll.add_child(details)

	var intro := Label.new()
	intro.text = tr("invite_explainer")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 26)
	intro.add_theme_color_override("font_color", Color("#a8b3c7"))
	details.add_child(intro)

	var code_card := PanelContainer.new()
	var code_style := StyleBoxFlat.new()
	code_style.bg_color = Color("#111b2e")
	code_style.set_corner_radius_all(18)
	code_style.content_margin_left = 18
	code_style.content_margin_right = 18
	code_style.content_margin_top = 14
	code_style.content_margin_bottom = 14
	code_card.add_theme_stylebox_override("panel", code_style)
	details.add_child(code_card)
	var code_row: BoxContainer = VBoxContainer.new() if get_viewport_rect().size.x < 600.0 else HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	code_card.add_child(code_row)
	var code_box := VBoxContainer.new()
	code_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_box.add_theme_constant_override("separation", 2)
	code_row.add_child(code_box)
	var code_caption := Label.new()
	code_caption.text = tr("invite_code_label").to_upper()
	code_caption.add_theme_font_size_override("font_size", 22)
	code_caption.add_theme_color_override("font_color", Color("#8492a8"))
	code_box.add_child(code_caption)
	var code_label := Label.new()
	code_label.text = ref_code
	code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_label.add_theme_font_size_override("font_size", 30)
	code_label.add_theme_color_override("font_color", Color("#fbbf24"))
	code_box.add_child(code_label)
	var copy_code_btn := CandarUI.make_secondary_button(tr("invite_copy_code"), 80)
	copy_code_btn.custom_minimum_size.x = 160
	copy_code_btn.add_theme_font_size_override("font_size", 24)
	copy_code_btn.pressed.connect(func():
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(ref_code)
			copy_code_btn.text = "✓ " + tr("invite_copy_code")
			Global.analytics_event("referral_code_copied", {"screen": "profile"})
			_toast(tr("invite_code_copied"))
	)
	code_row.add_child(copy_code_btn)

	var share_btn := CandarUI.make_primary_button(tr("invite_share"), 88)
	share_btn.add_theme_font_size_override("font_size", 28)
	share_btn.pressed.connect(func():
		var txt := tr("share_text") % ref_code
		var native_opened := Global.share_invite_text(txt, tr("share_title"), profile_link)
		Global.analytics_event("referral_share_opened", {"screen": "profile", "native": native_opened})
		if not native_opened:
			_toast(tr("toast_share_copied"))
	)
	details.add_child(share_btn)

	var copy_link_btn := CandarUI.make_secondary_button(tr("invite_copy_link"), 80)
	copy_link_btn.add_theme_font_size_override("font_size", 26)
	copy_link_btn.pressed.connect(func():
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(profile_link)
			copy_link_btn.text = "✓ " + tr("invite_copy_link")
			Global.analytics_event("referral_link_copied", {"screen": "profile"})
			_toast(tr("invite_link_copied"))
	)
	details.add_child(copy_link_btn)

func _close_invite_sheet() -> void:
	if _invite_overlay and is_instance_valid(_invite_overlay):
		_invite_overlay.queue_free()
	_invite_overlay = null

func _on_reset_pressed() -> void:
	if _account_busy:
		return
	var mail := _get_field_string(user_data, "email")
	if mail == "":
		_show_info_dialog(tr("dialog_reset_email_missing"))
		return
	_set_account_busy(true)
	var reset_label := btn_reset.text
	btn_reset.text = _ui_text("Gönderiliyor…", "Sending…")
	var res: Array = await Global.send_password_reset(mail)
	btn_reset.text = reset_label
	_set_account_busy(false)
	if res.size() > 0 and bool(res[0]):
		_show_info_dialog(tr("dialog_reset_sent"))
	else:
		_show_info_dialog(tr("dialog_reset_failed"))

func _show_language_dialog() -> void:
	var popup := AcceptDialog.new()
	popup.title = _ui_text("Uygulama Dili", "App Language")
	popup.get_ok_button().text = tr("common_close")
	add_child(popup)
	popup.confirmed.connect(func() -> void: popup.queue_free())
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(280, 50)
	var language_names := [
		"English", "Türkçe", "Deutsch", "Français", "Español",
		"Português", "Русский", "简体中文", "日本語", "한국어",
		"العربية", "हिन्दी"
	]
	for i in range(Global.SUPPORTED_LANGS.size()):
		selector.add_item(language_names[i], i)
	var selected := Global.SUPPORTED_LANGS.find(Global.current_lang)
	if selected >= 0:
		selector.select(selected)
	selector.item_selected.connect(func(index: int) -> void:
		var next_language: String = Global.SUPPORTED_LANGS[index]
		if next_language != Global.current_lang:
			Global.set_language(next_language)
			# Recreate the screen to update dynamically built UI and tr() nodes.
			get_tree().call_deferred("reload_current_scene")
	)
	popup.add_child(selector)
	popup.popup_centered()

func _on_logout_pressed() -> void:
	if _account_busy:
		return
	await Global.logout()
	get_tree().change_scene_to_file("res://onboarding.tscn")


# ======== Dialog / Popup ========
func _create_glass_dialog(title_text: String, size := Vector2(420, 420), destructive := false) -> Control:
	_close_invite_sheet()
	if is_instance_valid(_active_sheet):
		_close_profile_sheet(_active_sheet)
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.02, 0.04, 0.78)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)

	var stage := VBoxContainer.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(stage)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(air)

	var sheet := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0b1220")
	sb.corner_radius_top_left = 28
	sb.corner_radius_top_right = 28
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 22
	sheet.add_theme_stylebox_override("panel", sb)
	sheet.custom_minimum_size = Vector2(get_viewport_rect().size.x, minf(size.y, get_viewport_rect().size.y * 0.70))
	stage.add_child(sheet)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	sheet.add_child(v)
	var handle := ColorRect.new()
	handle.color = Color("#ef4444") if destructive else Color("#f59e0b")
	handle.custom_minimum_size = Vector2(46, 4)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(handle)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	v.add_child(header)
	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("#fecaca") if destructive else Color("#f8fafc"))
	header.add_child(title)
	var close_btn := CandarUI.make_ghost_icon_button("×", 80)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", Color("#f8fafc"))
	close_btn.pressed.connect(_close_profile_sheet.bind(overlay))
	header.add_child(close_btn)

	var rt := RichTextLabel.new()
	rt.name = "rt"
	rt.bbcode_enabled = true
	rt.fit_content = false
	rt.scroll_active = true
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(maxf(280.0, get_viewport_rect().size.x - 44.0), 110.0)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 28)
	rt.add_theme_color_override("default_color", COL_TEXT_MAIN)
	v.add_child(rt)

	var foot := Label.new()
	foot.name = "foot"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_theme_font_size_override("font_size", 26)
	foot.add_theme_color_override("font_color", COL_TEXT_SUB)
	v.add_child(foot)
	var actions := GridContainer.new()
	actions.name = "actions"
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 10)
	v.add_child(actions)

	var banner_clearance := Control.new()
	banner_clearance.custom_minimum_size.y = CandarUI.MODAL_BANNER_CLEARANCE if not Global.is_ad_free_user() else 18.0
	banner_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(banner_clearance)
	_active_sheet = overlay
	return overlay

func _close_profile_sheet(sheet: Control) -> void:
	if is_instance_valid(sheet):
		if sheet == _active_sheet:
			_active_sheet = null
		sheet.queue_free()

func _popup_glass_dialog(_dlg: Control, _preferred_size: Vector2) -> void:
	# Alt panel oluşturulurken zaten görünürdür; eski çağrılar işlev uyumluluğu için kalır.
	pass

func _show_info_dialog(text: String) -> void:
	var d := _create_glass_dialog(tr("dialog_info_title"), Vector2(360, 220))
	var rt := d.find_child("rt", true, false) as RichTextLabel
	if rt:
		rt.text = text
	_popup_glass_dialog(d, Vector2(360, 220))

# ======== Liderlik ========
func _open_achievements() -> void:
	Global.analytics_event("achievements_open", {"screen": "profile"})
	var unlocked := _unlocked_achievement_ids()
	var xp: int = maxi(0, _get_field_int(user_data, "xp", 0))
	var xp_progress: Dictionary = Global.get_xp_progress(xp)
	var level := int(xp_progress.get("level", 1))
	var current_xp := int(xp_progress.get("current_xp", 0))
	var needed_xp := int(xp_progress.get("needed_xp", 100))
	var lines: PackedStringArray = []
	lines.append("[center][b]%s %d[/b] · %d/%d XP[/center]" % [
		_ui_text("Seviye", "Level"), level, current_xp, needed_xp
	])
	lines.append("")
	for achievement in ACHIEVEMENT_CATALOG:
		var achievement_id := str(achievement["id"])
		var icon := "✓" if unlocked.has(achievement_id) else "○"
		var color := "#fbbf24" if unlocked.has(achievement_id) else "#94a3b8"
		lines.append("[color=%s]%s %s[/color]" % [
			color,
			icon,
			tr(str(achievement["name"]))
		])

	var dlg := _create_glass_dialog(_ui_text("Başarı Koleksiyonu", "Achievement Collection"), Vector2(520, 620))
	var rt := dlg.find_child("rt", true, false) as RichTextLabel
	var foot := dlg.find_child("foot", true, false) as Label
	if rt:
		rt.text = "\n".join(lines)
	if foot:
		foot.text = _ui_text(
			"%d/%d başarı açıldı · günlük serini koruyarak yenilerini aç.",
			"%d/%d unlocked · keep your daily streak to unlock more."
		) % [unlocked.size(), ACHIEVEMENT_CATALOG.size()]
	_popup_glass_dialog(dlg, Vector2(520, 620))

func _unlocked_achievement_ids() -> Dictionary:
	var unlocked := {}
	var raw: Variant = user_data.get("achievements", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return unlocked
	var array_value: Variant = (raw as Dictionary).get("arrayValue", {})
	if typeof(array_value) != TYPE_DICTIONARY:
		return unlocked
	for item in (array_value as Dictionary).get("values", []):
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has("stringValue"):
			unlocked[str((item as Dictionary)["stringValue"])] = true
	return unlocked

func _open_leaderboard() -> void:
	Global.analytics_event("open_leaderboard", {"screen": "profile"})
	var dlg := _create_glass_dialog(tr("dialog_leaderboard_title"), Vector2(520, 620))
	var rt := dlg.find_child("rt", true, false) as RichTextLabel
	var foot := dlg.find_child("foot", true, false) as Label

	if rt:
		rt.text = tr("leaderboard_loading_bb")
		# Tüm tablo yazıları için temel font büyüt
		rt.add_theme_font_size_override("normal_font_size", 28)

	if foot:
		foot.text = ""

	_popup_glass_dialog(dlg, Vector2(520, 620))

	var list: Array = []
	if Global.has_method("get_users_sample"):
		list = await Global.get_users_sample(80)
	else:
		list = await Global.get_leaderboard_top(80)
	if not is_instance_valid(dlg) or dlg.is_queued_for_deletion():
		return
	var rows: Array[Dictionary] = []

	for it in list:
		var f: Dictionary = {}
		if typeof(it) == TYPE_DICTIONARY and (it as Dictionary).has("fields"):
			f = (it as Dictionary)["fields"]
		elif typeof(it) == TYPE_DICTIONARY and (it as Dictionary).has("document"):
			var ddoc: Variant = (it as Dictionary)["document"]
			if typeof(ddoc) == TYPE_DICTIONARY and (ddoc as Dictionary).has("fields"):
				f = (ddoc as Dictionary)["fields"]

		if f.is_empty():
			continue

		var mail := _get_field_string(f, "email")
		var pts := _get_field_double(f, "points")
		var ref_count := int(_get_field_double(f, "referralCount"))
		rows.append({"email": (mail if mail != "" else "—"), "points": pts, "refs": ref_count})

	var self_mail := _get_field_string(user_data, "email")

	# BACKEND BOŞ GELİRSE EN AZINDAN KENDİN GÖZÜKSÜN
	if rows.is_empty() and self_mail != "":
		var self_pts := _get_field_double(user_data, "points")
		rows.append({"email": self_mail, "points": self_pts, "refs": referans_sayisi})

	# Referans sayısına göre sırala; eşitlikte Candar puanı belirleyici olsun.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["refs"]) == int(b["refs"]):
			return float(a["points"]) > float(b["points"])
		return int(a["refs"]) > int(b["refs"])
	)

	var bb := _leaderboard_bbcode(rows, self_mail)
	if rt:
		rt.text = (bb if bb != "" else tr("leaderboard_empty_bb"))

	if foot and self_mail != "":
		var rank := -1
		var self_refs := referans_sayisi
		for i in rows.size():
			if String(rows[i]["email"]) == self_mail:
				rank = i + 1
				self_refs = int(rows[i]["refs"])
				break
		if rank > 0:
			foot.text = "%s · %d %s" % [tr("leaderboard_your_rank") % [rank, rows.size()], self_refs, _ui_text("referans", "refs")]
			foot.add_theme_color_override("font_color", COL_ACCENT_BOOST)
			foot.add_theme_font_size_override("font_size", 28)

func _leaderboard_bbcode(rows: Array[Dictionary], self_mail: String) -> String:
	if rows.is_empty():
		return tr("leaderboard_empty_bb")

	var bb := ""
	var amber_hex := COL_ACCENT_BOOST.to_html(false)
	var main_text_hex := COL_TEXT_MAIN.to_html(false)

	# ÜSTTE BÜYÜK BAŞLIK
	bb += "[center][b][color=#%s][font_size=28]%s[/font_size][/color][/b][/center]\n\n" % [
		amber_hex, _ui_text("TOP 25 REFERANS", "TOP 25 REFERRALS")
	]

	# Tabloyu biraz daha büyük fontla çiz
	bb += "[font_size=26]"
	bb += "[table=3]\n"
	bb += "[cell][b]%s[/b][/cell][cell][b]%s[/b][/cell][cell][right][b]%s[/b][/right][/cell]\n" % [
		tr("leaderboard_col_rank"),
		tr("leaderboard_col_email"),
		_ui_text("Referans", "Refs")
	]

	var limit: int = min(25, rows.size())
	for i in range(limit):
		var mail := String(rows[i]["email"])
		var refs: int = int(rows[i]["refs"])
		var masked := _mask_email(mail)

		var icon := " "
		if i == 0:
			icon = "★"
		elif i == 1:
			icon = "★"
		elif i == 2:
			icon = "★"

		var rank_text := "%s  %02d." % [icon, i + 1]
		var refs_text := str(refs)
		var is_me := (self_mail != "" and mail == self_mail)

		if is_me:
			bb += "[cell][color=#%s]%s[/color][/cell]" % [amber_hex, rank_text]
			bb += "[cell][color=#%s]%s[/color][/cell]" % [amber_hex, masked]
			bb += "[cell][right][color=#%s]%s[/color][/right][/cell]\n" % [amber_hex, refs_text]
		else:
			bb += "[cell][color=#%s]%s[/color][/cell]" % [main_text_hex, rank_text]
			bb += "[cell][color=#%s]%s[/color][/cell]" % [main_text_hex, masked]
			bb += "[cell][right][color=#%s]%s[/color][/right][/cell]\n" % [main_text_hex, refs_text]

	bb += "[/table]"
	bb += "[/font_size]"
	return bb

func _mask_email(mail: String) -> String:
	if mail == "—":
		return mail
	var at := mail.find("@")
	if at < 0:
		return "•••"
	if at <= 1:
		return "•••" + mail.substr(at)
	return mail.substr(0, 2) + "•••" + mail.substr(at, mail.length() - at)

# ======== Badge Avatar Renderer ========
func _make_badge_avatar(ring_color: Color, glow_color: Color) -> Texture2D:
	var size := 132
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var cx := size / 2.0
	var cy := size / 2.0
	var r_outer := 56.0
	var r_inner := 42.0
	var r_glow := 62.0

	for y in size:
		for x in size:
			var dx := x - cx
			var dy := y - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r_glow and d > r_outer:
				var t := 1.0 - clampf((d - r_outer) / (r_glow - r_outer), 0.0, 1.0)
				var c := Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a / 255.0 * t * 0.6)
				img.set_pixel(x, y, c)

	for y in size:
		for x in size:
			var dx := x - cx
			var dy := y - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r_outer and d >= r_inner:
				img.set_pixel(x, y, ring_color)

	for y in size:
		for x in size:
			var dx := x - cx
			var dy := y - cy
			var d := sqrt(dx * dx + dy * dy)
			if d < r_inner:
				img.set_pixel(x, y, COL_BG_TOP.darkened(0.1))

	return ImageTexture.create_from_image(img)

# ======== Toast ========
func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0,0,0,0.85)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_toast_panel.add_theme_stylebox_override("panel", sb)

	_toast_label = Label.new()
	_toast_label.add_theme_color_override("font_color", COL_TEXT_MAIN)
	_toast_label.add_theme_font_size_override("font_size", 26)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)

	add_child(_toast_panel)
	_toast_panel.z_index = 120
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.anchor_top = 1.0
	_toast_panel.offset_left = -100
	_toast_panel.offset_right = 100
	_toast_panel.offset_bottom = -24
	_toast_panel.visible = false

func _toast(msg: String, duration := 1.4) -> void:
	_toast_label.text = msg
	var width := minf(get_viewport_rect().size.x - 40.0, 640.0)
	_toast_panel.offset_left = -width / 2.0
	_toast_panel.offset_right = width / 2.0
	_toast_panel.offset_top = -CandarUI.MODAL_BANNER_CLEARANCE - 100
	_toast_panel.offset_bottom = -CandarUI.MODAL_BANNER_CLEARANCE
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_toast_panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(_toast_panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(Callable(self, "_hide_toast"))

func _hide_toast() -> void:
	_toast_panel.visible = false
