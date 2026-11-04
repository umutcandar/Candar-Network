extends Control

# ==========================================
#  AYARLAR VE DEĞİŞKENLER
# ==========================================

# --- Sahne Bağlantıları ---
@onready var panel: PanelContainer    = $PanelContainer
@onready var vbox: VBoxContainer      = $PanelContainer/VBoxContainer
@onready var scroll: ScrollContainer  = $PanelContainer/VBoxContainer/ScrollContainer
@onready var chat_box: VBoxContainer  = $PanelContainer/VBoxContainer/ScrollContainer/ChatBox
@onready var row: HBoxContainer       = $PanelContainer/VBoxContainer/HBoxContainer
@onready var input: LineEdit          = $PanelContainer/VBoxContainer/HBoxContainer/Input
@onready var send_btn: Button         = $PanelContainer/VBoxContainer/HBoxContainer/SendButton
@onready var status_label: Label      = $PanelContainer/VBoxContainer/StatusLabel

# --- Durum Değişkenleri ---
var sending: bool = false
var is_premium: bool = false
var back_btn: Button = null
var suggestions_box: BoxContainer = null

# --- Renk Paleti (Premium Tema) ---
const COL_BG_TOP        = CandarUI.COL_BG_TOP
const COL_BG_BOT        = CandarUI.COL_BG_BOT
const COL_ACCENT        = CandarUI.COL_ACCENT
const COL_USER_BUBBLE   = Color("#4f46e5")
const COL_AI_BUBBLE     = Color("#334155")
const COL_TEXT_LIGHT    = CandarUI.COL_TEXT

# ==========================================
#  BAŞLANGIÇ (READY)
# ==========================================
func _ready() -> void:
	Global.analytics_page("Candar Ai", "app://candar/chat")
	Global.analytics_event("app_screen_view", {"screen": "chat"})

	# 2. Global'den Premium bilgisini çek
	if has_node("/root/Global"):
		var g = get_node("/root/Global")
		if "market_is_premium" in g:
			is_premium = bool(g.market_is_premium)
		if g.has_method("is_user_premium"):
			is_premium = g.is_user_premium()

	# 3. Arayüzü oluştur
	_create_screen_header()
	_apply_layout()
	_apply_style_premium()
	_build_suggestions()
	_apply_mobile_scaling()
	
	# Safe Area'yı uygula ama klavye açılınca bunu ezeceğiz
	await Global.apply_safe_area(self)

	# 4. Eğer reklam varsa gizle
	_hide_banner_if_any()

	# 5. Tıklama / buton olaylarını bağla
	send_btn.pressed.connect(_send)
	input.text_submitted.connect(func(_t): _send())
	# 6. Yazıları Çevir
	input.placeholder_text = tr("chat_input_placeholder")
	input.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	_update_status_label_initial()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _update_status_label_initial() -> void:
	if is_premium:
		status_label.text = tr("chat_status_premium_active")
		status_label.add_theme_color_override("font_color", COL_ACCENT)
	else:
		status_label.text = tr("chat_status_ready")
		status_label.add_theme_color_override("font_color", Color("#94a3b8"))

func _is_tr() -> bool:
	var locale := TranslationServer.get_locale()
	return locale.begins_with("tr") if locale != "" else OS.get_locale().begins_with("tr")

func _ui_text(tr_text: String, en_text: String) -> String:
	return Global.localized_ui_text(tr_text, en_text)

# ==========================================
#  HEADER (ÜST BAR VE GERİ BUTONU)
# ==========================================
func _create_screen_header() -> void:
	var hdr := CandarUI.create_header(self, tr("chat_title"), true)
	hdr["header"].z_index = 40
	if hdr.get("back") and hdr["back"]:
		hdr["back"].pressed.connect(_go_home)

func _go_home() -> void:
	DisplayServer.virtual_keyboard_hide()
	Global.analytics_event("chat_back", {"screen": "chat"})
	get_tree().change_scene_to_file("res://home.tscn")

