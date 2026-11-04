extends Control

# ---- RENK PALETİ ----
const COL_BG_TOP 		= CandarUI.COL_BG_TOP
const COL_BG_BOT 		= CandarUI.COL_BG_BOT
const COL_ACCENT_BOOST = CandarUI.COL_ACCENT
const COL_ACCENT_PREM  = CandarUI.COL_ACCENT_PREM
const COL_TEXT_MAIN    = CandarUI.COL_TEXT
const COL_TEXT_SUB     = CandarUI.COL_TEXT_SUB
const COL_ROW_BG       = CandarUI.COL_BG_BOT
const COL_ROW_BORDER   = Color("#2d394b")

# ---- NODE REF ----
@onready var panel: PanelContainer      = $PanelContainer
@onready var scroll_container: ScrollContainer = $PanelContainer/ScrollContainer
@onready var root_box: VBoxContainer    = $PanelContainer/ScrollContainer/VBoxContainer
@onready var status_label: Label        = $PanelContainer/ScrollContainer/VBoxContainer/StatusLabel

# Bölüm container’ları
@onready var boost_section: VBoxContainer   = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection
@onready var premium_section: VBoxContainer = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection

# Başlıklar
@onready var title_label: Label         = $PanelContainer/ScrollContainer/VBoxContainer/TitleLabel
@onready var boost_title_label: Label   = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostTitleLabel
@onready var premium_title_label: Label = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumTitleLabel

# Listeler
@onready var boost_list: VBoxContainer   = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList
@onready var premium_list: VBoxContainer = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList

# Boost Row’ları
@onready var row_b1  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost1Row
@onready var row_b3  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost3Row
@onready var row_b7  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost7Row
@onready var row_p30 = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList/Prem30Row

@onready var info_b1  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost1Row/Boost1Info
@onready var info_b3  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost3Row/Boost3Info
@onready var info_b7  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost7Row/Boost7Info
@onready var info_p30 = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList/Prem30Row/Prem30Info

@onready var btn_b1  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost1Row/Boost1Button
@onready var btn_b3  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost3Row/Boost3Button
@onready var btn_b7  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost7Row/Boost7Button
@onready var btn_p30 = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList/Prem30Row/Prem30Button

# Labels
@onready var lbl_b1_name  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost1Row/Boost1Info/Boost1NameLabel
@onready var lbl_b1_desc  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost1Row/Boost1Info/Boost1DescLabel
@onready var lbl_b3_name  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost3Row/Boost3Info/Boost3NameLabel
@onready var lbl_b3_desc  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost3Row/Boost3Info/Boost3DescLabel
@onready var lbl_b7_name  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost7Row/Boost7Info/Boost7NameLabel
@onready var lbl_b7_desc  = $PanelContainer/ScrollContainer/VBoxContainer/BoostSection/BoostList/Boost7Row/Boost7Info/Boost7DescLabel
@onready var lbl_p30_name = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList/Prem30Row/Prem30Info/Prem30NameLabel
@onready var lbl_p30_desc = $PanelContainer/ScrollContainer/VBoxContainer/PremiumSection/PremiumList/Prem30Row/Prem30Info/Prem30DescLabel

var back_button: Button
var _toast_token: int = 0
var value_card: PanelContainer
var calculator_card: PanelContainer
var calculator_label: Label
var comparison_card: PanelContainer
var comparison_label: Label
var premium_panel_card: PanelContainer
var premium_panel_label: Label
var top_spacer: Control
var market_context := {
	"points": 0.0,
	"refs": 0,
	"base_rate": 1.0,
	"current_multiplier": 1.0,
	"rewarded_multiplier": 1.0,
	"total_rate": 1.0,
	"is_premium": false
}
const PRODUCT_IDS := {
	"basic": "candar.boost.basic.30d",
	"pro": "candar.boost.pro.30d",
	"ultra": "candar.boost.ultra.30d",
	"premium": "candar.premium.30d"
}
const FALLBACK_PRICES := {
	"candar.boost.basic.30d": "0.99$",
	"candar.boost.pro.30d": "1.99$",
	"candar.boost.ultra.30d": "2.99$",
	"candar.premium.30d": "2.99$"
}

