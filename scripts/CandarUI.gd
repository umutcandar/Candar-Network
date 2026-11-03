extends Node
## Shared Candar Network design system — colors, cards, nav, typography.

enum Tab { HOME, MARKET, CHAT, PROFILE }

const NAV_HEIGHT := 74.0
# 50 pt banner + iPhone home-indicator safe area + a small breathing gap.
# Android devices with a shorter navigation inset simply get a little more room.
const AD_BANNER_INSET := 96.0
# Native banner bazı iPhone boyutlarında safe-area ile birlikte daha yüksek bir
# dokunma/görünürlük alanı kaplıyor. Alt paneller için ekstra nefes payı.
const MODAL_BANNER_CLEARANCE := 132.0
const HEADER_HEIGHT := 64.0
const HEADER_SAFE_TOP := 36.0
const HEADER_TOTAL_HEIGHT := HEADER_SAFE_TOP + HEADER_HEIGHT
const IOS_HEADER_SAFE_TOP := 58.0

const COL_BG_TOP := Color("#0f172a")
const COL_BG_MID := Color("#111827")
const COL_BG_BOT := Color("#1e293b")
const COL_ACCENT := Color("#f59e0b")
const COL_ACCENT_BRIGHT := Color("#FFA51B")
const COL_ACCENT_PREM := Color("#6366f1")
const COL_TEXT := Color("#f8fafc")
const COL_TEXT_SUB := Color("#94a3b8")
const COL_SURFACE := Color(0.08, 0.11, 0.19, 0.94)
const COL_BTN_DARK := Color("#232c3b")
const COL_SUCCESS := Color("#34d399")

const FONT_HERO := 48
const FONT_TITLE := 22
const FONT_BODY := 16
const FONT_CAPTION := 14


func display_name_from_email(email: String) -> String:
	var e := email.strip_edges()
	if e == "":
		return ""
	if e.find("@") == -1:
		return e
	var local := e.split("@")[0]
	if local == "":
		return e
	local = local.replace(".", " ").replace("_", " ")
	return local.capitalize()


func add_gradient_bg(parent: Control, node_name := "CandarGradient") -> TextureRect:
	if parent.get_node_or_null(node_name):
		return parent.get_node(node_name)
	var tex_rect := TextureRect.new()
	tex_rect.name = node_name
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([COL_BG_TOP, COL_BG_MID, COL_BG_BOT])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gtex := GradientTexture2D.new()
	gtex.gradient = gradient
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 64
	gtex.height = 64
	tex_rect.texture = gtex
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tex_rect)
	parent.move_child(tex_rect, 0)
	return tex_rect


func make_card(
	border := COL_ACCENT,
	radius := 18,
	bg := COL_SURFACE,
	margin := 14
) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.border_color = Color(border.r, border.g, border.b, 0.45)
	sb.set_border_width_all(1)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card


func style_hero_label(lbl: Label, size := FONT_HERO) -> void:
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", COL_TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func style_title_label(lbl: Label, accent := false) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_TITLE)
	lbl.add_theme_color_override("font_color", COL_ACCENT if accent else COL_TEXT)


func style_body_label(lbl: Label, sub := false) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_BODY)
	lbl.add_theme_color_override("font_color", COL_TEXT_SUB if sub else COL_TEXT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func style_caption_label(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_CAPTION)
	lbl.add_theme_color_override("font_color", COL_TEXT_SUB)


func make_primary_button(text: String, height := 60.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, height)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color("#1a1408"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_ACCENT_BRIGHT
	normal.set_corner_radius_all(20)
	normal.shadow_size = 12
	normal.shadow_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.35)
	var hover := normal.duplicate()
	hover.bg_color = COL_ACCENT_BRIGHT.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = COL_ACCENT.darkened(0.08)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", pressed)
	return btn


func make_secondary_button(text: String, height := 52.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, height)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COL_ACCENT_BRIGHT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_BTN_DARK
	normal.set_corner_radius_all(16)
	var hover := normal.duplicate()
	hover.bg_color = Color("#2b3547")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#1e2634")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn


func make_ghost_icon_button(icon_text: String, size := 44.0) -> Button:
	var btn := Button.new()
	btn.text = icon_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07)
	sb.set_corner_radius_all(int(size / 2))
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", COL_TEXT)
	return btn


func top_safe_inset() -> float:
	var fallback := IOS_HEADER_SAFE_TOP if OS.has_feature("ios") else HEADER_SAFE_TOP
	if OS.has_feature("ios") or OS.has_feature("android"):
		var safe := DisplayServer.get_display_safe_area()
		if safe.position.y > 0:
			# DisplayServer güvenli alanı ekran pikseliyle, Control yerleşimi ise
			# gerilmiş viewport koordinatıyla dönebilir. Doğrudan kullanmak bazı
			# iPhone'larda üstte gereksiz büyük boşluk oluşturur.
			var viewport_size := get_viewport().get_visible_rect().size
			var screen_size := Vector2(DisplayServer.screen_get_size())
			var display_scale := 1.0
			if viewport_size.x > 0.0 and screen_size.x > viewport_size.x:
				display_scale = screen_size.x / viewport_size.x
			var safe_top := float(safe.position.y) / display_scale
			return max(fallback, safe_top)
	return fallback