# ==========================================
#  YENİ KLAVYE SİSTEMİ (Jilet Gibi)
# ==========================================
# _process fonksiyonunu sildik, yerine bu sinyalleri kullanıyoruz.

func _on_keyboard_shown(rect: Rect2, _screen_index: int = 0) -> void:
	# Klavye yüksekliğini al
	var k_height = rect.size.y
	
	# Ana panelin altını klavye kadar yukarı çek.
	# Eksi (-) değeri yukarı çeker.
	# "Safe Area"yı düşünme, çünkü klavye safe area'nın üstüne biner.
	panel.offset_bottom = -k_height
	
	# Scroll'u en aşağı kaydır ki mesaj görünsün
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _on_keyboard_hidden() -> void:
	# Klavye kapanınca paneli eski yerine (0'a veya Safe Area hizasına) getir
	panel.offset_bottom = 0
	
	# Scroll'u tekrar düzelt
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

# ==========================================
#  DÜZEN VE STİL (LAYOUT)
# ==========================================
func _apply_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_top", int(CandarUI.header_total_height() + 8))
	margin_container.add_theme_constant_override("margin_bottom", 8)

	if vbox.get_parent():
		vbox.get_parent().remove_child(vbox)
	margin_container.add_child(vbox)
	panel.add_child(margin_container)

	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.size_flags_stretch_ratio = 0.76
	send_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_btn.size_flags_stretch_ratio = 0.24

func _apply_style_premium() -> void:
	CandarUI.add_gradient_bg(self, "ChatGradient")

	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	vbox.add_theme_constant_override("separation", 16)
	chat_box.add_theme_constant_override("separation", 16)

	var input_sb = StyleBoxFlat.new()
	input_sb.bg_color = Color(0, 0, 0, 0.4)
	input_sb.set_corner_radius_all(24)
	input_sb.border_width_bottom = 1
	input_sb.border_color = Color(1, 1, 1, 0.15)
	input_sb.content_margin_left = 20
	input_sb.content_margin_right = 20

	input.add_theme_stylebox_override("normal", input_sb)
	input.add_theme_stylebox_override("focus", input_sb)
	input.add_theme_font_size_override("font_size", 18)
	input.caret_blink = true

	send_btn.text = tr("chat_send")
	var btn_sb = StyleBoxFlat.new()
	btn_sb.bg_color = COL_ACCENT
	btn_sb.set_corner_radius_all(24)
	var btn_prs = btn_sb.duplicate()
	btn_prs.bg_color = COL_ACCENT.darkened(0.1)

	send_btn.add_theme_stylebox_override("normal", btn_sb)
	send_btn.add_theme_stylebox_override("hover", btn_sb)
	send_btn.add_theme_stylebox_override("pressed", btn_prs)
	send_btn.add_theme_stylebox_override("disabled", btn_prs)
	send_btn.add_theme_font_size_override("font_size", 18)
	send_btn.add_theme_color_override("font_color", Color.WHITE)

	row.add_theme_constant_override("separation", 8)

func _build_suggestions() -> void:
	if suggestions_box and is_instance_valid(suggestions_box):
		return
	var compact := get_viewport_rect().size.x < 520.0
	if compact:
		suggestions_box = VBoxContainer.new()
	else:
		suggestions_box = HBoxContainer.new()
	suggestions_box.add_theme_constant_override("separation", 8)
	suggestions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var suggestions := [
		_ui_text("Bugünkü stratejim ne?", "What is my strategy today?"),
		_ui_text("Boost almalı mıyım?", "Should I buy a boost?"),
		_ui_text("Referansı nasıl artırırım?", "How can I get more referrals?")
	]
	for s in suggestions:
		var btn := Button.new()
		btn.text = s
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 40 if compact else 42)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", COL_TEXT_LIGHT)
		btn.clip_text = true
		btn.tooltip_text = s
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.07)
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.1)
		var hover := sb.duplicate()
		hover.bg_color = Color(1, 1, 1, 0.12)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.pressed.connect(_on_suggestion_pressed.bind(s))
		suggestions_box.add_child(btn)

	var idx := vbox.get_children().find(scroll)
	vbox.add_child(suggestions_box)
	if idx >= 0:
		vbox.move_child(suggestions_box, idx)