func _ready() -> void:
	Global.analytics_page("Market", "app://candar/market")
	Global.analytics_event("app_screen_view", {"screen": "market"})
	_create_background()
	_create_header()
	_apply_layout()
	_create_calculator_card()
	_apply_style_premium()
	_apply_texts()
	_apply_market_responsive_typography()
	if not get_viewport().size_changed.is_connected(_apply_market_responsive_typography):
		get_viewport().size_changed.connect(_apply_market_responsive_typography)

	await Global.apply_safe_area(self)
	_apply_market_responsive_typography()
	_style_product_rows()
	if scroll_container:
		if (OS.has_feature("android") or OS.has_feature("ios")) and not Global.is_ad_free_user():
			CandarUI.apply_banner_bottom_inset(scroll_container)
		else:
			scroll_container.offset_bottom = 0
	if back_button:
		back_button.visible = true

	# IAPManager autoload bağla (varsa)
	_try_connect_iap()

	# Eski sahneyi gizle (şerit başlık)
	if title_label:
		title_label.visible = false

		# Buton Eventleri
	btn_b1.pressed.connect(func(): _start_purchase(PRODUCT_IDS["basic"]))
	btn_b3.pressed.connect(func(): _start_purchase(PRODUCT_IDS["pro"]))
	btn_b7.pressed.connect(func(): _start_purchase(PRODUCT_IDS["ultra"]))
	btn_p30.pressed.connect(func(): _start_purchase(PRODUCT_IDS["premium"]))

	back_button.pressed.connect(_on_back_pressed)

	var uid: String = Global.get_uid()
	if uid == "":
		status_label.text = tr("market_status_need_login")
	else:
		status_label.text = tr("market_status_choose")
		
	var ready_iap := _iap_manager()
	if OS.get_name() == "iOS" and ready_iap != null and ready_iap.has_method("ios_request_products"):
		ready_iap.ios_request_products([
			PRODUCT_IDS["basic"],
			PRODUCT_IDS["pro"],
			PRODUCT_IDS["ultra"],
			PRODUCT_IDS["premium"]
		])
	await _load_market_context()

func _iap_manager() -> Node:
	var node := get_node_or_null("/root/IapManager")
	if node != null:
		return node
	if typeof(IapManager) != TYPE_NIL:
		return IapManager
	return null

func _try_connect_iap() -> void:
	# Autoload adın: IapManager (Project Settings -> Autoload)
	# Bu scriptte global değişken olarak görünür.
	var iap := _iap_manager()
	if iap == null:
		print("[MARKET] IapManager autoload yok.")
		return

	# sinyal var mı kontrol et
	if iap.has_signal("purchase_applied"):
		# aynı sahne tekrar açılırsa çifte bağlanmasın
		if not iap.purchase_applied.is_connected(_on_purchase_applied):
			iap.purchase_applied.connect(_on_purchase_applied)
	if iap.has_signal("product_details_updated"):
		if not iap.product_details_updated.is_connected(_refresh_store_prices):
			iap.product_details_updated.connect(_refresh_store_prices)

func _on_back_pressed() -> void:
	_go_home()

func _go_home() -> void:
	Global.analytics_event("market_back", {"screen": "market"})
	get_tree().change_scene_to_file("res://home.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_home()

# ----------------------------------------------------------
# UI & STİL (senin mevcut fonksiyonların aynen)
# ----------------------------------------------------------
func _create_header() -> void:
	var hdr := CandarUI.create_header(self, tr("market_title"), true)
	if hdr.get("header") and hdr["header"]:
		(hdr["header"] as Panel).z_index = 40
	if hdr.get("back") and hdr["back"]:
		back_button = hdr["back"]
		back_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		back_button.size = Vector2(44, 44)
		back_button.position = Vector2(12, CandarUI.top_safe_inset() + 10.0)

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
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tex_rect)
	move_child(tex_rect, 0)