func header_total_height() -> float:
	return top_safe_inset() + HEADER_HEIGHT


func create_header(parent: Control, title: String, show_back := false) -> Dictionary:
	var safe_top := top_safe_inset()
	var total_height := safe_top + HEADER_HEIGHT
	var header := Panel.new()
	header.name = "ScreenHeader"
	header.z_index = 20
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = total_height
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.97)
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.08)
	header.add_theme_stylebox_override("panel", sb)
	parent.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_lbl.offset_top = safe_top
	title_lbl.offset_bottom = total_height
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_title_label(title_lbl)
	header.add_child(title_lbl)

	var back_btn: Button = null
	if show_back:
		back_btn = make_ghost_icon_button("←")
		back_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		back_btn.size = back_btn.custom_minimum_size
		back_btn.position = Vector2(12, safe_top + (HEADER_HEIGHT - back_btn.size.y) / 2.0)
		header.add_child(back_btn)

	return {"header": header, "title": title_lbl, "back": back_btn}


func apply_scroll_bottom_inset(scroll: ScrollContainer, extra := 0.0) -> void:
	if scroll == null:
		return
	scroll.offset_bottom = -(NAV_HEIGHT + extra)


func apply_banner_bottom_inset(scroll: ScrollContainer, extra := 0.0) -> void:
	if scroll == null:
		return
	var inset := AD_BANNER_INSET + extra
	var container := scroll.get_parent()
	# ScrollContainer children are laid out by their parent Container, so changing
	# the scroll offset directly may be ignored. Reserve space on the outer
	# container to keep the final button/footer fully above the native ad.
	if container is MarginContainer:
		var margin := container as MarginContainer
		var current_bottom := margin.get_theme_constant("margin_bottom")
		margin.add_theme_constant_override("margin_bottom", maxi(current_bottom, int(inset)))
	elif container is Control:
		var outer := container as Control
		outer.offset_bottom = minf(outer.offset_bottom, -inset)
	else:
		scroll.offset_bottom = -inset


func apply_content_margins(margin: MarginContainer, bottom_extra := NAV_HEIGHT) -> void:
	margin.add_theme_constant_override("margin_bottom", int(bottom_extra + 8))


func add_bottom_nav(screen: Control, active: Tab) -> PanelContainer:
	if screen.get_node_or_null("BottomNav"):
		return screen.get_node("BottomNav")

	var bar := PanelContainer.new()
	bar.name = "BottomNav"
	bar.z_index = 30
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -NAV_HEIGHT
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = Color(0.05, 0.08, 0.14, 0.98)
	bar_sb.border_width_top = 1
	bar_sb.border_color = Color(1, 1, 1, 0.08)
	bar_sb.content_margin_left = 8
	bar_sb.content_margin_right = 8
	bar_sb.content_margin_top = 6
	bar_sb.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", bar_sb)
	screen.add_child(bar)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(row)

	var defs := [
		{"tab": Tab.HOME, "icon": "⌂", "label": "Home", "scene": "res://home.tscn"},
		{"tab": Tab.MARKET, "icon": "🛒", "label": "Market", "scene": "res://market.tscn"},
		{"tab": Tab.CHAT, "icon": "💬", "label": "AI", "scene": "res://chat.tscn"},
		{"tab": Tab.PROFILE, "icon": "👤", "label": "Profil", "scene": "res://profile.tscn"},
	]
	if TranslationServer.get_locale().begins_with("tr"):
		defs[0]["label"] = "Ana"
		defs[2]["label"] = "AI"
		defs[3]["label"] = "Profil"

	for def in defs:
		var cell := _make_nav_cell(def, active == def["tab"])
		row.add_child(cell)

	return bar


func _make_nav_cell(def: Dictionary, is_active: bool) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 2)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = false
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.18) if is_active else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.pressed.connect(func(): _nav_go(def["scene"], is_active))
	wrap.add_child(btn)

	var icon := Label.new()
	icon.text = def["icon"]
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 20)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	icon.position.y = 6

	var lbl := Label.new()
	lbl.text = def["label"]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COL_ACCENT if is_active else COL_TEXT_SUB)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)

	return wrap


func _nav_go(scene_path: String, already_active: bool) -> void:
	if already_active:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if scene_path == "res://chat.tscn":
		if Global.has_method("ads_set_banner_allowed"):
			Global.ads_set_banner_allowed(false)
		elif Global.has_method("ads_hide_banner"):
			Global.ads_hide_banner()
	elif Global.has_method("ads_set_banner_allowed"):
		Global.ads_set_banner_allowed(true)
	tree.change_scene_to_file(scene_path)


func make_section_title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	style_title_label(lbl, true)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return lbl


func make_stat_pill(title: String, value: String) -> PanelContainer:
	var pill := make_card(Color("#334155"), 14, Color(0.06, 0.09, 0.16, 0.92), 10)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	pill.add_child(box)
	var t := Label.new()
	t.text = title
	style_caption_label(t)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var v := Label.new()
	v.text = value
	v.name = "Value"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", COL_TEXT)
	box.add_child(v)
	return pill


func set_stat_pill_value(pill: PanelContainer, value: String) -> void:
	if pill == null:
		return
	var v := pill.find_child("Value", true, false)
	if v is Label:
		(v as Label).text = value