func _on_suggestion_pressed(text: String) -> void:
	input.text = text
	input.caret_column = input.text.length()
	input.grab_focus()

func _apply_mobile_scaling() -> void:
	row.custom_minimum_size.y = 64
	input.custom_minimum_size.y = 54
	send_btn.custom_minimum_size.y = 54
	if get_viewport_rect().size.x < 420.0:
		send_btn.text = "→"
		send_btn.custom_minimum_size.x = 58
	else:
		send_btn.text = tr("chat_send")
	if suggestions_box:
		for child in suggestions_box.get_children():
			if child is Button:
				(child as Button).custom_minimum_size.y = 40

func _hide_banner_if_any() -> void:
	if has_node("/root/Global") and Global.has_method("ads_set_banner_allowed"):
		Global.ads_set_banner_allowed(false)
		return
	if has_node("/root/AdMob"):
		get_node("/root/AdMob").hide_banner()
	elif has_node("Admob"):
		get_node("Admob").hide_banner()

# ----------------------------------------------------------
#  MESAJ GÖNDERME
# ----------------------------------------------------------
func _send() -> void:
	if sending:
		return

	var user_text := input.text.strip_edges()
	if user_text == "":
		return
	if user_text.length() > 1000:
		_add_system_message(_ui_text("Mesajını 1000 karakterle sınırla.", "Keep your message within 1,000 characters."))
		return
	Global.analytics_event("chat_send", {"screen": "chat", "premium": is_premium})

	sending = true
	input.editable = false
	send_btn.disabled = true

	status_label.text = tr("chat_status_thinking")
	status_label.add_theme_color_override("font_color", COL_ACCENT)

	_add_chat_bubble("user", user_text)
	input.text = ""

	var locale := TranslationServer.get_locale()

	var res: Dictionary = {}
	if has_node("/root/Firebase"):
		res = await get_node("/root/Firebase").chat_send({
			"prompt": user_text,
			"lang": locale,
		})
	else:
		res = {"error": tr("chat_system_connection_error"), "status": 503}

	sending = false
	input.editable = true
	send_btn.disabled = false
	input.grab_focus()

	if res.has("answer"):
		Global.analytics_event("chat_answer", {"screen": "chat", "premium": bool(res.get("premium", false)), "remaining": int(res.get("remaining", 0))})
		_add_chat_bubble("ai", str(res["answer"]))
		is_premium = bool(res.get("premium", false))

		if is_premium:
			status_label.text = tr("chat_status_premium_short")
			status_label.add_theme_color_override("font_color", COL_ACCENT)
		else:
			status_label.text = tr("chat_status_remaining") % int(res.get("remaining", 0))
			status_label.add_theme_color_override("font_color", Color("#94a3b8"))
	else:
		Global.analytics_event("chat_error", {"screen": "chat", "status": int(res.get("status", 0)), "message": str(res.get("error", "")).substr(0, 96)})
		var error_msg := _chat_error_message(res)
		input.text = user_text
		status_label.text = tr("chat_status_error")
		_add_system_message(error_msg)

func _chat_error_message(res: Dictionary) -> String:
	var status := int(res.get("status", 0))
	var raw := str(res.get("error", ""))
	var lower := raw.to_lower()
	if status in [500, 502, 503, 504] or lower.find("not available") != -1 or lower.find("billing") != -1:
		return tr("chat_system_connection_error")
	if raw.strip_edges() != "":
		return raw
	return tr("chat_system_connection_error")