func _apply_layout() -> void:
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	if scroll_container:
		scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll_container.offset_top = CandarUI.header_total_height() + 8.0
		scroll_container.offset_bottom = 0
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var viewport_w: float = get_viewport_rect().size.x
	var compact: bool = viewport_w < 520.0
	var content_w: float = min(viewport_w - (24 if compact else 48), 560)
	root_box.custom_minimum_size.x = max(320, content_w)
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root_box.add_theme_constant_override("separation", 12)
	if top_spacer == null or not is_instance_valid(top_spacer):
		top_spacer = Control.new()
		top_spacer.name = "HeaderSpacer"
		root_box.add_child(top_spacer)
		root_box.move_child(top_spacer, 0)
	top_spacer.custom_minimum_size.y = CandarUI.header_total_height() + 8.0

	boost_section.add_theme_constant_override("separation", 8)
	premium_section.add_theme_constant_override("separation", 8)
	boost_list.add_theme_constant_override("separation", 12)
	premium_list.add_theme_constant_override("separation", 12)

	var rows = [row_b1, row_b3, row_b7, row_p30]
	var infos = [info_b1, info_b3, info_b7, info_p30]
	var btns = [btn_b1, btn_b3, btn_b7, btn_p30]

	for i in range(rows.size()):
		var row = rows[i]
		var info = infos[i]
		var btn = btns[i]
		if row:
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.custom_minimum_size.y = 88 if compact else 76
			if row.has_method("add_theme_constant_override"):
				row.add_theme_constant_override("separation", 8 if compact else 5)
		if info:
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.size_flags_stretch_ratio = 2.4 if compact else 1.8
			info.alignment = BoxContainer.ALIGNMENT_CENTER
		if btn:
			btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.custom_minimum_size = Vector2(96 if compact else 140, 48 if compact else 52)

func _style_product_rows() -> void:
	var rows := [row_b1, row_b3, row_b7, row_p30]
	for row in rows:
		if row == null or row.get_parent() is PanelContainer:
			continue
		var parent: Node = row.get_parent()
		var idx: int = row.get_index()
		var wrap := CandarUI.make_card(COL_ACCENT_BOOST, 14, COL_ROW_BG, 12)
		parent.remove_child(row)
		wrap.add_child(row)
		parent.add_child(wrap)
		parent.move_child(wrap, idx)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _is_tr() -> bool:
	var locale := TranslationServer.get_locale()
	return locale.begins_with("tr") if locale != "" else OS.get_locale().begins_with("tr")

func _ui_text(tr_text: String, en_text: String) -> String:
	return Global.localized_ui_text(tr_text, en_text)