# ==========================================
#  BALONCUK SİSTEMİ
# ==========================================
func _add_chat_bubble(role: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.alignment = BoxContainer.ALIGNMENT_END if role == "user" else BoxContainer.ALIGNMENT_BEGIN

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var max_width: float = panel.size.x * 0.75
	if max_width <= 0:
		max_width = 300.0

	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.set_corner_radius_all(22)

	if role == "user":
		sb.bg_color = COL_USER_BUBBLE
		sb.corner_radius_bottom_right = 4
	else:
		sb.bg_color = COL_AI_BUBBLE
		sb.corner_radius_bottom_left = 4

	bubble.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COL_TEXT_LIGHT)
	lbl.custom_minimum_size.x = min(max(120, text.length() * 9), max_width)

	bubble.add_child(lbl)
	h.add_child(bubble)
	chat_box.add_child(h)

	bubble.modulate.a = 0.0
	bubble.scale = Vector2(0.8, 0.8)
	bubble.pivot_offset = bubble.size / 2
	var tw = create_tween().set_parallel(true)
	tw.tween_property(bubble, "modulate:a", 1.0, 0.3)
	tw.tween_property(bubble, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

func _add_system_message(text: String) -> void:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	h.add_child(lbl)
	chat_box.add_child(h)
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value

#  PROFESYONEL KLAVYE YÖNETİMİ (Scaling Fix)
# ==========================================
var _last_k_height: float = 0.0

func _process(_delta: float) -> void:
	# Sadece mobilde çalıştır
	if not OS.has_feature("mobile"):
		return

	# 1. Klavyenin HAM yüksekliğini al (Cihazın gerçek pikselleri)
	var real_keyboard_height = DisplayServer.virtual_keyboard_get_height()
	
	# Değişiklik yoksa işlem yapma (Performans koruması)
	if real_keyboard_height == _last_k_height:
		return
	_last_k_height = real_keyboard_height

	# 2. Skalayı Hesapla (Tasarım Çözünürlüğü vs Gerçek Ekran)
	# Godot'un viewport yüksekliği / Cihazın ekran yüksekliği
	var scale_factor = get_viewport().get_visible_rect().size.y / float(DisplayServer.screen_get_size().y)
	
	# 3. Klavyenin bizim sahnemizdeki karşılığını bul
	var adjusted_height = real_keyboard_height * scale_factor

	# 5. Pozisyonu Ayarla
	if adjusted_height > 0:
		# KLAVYE AÇIK:
		# Safe area'yı yok say, direkt klavye yüksekliği kadar yukarı it.
		# Not: Bazen klavye öneri çubuğu safe area'yı kapsar, o yüzden sadece klavye yeterlidir.
		panel.offset_bottom = -adjusted_height
	else:
		panel.offset_bottom = 0

	# 6. Scroll'u hemen güncelle ki mesaj klavyenin altında kalmasın
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
func _on_keyboard_height_changed(height: float) -> void:
	# Eğer klavye açıksa (yükseklik > 0)
	if height > 0:
		# Panelin altını klavye kadar yukarı çek
		# NOT: Safe area'yı düşünme, klavye safe area'nın üstüne biner.
		panel.offset_bottom = -height
	else:
		# Klavye kapandıysa paneli sıfırla
		panel.offset_bottom = 0
	
	# Mesaj baloncuğunu hemen görünür yapmak için scroll'u aşağı it
	await get_tree().process_frame
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
# ==========================================
#  EKRAN GİRİŞLERİ
# ==========================================
func _input(event: InputEvent) -> void:
	# Boşluğa tıklayınca klavyeyi kapat
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
		var pos: Vector2 = event.position
		if not input.get_global_rect().has_point(pos) and not send_btn.get_global_rect().has_point(pos):
			input.release_focus()
			DisplayServer.virtual_keyboard_hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_home()