func _create_value_card() -> void:
	if value_card and is_instance_valid(value_card):
		return
	value_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color("#f59e0b55")
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.24)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	value_card.add_theme_stylebox_override("panel", sb)
	value_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	value_card.add_child(box)

	var headline := Label.new()
	headline.text = _ui_text("Hız paketleri", "Speed packs")
	headline.add_theme_color_override("font_color", COL_TEXT_MAIN)
	headline.add_theme_font_size_override("font_size", 21)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(headline)

	var body := Label.new()
	body.text = _ui_text(
		"Satın alınan boost, referans ve reklam boost'u toplam günlük puan oranına eklenir.",
		"Paid boost, referrals, and ad boost all count toward your total daily point rate."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", COL_TEXT_SUB.lightened(0.12))
	body.add_theme_font_size_override("font_size", 16)
	box.add_child(body)

	var trust := Label.new()
	trust.text = _ui_text("Güvenli ödeme: App Store / Google Play", "Secure checkout: App Store / Google Play")
	trust.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trust.add_theme_color_override("font_color", COL_ACCENT_BOOST.lightened(0.12))
	trust.add_theme_font_size_override("font_size", 15)
	box.add_child(trust)

	root_box.add_child(value_card)
	var idx := root_box.get_children().find(boost_section)
	if idx >= 0:
		root_box.move_child(value_card, idx)

func _create_calculator_card() -> void:
	if calculator_card and is_instance_valid(calculator_card):
		return
	var nodes := _create_market_info_card(
		_ui_text("Boost Hesaplayıcı", "Boost Calculator"),
		_ui_text("Hesaplayıcı yükleniyor...", "Loading calculator...")
	)
	calculator_card = nodes["card"]
	calculator_label = nodes["label"]
	root_box.add_child(calculator_card)
	var idx := root_box.get_children().find(boost_section)
	if idx >= 0:
		root_box.move_child(calculator_card, idx + 1)

func _create_comparison_card() -> void:
	if comparison_card and is_instance_valid(comparison_card):
		return
	var nodes := _create_market_info_card(
		_ui_text("Paket Karşılaştırması", "Package Comparison"),
		_ui_text("Basic x2 · Pro x3 · Ultra x7", "Basic x2 · Pro x3 · Ultra x7")
	)
	comparison_card = nodes["card"]
	comparison_label = nodes["label"]
	root_box.add_child(comparison_card)
	var idx := root_box.get_children().find(calculator_card)
	if idx >= 0:
		root_box.move_child(comparison_card, idx + 1)

func _create_premium_panel_card() -> void:
	if premium_panel_card and is_instance_valid(premium_panel_card):
		return
	var nodes := _create_market_info_card(
		_ui_text("Premium Avantajları", "Premium Benefits"),
		_ui_text("Premium panel yükleniyor...", "Loading premium panel...")
	)
	premium_panel_card = nodes["card"]
	premium_panel_label = nodes["label"]
	root_box.add_child(premium_panel_card)
	var idx := root_box.get_children().find(premium_section)
	if idx >= 0:
		root_box.move_child(premium_panel_card, idx)

func _create_market_info_card(title: String, body: String) -> Dictionary:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color("#f59e0b55")
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.24)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var headline := Label.new()
	headline.text = title
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_color_override("font_color", COL_ACCENT_BOOST.lightened(0.1))
	headline.add_theme_font_size_override("font_size", 21)
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)

	var label := Label.new()
	label.text = body
	label.add_theme_color_override("font_color", COL_TEXT_SUB.lightened(0.12))
	label.add_theme_font_size_override("font_size", 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return {"card": card, "label": label}

func _load_market_context() -> void:
	var uid: String = Global.get_uid()
	if uid == "":
		_update_market_cards()
		return
	var doc: Dictionary = await Global.get_user_doc(uid)
	if typeof(doc) != TYPE_DICTIONARY or not (doc as Dictionary).has("fields"):
		_update_market_cards()
		return
	var fields: Dictionary = (doc as Dictionary)["fields"]
	Global.sync_point_entitlements(fields)
	if Global.is_ad_free_user():
		Global.ads_hide_banner()
		scroll_container.offset_bottom = 0
	var mining_fields: Dictionary = fields.get("mining", {}).get("mapValue", {}).get("fields", {})
	var ref_code := _field_string(fields, "referralCode")
	var refs := 0
	if ref_code != "":
		var raw: Array = await Global.get_users_by_referral(ref_code)
		if typeof(raw) == TYPE_ARRAY:
			refs = raw.size()
	var base_rate := _field_number(mining_fields, "base_rate", 1.0)
	if base_rate <= 0.0:
		base_rate = 1.0
	var current_mult := _field_number(fields, "currentMultiplier", _field_number(mining_fields, "active_multiplier", 1.0))
	var rate_components: Dictionary = await Global.get_user_mining_rate_components(uid, fields)
	var premium := false
	if fields.has("isPremium") and typeof(fields["isPremium"]) == TYPE_DICTIONARY and fields["isPremium"].has("booleanValue"):
		premium = bool(fields["isPremium"]["booleanValue"])
	var premium_fields: Dictionary = fields.get("premium", {}).get("mapValue", {}).get("fields", {})
	if premium_fields.has("is_active") and typeof(premium_fields["is_active"]) == TYPE_DICTIONARY and premium_fields["is_active"].has("booleanValue"):
		premium = bool(premium_fields["is_active"]["booleanValue"])
	market_context = {
		"points": _field_number(fields, "points", 0.0),
		"refs": int(rate_components.get("ref_count", refs)),
		"base_rate": float(rate_components.get("base_rate", base_rate)),
		"current_multiplier": float(rate_components.get("active_multiplier", current_mult)),
		"rewarded_multiplier": float(rate_components.get("rewarded_multiplier", 1.0)),
		"total_rate": float(rate_components.get("total_rate", base_rate)),
		"is_premium": premium
	}
	_update_market_cards()

func _update_market_cards() -> void:
	var refs := int(market_context.get("refs", 0))
	var base_rate := float(market_context.get("base_rate", 1.0))
	var ref_rate := 1.0 + float(refs) * 0.05
	var current_mult := float(market_context.get("current_multiplier", 1.0))
	var rewarded_mult := float(market_context.get("rewarded_multiplier", 1.0))
	var current_daily := float(market_context.get("total_rate", base_rate * ref_rate * current_mult * rewarded_mult))
	var calc_lines := []
	var per_day := _ui_text("/ gün", "/ day")
	for pack in [
		{"name": "Basic", "mult": 2.0},
		{"name": "Pro", "mult": 3.0},
		{"name": "Ultra", "mult": 7.0}
	]:
		var daily := base_rate * ref_rate * rewarded_mult * float(pack["mult"])
		calc_lines.append("%s x%.0f: %.2f %s" % [String(pack["name"]), float(pack["mult"]), daily, per_day])
	if calculator_label:
		calculator_label.text = _ui_text(
			"Şu an: %.2f / gün\nReferans: %d · x%.2f · Reklam boost: x%.2f\n%s",
			"Now: %.2f / day\nRefs: %d · x%.2f · Ad boost: x%.2f\n%s"
		) % [current_daily, refs, ref_rate, rewarded_mult, "\n".join(calc_lines)]
	if comparison_label:
		comparison_label.text = _ui_text(
			"Basic x2: başlangıç için ekonomik\nPro x3: fiyat/performans ve önerilen paket\nUltra x7: en hızlı büyüme paketi\nPremium: reklamsız deneyim + AI avantajı + profil rozeti",
			"Basic x2: economical start\nPro x3: recommended value pack\nUltra x7: fastest growth pack\nPremium: ad-free experience + AI advantage + profile badge"
		)
	if premium_panel_label:
		var state := _ui_text("Aktif", "Active") if bool(market_context.get("is_premium", false)) else _ui_text("Kapalı", "Off")
		premium_panel_label.text = _ui_text(
			"Premium durumun: %s\nPremium alan kullanıcı reklam görmez, AI tarafında daha güçlü görünür ve profilde özel rozet taşır.",
			"Premium status: %s\nPremium users do not see ads, get a stronger AI experience, and carry a special profile badge."
		) % state

func _field_string(fields: Dictionary, key: String) -> String:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("stringValue"):
		return String((v as Dictionary)["stringValue"])
	return ""

func _field_number(fields: Dictionary, key: String, default_value: float = 0.0) -> float:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY:
		if (v as Dictionary).has("doubleValue"):
			return float((v as Dictionary)["doubleValue"])
		if (v as Dictionary).has("integerValue"):
			return float((v as Dictionary)["integerValue"])
		if (v as Dictionary).has("stringValue") and String((v as Dictionary)["stringValue"]).is_valid_float():
			return float(String((v as Dictionary)["stringValue"]))
	return default_value

func _apply_market_responsive_typography() -> void:
	var vs := get_viewport_rect().size
	var is_compact := vs.x < 520.0
	var title_fs := 20 if is_compact else 28
	var body_fs := 14 if is_compact else 20
	var button_fs := 15 if is_compact else 20
	for l in [boost_title_label, premium_title_label]:
		if l:
			l.add_theme_font_size_override("font_size", title_fs)
	for l in [lbl_b1_name, lbl_b3_name, lbl_b7_name, lbl_p30_name, lbl_b1_desc, lbl_b3_desc, lbl_b7_desc, lbl_p30_desc, status_label]:
		if l:
			l.add_theme_font_size_override("font_size", body_fs)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if value_card:
		for n in value_card.find_children("*", "Label", true, false):
			var label := n as Label
			if label:
				label.add_theme_font_size_override("font_size", max(14, body_fs - 3))
	for card in [calculator_card, comparison_card, premium_panel_card]:
		if card:
			for n in card.find_children("*", "Label", true, false):
				var label := n as Label
				if label:
					label.add_theme_font_size_override("font_size", max(14, body_fs - 3))
	for b in [btn_b1, btn_b3, btn_b7, btn_p30]:
		if b:
			b.add_theme_font_size_override("font_size", button_fs)
			b.custom_minimum_size = Vector2(96 if is_compact else 128, 46 if is_compact else 48)

func _apply_style_premium() -> void:
	boost_title_label.text = tr("boost_section_title")
	boost_title_label.add_theme_color_override("font_color", COL_ACCENT_BOOST.lightened(0.2))
	boost_title_label.add_theme_font_size_override("font_size", 22)

	premium_title_label.text = tr("premium_section_title")
	premium_title_label.add_theme_color_override("font_color", COL_ACCENT_PREM.lightened(0.2))
	premium_title_label.add_theme_font_size_override("font_size", 22)

	var names = [lbl_b1_name, lbl_b3_name, lbl_b7_name, lbl_p30_name]
	for l in names:
		l.add_theme_color_override("font_color", COL_TEXT_MAIN)
		l.add_theme_font_size_override("font_size", 18)

	var descs = [lbl_b1_desc, lbl_b3_desc, lbl_b7_desc, lbl_p30_desc]
	for l in descs:
		l.add_theme_color_override("font_color", COL_TEXT_SUB)
		l.add_theme_font_size_override("font_size", 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var row_style = _get_row_style()
	for row in [row_b1, row_b3, row_b7, row_p30]:
		if row is PanelContainer:
			row.add_theme_stylebox_override("panel", row_style)

	var sb_boost   = _get_btn_style(COL_ACCENT_BOOST)
	var sb_boost_h = _get_btn_style(COL_ACCENT_BOOST.lightened(0.1))

	for b in [btn_b1, btn_b3, btn_b7]:
		b.add_theme_stylebox_override("normal", sb_boost)
		b.add_theme_stylebox_override("hover", sb_boost_h)
		b.add_theme_stylebox_override("pressed", sb_boost_h)
		b.add_theme_color_override("font_color", Color("#1e1b10"))
		b.add_theme_font_size_override("font_size", 28)

	var sb_prem   = _get_btn_style(COL_ACCENT_PREM)
	var sb_prem_h = _get_btn_style(COL_ACCENT_PREM.lightened(0.1))

	btn_p30.add_theme_stylebox_override("normal", sb_prem)
	btn_p30.add_theme_stylebox_override("hover", sb_prem_h)
	btn_p30.add_theme_stylebox_override("pressed", sb_prem_h)
	btn_p30.add_theme_color_override("font_color", Color.WHITE)
	btn_p30.add_theme_font_size_override("font_size", 28)

	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", COL_TEXT_SUB.lightened(0.2))
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.custom_minimum_size.y = 48

func _get_btn_style(col: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.border_width_top = 1
	sb.border_width_left = 1
	sb.border_color = col.lightened(0.3)
	return sb

func _get_row_style() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = COL_ROW_BG
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(1)
	sb.border_color = COL_ROW_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(16)
	return sb

func _apply_texts() -> void:
	lbl_b1_name.text = "%s  x2" % tr("boost_basic_name")
	lbl_b1_desc.text = tr("boost_basic_desc")

	lbl_b3_name.text = "%s  x3  %s" % [tr("boost_pro_name"), _ui_text("Popüler", "Popular")]
	lbl_b3_desc.text = tr("boost_pro_desc")

	lbl_b7_name.text = "%s  x7  %s" % [tr("boost_ultra_name"), _ui_text("En güçlü", "Strongest")]
	lbl_b7_desc.text = tr("boost_ultra_desc")

	lbl_p30_name.text = "%s  %s" % [tr("premium_30_name"), _ui_text("Reklamsız", "Ad-free")]
	lbl_p30_desc.text = tr("premium_30_desc")
	_refresh_store_prices()

func _refresh_store_prices() -> void:
	var iap := _iap_manager()
	var price_source = iap if iap != null and iap.has_method("get_display_price") else null
	var pairs := [
		[btn_b1, PRODUCT_IDS["basic"]],
		[btn_b3, PRODUCT_IDS["pro"]],
		[btn_b7, PRODUCT_IDS["ultra"]],
		[btn_p30, PRODUCT_IDS["premium"]]
	]
	for pair in pairs:
		var btn: Button = pair[0]
		var product_id: String = pair[1]
		var fallback := str(FALLBACK_PRICES.get(product_id, ""))
		btn.text = price_source.get_display_price(product_id, fallback) if price_source != null else fallback

# ----------------------------------------------------------
# SATIN ALMA
# ----------------------------------------------------------
func _set_loading(loading: bool) -> void:
	for b in [btn_b1, btn_b3, btn_b7, btn_p30]:
		b.disabled = loading

func _start_purchase(product_id: String) -> void:
	if Global.get_uid() == "":
		status_label.text = tr("market_status_need_login")
		return

	Global.analytics_event("begin_checkout", {"screen": "market", "item_id": product_id})
	_set_loading(true)
	status_label.text = tr("market_processing")

	await _purchase_async(product_id)

func buy_product(product_id: String):
	_start_purchase(product_id)

func _purchase_async(product_id: String) -> void:
	var res: Dictionary = {}
	var iap := _iap_manager()

	if iap == null:
		print("[MARKET] IapManager autoload yok!")
		_set_loading(false)
		status_label.text = tr("market_error") + ": IAP missing"
		return

	print("[MARKET] Satın alma başlatılıyor: ", product_id)

	if product_id.begins_with("candar.boost"):
		res = await iap.buy_boost(product_id)
	else:
		res = await iap.buy_premium(product_id)

	print("[MARKET] Satın alma sonucu: ", res)
	_handle_purchase_result(product_id, res)

func show_success_popup(text: String, is_premium: bool) -> void:
	_toast_token += 1
	var my_token := _toast_token

	status_label.text = text
	status_label.visible = true

	if is_premium:
		status_label.add_theme_color_override("font_color", COL_ACCENT_PREM)
	else:
		status_label.add_theme_color_override("font_color", COL_ACCENT_BOOST)

	await get_tree().create_timer(2.5).timeout
	if my_token == _toast_token and status_label.text == text:
		status_label.text = ""

func _on_purchase_applied(res: Dictionary) -> void:
	# satın alma kesinleşti -> loading kapat
	_set_loading(false)

	var prem := bool(res.get("is_premium", false))
	var msg := String(res.get("message", "Satın alma tamamlandı"))
	var boost_catchup: Dictionary = res.get("boostCatchup", {}) if typeof(res.get("boostCatchup", {})) == TYPE_DICTIONARY else {}
	await _load_market_context()
	if prem:
		msg = _ui_text("Premium aktif edildi.", "Premium is active.")
	else:
		var rate_components: Dictionary = res.get("rateComponents", {}) if typeof(res.get("rateComponents", {})) == TYPE_DICTIONARY else {}
		var active_mult := float(rate_components.get("boostMultiplier", market_context.get("current_multiplier", res.get("multiplier", 1.0))))
		var total_daily := float(rate_components.get("totalRate", market_context.get("total_rate", 1.0)))
		var catchup_delta := float(boost_catchup.get("delta", 0.0))
		if catchup_delta > 0.0:
			msg = _ui_text(
				"Boost x%.0f aktif. Günlük puan oranın %.2f oldu ve hesabına +%.2f Candar puanı eklendi.",
				"Boost x%.0f is active. Your daily point rate is now %.2f and +%.2f Candar points were added."
			) % [active_mult, total_daily, catchup_delta]
		else:
			msg = _ui_text(
				"Boost x%.0f aktif. Yeni günlük puanın: %.2f",
				"Boost x%.0f is active. New daily points: %.2f"
			) % [active_mult, total_daily]
	await show_success_popup(msg, prem)

func _handle_purchase_result(product_id: String, res: Dictionary) -> void:
	# Bu fonksiyon sadece "akış sonucu" için; asıl başarılı mesajı purchase_applied ile gelir.
	# Yine de hata varsa burada gösterelim.
	var ok := bool(res.get("ok", false))
	if ok:
		Global.analytics_event("purchase_flow_ok", {"screen": "market", "item_id": product_id})
		_set_loading(false)
		return

	if bool(res.get("pending", false)) or str(res.get("error", "")) == "purchase_pending":
		_set_loading(false)
		status_label.text = tr("purchase_pending")
		status_label.add_theme_color_override("font_color", COL_ACCENT_BOOST)
		return

	_set_loading(false)
	Global.analytics_event("purchase_flow_error", {"screen": "market", "item_id": product_id, "message": str(res).substr(0, 96)})

	var err_text := ""
	if res.has("error"):
		err_text = str(res["error"])
	elif res.has("message"):
		err_text = str(res["message"])

	if err_text == "":
		status_label.text = tr("market_error")
	else:
		status_label.text = tr("market_error") + ": " + err_text

	status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	print("[MARKET] Satın alma HATA: ", err_text, " / full: ", res)
