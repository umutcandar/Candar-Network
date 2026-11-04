# home.gd — Godot 4.5 (Localization Fixed Full)
extends Control

# ---------- SAHNE NODES ----------
@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var main_box: VBoxContainer = $MarginContainer/ScrollContainer/VBoxContainer
@onready var welcome_label 	: Label  = $MarginContainer/ScrollContainer/VBoxContainer/WelcomeLabel
@onready var puan_label 	: Label  = $MarginContainer/ScrollContainer/VBoxContainer/PuanLabel
@onready var mining_button 	: Button = $MarginContainer/ScrollContainer/VBoxContainer/MiningButton
@onready var profile_button : Button = $MarginContainer/ScrollContainer/VBoxContainer/ProfileButton
@onready var logout_button 	: Button = $MarginContainer/ScrollContainer/VBoxContainer/LogoutButton
@onready var market_button 	: Button = $MarginContainer/ScrollContainer/VBoxContainer/MarketButton
@onready var chat_button 	: Button = $MarginContainer/ScrollContainer/VBoxContainer/ChatButton

# ---------- REAL AD UNIT IDS ----------
const IOS_BANNER_ID 	   := "ca-app-pub-3086179575899998/8285142170"
const IOS_INTERSTITIAL_ID  := "ca-app-pub-3086179575899998/6972060507"
const IOS_REWARDED_ID 	   := "ca-app-pub-3086179575899998/4038775406"

const AND_BANNER_ID 	   := "ca-app-pub-3086179575899998/3506019172"
const AND_INTERSTITIAL_ID  := "ca-app-pub-3086179575899998/3083940247"
const AND_REWARDED_ID 	   := "ca-app-pub-3086179575899998/9932720942"
const REWARDED_BOOST_BUTTON_ENABLED := true
const REWARDED_BOOST_HOME_VISIBLE := false
const POINT_CENTER_ENABLED := true

# ---------- DURUM ----------
var countdown_label  : Label
var countdown_card 	 : PanelContainer
var footer_label 	 : Label
var rewarded_button  : Button
var dashboard_card   : PanelContainer
var dash_points_label: Label
var dash_rate_label  : Label
var dash_boost_label : Label
var dash_premium_label: Label
var dash_refs_label  : Label
var dashboard_grid   : GridContainer
var status_card      : PanelContainer
var streak_card      : PanelContainer
var streak_label     : Label
var tasks_card       : PanelContainer
var tasks_label      : Label
var missions_card    : PanelContainer
var missions_label   : Label
var strategy_card    : PanelContainer
var strategy_label   : Label
var real_team_label: Label
var referral_team_card: PanelContainer
var referral_team_label: Label
var referral_team_slots: Label
var point_center_card: PanelContainer
var point_center_label: Label
var ecosystem_card   : PanelContainer
var ecosystem_label  : Label
var growth_news_card : PanelContainer
var growth_news_label: Label
var community_roles_card: PanelContainer
var community_roles_label: Label
var premium_panel_card : PanelContainer
var premium_panel_label: Label
var hero_balance_label: Label
var hero_unit_label: Label
var progress_label: Label
var journey_progress_bar: ProgressBar
var journey_button: Button
var roadmap_steps_cache: Array = []
var stat_speed_pill: PanelContainer
var stat_boost_pill: PanelContainer
var stat_ref_pill: PanelContainer
var home_stats_row: HBoxContainer
var quick_actions_card: PanelContainer
var quick_actions_grid: GridContainer
var referanslar_popup
var tutorial_popup: AcceptDialog
var app_modal_overlay: ColorRect
var app_modal_panel: PanelContainer
var app_modal_title: Label
var app_modal_body: RichTextLabel
var app_modal_actions: GridContainer
var app_modal_action: Callable = Callable()
var app_modal_dismiss_action: Callable = Callable()
var invite_content_box: VBoxContainer
var current_user_id  : String = ""
var user_data 		 : Dictionary = {}
var mining_interval_seconds := 86400 	  # 24 saat
var mining_timer: Timer = null
var kazim_orani := 0.0
var home_points := 0.0
var home_ref_count := 0
var home_active_multiplier := 1.0
var home_rewarded_multiplier := 1.0
var home_premium_active := false
var home_reward_ready := false
var _home_sync_in_flight := false
var _home_sync_requested := false
var _engagement_synced_this_session := false
var _rewarded_flow_in_progress := false

var mining_in_progress := false
var _scroll_dragging := false
var _scroll_drag_total := 0.0
var _scroll_last_pos := Vector2.ZERO

# Interstitial kontrol
var interstitial_show_chance := 0.35
var min_time_between_interstitials := 180
var last_interstitial_show_time := 0

# ---------- Poing AdMob Değişkenleri ----------
var _banner_view 	   : AdView
var _interstitial_ad   : InterstitialAd
var _rewarded_ad 	   : RewardedAd

var _interstitial_cb   : InterstitialAdLoadCallback
var _rewarded_cb 	   : RewardedAdLoadCallback

# ---------- HELPERS ----------
func _num_field(field: Dictionary, default_value: float = 0.0) -> float:
	if field.has("doubleValue"):
		return float(field["doubleValue"])
	if field.has("integerValue"):
		return float(field["integerValue"])
	if field.has("stringValue"):
		var s := String(field["stringValue"])
		if s.is_valid_float():
			return float(s)
		if s.is_valid_int():
			return float(int(s))
	return default_value

func _is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")
func _is_ios() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("ios")

func _is_tr() -> bool:
	var locale := TranslationServer.get_locale()
	return locale.begins_with("tr") if locale != "" else OS.get_locale().begins_with("tr")

func _ui_text(tr_text: String, en_text: String) -> String:
	return tr_text if _is_tr() else en_text

# ---------- AdMob (Global + ATT safe) ----------
# Not: iOS'ta ATT iznini Global zaten yönetiyor (ATT -> MobileAds.initialize).
# Bu dosyada AdMob'u ikinci kez initialize etmiyoruz.
func _init_admob() -> void:
	if not _is_mobile():
		return

	await Global.ads_init_after_att(
		IOS_BANNER_ID, IOS_INTERSTITIAL_ID, IOS_REWARDED_ID,
		AND_BANNER_ID, AND_INTERSTITIAL_ID, AND_REWARDED_ID
	)
	if not is_inside_tree():
		return
	# Chat disables banners globally. Restore the home screen placement after
	# returning, including when the SDK was already initialized in this session.
	Global.ads_set_banner_allowed(true)
	# Banner'ı gerekiyorsa yükle
	if not Global.is_ad_free_user():
		Global.ads_on_focus_in()

func _load_banner() -> void:
	if not _is_mobile(): return
	if Global.is_ad_free_user(): return
	Global.ads_on_focus_in()

func _hide_banner() -> void:
	Global.ads_hide_banner()

# Interstitial: sahne değişimini geciktirmiyoruz (action_after_ad hemen çalışır),
# reklam uygun şartlarda gösterilir.
func try_show_interstitial_ad(action_after_ad: Callable = Callable()):
	if action_after_ad.is_valid():
		action_after_ad.call()
	if not _is_mobile(): return
	if Global.is_ad_free_user(): return
	Global.ads_try_show_interstitial(interstitial_show_chance, min_time_between_interstitials)

func _show_rewarded() -> bool:
	if not _is_mobile(): return false
	if Global.is_user_premium(): return false
	return Global.ads_show_rewarded()

func _show_rewarded_and_wait(attempt_at: int = 0) -> bool:
	if not _is_mobile(): return false
	if Global.is_user_premium(): return false
	return await Global.ads_show_rewarded_and_wait(180.0, current_user_id, attempt_at)

func _show_daily_reward_ad() -> bool:
	if not _is_mobile(): return false
	if Global.is_ad_free_user(): return false
	Global.ads_load_rewarded()
	var started_ms := Time.get_ticks_msec()
	while not Global.ads_has_rewarded_ready() and Time.get_ticks_msec() - started_ms < 6000:
		await get_tree().create_timer(0.1).timeout
	if not Global.ads_has_rewarded_ready():
		return false
	return await _show_rewarded_and_wait()


# ---------- UI ----------
func _apply_modern_style():
	if has_node("ColorRect"):
		$ColorRect.visible = false
	CandarUI.add_gradient_bg(self, "HomeGradient")
	var box := main_box
	box.add_theme_constant_override("separation", 16)

	welcome_label.add_theme_font_size_override("font_size", 18)
	welcome_label.add_theme_color_override("font_color", CandarUI.COL_TEXT_SUB)
	welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	puan_label.visible = false

	var hero_card := CandarUI.make_card(CandarUI.COL_ACCENT, 22, Color(0.06, 0.09, 0.16, 0.95), 20)
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 4)
	hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_card.add_child(hero_box)

	hero_balance_label = Label.new()
	CandarUI.style_hero_label(hero_balance_label, 52)
	hero_balance_label.text = "0.00"
	hero_box.add_child(hero_balance_label)

	hero_unit_label = Label.new()
	hero_unit_label.text = tr("home_candar_points")
	hero_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_unit_label.add_theme_font_size_override("font_size", 16)
	hero_unit_label.add_theme_color_override("font_color", CandarUI.COL_TEXT_SUB)
	hero_box.add_child(hero_unit_label)

	var idx_welcome := box.get_children().find(welcome_label)
	box.add_child(hero_card)
	if idx_welcome >= 0:
		box.move_child(hero_card, idx_welcome + 1)

	# Kazım butonu — ana CTA
	mining_button.custom_minimum_size = Vector2(0, 72)
	mining_button.add_theme_font_size_override("font_size", 20)
	mining_button.add_theme_color_override("font_color", Color("#1a1408"))
	var mining_style := StyleBoxFlat.new()
	mining_style.bg_color = CandarUI.COL_ACCENT_BRIGHT
	mining_style.shadow_size = 20
	mining_style.shadow_color = Color(CandarUI.COL_ACCENT.r, CandarUI.COL_ACCENT.g, CandarUI.COL_ACCENT.b, 0.4)
	mining_style.set_corner_radius_all(26)
	var mining_h := mining_style.duplicate(); mining_h.bg_color = CandarUI.COL_ACCENT_BRIGHT.lightened(0.08)
	var mining_p := mining_style.duplicate(); mining_p.bg_color = CandarUI.COL_ACCENT.darkened(0.06)
	mining_button.add_theme_stylebox_override("normal", mining_style)
	mining_button.add_theme_stylebox_override("hover", mining_h)
	mining_button.add_theme_stylebox_override("pressed", mining_p)

	for item in [
		{"button": market_button, "text": tr("market_button")},
		{"button": chat_button, "text": tr("home_btn_ai")},
		{"button": profile_button, "text": tr("profile_button")},
		{"button": logout_button, "text": tr("logout_button")}
	]:
		var btn: Button = item["button"]
		if btn:
			_style_home_menu_button(btn, str(item["text"]))
	_style_quick_access_buttons()

# ---------- READY ----------
func _ready():
	Global.analytics_page("Home", "app://candar/home")
	Global.analytics_event("app_screen_view", {"screen": "home"})
	_inject_dynamic_nodes()
	if not Global.rewarded_boost_applied.is_connected(_on_rewarded_boost_applied):
		Global.rewarded_boost_applied.connect(_on_rewarded_boost_applied)
	kazim_orani = Global.mining_rate
	_apply_modern_style()
	_configure_scroll_behavior()
	await Global.apply_safe_area(self)
	_apply_home_responsive_layout()
	if not get_viewport().size_changed.is_connected(_apply_home_responsive_layout):
		get_viewport().size_changed.connect(_apply_home_responsive_layout)
	# ÇEVİRİ DÜZELTİLDİ
	welcome_label.text = tr("home_welcome") # "Hoş geldin"
	puan_label.text = tr("home_points_loading") # "Candar yükleniyor..."

	current_user_id = get_current_uid()
	if current_user_id != "":
		load_user_data(current_user_id)
	else:
		get_tree().call_deferred("change_scene_to_file", "res://onboarding.tscn")
		return

	mining_button.pressed.connect(_on_mining_button_pressed)
	profile_button.pressed.connect(_on_profile_button_pressed)
	logout_button.pressed.connect(_on_logout_button_pressed)
	chat_button.pressed.connect(_on_chat_button_pressed)
	if market_button:
		market_button.pressed.connect(_open_market)

	if _is_mobile():
		await _init_admob()

	if _is_mobile() and not Global.is_ad_free_user():
		CandarUI.apply_banner_bottom_inset(scroll_container)
	else:
		scroll_container.offset_bottom = 0

func _configure_scroll_behavior() -> void:
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.follow_focus = true
	scroll_container.mouse_filter = Control.MOUSE_FILTER_STOP
	main_box.mouse_filter = Control.MOUSE_FILTER_PASS

func _apply_home_responsive_layout() -> void:
	var margin := $MarginContainer as MarginContainer
	var box := main_box
	var vs := get_viewport_rect().size
	var is_tablet := vs.x >= 900.0 or (vs.x > 700.0 and vs.y / maxf(vs.x, 1.0) < 1.55)
	var content_w := minf(vs.x - 40.0, 640.0 if is_tablet else 560.0)
	content_w = maxf(content_w, minf(vs.x - 24.0, 360.0))
	var side_margin := maxf((vs.x - content_w) / 2.0, 14.0)
	var top_margin := 26.0 if is_tablet else 18.0
	var bottom_margin := 28.0 if is_tablet else 18.0
	if _is_mobile() and not Global.is_ad_free_user():
		bottom_margin += CandarUI.AD_BANNER_INSET

	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.scale = Vector2.ONE
	margin.offset_left = 0
	margin.offset_top = CandarUI.top_safe_inset() if _is_mobile() else 0.0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", int(side_margin))
	margin.add_theme_constant_override("margin_right", int(side_margin))
	margin.add_theme_constant_override("margin_top", int(top_margin))
	margin.add_theme_constant_override("margin_bottom", int(bottom_margin))

	box.custom_minimum_size = Vector2(0, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 18 if is_tablet else 14)

	var main_font := 25 if is_tablet else 22
	var title_font := 32 if is_tablet else 28
	var small_font := 20 if is_tablet else 18
	welcome_label.add_theme_font_size_override("font_size", title_font)
	puan_label.add_theme_font_size_override("font_size", main_font)
	if countdown_label:
		countdown_label.add_theme_font_size_override("font_size", small_font)
	if footer_label:
		footer_label.add_theme_font_size_override("font_size", small_font)
		footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if hero_balance_label:
		hero_balance_label.add_theme_font_size_override("font_size", 48 if not is_tablet else 56)
	var logo := get_node_or_null("MarginContainer/ScrollContainer/VBoxContainer/TextureRect") as TextureRect
	if logo:
		logo.custom_minimum_size = Vector2(70, 70) if not is_tablet else Vector2(84, 84)
	for l in [progress_label, strategy_label]:
		if l:
			l.add_theme_font_size_override("font_size", small_font)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [referral_team_label, point_center_label, ecosystem_label, growth_news_label, community_roles_label]:
		if l:
			l.add_theme_font_size_override("font_size", 17 if not is_tablet else 19)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for b in [mining_button, rewarded_button]:
		if b:
			b.add_theme_font_size_override("font_size", main_font)
			b.custom_minimum_size.y = 64 if is_tablet else 58
	if quick_actions_grid:
		quick_actions_grid.columns = 1
	for b in [chat_button, market_button, profile_button]:
		if b:
			b.add_theme_font_size_override("font_size", 20 if is_tablet else 18)
			b.custom_minimum_size.y = 64 if is_tablet else 58
	if logout_button:
		logout_button.add_theme_font_size_override("font_size", 17 if is_tablet else 16)
		logout_button.custom_minimum_size.y = 50 if is_tablet else 46

# ---------- MARKET ----------
func _open_market():
	Global.analytics_event("open_market", {"screen": "home"})
	if Global.has_method("ads_set_banner_allowed"):
		Global.ads_set_banner_allowed(true)
	else:
		_hide_banner()
	get_tree().change_scene_to_file("res://market.tscn")

# ---------- DINAMIK NODES ----------
func _inject_dynamic_nodes():
	var box := main_box

	# --- COUNTDOWN PILL ---
	countdown_card = PanelContainer.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.1, 0.12, 0.21, 0.92)
	pill.set_corner_radius_all(18)
	pill.shadow_size  = 20
	pill.shadow_color = Color(0, 0, 0, 0.3)
	pill.border_color = Color("#FFA51B66")
	pill.set_border_width_all(1)
	countdown_card.add_theme_stylebox_override("panel", pill)
	countdown_card.custom_minimum_size = Vector2(0, 54)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)

	countdown_label = Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 28)
	countdown_label.add_theme_color_override("font_color", Color(0.96,0.96,0.98,0.95))
	
	# ÇEVİRİ DÜZELTİLDİ: tr()
	countdown_label.text = tr("home_countdown") % [0,0,0]
	m.add_child(countdown_label)
	countdown_card.add_child(m)

	var idx := box.get_children().find(mining_button)
	box.add_child(countdown_card)
	box.move_child(countdown_card, idx + 1)

	# --- HIZLI İSTATİSTİKLER ---
	home_stats_row = HBoxContainer.new()
	home_stats_row.add_theme_constant_override("separation", 8)
	stat_speed_pill = CandarUI.make_stat_pill(tr("home_rate_short"), "x1.00")
	stat_boost_pill = CandarUI.make_stat_pill(tr("home_boost_short"), "x1")
	stat_ref_pill = CandarUI.make_stat_pill(tr("home_refs_short"), "0")
	for p in [stat_speed_pill, stat_boost_pill, stat_ref_pill]:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		home_stats_row.add_child(p)
	box.add_child(home_stats_row)
	box.move_child(home_stats_row, idx + 2)

	# Ana hedeflere ayrılmış, belirgin bir hızlı erişim kartı.
	var quick_nodes := _add_feature_card(
		tr("home_quick_access_title"),
		tr("home_quick_access_desc"),
		Color("#f59e0b88")
	)
	quick_actions_card = quick_nodes["card"]
	var quick_box := quick_nodes["box"] as VBoxContainer
	var quick_desc := quick_nodes["label"] as Label
	if quick_desc:
		quick_desc.visible = false
	quick_actions_grid = GridContainer.new()
	quick_actions_grid.columns = 1
	quick_actions_grid.add_theme_constant_override("h_separation", 8)
	quick_actions_grid.add_theme_constant_override("v_separation", 8)
	quick_actions_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_box.add_child(quick_actions_grid)
	for quick_button in [chat_button, market_button, profile_button]:
		if quick_button:
			quick_button.reparent(quick_actions_grid)
	box.add_child(quick_actions_card)
	box.move_child(quick_actions_card, idx + 3)

	var insert_pos := idx + 4

	# Eski dashboard hücreleri (güncelleme fonksiyonları için tutuluyor)
	dash_points_label = null
	dash_rate_label = null
	dash_boost_label = null
	dash_premium_label = null
	dash_refs_label = null

	var progress_nodes := _add_feature_card(
		tr("home_roadmap_title"),
		tr("toast_loading"),
		Color("#334155")
	)
	streak_card = progress_nodes["card"]
	progress_label = progress_nodes["label"]
	streak_label = progress_label
	tasks_label = progress_label
	missions_label = progress_label
	journey_progress_bar = ProgressBar.new()
	journey_progress_bar.min_value = 0.0
	journey_progress_bar.max_value = 6.0
	journey_progress_bar.step = 1.0
	journey_progress_bar.show_percentage = false
	journey_progress_bar.custom_minimum_size = Vector2(0, 14)
	var journey_bg := StyleBoxFlat.new()
	journey_bg.bg_color = Color("#1b2436")
	journey_bg.set_corner_radius_all(999)
	var journey_fill := StyleBoxFlat.new()
	journey_fill.bg_color = Color("#fbbf24")
	journey_fill.set_corner_radius_all(999)
	journey_progress_bar.add_theme_stylebox_override("background", journey_bg)
	journey_progress_bar.add_theme_stylebox_override("fill", journey_fill)
	(progress_nodes["box"] as VBoxContainer).add_child(journey_progress_bar)
	journey_button = _mk_card_action_button(tr("home_roadmap_view"))
	journey_button.pressed.connect(_open_roadmap)
	(progress_nodes["box"] as VBoxContainer).add_child(journey_button)
	box.add_child(streak_card)
	box.move_child(streak_card, insert_pos)
	insert_pos += 1

	var team_nodes := _add_feature_card(
		_ui_text("👥 Referans Takımım", "👥 My Referral Team"),
		_ui_text("Takımın yükleniyor...", "Loading your team..."),
		Color("#38bdf866")
	)
	referral_team_card = team_nodes["card"]
	referral_team_label = team_nodes["label"]
	referral_team_slots = Label.new()
	referral_team_slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	referral_team_slots.add_theme_font_size_override("font_size", 25)
	referral_team_slots.add_theme_color_override("font_color", Color("#fbbf24"))
	(team_nodes["box"] as VBoxContainer).add_child(referral_team_slots)
	var team_button := _mk_card_action_button(_ui_text("Takımı Gör / Davet Et", "View Team / Invite"))
	team_button.pressed.connect(_on_referanslar_button_pressed)
	(team_nodes["box"] as VBoxContainer).add_child(team_button)
	box.add_child(referral_team_card)
	box.move_child(referral_team_card, insert_pos)
	insert_pos += 1

	var real_team_nodes := _add_feature_card(
		_ui_text("🌐 Candar Topluluk Takımı", "🌐 Candar Community Team"),
		_ui_text("30 kişilik bir takım kur, kodla katıl veya sıralamayı gör.", "Create or join a 30-member team and compete on the leaderboard."),
		Color("#06b6d466")
	)
	real_team_label = real_team_nodes["label"]
	var real_team_button := _mk_card_action_button(_ui_text("Takım Merkezini Aç", "Open Team Center"))
	real_team_button.pressed.connect(_open_real_team_center)
	(real_team_nodes["box"] as VBoxContainer).add_child(real_team_button)
	box.add_child(real_team_nodes["card"])
	box.move_child(real_team_nodes["card"], insert_pos)
	insert_pos += 1

	var point_nodes := _add_feature_card(
		_ui_text("🎁 Puan Kullanım Merkezi", "🎁 Points Use Center"),
		_ui_text("Candar puanlarını gerçek uygulama avantajlarında kullan.", "Use Candar points for real in-app benefits."),
		Color("#f59e0b77")
	)
	point_center_card = point_nodes["card"]
	point_center_label = point_nodes["label"]
	var point_button := _mk_card_action_button(_ui_text("Avantajları Aç", "Open Benefits"))
	point_button.pressed.connect(_open_point_center)
	(point_nodes["box"] as VBoxContainer).add_child(point_button)
	box.add_child(point_center_card)
	box.move_child(point_center_card, insert_pos)
	insert_pos += 1

	var ecosystem_nodes := _add_feature_card(
		tr("home_center_title"),
		tr("home_center_desc"),
		Color("#334155")
	)
	ecosystem_card = ecosystem_nodes["card"]
	ecosystem_label = ecosystem_nodes["label"]
	var center_button := _mk_card_action_button(tr("home_center_open"))
	center_button.pressed.connect(_open_ecosystem)
	(ecosystem_nodes["box"] as VBoxContainer).add_child(center_button)
	box.add_child(ecosystem_card)
	box.move_child(ecosystem_card, insert_pos)
	insert_pos += 1

	var roles_nodes := _add_feature_card(
		_ui_text("🏅 Topluluk Rolleri", "🏅 Community Roles"),
		_ui_text("Kalıcı rollerin hesaplanıyor...", "Calculating your permanent roles..."),
		Color("#fb718566")
	)
	community_roles_card = roles_nodes["card"]
	community_roles_label = roles_nodes["label"]
	var roles_button := _mk_card_action_button(_ui_text("Rol Koleksiyonunu Gör", "View Role Collection"))
	roles_button.pressed.connect(_open_community_roles)
	(roles_nodes["box"] as VBoxContainer).add_child(roles_button)
	box.add_child(community_roles_card)
	box.move_child(community_roles_card, insert_pos)
	insert_pos += 1

	var news_nodes := _add_feature_card(
		_ui_text("📣 Candar Gelişiyor", "📣 Candar Is Growing"),
		_ui_text("Temmuz 2026 · Günlük kazım, gelişim ve topluluk özellikleri yenilendi.", "July 2026 · Daily points, progress, and community features were improved."),
		Color("#34d39955")
	)
	growth_news_card = news_nodes["card"]
	growth_news_label = news_nodes["label"]
	var news_button := _mk_card_action_button(_ui_text("Gelişim Haberlerini Oku", "Read Growth News"))
	news_button.pressed.connect(_open_growth_news)
	(news_nodes["box"] as VBoxContainer).add_child(news_button)
	box.add_child(growth_news_card)
	box.move_child(growth_news_card, insert_pos)
	insert_pos += 1

	var strategy_nodes := _add_feature_card(
		_ui_text("💡 Bugünün Odağı", "💡 Today's Focus"),
		_ui_text("Kişisel öneri hazırlanıyor...", "Preparing personal advice...")
	)
	strategy_card = strategy_nodes["card"]
	strategy_label = strategy_nodes["label"]
	box.add_child(strategy_card)
	box.move_child(strategy_card, insert_pos)
	insert_pos += 1

	if logout_button:
		logout_button.visible = true
		box.move_child(logout_button, insert_pos)
		insert_pos += 1
	
	# --- OPSIYONEL REWARDED REKLAM BUTONU ---
	if REWARDED_BOOST_BUTTON_ENABLED:
		rewarded_button = _mk_card_action_button(_ui_text("Ekstra oran için reklam izle", "Watch ad for extra rate"))
		rewarded_button.custom_minimum_size = Vector2(0, 50)
		rewarded_button.add_theme_font_size_override("font_size", 17)
		rewarded_button.visible = REWARDED_BOOST_HOME_VISIBLE
		rewarded_button.pressed.connect(_on_rewarded_button_pressed)
		box.add_child(rewarded_button)
		box.move_child(rewarded_button, insert_pos)
		insert_pos += 1

	# İkincil ayrıntılar tek Candar Merkezi altında açılır; ana sayfa sakin kalır.
	for secondary_card in [strategy_card, point_center_card, referral_team_card, community_roles_card, growth_news_card]:
		if secondary_card:
			secondary_card.visible = false

	# Ürün hiyerarşisi: kazım → durum → ana araçlar → ilerleme → merkez.
	# AI/Market/Profil artık kullanıcı ekranı tararken ilk görüş alanında kalır.
	var ordered_nodes: Array[Control] = [
		home_stats_row,
		quick_actions_card,
		streak_card,
		ecosystem_card
	]
	var ordered_pos := idx + 2
	for ordered_node in ordered_nodes:
		box.move_child(ordered_node, ordered_pos)
		ordered_pos += 1
	box.move_child(logout_button, ordered_pos)

	# --- FOOTER ---
	footer_label = Label.new()
	var app_version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	footer_label.text = "Candar Network • v%s • 2026" % app_version if app_version != "" else "Candar Network • 2026"
	footer_label.modulate = Color(1,1,1,0.6)
	box.add_child(footer_label)

	countdown_card.visible = false
	mining_button.visible  = true

func _mk_dashboard_cell(title: String, value: String) -> Label:
	var lbl := Label.new()
	lbl.text = "%s\n%s" % [title, value]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.42))
	lbl.add_theme_constant_override("outline_size", 1)
	lbl.custom_minimum_size = Vector2(0, 52)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl

func _add_feature_card(title: String, body: String, border_color := Color("#f59e0b55")) -> Dictionary:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.09, 0.15, 0.96)
	style.set_corner_radius_all(18)
	style.shadow_size = 10
	style.shadow_color = Color(0, 0, 0, 0.20)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	card.add_theme_stylebox_override("panel", style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color("#fbbf24"))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 16)
	body_label.add_theme_color_override("font_color", Color("#cbd5e1"))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body_label)

	return {"card": card, "box": box, "label": body_label}

func _mk_compact_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color("#232c3b"))
	var base := StyleBoxFlat.new()
	base.bg_color = Color("#FFD074")
	base.set_corner_radius_all(14)
	var hover := base.duplicate()
	hover.bg_color = Color("#ffe09a")
	var pressed := base.duplicate()
	pressed.bg_color = Color("#f3b645")
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

func _mk_card_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color("#fbbf24"))
	var base := StyleBoxFlat.new()
	base.bg_color = Color("#1b2638")
	base.border_color = Color("#f59e0b55")
	base.set_border_width_all(1)
	base.set_corner_radius_all(13)
	var hover := base.duplicate()
	hover.bg_color = Color("#263449")
	var pressed := base.duplicate()
	pressed.bg_color = Color("#111b2b")
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", pressed)
	return btn

func _style_home_menu_button(btn: Button, text: String) -> void:
	btn.text = text
	btn.visible = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 72)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", CandarUI.COL_ACCENT_BRIGHT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = CandarUI.COL_BTN_DARK
	normal.set_corner_radius_all(16)
	normal.shadow_size = 10
	normal.shadow_color = Color(0, 0, 0, 0.20)
	var hover := normal.duplicate()
	hover.bg_color = Color("#2b3547")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#1e2634")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)

func _style_quick_access_buttons() -> void:
	if chat_button:
		chat_button.text = tr("home_btn_ai")
		chat_button.add_theme_color_override("font_color", Color("#f8fafc"))
		var ai_normal := StyleBoxFlat.new()
		ai_normal.bg_color = Color("#172235")
		ai_normal.border_color = Color("#f59e0b88")
		ai_normal.set_border_width_all(1)
		ai_normal.set_corner_radius_all(17)
		var ai_hover := ai_normal.duplicate()
		ai_hover.bg_color = Color("#223149")
		var ai_pressed := ai_normal.duplicate()
		ai_pressed.bg_color = Color("#101a2a")
		chat_button.add_theme_stylebox_override("normal", ai_normal)
		chat_button.add_theme_stylebox_override("hover", ai_hover)
		chat_button.add_theme_stylebox_override("pressed", ai_pressed)
		chat_button.add_theme_stylebox_override("focus", ai_hover)

	for secondary_button in [market_button, profile_button]:
		if secondary_button:
			secondary_button.add_theme_color_override("font_color", Color("#f8fafc"))
			var secondary_normal := StyleBoxFlat.new()
			secondary_normal.bg_color = Color("#172235")
			secondary_normal.border_color = Color("#f59e0b66")
			secondary_normal.set_border_width_all(1)
			secondary_normal.set_corner_radius_all(15)
			var secondary_hover := secondary_normal.duplicate()
			secondary_hover.bg_color = Color("#223149")
			var secondary_pressed := secondary_normal.duplicate()
			secondary_pressed.bg_color = Color("#101a2a")
			secondary_button.add_theme_stylebox_override("normal", secondary_normal)
			secondary_button.add_theme_stylebox_override("hover", secondary_hover)
			secondary_button.add_theme_stylebox_override("pressed", secondary_pressed)
			secondary_button.add_theme_stylebox_override("focus", secondary_hover)

func _set_rewarded_button_idle() -> void:
	if rewarded_button == null or _rewarded_flow_in_progress:
		return
	if not REWARDED_BOOST_BUTTON_ENABLED:
		rewarded_button.visible = false
		rewarded_button.disabled = true
		return
	rewarded_button.visible = REWARDED_BOOST_HOME_VISIBLE
	rewarded_button.disabled = false
	rewarded_button.text = _ui_text("Ekstra oran için reklam izle", "Watch ad for extra rate")

func _set_rewarded_button_blocked(status: Dictionary) -> void:
	if rewarded_button == null:
		return
	rewarded_button.visible = REWARDED_BOOST_HOME_VISIBLE
	rewarded_button.disabled = true
	var error_code := str(status.get("error", ""))
	match error_code:
		"rewarded_boost_daily_limit":
			rewarded_button.text = _ui_text("Bugünkü reklam hakkı doldu", "Daily ad limit reached")
		"rewarded_boost_daily_attempt_limit":
			rewarded_button.text = _ui_text("2 reklam hakkı doldu · %s", "2-ad limit reached · %s") % _format_rewarded_wait_time(int(status.get("remaining_seconds", 0)))
		"rewarded_boost_max_reached":
			rewarded_button.text = _ui_text("Maksimum boost · %s", "Max boost · %s") % _format_rewarded_wait_time(int(status.get("remaining_seconds", 0)))
		"rewarded_boost_cooldown":
			rewarded_button.text = _format_rewarded_wait_time(int(status.get("remaining_seconds", 0)))
		_:
			rewarded_button.text = _ui_text("Reklam şu an kullanılamıyor", "Ad unavailable")

func _refresh_rewarded_button_state() -> void:
	if rewarded_button == null or not REWARDED_BOOST_BUTTON_ENABLED or _rewarded_flow_in_progress:
		return
	if current_user_id == "":
		return
	var boost_status: Dictionary = await Global.get_rewarded_boost_status(current_user_id)
	# A status request that started before a tap must not unlock the active flow.
	if _rewarded_flow_in_progress:
		return
	if not bool(boost_status.get("can_apply", true)):
		_set_rewarded_button_blocked(boost_status)
	else:
		_set_rewarded_button_idle()

func _on_rewarded_boost_applied(payload: Dictionary) -> void:
	if not is_inside_tree() or current_user_id == "":
		return
	var components: Dictionary = {}
	var raw_components: Variant = payload.get("components", {})
	if typeof(raw_components) == TYPE_DICTIONARY:
		components = raw_components

	var rewarded_multiplier := float(payload.get(
		"rewarded_multiplier",
		components.get("rewarded_multiplier", home_rewarded_multiplier)
	))
	var total_rate := float(payload.get(
		"total_rate",
		components.get("total_rate", Global.mining_rate)
	))
	var active_multiplier := float(components.get("active_multiplier", home_active_multiplier))
	var points_boost_multiplier := float(components.get("points_boost_multiplier", 1.0))
	var ref_count := int(components.get("ref_count", home_ref_count))

	Global.mining_rate = total_rate
	kazim_orani = total_rate
	user_data["rewardedBoostMultiplier"] = {"doubleValue": rewarded_multiplier}
	user_data["lastKnownMiningRate"] = {"doubleValue": total_rate}
	_update_dashboard(
		home_points,
		total_rate,
		active_multiplier * points_boost_multiplier,
		rewarded_multiplier,
		home_premium_active,
		ref_count
	)
	_request_home_data_sync()

func _request_home_data_sync() -> void:
	if current_user_id == "":
		return
	_home_sync_requested = true
	if not _home_sync_in_flight:
		call_deferred("_run_home_data_sync")

func _run_home_data_sync() -> void:
	if _home_sync_in_flight or current_user_id == "":
		return
	_home_sync_in_flight = true
	while _home_sync_requested and is_inside_tree():
		_home_sync_requested = false
		var latest_doc: Dictionary = await Global.get_user_doc(current_user_id)
		if latest_doc.has("fields") and typeof(latest_doc["fields"]) == TYPE_DICTIONARY:
			user_data = latest_doc["fields"]
			await update_kazim_orani_ve_ui()
		await _refresh_rewarded_button_state()
	_home_sync_in_flight = false

func _show_app_modal(title: String, body: String, action_text: String = "", action: Callable = Callable(), dismiss_action: Callable = Callable()) -> void:
	_close_app_modal(false)

	app_modal_action = action
	app_modal_dismiss_action = dismiss_action
	app_modal_overlay = ColorRect.new()
	app_modal_overlay.color = Color(0, 0, 0, 0.68)
	app_modal_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	app_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(app_modal_overlay)
	move_child(app_modal_overlay, get_child_count() - 1)

	var stage := VBoxContainer.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	app_modal_overlay.add_child(stage)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(air)

	app_modal_panel = PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#0b1220")
	panel_style.corner_radius_top_left = 28
	panel_style.corner_radius_top_right = 28
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 22
	app_modal_panel.add_theme_stylebox_override("panel", panel_style)
	app_modal_panel.custom_minimum_size = Vector2(get_viewport_rect().size.x, 0)
	stage.add_child(app_modal_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	app_modal_panel.add_child(box)

	var handle := ColorRect.new()
	handle.color = Color("#f59e0b")
	handle.custom_minimum_size = Vector2(46, 4)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(handle)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	app_modal_title = Label.new()
	app_modal_title.text = title
	app_modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_modal_title.add_theme_font_size_override("font_size", 25)
	app_modal_title.add_theme_color_override("font_color", Color("#f8fafc"))
	header.add_child(app_modal_title)
	var x_btn := CandarUI.make_ghost_icon_button("×", 42)
	x_btn.add_theme_font_size_override("font_size", 28)
	x_btn.add_theme_color_override("font_color", Color("#f8fafc"))
	x_btn.pressed.connect(func(): _close_app_modal(false))
	header.add_child(x_btn)

	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body_line_count := maxi(2, body.count("\n") + 1)
	# Panel banner'ın üstünde sabit kalırken uzun Yol Haritası/rol metinleri
	# kendi alanında kayar; panel hiçbir cihazda ekran dışına taşmaz.
	var body_height := minf(
		maxf(88.0, float(body_line_count) * 36.0),
		minf(get_viewport_rect().size.y * 0.40, 360.0)
	)
	body_scroll.custom_minimum_size = Vector2(0, body_height)
	box.add_child(body_scroll)

	app_modal_body = RichTextLabel.new()
	app_modal_body.fit_content = true
	app_modal_body.scroll_active = false
	app_modal_body.bbcode_enabled = false
	app_modal_body.text = body
	app_modal_body.custom_minimum_size = Vector2(maxf(280.0, get_viewport_rect().size.x - 44.0), 100.0)
	app_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_modal_body.add_theme_font_size_override("normal_font_size", 22)
	app_modal_body.add_theme_color_override("default_color", Color("#e5e7eb"))
	app_modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_scroll.add_child(app_modal_body)

	app_modal_actions = GridContainer.new()
	app_modal_actions.columns = 2 if action_text != "" and action.is_valid() else 1
	app_modal_actions.add_theme_constant_override("h_separation", 12)
	app_modal_actions.add_theme_constant_override("v_separation", 12)
	box.add_child(app_modal_actions)

	var close_key := "common_cancel" if action_text != "" and action.is_valid() else "common_close"
	var close_btn := _mk_card_action_button(tr(close_key))
	close_btn.custom_minimum_size = Vector2(150, 58)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func(): _close_app_modal(false))
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_modal_actions.add_child(close_btn)

	if action_text != "" and action.is_valid():
		var next_btn := _mk_compact_button(action_text)
		next_btn.custom_minimum_size = Vector2(150, 58)
		next_btn.add_theme_font_size_override("font_size", 20)
		next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next_btn.pressed.connect(func(): _close_app_modal(true))
		app_modal_actions.add_child(next_btn)

	var banner_clearance := Control.new()
	banner_clearance.custom_minimum_size.y = CandarUI.MODAL_BANNER_CLEARANCE if not Global.is_ad_free_user() else 18.0
	banner_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(banner_clearance)

func _show_choice_modal(title: String, body: String, choices: Array) -> void:
	_show_app_modal(title, body)
	if not app_modal_actions or not is_instance_valid(app_modal_actions):
		return
	app_modal_actions.columns = 2
	var close_btn := app_modal_actions.get_child(0) if app_modal_actions.get_child_count() > 0 else null
	for choice in choices:
		if typeof(choice) != TYPE_DICTIONARY:
			continue
		var action: Callable = choice.get("action", Callable())
		if not action.is_valid():
			continue
		var btn := _mk_card_action_button(str(choice.get("text", "")))
		btn.custom_minimum_size = Vector2(150, 58)
		btn.add_theme_font_size_override("font_size", 20)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_run_modal_choice.bind(action))
		app_modal_actions.add_child(btn)
	if close_btn:
		app_modal_actions.move_child(close_btn, app_modal_actions.get_child_count() - 1)

func _run_modal_choice(action: Callable) -> void:
	_close_app_modal(false)
	if action.is_valid():
		action.call()

func _close_app_modal(run_action: bool = false) -> void:
	var action := app_modal_action
	var dismiss_action := app_modal_dismiss_action
	app_modal_action = Callable()
	app_modal_dismiss_action = Callable()
	if app_modal_overlay and is_instance_valid(app_modal_overlay):
		app_modal_overlay.queue_free()
	app_modal_overlay = null
	app_modal_panel = null
	app_modal_title = null
	app_modal_body = null
	app_modal_actions = null
	invite_content_box = null
	referanslar_popup = false
	if run_action and action.is_valid():
		action.call()
	elif dismiss_action.is_valid():
		dismiss_action.call()

# ---------- UID ----------
func get_current_uid() -> String:
	var path := "user://uid.txt"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var uid := f.get_as_text().strip_edges()
		f.close()
		return uid
	return ""

# ---------- USER DATA ----------
func load_user_data(uid: String) -> void:
	# ÇEVİRİ DÜZELTİLDİ
	puan_label.text = tr("home_points_loading")
	mining_button.disabled = true
	mining_button.text = tr("home_loading")

	var user_doc_result = await Global.get_user_doc(uid)
	if user_doc_result is Dictionary and user_doc_result.has("fields"):
		user_data = user_doc_result["fields"]
		Global.sync_point_entitlements(user_data)
		if Global.is_ad_free_user():
			_hide_banner()
			scroll_container.offset_bottom = 0
			_apply_home_responsive_layout()
		# Ana CTA'yı açmak için ölçüm/token ağ çağrılarını bekletme. Yavaş ağda
		# yeni kullanıcı günlük ödül butonunu saniyelerce kullanamıyordu.
		if not _engagement_synced_this_session:
			_engagement_synced_this_session = true
			call_deferred("_sync_engagement_in_background", uid, user_data.duplicate(true))
		var username = String(user_data.get("email", {}).get("stringValue", ""))
		var display := CandarUI.display_name_from_email(username)
		if display == "":
			display = username
		welcome_label.text = tr("home_welcome_user").replace("%s", display)
		
		await update_kazim_orani_ve_ui()
		_update_mining_button()
		await _refresh_rewarded_button_state()
		var tutorial_shown := await _check_and_show_tutorial()
		if not tutorial_shown:
			_maybe_show_first_session_growth_modal()
	else:
		welcome_label.text = tr("home_welcome_load_failed")
		puan_label.text = tr("home_points_load_failed")
		mining_button.visible = true
		mining_button.disabled = true
		mining_button.text = tr("home_mining_button_default")
		_show_app_modal(
			_ui_text("Bağlantı kurulamadı", "Connection failed"),
			_ui_text("Hesap bilgilerin yüklenemedi. İnternet bağlantını kontrol edip tekrar dene.", "Your account could not be loaded. Check your connection and try again."),
			_ui_text("Tekrar dene", "Try again"),
			func(): load_user_data(uid)
		)
		push_error("Kullanıcı verisi yüklenemedi")

func _sync_engagement_in_background(uid: String, fields: Dictionary) -> void:
	var engagement_result := await Global.sync_user_engagement_metadata(uid, fields)
	if engagement_result.is_empty() or not bool(engagement_result[0]):
		push_warning("[HOME] Engagement metadata sync failed: %s" % engagement_result)
	var push_result := await Global.sync_native_push_token_if_available()
	if push_result.is_empty() or not bool(push_result[0]):
		# Token henüz oluşmadığında bu normaldir; sonraki uygulama açılışında
		# yeniden denenir ve ana kullanıcı akışını etkilemez.
		print("[HOME] Push token sync deferred: ", push_result)

# ---------- CIKIS ----------
func _on_logout_button_pressed():
	try_show_interstitial_ad(func():
		await Global.logout()
		get_tree().change_scene_to_file("res://onboarding.tscn")
	)
# ---------- MINING BUTONU DURUM ----------
func _update_mining_button():
	if not user_data.has("lastMiningStart") or int(user_data["lastMiningStart"]["integerValue"]) == 0:
		_set_mining_ready()
		return

	var last_time := int(user_data["lastMiningStart"]["integerValue"])
	var now := int(Time.get_unix_time_from_system())
	var kalan := mining_interval_seconds - (now - last_time)

	if kalan <= 0:
		_set_mining_ready()
	else:
		mining_button.visible = false
		if countdown_card: countdown_card.visible = true
		_set_rewarded_button_idle()
		_start_mining_timer(kalan)

func _set_mining_ready() -> void:
	home_reward_ready = true
	mining_button.visible = true
	mining_button.disabled = false
	mining_button.text = tr("home_mining_button_default")
	if countdown_card: countdown_card.visible = false
	_set_rewarded_button_idle()
	if _is_mobile() and not Global.is_ad_free_user():
		Global.ads_preload_interstitial()
	mining_timer_stop_and_free()
	_update_growth_panels()

@warning_ignore("unused_parameter")
func _start_mining_timer(kalan: int):
	mining_timer_stop_and_free()
	mining_timer = Timer.new()
	mining_timer.wait_time = 1.0
	mining_timer.one_shot = false
	add_child(mining_timer)
	mining_timer.timeout.connect(func():
		var last_time := int(user_data["lastMiningStart"]["integerValue"])
		var now := int(Time.get_unix_time_from_system())
		var kalan2 := mining_interval_seconds - (now - last_time)
		if kalan2 <= 0:
			_set_mining_ready()
		else:
			@warning_ignore("integer_division")
			var saat := kalan2 / 3600
			@warning_ignore("integer_division")
			var dakika := (kalan2 % 3600) / 60
			var saniye := kalan2 % 60
			if countdown_label:
				# ÇEVİRİ DÜZELTİLDİ
				countdown_label.text = tr("home_countdown") % [saat, dakika, saniye]
	)
	mining_timer.start()

func mining_timer_stop_and_free() -> void:
	if mining_timer and is_instance_valid(mining_timer):
		mining_timer.stop()
		mining_timer.queue_free()
		mining_timer = null

# ---------- MINING ISLEMI ----------
func _on_mining_button_pressed() -> void:
	if mining_in_progress: return
	Global.analytics_event("daily_reward_tap", {"screen": "home"})
	var streak_before := _get_daily_streak()

	# Rate limiting kontrolü
	if not Global.check_rate_limit("mining", current_user_id):
		var remaining: int = Global.get_rate_limit_remaining("mining", current_user_id)
		puan_label.text = _ui_text("Günlük limit aşıldı. Kalan: %d", "Daily limit exceeded. Remaining: %d") % remaining
		return

	mining_in_progress = true
	mining_button.disabled = true
	mining_button.text = tr("home_mining_button_doing")
	if countdown_card: countdown_card.visible = false

	var kazim_result: Array = await Global.kazim_yap()
	mining_in_progress = false

	if kazim_result.size() > 0 and bool(kazim_result[0]):
		var reward_value := 1.0
		var shield_used := false
		var shield_earned := false
		var referral_reward_qualified := false
		var referral_reward_points := 0
		if kazim_result.size() > 1:
			var reward_payload = kazim_result[1]
			if typeof(reward_payload) == TYPE_DICTIONARY:
				reward_value = float(reward_payload.get("reward", reward_payload.get("rate", 1.0)))
				shield_used = bool(reward_payload.get("streakShieldUsed", false))
				shield_earned = bool(reward_payload.get("streakShieldEarned", false))
				referral_reward_qualified = bool(reward_payload.get("referralRewardQualified", false))
				referral_reward_points = int(reward_payload.get("referralRewardPoints", 0))
			elif typeof(reward_payload) in [TYPE_FLOAT, TYPE_INT]:
				reward_value = float(reward_payload)
		Global.analytics_event("earn_virtual_currency", {
			"virtual_currency_name": "Candar",
			"value": reward_value,
			"screen": "home"
		})
		_mark_activation_first_task_complete()
		if referral_reward_qualified:
			Global.analytics_event("referral_reward_qualified", {
				"screen": "home",
				"reward_points": referral_reward_points
			})
		# Achievement kontrolü
		var ach_result: Array = await Global.check_and_unlock_achievements(current_user_id)
		var unlocked_achievements: Array = []
		if ach_result[0] and ach_result[1].size() > 0:
			unlocked_achievements = ach_result[1]
		
		# Activity log
		await Global.log_activity("mining", {"points": reward_value})
		
		# Widget güncelle
		await Global.update_widget()
		
		await load_user_data(current_user_id)
		if shield_used:
			Global.analytics_event("streak_shield_used", {"screen": "home"})
		if shield_earned:
			Global.analytics_event("streak_shield_earned", {"screen": "home"})
		var streak_after := _get_daily_streak()
		var shareable_streak := _is_shareable_streak_milestone(streak_before, streak_after)
		var daily_ad_shown := false
		if _is_mobile() and not Global.is_ad_free_user():
			# Rewarded reklam yalnız kullanıcının açıkça "reklam boost" aksiyonuna
			# basmasıyla gösterilir. Günlük ödülün ardından otomatik rewarded açmak
			# kullanıcı beklentisini ve ödüllü reklam politikasını ihlal eder.
			Global.ads_load_rewarded()
			_set_rewarded_button_idle()
			# Başarılı günlük kazımda rastgele seçim veya reklam aralığı uygulanmaz.
			# Hazır değilse kısa süre yüklenmesini bekle; reklam yoksa ödülü engelleme.
			daily_ad_shown = await Global.ads_show_interstitial_when_ready(4.0)
			Global.analytics_event("daily_reward_ad_result", {"screen": "home", "shown": daily_ad_shown})
		_show_growth_celebration(unlocked_achievements, shield_used, shield_earned, streak_before, streak_after)
		# iOS mağaza değerlendirme penceresi tam ekran reklamla çakışmasın.
		if not shareable_streak and not daily_ad_shown:
			Global.maybe_request_store_review("daily_reward")
		return

	var error_msg := (str(kazim_result[1]) if kazim_result.size() > 1 else "Error")
	# Sunucu günlük ödülün gerçek 24 saat kuralını zaten atomik uygular.
	# Geçici ağ hatasının istemcide 24 saatlik sahte kilide dönüşmesini önle.
	Global.reset_rate_limit("mining", current_user_id)
	Global.analytics_event("daily_reward_error", {"screen": "home", "message": error_msg.substr(0, 96)})
	var friendly_error := _friendly_home_error(error_msg)
	puan_label.text = tr("home_points_error")
	mining_button.disabled = false
	mining_button.text = tr("home_mining_button_default")
	_show_app_modal(_ui_text("Ödül alınamadı", "Reward unavailable"), friendly_error)
	push_error("Kazım hatası: %s" % error_msg)

func _show_achievement_popup(unlocked_achievements: Array):
	if unlocked_achievements.is_empty():
		return

	var text := ""
	for ach in unlocked_achievements:
		text += "🏆 " + tr(ach["name"]) + " (+%d XP)\n" % ach["xp"]

	_show_app_modal(tr("achievement_unlocked_title"), text.strip_edges())

func _is_shareable_streak_milestone(previous_streak: int, current_streak: int) -> bool:
	return current_streak > previous_streak and current_streak in [3, 7, 30]

func _show_growth_celebration(unlocked_achievements: Array, shield_used: bool, shield_earned: bool, previous_streak: int, current_streak: int) -> void:
	var lines: PackedStringArray = []
	if shield_used:
		lines.append(_ui_text(
			"🛡️ Bir günü kaçırdın ama Seri Kalkanın serini korudu.",
			"🛡️ You missed one day, but your Streak Shield protected the streak."
		))
	if shield_earned:
		lines.append(_ui_text(
			"🛡️ 7 günlük yolculuk tamamlandı: 1 Seri Kalkanı kazandın.",
			"🛡️ 7-day journey complete: you earned 1 Streak Shield."
		))
	for achievement in unlocked_achievements:
		lines.append("🏆 %s (+%d XP)" % [tr(achievement["name"]), int(achievement["xp"])])
	var shareable_streak := _is_shareable_streak_milestone(previous_streak, current_streak)
	if shareable_streak:
		lines.append(_ui_text(
			"🔥 %d günlük seri tamamlandı. Arkadaşını davet edip birlikte devam et.",
			"🔥 %d-day streak complete. Invite a friend and keep going together."
		) % current_streak)
	if lines.is_empty():
		return
	if shareable_streak:
		_show_app_modal(
			_ui_text("Serin büyüyor", "Your streak is growing"),
			"\n\n".join(lines),
			_ui_text("Seriyi Paylaş", "Share Streak"),
			_share_streak_milestone.bind(current_streak)
		)
	else:
		_show_app_modal(
			_ui_text("İlerleme ödülü", "Progress reward"),
			"\n\n".join(lines)
		)

func _share_streak_milestone(streak: int) -> void:
	var code := _get_field_string(user_data, "referralCode")
	var invite_link := Global.APP_DOWNLOAD_LINK
	if code != "":
		invite_link = _referral_download_link(code)
	var share_text := _ui_text(
		"Candar'da %d günlük serimi tamamladım 🔥 Sen de katıl; birlikte devam edelim.",
		"I completed a %d-day streak on Candar 🔥 Join me and let's keep going together."
	) % streak
	if code != "":
		share_text += "\n" + _ui_text("Davet kodum: %s", "My invite code: %s") % code
	var native_opened := Global.share_invite_text(
		share_text,
		_ui_text("Candar serimi paylaş", "Share my Candar streak"),
		invite_link
	)
	Global.analytics_event("streak_share_opened", {
		"screen": "home",
		"streak": streak,
		"native": native_opened,
		"has_referral": code != ""
	})

func _friendly_home_error(error_msg: String) -> String:
	var msg := error_msg.strip_edges()
	var lower := msg.to_lower()
	if lower.find("permission_denied") != -1 or lower.find("insufficient permissions") != -1 or lower.find("permission") != -1 or lower.find("403") != -1:
		return _ui_text(
			"Günlük ödül servisi izin hatası döndürdü. Oturumu yenileyip tekrar dene; sorun sürerse sunucu kuralını güncellemem gerekiyor.",
			"The daily reward service returned a permission error. Sign in again and retry; if it continues, the server rule needs an update."
		)
	if msg.begins_with("{") or msg.length() > 160:
		return _ui_text("Günlük ödül alınamadı. Lütfen biraz sonra tekrar deneyin.", "Daily reward could not be claimed. Please try again later.")
	return msg

func _format_rewarded_wait_time(seconds: int) -> String:
	var remaining: int = maxi(0, seconds)
	var minutes := int(ceil(float(remaining) / 60.0))
	if minutes >= 60:
		var hours := int(ceil(float(minutes) / 60.0))
		return _ui_text("%d saat sonra tekrar dene.", "Try again in %d hours.") % hours
	return _ui_text("%d dakika sonra tekrar dene.", "Try again in %d minutes.") % max(1, minutes)

func _rewarded_boost_error_message(payload: Variant) -> String:
	if typeof(payload) != TYPE_DICTIONARY:
		return _ui_text("Oran sunucuya yazılamadı. Lütfen tekrar dene.", "The rate could not be saved. Please try again.")

	var data: Dictionary = payload
	var error_code := str(data.get("error", ""))
	match error_code:
		"rewarded_boost_cooldown":
			return _ui_text(
				"Reklam boost'u için kısa bir bekleme süresi var. %s",
				"There is a short wait before the next ad boost. %s"
			) % _format_rewarded_wait_time(int(data.get("remaining_seconds", 0)))
		"rewarded_boost_daily_limit":
			return _ui_text(
				"Bugünkü 2 reklam hakkını kullandın. Yarın tekrar deneyebilirsin.",
				"You used today's 2 ad attempts. You can try again tomorrow."
			)
		"rewarded_boost_daily_attempt_limit":
			return _ui_text(
				"24 saat içinde 2 reklam hakkını kullandın. %s",
				"You used 2 ad attempts within 24 hours. %s"
			) % _format_rewarded_wait_time(int(data.get("remaining_seconds", 0)))
		"rewarded_boost_max_reached":
			return _ui_text(
				"Reklam boost'un maksimum seviyeye ulaştı.",
				"Your ad boost has reached the maximum level."
			)
		"rewarded_boost_attempt_service_unavailable":
			return _ui_text(
				"Reklam hakkın doğrulanamadı. Hakkının boşa gitmemesi için reklam açılmadı; biraz sonra tekrar dene.",
				"Your ad attempt could not be verified. The ad was not opened so your attempt would not be wasted; please try again shortly."
			)
	return _ui_text("Oran sunucuya yazılamadı. Lütfen tekrar dene.", "The rate could not be saved. Please try again.")

func _on_rewarded_button_pressed() -> void:
	# The Candar Center invokes this without the hidden home button, so disabling
	# that button alone does not prevent duplicate reservations and ad shows.
	if _rewarded_flow_in_progress:
		return
	_rewarded_flow_in_progress = true
	await _run_rewarded_boost_flow()
	_rewarded_flow_in_progress = false
	_set_rewarded_button_idle()
	await _refresh_rewarded_button_state()

func _run_rewarded_boost_flow() -> void:
	if not REWARDED_BOOST_BUTTON_ENABLED:
		if rewarded_button:
			rewarded_button.visible = false
			rewarded_button.disabled = true
		return
	Global.analytics_event("rewarded_boost_tap", {"screen": "home"})
	if rewarded_button:
		rewarded_button.visible = REWARDED_BOOST_HOME_VISIBLE
		rewarded_button.disabled = true
		rewarded_button.text = _ui_text("Reklam hazırlanıyor...", "Preparing ad...")

	if not _is_mobile() or Global.is_user_premium():
		_set_rewarded_button_idle()
		_show_app_modal(
			_ui_text("Reklam kullanılamıyor", "Ad unavailable"),
			_ui_text(
				"Reklam boost'u sadece mobilde reklam tamamlandığında uygulanır.",
				"Ad boost is applied only on mobile after the rewarded ad is completed."
			)
		)
		return

	var boost_status: Dictionary = await Global.get_rewarded_boost_status(current_user_id)
	if not bool(boost_status.get("can_apply", true)):
		_set_rewarded_button_blocked(boost_status)
		Global.analytics_event("rewarded_boost_blocked_before_ad", {
			"screen": "home",
			"reason": str(boost_status.get("error", ""))
		})
		_show_app_modal(
			_ui_text("Reklam boost beklemede", "Ad boost waiting"),
			_rewarded_boost_error_message(boost_status)
		)
		return

	Global.ads_load_rewarded()
	var started_ms := Time.get_ticks_msec()
	while not Global.ads_has_rewarded_ready() and Time.get_ticks_msec() - started_ms < 6000:
		await get_tree().create_timer(0.1).timeout
	if not Global.ads_has_rewarded_ready():
		_set_rewarded_button_idle()
		Global.analytics_event("rewarded_boost_ad_not_ready", {"screen": "home"})
		_show_app_modal(
			_ui_text("Reklam hazır değil", "Ad not ready"),
			_ui_text(
				"Reklam şu an hazır değil. Biraz sonra tekrar dene.",
				"The rewarded ad is not ready right now. Please try again shortly."
			)
		)
		return

	var attempt_result: Dictionary = await Global.reserve_rewarded_boost_attempt()
	if not bool(attempt_result.get("ok", false)):
		var attempt_error := str(attempt_result.get("error", ""))
		if Global.is_rewarded_boost_limit_error(attempt_error):
			_set_rewarded_button_blocked(attempt_result)
		else:
			_set_rewarded_button_idle()
		Global.analytics_event("rewarded_boost_blocked_before_ad", {
			"screen": "home",
			"reason": attempt_error
		})
		_show_app_modal(
			_ui_text("Reklam şu an kullanılamıyor", "Ad unavailable"),
			_rewarded_boost_error_message(attempt_result)
		)
		return

	var attempt_at := int(attempt_result.get("attempt_at", 0))
	var completed := await _show_rewarded_and_wait(attempt_at)
	if not completed:
		var ad_result: Dictionary = Global.ads_get_last_rewarded_result()
		Global.analytics_event("rewarded_boost_ad_not_completed", {
			"screen": "home",
			"reason": str(ad_result.get("reason", "unknown")),
			"duration_ms": int(ad_result.get("duration_ms", 0))
		})
		await _refresh_rewarded_button_state()
		_show_app_modal(
			_ui_text("Reklam tamamlanmadı", "Ad not completed"),
			_ui_text(
				"Oran artışı için reklamı tamamlaman gerekiyor. Oran eklenmedi.",
				"You need to complete the rewarded ad for the rate boost. No rate was added."
			)
		)
		return

	if rewarded_button:
		rewarded_button.text = _ui_text("Oran ekleniyor...", "Applying rate...")

	var result: Array = await Global.activate_rewarded_boost(current_user_id, attempt_at)
	if result.size() > 0 and bool(result[0]):
		var payload: Variant = result[1]
		var rewarded_multiplier := 1.0
		var total_rate := Global.mining_rate
		if typeof(payload) == TYPE_DICTIONARY:
			rewarded_multiplier = float(payload.get("rewarded_multiplier", 1.0))
			total_rate = float(payload.get("total_rate", total_rate))
		elif typeof(payload) in [TYPE_FLOAT, TYPE_INT]:
			rewarded_multiplier = float(payload)
		Global.analytics_event("rewarded_boost_applied", {"screen": "home", "rewarded_multiplier": rewarded_multiplier, "total_rate": total_rate})
		var boost_percent := int(round((rewarded_multiplier - 1.0) * 100.0))
		var latest_doc: Dictionary = await Global.get_user_doc(current_user_id)
		if latest_doc.has("fields") and typeof(latest_doc["fields"]) == TYPE_DICTIONARY:
			user_data = latest_doc["fields"]
		await update_kazim_orani_ve_ui()

		_set_rewarded_button_idle()
		await _refresh_rewarded_button_state()
		_show_app_modal(
			_ui_text("🚀 Oran Artışı Aktif!", "🚀 Rate Boost Active!"),
			_ui_text(
				"Reklam boost'un %%%d seviyesine çıktı.\nYeni toplam oranın: x%.2f",
				"Your ad boost reached %%%d.\nNew total rate: x%.2f"
			) % [boost_percent, Global.mining_rate]
		)
	else:
		_set_rewarded_button_idle()
		Global.analytics_event("rewarded_boost_apply_failed", {"screen": "home"})
		var payload: Variant = result[1] if result.size() > 1 else {}
		_show_app_modal(
			_ui_text("Boost uygulanamadı", "Boost could not be applied"),
			_rewarded_boost_error_message(payload)
		)

# ---------- GERÇEK TOPLULUK TAKIMLARI ----------
func _open_real_team_center() -> void:
	var state: Dictionary = await Global.get_my_team()
	if not bool(state.get("ok", false)):
		_show_app_modal(_ui_text("Takım sunucusu", "Team service"),
			str(state.get("error", _ui_text("Takım bilgisi alınamadı.", "Team data unavailable."))))
		return

	var dialog := AcceptDialog.new()
	dialog.title = _ui_text("Candar Takım Merkezi", "Candar Team Center")
	dialog.get_ok_button().text = _ui_text("Kapat", "Close")
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.custom_minimum_size = Vector2(280, 0)
	dialog.add_child(content)

	if bool(state.get("inTeam", false)):
		var team: Dictionary = state.get("team", {})
		var code := str(team.get("code", ""))
		var headline := Label.new()
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		headline.text = "%s\n%s: %s\n%s: %d/%d" % [
			str(team.get("name", "")),
			_ui_text("Takım kodu", "Team code"), code,
			_ui_text("Üyeler", "Members"), int(team.get("memberCount", 0)),
			int(team.get("maxMembers", 30))
		]
		content.add_child(headline)
		if real_team_label:
			real_team_label.text = str(team.get("name", ""))
		var copy_btn := Button.new()
		copy_btn.text = _ui_text("Takım Kodunu Kopyala", "Copy Team Code")
		copy_btn.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(code)
			_show_app_modal(_ui_text("Kopyalandı", "Copied"), code)
		)
		content.add_child(copy_btn)
		var leave_btn := Button.new()
		leave_btn.text = _ui_text("Takımdan Ayrıl", "Leave Team")
		leave_btn.pressed.connect(_leave_real_team_pressed.bind(dialog))
		content.add_child(leave_btn)
	else:
		var name_field := LineEdit.new()
		name_field.placeholder_text = _ui_text("Yeni takım adı (3–40 karakter)", "New team name (3–40 characters)")
		content.add_child(name_field)
		var create_btn := Button.new()
		create_btn.text = _ui_text("Yeni Takım Kur", "Create a Team")
		create_btn.pressed.connect(_create_real_team_pressed.bind(name_field, dialog))
		content.add_child(create_btn)
		var code_field := LineEdit.new()
		code_field.placeholder_text = _ui_text("Katılım kodu (T ile başlar)", "Invite code (starts with T)")
		code_field.max_length = 16
		content.add_child(code_field)
		var join_btn := Button.new()
		join_btn.text = _ui_text("Kodla Takıma Katıl", "Join with Code")
		join_btn.pressed.connect(_join_real_team_pressed.bind(code_field, dialog))
		content.add_child(join_btn)
		if real_team_label:
			real_team_label.text = _ui_text("Henüz bir topluluk takımına katılmadın.", "You have not joined a community team yet.")

	var leaderboard_btn := Button.new()
	leaderboard_btn.text = _ui_text("Takım Sıralamasını Gör", "View Team Leaderboard")
	leaderboard_btn.pressed.connect(_open_real_team_leaderboard)
	content.add_child(leaderboard_btn)
	dialog.popup_centered_ratio(0.85)

func _create_real_team_pressed(field: LineEdit, dialog: AcceptDialog) -> void:
	var team_name := field.text.strip_edges()
	if team_name.length() < 3:
		_show_app_modal(_ui_text("Takım adı çok kısa", "Team name too short"),
			_ui_text("En az 3 karakter gir.", "Please enter at least 3 characters."))
		return
	dialog.hide()
	var response: Array = await Global.create_team(team_name)
	_show_real_team_result(response,
		_ui_text("Takım oluşturuldu", "Team created"),
		_ui_text("Yeni takımın kuruldu. Kodu arkadaşlarınla paylaş.", "Your team is ready. Share the code with friends."))

func _join_real_team_pressed(field: LineEdit, dialog: AcceptDialog) -> void:
	var code := field.text.strip_edges().to_upper()
	if code == "":
		_show_app_modal(_ui_text("Kod gerekli", "Code required"),
			_ui_text("Katılım kodunu gir.", "Enter an invite code."))
		return
	dialog.hide()
	var response: Array = await Global.join_team(code)
	_show_real_team_result(response,
		_ui_text("Takıma katıldın", "Joined team"),
		_ui_text("Artık bu takımın bir üyesisin.", "You are now a member of this team."))

func _leave_real_team_pressed(dialog: AcceptDialog) -> void:
	dialog.hide()
	var response: Array = await Global.leave_team()
	_show_real_team_result(response,
		_ui_text("Takımdan ayrıldın", "Left team"),
		_ui_text("İstediğinde başka bir takıma katılabilirsin.", "You may join another team whenever you like."))

func _show_real_team_result(response: Array, title_ok: String, message_ok: String) -> void:
	var success := response.size() >= 1 and bool(response[0])
	if success:
		if real_team_label:
			real_team_label.text = _ui_text("Takım bilgini güncellemek için merkeze gir.", "Open the center to refresh team status.")
		_show_app_modal(title_ok, message_ok)
	else:
		var payload: Variant = response[1] if response.size() > 1 else {}
		var message := str(payload.get("error", "Team action failed")) if typeof(payload) == TYPE_DICTIONARY else str(payload)
		_show_app_modal(_ui_text("Takım işlemi başarısız", "Team action failed"), message)

func _open_real_team_leaderboard() -> void:
	var teams: Array = await Global.get_team_leaderboard(10)
	if teams.is_empty():
		_show_app_modal(_ui_text("Takım sıralaması", "Team rankings"),
			_ui_text("Henüz listelenecek takım yok.", "No teams to display yet."))
		return
	var lines: PackedStringArray = []
	for i in range(teams.size()):
		var team: Dictionary = teams[i]
		lines.append("%d. %s — %d/30" % [i + 1, str(team.get("name", "")), int(team.get("memberCount", 0))])
	_show_app_modal(_ui_text("En Aktif Takımlar", "Team Leaderboard"), "\n".join(lines))

# ---------- REFERANSLAR ----------
func _on_referanslar_button_pressed():
	Global.analytics_event("open_referrals", {"screen": "home"})
	var my_ref_code: String = str(user_data.get("referralCode", {}).get("stringValue", ""))
	if my_ref_code.is_empty():
		_show_app_modal(tr("home_refs_popup_title"), tr("home_refs_no_code"))
		return
	_show_referral_invite_modal(my_ref_code)

	var result: Array = await Global.get_users_by_referral(my_ref_code)
	if referanslar_popup and invite_content_box and is_instance_valid(invite_content_box):
		_render_referral_invite_content(my_ref_code, result, false)

func _referral_mission_summary(count: int) -> String:
	return _ui_text(
		"Hedefler: %d/3 Starter · %d/10 Rozet · %d/25 Premium hedefi",
		"Missions: %d/3 Starter · %d/10 Badge · %d/25 Premium target"
	) % [min(count, 3), min(count, 10), min(count, 25)]

func _team_slot_text(count: int) -> String:
	var slots: PackedStringArray = []
	for i in range(5):
		slots.append("●" if i < mini(count, 5) else "○")
	return " ".join(slots)

func _next_referral_target_text(count: int) -> String:
	var targets := [1, 3, 10, 25]
	for target in targets:
		if count < target:
			var next_boost := 1.0 + float(count + 1) * 0.05
			return tr("team_next_target") % [next_boost, count, target, target - count]
	return tr("team_all_complete")

func _copy_referral_code(code: String) -> void:
	if code == "":
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code)

func _referral_download_link(code: String) -> String:
	return "%s?ref=%s&src=app_invite&utm_source=app&utm_medium=referral&utm_campaign=member_invite" % [
		Global.APP_DOWNLOAD_LINK,
		code.uri_encode()
	]

func _share_referral_invite(code: String) -> void:
	var invite_link := _referral_download_link(code)
	var invite_text := tr("share_text") % code
	Global.analytics_event("share_referral_tap", {"screen": "home", "method": "native_share"})
	# Global fallback'ta metin ve takip parametreli bağlantı birlikte panoya
	# yazılır; burada tekrar yalnız metni yazmak indirme bağlantısını siliyordu.
	Global.share_invite_text(invite_text, tr("share_title"), invite_link)

func _invite_next_target(count: int) -> int:
	for target in [1, 3, 10, 25]:
		if count < target:
			return target
	return 25

func _make_invite_metric(title: String, value: String, accent: Color) -> PanelContainer:
	var card := CandarUI.make_card(accent, 16, Color(0.08, 0.11, 0.18, 0.96), 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 24)
	value_label.add_theme_color_override("font_color", accent)
	box.add_child(value_label)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color("#cbd5e1"))
	box.add_child(title_label)
	return card

func _show_referral_invite_modal(code: String) -> void:
	_show_app_modal(tr("invite_button"), "")
	referanslar_popup = true
	if app_modal_panel:
		app_modal_panel.custom_minimum_size.x = minf(get_viewport_rect().size.x - 28.0, 680.0)
	if app_modal_body and is_instance_valid(app_modal_body):
		var body_scroll := app_modal_body.get_parent() as ScrollContainer
		body_scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y * 0.50, 440.0)
		body_scroll.remove_child(app_modal_body)
		app_modal_body.queue_free()
		app_modal_body = null
		invite_content_box = VBoxContainer.new()
		invite_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		invite_content_box.add_theme_constant_override("separation", 12)
		body_scroll.add_child(invite_content_box)

	if app_modal_actions and is_instance_valid(app_modal_actions):
		for child in app_modal_actions.get_children():
			app_modal_actions.remove_child(child)
			child.queue_free()
		app_modal_actions.columns = 1

		var share_button := CandarUI.make_primary_button(
			"↗ " + tr("invite_button"),
			58
		)
		share_button.pressed.connect(_share_referral_invite.bind(code))
		app_modal_actions.add_child(share_button)

		var copy_button := CandarUI.make_secondary_button(
			"⧉ " + tr("team_copy_code"),
			52
		)
		copy_button.pressed.connect(func():
			_copy_referral_code(code)
			copy_button.text = "✓ " + tr("team_invite_ready")
			Global.analytics_event("share_referral_tap", {"screen": "home", "method": "copy_code"})
		)
		app_modal_actions.add_child(copy_button)

		var close_button := _mk_card_action_button(tr("common_close"))
		close_button.custom_minimum_size.y = 48
		close_button.pressed.connect(func(): _close_app_modal(false))
		app_modal_actions.add_child(close_button)

	_render_referral_invite_content(code, [], true)

func _render_referral_invite_content(code: String, referrals: Array, loading: bool) -> void:
	if invite_content_box == null or not is_instance_valid(invite_content_box):
		return
	for child in invite_content_box.get_children():
		invite_content_box.remove_child(child)
		child.queue_free()

	var hero := CandarUI.make_card(Color("#38bdf8"), 20, Color("#101827"), 16)
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 7)
	hero.add_child(hero_box)
	var hero_icon := Label.new()
	hero_icon.text = "👥"
	hero_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_icon.add_theme_font_size_override("font_size", 38)
	hero_box.add_child(hero_icon)
	var hero_title := Label.new()
	hero_title.text = tr("share_title")
	hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_title.add_theme_font_size_override("font_size", 20)
	hero_title.add_theme_color_override("font_color", Color("#f8fafc"))
	hero_box.add_child(hero_title)
	var hero_caption := Label.new()
	hero_caption.text = tr("invite_auto_attribution")
	hero_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_caption.add_theme_font_size_override("font_size", 15)
	hero_caption.add_theme_color_override("font_color", Color("#94a3b8"))
	hero_box.add_child(hero_caption)
	invite_content_box.add_child(hero)

	var code_card := CandarUI.make_card(Color("#f59e0b"), 18, Color("#1b2436"), 15)
	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 4)
	code_card.add_child(code_box)
	var code_caption := Label.new()
	code_caption.text = tr("team_invite_ready").to_upper()
	code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_caption.add_theme_font_size_override("font_size", 13)
	code_caption.add_theme_color_override("font_color", Color("#94a3b8"))
	code_box.add_child(code_caption)
	var code_label := Label.new()
	code_label.text = code
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 32)
	code_label.add_theme_color_override("font_color", Color("#fbbf24"))
	code_box.add_child(code_label)
	var code_hint := Label.new()
	code_hint.text = tr("invite_code_auto_fill")
	code_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_hint.add_theme_font_size_override("font_size", 14)
	code_hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	code_box.add_child(code_hint)
	invite_content_box.add_child(code_card)

	if loading:
		var loading_label := Label.new()
		loading_label.text = tr("loading_referrals")
		loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_label.add_theme_font_size_override("font_size", 17)
		loading_label.add_theme_color_override("font_color", Color("#94a3b8"))
		invite_content_box.add_child(loading_label)
		return

	var count := referrals.size()
	var next_target := _invite_next_target(count)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	metrics.add_child(_make_invite_metric(
		tr("profile_referrals"),
		str(count),
		Color("#38bdf8")
	))
	metrics.add_child(_make_invite_metric(
		tr("home_rate_short"),
		"x%.2f" % (1.0 + float(count) * 0.05),
		Color("#34d399")
	))
	invite_content_box.add_child(metrics)

	var progress_caption := Label.new()
	progress_caption.text = tr("team_next_target") % [
		1.0 + float(count + 1) * 0.05,
		min(count, next_target),
		next_target,
		max(0, next_target - count)
	]
	progress_caption.add_theme_font_size_override("font_size", 15)
	progress_caption.add_theme_color_override("font_color", Color("#cbd5e1"))
	invite_content_box.add_child(progress_caption)
	var progress := ProgressBar.new()
	progress.min_value = 0
	progress.max_value = max(1, next_target)
	progress.value = min(count, next_target)
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	var progress_bg := StyleBoxFlat.new()
	progress_bg.bg_color = Color("#1b2436")
	progress_bg.set_corner_radius_all(999)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color("#fbbf24")
	progress_fill.set_corner_radius_all(999)
	progress.add_theme_stylebox_override("background", progress_bg)
	progress.add_theme_stylebox_override("fill", progress_fill)
	invite_content_box.add_child(progress)

	var team_title := Label.new()
	team_title.text = tr("team_title")
	team_title.add_theme_font_size_override("font_size", 19)
	team_title.add_theme_color_override("font_color", Color("#f8fafc"))
	invite_content_box.add_child(team_title)

	if referrals.is_empty():
		var empty_label := Label.new()
		empty_label.text = tr("home_refs_empty")
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color("#94a3b8"))
		invite_content_box.add_child(empty_label)
	else:
		var shown := mini(referrals.size(), 8)
		for i in range(shown):
			var member: Variant = referrals[i]
			var member_email := _ui_text("Yeni Candar üyesi", "New Candar member")
			if typeof(member) == TYPE_DICTIONARY:
				var member_fields: Dictionary = (member as Dictionary).get("fields", {})
				var raw_email := _get_field_string(member_fields, "email")
				if raw_email != "":
					member_email = raw_email if raw_email.contains("***") else _mask_email(raw_email)
			var member_row := PanelContainer.new()
			var member_style := StyleBoxFlat.new()
			member_style.bg_color = Color("#151f30")
			member_style.set_corner_radius_all(13)
			member_style.content_margin_left = 12
			member_style.content_margin_right = 12
			member_style.content_margin_top = 9
			member_style.content_margin_bottom = 9
			member_row.add_theme_stylebox_override("panel", member_style)
			var member_label := Label.new()
			member_label.text = "✓  " + member_email
			member_label.add_theme_font_size_override("font_size", 15)
			member_label.add_theme_color_override("font_color", Color("#dbeafe"))
			member_row.add_child(member_label)
			invite_content_box.add_child(member_row)
		if referrals.size() > shown:
			var more_label := Label.new()
			more_label.text = _ui_text(
				"+%d takım üyesi daha",
				"+%d more team members"
			) % (referrals.size() - shown)
			more_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			more_label.add_theme_color_override("font_color", Color("#94a3b8"))
			invite_content_box.add_child(more_label)

func _mask_email(mail: String) -> String:
	var at := mail.find("@")
	if at <= 1:
		return mail
	return mail.substr(0, 2) + "***" + mail.substr(at, mail.length() - at)

# ---------- CANDAR EKOSISTEMI ----------
func _open_ecosystem() -> void:
	Global.analytics_event("ecosystem_open", {"screen": "home"})
	var center_choices: Array = [
		{"text": _ui_text("Candar Ai", "Candar Ai"), "action": Callable(self, "_on_chat_button_pressed")},
		{"text": tr("center_my_team"), "action": Callable(self, "_on_referanslar_button_pressed")},
		{"text": tr("center_roles"), "action": Callable(self, "_open_community_roles")},
		{"text": tr("center_ad_boost"), "action": Callable(self, "_on_rewarded_button_pressed")},
		{"text": tr("center_growth_news"), "action": Callable(self, "_open_growth_news")}
	]
	if POINT_CENTER_ENABLED:
		center_choices.insert(1, {"text": tr("center_points"), "action": Callable(self, "_open_point_center")})
	_show_choice_modal(
		tr("ecosystem_title"),
		tr("ecosystem_body"),
		center_choices
	)

func _open_growth_news() -> void:
	_show_app_modal(
		tr("growth_news_title"),
		tr("growth_news_body_current")
	)

func _open_community_roles() -> void:
	Global.analytics_event("community_roles_open", {"screen": "home"})
	_show_app_modal(
		tr("center_roles"),
		_build_roles_detail()
	)

func _build_roles_detail() -> String:
	var unlocked := _unlocked_achievement_ids()
	var lines: PackedStringArray = []
	var founder := _is_founding_member()
	var streak_master := unlocked.has("7_day_streak") or _get_daily_streak() >= 7
	var network_builder := unlocked.has("first_referral") or home_ref_count >= 1
	var community_leader := unlocked.has("10_referrals") or home_ref_count >= 10
	var roles := [
		{"done": founder, "key": "role_founding_member"},
		{"done": streak_master, "key": "role_streak_master"},
		{"done": network_builder, "key": "role_network_builder"},
		{"done": community_leader, "key": "role_community_pioneer"}
	]
	for role in roles:
		lines.append("%s %s" % [
			"🏅" if bool(role["done"]) else "○",
			tr(str(role["key"]))
		])
	lines.append("")
	lines.append(tr("roles_permanent_note"))
	return "\n".join(lines)

func _open_point_center() -> void:
	Global.analytics_event("point_center_open", {"screen": "home"})
	var ai_credits := _get_field_int(user_data, "aiBonusCredits", 0)
	var profile_gold := _get_field_string(user_data, "profilePrivilege") == "gold"
	var ad_free_active := _timestamp_field_active("pointsAdFreeUntil")
	var point_boost_active := _timestamp_field_active("pointsBoostUntil")
	_show_choice_modal(
		tr("point_center_title"),
		tr("point_center_body") % [
			home_points,
			"✓" if ad_free_active else "○",
			"✓" if point_boost_active else "○",
			"✓" if profile_gold else "○",
			ai_credits
		],
		[
			{"text": tr("point_ad_free_button"), "action": _point_reward_confirm.bind("ad_free_24h", tr("point_ad_free_reward"), 25)},
			{"text": tr("point_boost_button"), "action": _point_reward_confirm.bind("boost_24h", tr("point_boost_reward"), 40)},
			{"text": tr("point_gold_button"), "action": _point_reward_confirm.bind("profile_gold", tr("point_gold_reward"), 75)},
			{"text": tr("point_ai_button"), "action": _point_reward_confirm.bind("ai_5", tr("point_ai_reward"), 30)}
		]
	)

func _point_reward_confirm(reward_id: String, reward_name: String, cost: int) -> void:
	_show_app_modal(
		tr("point_confirm_title"),
		tr("point_confirm_body").replace("%d", str(cost)).replace("%s", reward_name),
		tr("common_confirm"),
		_redeem_point_reward.bind(reward_id)
	)

func _redeem_point_reward(reward_id: String) -> void:
	_show_app_modal(tr("point_processing_title"), tr("point_processing_body"))
	var result: Dictionary = await Global.redeem_point_reward(reward_id)
	if not bool(result.get("ok", false)):
		_show_app_modal(
			tr("point_failed_title"),
			str(result.get("error", tr("common_try_again")))
		)
		return
	Global.analytics_event("point_reward_redeemed", {"screen": "home", "reward_id": reward_id})
	await load_user_data(current_user_id)
	if Global.is_ad_free_user():
		_hide_banner()
		_apply_home_responsive_layout()
	_show_app_modal(
		tr("point_active_title"),
		tr("point_active_body")
	)

# ---------- MINI OYUNLAR ----------
# ---------- TUTORIAL ----------
func _check_and_show_tutorial() -> bool:
	if not Global.should_show_tutorial_for_fields(user_data):
		return false
	Global.start_tutorial()
	_show_tutorial_step()
	return true

func _growth_modal_state_path() -> String:
	return "user://growth_first_session.cfg"

func _maybe_show_first_session_growth_modal() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_growth_modal_state_path())
	if bool(cfg.get_value("home", "shown", false)):
		return
	Global.analytics_event("growth_first_session_modal", {"screen": "home"})

	var title := _ui_text("İlk hedefini seç", "Choose your first goal")
	var body := _ui_text(
		"Sana uygun başlangıcı seç. İlk adımın yalnızca günlük puanını almak; sonra hedefini birlikte büyüteceğiz.",
		"Pick the start that fits you. Your first step is simply collecting today's points; then we'll build toward your goal."
	)
	_show_choice_modal(
		title,
		body,
		[
			{"text": _ui_text("🔥 Seri yap", "🔥 Build a streak"), "action": _select_activation_goal.bind("streak")},
			{"text": _ui_text("⭐ Puan biriktir", "⭐ Earn points"), "action": _select_activation_goal.bind("points")},
			{"text": _ui_text("🤝 Ağını büyüt", "🤝 Grow your network"), "action": _select_activation_goal.bind("network")},
		]
	)

func _select_activation_goal(goal: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_growth_modal_state_path())
	cfg.set_value("home", "shown", true)
	cfg.set_value("home", "shown_at", int(Time.get_unix_time_from_system()))
	cfg.set_value("home", "goal", goal)
	cfg.save(_growth_modal_state_path())
	Global.analytics_event("activation_goal_selected", {"screen": "home", "goal": goal})

	var bodies := {
		"streak": _ui_text("Bugünkü puanını al. Yarın tekrar geldiğinde serinin ikinci gününü tamamlayacaksın.", "Collect today's points. Return tomorrow to complete day two of your streak."),
		"points": _ui_text("İlk günlük puanını şimdi al. Düzenli kazım, puan biriktirmenin temelidir.", "Collect your first daily points now. Consistent mining is the foundation of earning points."),
		"network": _ui_text("Önce ilk günlük puanını al. Ardından profilindeki referans kodunu paylaş; davetin 3 günlük seriyi tamamlayınca ikiniz de 10 puan kazanırsınız.", "Collect your first daily points, then share the referral code in your profile. When your invite completes a 3-day streak, you both earn 10 points."),
	}
	_show_app_modal(
		_ui_text("İlk adım hazır", "Your first step is ready"),
		str(bodies.get(goal, bodies["points"])),
		_ui_text("Günlük puanı al", "Collect points"),
		func(): _on_mining_button_pressed()
	)

func _mark_activation_first_task_complete() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_growth_modal_state_path())
	if bool(cfg.get_value("home", "first_task_complete", false)):
		return
	var goal := str(cfg.get_value("home", "goal", ""))
	if goal == "":
		return
	cfg.set_value("home", "first_task_complete", true)
	cfg.set_value("home", "first_task_completed_at", int(Time.get_unix_time_from_system()))
	cfg.save(_growth_modal_state_path())
	Global.analytics_event("activation_first_task_complete", {"screen": "home", "goal": goal})

func _show_tutorial_step() -> void:
	var step_data: Dictionary = Global.get_current_tutorial_step()
	if step_data.is_empty():
		return

	_show_app_modal(
		tr(step_data["title"]),
		tr(step_data["text"]),
		_ui_text("İleri", "Next"),
		_advance_tutorial_after_modal,
		_dismiss_tutorial_after_modal
	)

func _advance_tutorial_after_modal() -> void:
	Global.advance_tutorial()
	if Global.is_tutorial_completed():
		await Global.mark_tutorial_seen(current_user_id)
		user_data["tutorialSeen"] = {"booleanValue": true}
	else:
		_show_tutorial_step()

func _dismiss_tutorial_after_modal() -> void:
	await Global.mark_tutorial_seen(current_user_id)
	user_data["tutorialSeen"] = {"booleanValue": true}

# ---------- KAZIM ORANI / UI ----------
func update_kazim_orani_ve_ui() -> void:
	var mining = user_data.get("mining", {}).get("mapValue", {})
	var mining_fields = mining.get("fields", {})

	var premium = user_data.get("premium", {}).get("mapValue", {})
	var premium_fields = premium.get("fields", {})
	var premium_active = false
	if user_data.has("isPremium") and user_data["isPremium"].has("booleanValue"):
		premium_active = bool(user_data["isPremium"]["booleanValue"])
	if premium_fields.has("is_active"):
		var v = premium_fields["is_active"]
		if v.has("booleanValue"):
			premium_active = bool(v["booleanValue"])
	Global.market_is_premium = premium_active

	var rate_components: Dictionary = await Global.get_user_mining_rate_components(current_user_id, user_data)
	var active_mult := float(rate_components.get("active_multiplier", 1.0))
	var rewarded_mult := float(rate_components.get("rewarded_multiplier", 1.0))
	var points_boost_mult := float(rate_components.get("points_boost_multiplier", 1.0))
	var ref_count := int(rate_components.get("ref_count", 0))
	var total_rate := float(rate_components.get("total_rate", 1.0))
	Global.mining_rate = total_rate

	var points = _num_field(user_data.get("points", {}), _num_field(mining_fields.get("points", {}), 0.0))

	# ÇEVİRİ DÜZELTİLDİ
	var premium_txt := tr("status_inactive")
	if premium_active:
		premium_txt = tr("status_active")

	if hero_balance_label:
		hero_balance_label.text = "%.2f" % points
	_update_dashboard(points, total_rate, active_mult * points_boost_mult, rewarded_mult, premium_active, ref_count)

func _update_dashboard(points: float, total_rate: float, active_mult: float, rewarded_mult: float, premium_active: bool, ref_count: int) -> void:
	home_points = points
	home_ref_count = ref_count
	home_active_multiplier = active_mult
	home_rewarded_multiplier = rewarded_mult
	home_premium_active = premium_active
	home_reward_ready = _is_daily_reward_ready()
	if hero_balance_label:
		hero_balance_label.text = "%.2f" % points
	CandarUI.set_stat_pill_value(stat_speed_pill, "x%.2f" % total_rate)
	CandarUI.set_stat_pill_value(stat_boost_pill, "x%.2f" % (active_mult * rewarded_mult))
	CandarUI.set_stat_pill_value(stat_ref_pill, str(ref_count))
	_update_growth_panels()

func _update_growth_panels() -> void:
	var streak := _get_daily_streak()
	var unlocked := _unlocked_achievement_ids()
	var profile_ready := _get_field_string(user_data, "email") != "" and _get_field_string(user_data, "referralCode") != ""
	var first_reward := _get_field_int(user_data, "lastMiningStart", 0) > 0 or unlocked.has("first_mining")
	var seven_day := unlocked.has("7_day_streak") or streak >= 7
	var first_invite := unlocked.has("first_referral") or home_ref_count >= 1
	var level := maxi(1, _get_field_int(user_data, "level", 1))
	var new_level := level >= 2
	var special_advantage := home_premium_active or _get_field_string(user_data, "profilePrivilege") == "gold" or _timestamp_field_active("pointsAdFreeUntil") or _timestamp_field_active("pointsBoostUntil")
	var roadmap_steps := [
		{"done": profile_ready, "key": "roadmap_complete_account"},
		{"done": first_reward, "key": "roadmap_first_reward"},
		{"done": seven_day, "key": "roadmap_seven_day"},
		{"done": first_invite, "key": "roadmap_first_invite"},
		{"done": new_level, "key": "roadmap_new_level"},
		{"done": special_advantage, "key": "roadmap_special_benefit"}
	]
	roadmap_steps_cache = roadmap_steps.duplicate(true)
	var completed_steps := 0
	for step in roadmap_steps:
		if bool(step["done"]):
			completed_steps += 1
	if journey_progress_bar:
		journey_progress_bar.value = completed_steps

	if progress_label:
		var next_step := tr("roadmap_all_complete")
		for step in roadmap_steps:
			if not bool(step["done"]):
				next_step = tr(str(step["key"]))
				break
		progress_label.text = tr("roadmap_progress_summary") % [completed_steps, next_step, level, streak]

	if referral_team_label:
		referral_team_label.text = _next_referral_target_text(home_ref_count)
	if referral_team_slots:
		referral_team_slots.text = _team_slot_text(home_ref_count)
	if point_center_label:
		var active_benefits := 0
		active_benefits += 1 if _timestamp_field_active("pointsAdFreeUntil") else 0
		active_benefits += 1 if _timestamp_field_active("pointsBoostUntil") else 0
		active_benefits += 1 if _get_field_string(user_data, "profilePrivilege") == "gold" else 0
		point_center_label.text = _ui_text(
			"Bakiyen %.2f Candar · %d aktif avantaj\nReklamsız süre · Boost · Profil · AI hakları",
			"Balance %.2f Candar · %d active benefits\nAd-free time · Boost · Profile · AI credits"
		) % [home_points, active_benefits]
	if ecosystem_label:
		ecosystem_label.text = tr("home_center_summary") % [home_points, home_ref_count, completed_steps]
	if community_roles_label:
		var role_count := 0
		role_count += 1 if _is_founding_member() else 0
		role_count += 1 if seven_day else 0
		role_count += 1 if first_invite else 0
		role_count += 1 if unlocked.has("10_referrals") or home_ref_count >= 10 else 0
		community_roles_label.text = _ui_text(
			"%d/4 kalıcı rol açık · Kurucu Üye · Seri Ustası · Ağ Kurucusu",
			"%d/4 permanent roles unlocked · Founder · Streak Master · Network Builder"
		) % role_count
	if strategy_label:
		strategy_label.text = _build_strategy_text()

func _open_roadmap() -> void:
	Global.analytics_event("roadmap_open", {"screen": "home"})
	var lines: PackedStringArray = []
	for step in roadmap_steps_cache:
		lines.append("%s %s" % [
			_status_icon(bool(step.get("done", false))),
			tr(str(step.get("key", "")))
		])
	_show_app_modal(
		tr("home_roadmap_title"),
		"\n".join(lines)
	)

func _build_strategy_text() -> String:
	if home_reward_ready:
		return _ui_text(
			"Bugünkü kazımın hazır. Kazım Yap butonuyla Candar puanını alabilirsin.",
			"Today's points are ready. Use the main button to collect your Candar points."
		)
	if home_ref_count < 3:
		return _ui_text(
			"Takım hedefin %d/3. Tanıdığın kişileri davet et; her katılım ağ ilerlemeni görünür biçimde büyütür.",
			"Your team goal is %d/3. Invite people you know; every member visibly grows your network progress."
		) % home_ref_count
	if _get_daily_streak() < 7:
		return _ui_text(
			"Takım temelin hazır. Şimdi 7 günlük seriyi tamamlayarak Seri Ustası rolünü kalıcı olarak aç.",
			"Your team foundation is ready. Complete a 7-day streak to permanently unlock Streak Master."
		)
	if POINT_CENTER_ENABLED and not (_timestamp_field_active("pointsAdFreeUntil") or _timestamp_field_active("pointsBoostUntil") or _get_field_string(user_data, "profilePrivilege") == "gold"):
		return _ui_text(
			"Puanlarını biriktirmek tek seçenek değil: Puan Kullanım Merkezi'nden ilk uygulama içi avantajını açabilirsin.",
			"Saving points is not the only option: unlock your first in-app benefit in the Points Use Center."
		)
	return _ui_text(
		"Ekosistemde güçlü ilerliyorsun. Günlük kazımını sürdür, takım hedefini büyüt ve yeni gelişim haberlerini takip et.",
		"You're progressing strongly through the ecosystem. Keep collecting daily points, grow your team goal, and follow new growth news."
	)

func _status_icon(done: bool) -> String:
	return "✓" if done else "•"

func _get_field_string(fields: Dictionary, key: String) -> String:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("stringValue"):
		return String((v as Dictionary)["stringValue"])
	return ""

func _get_field_int(fields: Dictionary, key: String, default_value := 0) -> int:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY:
		if (v as Dictionary).has("integerValue"):
			return int(str((v as Dictionary)["integerValue"]))
		if (v as Dictionary).has("doubleValue"):
			return int(float((v as Dictionary)["doubleValue"]))
	return default_value

func _get_field_timestamp(fields: Dictionary, key: String) -> String:
	var v: Variant = fields.get(key, {})
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("timestampValue"):
		return str((v as Dictionary)["timestampValue"])
	return ""

func _timestamp_field_active(key: String) -> bool:
	var timestamp := _get_field_timestamp(user_data, key)
	if timestamp == "":
		return false
	var unix_exp := Time.get_unix_time_from_datetime_string(timestamp)
	return unix_exp > Time.get_unix_time_from_system()

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

func _is_founding_member() -> bool:
	var created_at := _get_field_timestamp(user_data, "createdAt")
	if created_at == "":
		# Eski hesaplarda createdAt alanı yoktu; mevcut legacy hesapları
		# kurucu topluluğun parçası olarak kalıcı biçimde kabul et.
		return _get_field_string(user_data, "email") != ""
	var created_unix := Time.get_unix_time_from_datetime_string(created_at)
	var founder_cutoff := Time.get_unix_time_from_datetime_string("2027-01-01T00:00:00Z")
	return created_unix > 0 and created_unix < founder_cutoff

func _get_daily_streak() -> int:
	return max(0, _get_field_int(user_data, "dailyStreak", 0))

func _streak_milestone_text(streak: int) -> String:
	if streak < 7:
		return "🎁 %s: %d/7 · x1.5" % [_ui_text("Seri bonusu", "Streak bonus"), streak]
	if streak < 30:
		return "🎁 %s: %d/30 · x2" % [_ui_text("Sonraki seri bonusu", "Next streak bonus"), streak]
	if streak < 100:
		return "🎁 %s: %d/100 · x3" % [_ui_text("Sonraki seri bonusu", "Next streak bonus"), streak]
	return "🎁 %s: x3" % _ui_text("Maksimum seri bonusu", "Maximum streak bonus")

func _today_key() -> int:
	return int(Time.get_unix_time_from_system() / 86400)

func _claimed_daily_reward_today() -> bool:
	var reward_day := _get_field_int(user_data, "lastRewardDay", -1)
	if reward_day >= 0:
		return reward_day == _today_key()
	var last := _get_field_int(user_data, "lastMiningStart", 0)
	return last > 0 and int(last / 86400) == _today_key()

func _is_daily_reward_ready() -> bool:
	var last := _get_field_int(user_data, "lastMiningStart", 0)
	if last <= 0:
		return true
	return int(Time.get_unix_time_from_system()) - last >= mining_interval_seconds

func _next_reward_status_text() -> String:
	if _is_daily_reward_ready():
		return _ui_text("hazır", "ready")
	var last := _get_field_int(user_data, "lastMiningStart", 0)
	var kalan := mining_interval_seconds - (int(Time.get_unix_time_from_system()) - last)
	kalan = max(kalan, 0)
	@warning_ignore("integer_division")
	var saat := kalan / 3600
	@warning_ignore("integer_division")
	var dakika := (kalan % 3600) / 60
	return _ui_text("%02d saat %02d dk", "%02d h %02d min") % [saat, dakika]

# ---------- PROFIL ----------
func _on_profile_button_pressed():
	Global.analytics_event("open_profile", {"screen": "home"})
	if Global.has_method("ads_set_banner_allowed"):
		Global.ads_set_banner_allowed(true)
	# change_scene kodunu bir fonksiyon (lambda) olarak gönderiyoruz
	try_show_interstitial_ad(func():
		get_tree().change_scene_to_file("res://profile.tscn")
	)

# ---------- FOCUS DONUSUNDE BANNER TAZELE ----------
func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _is_mobile():
		if not Global.is_ad_free_user():
			Global.ads_on_focus_in()
		_request_home_data_sync()

func _on_chat_button_pressed() -> void:
	Global.analytics_event("open_chat", {"screen": "home"})
	if Global.has_method("ads_set_banner_allowed"):
		Global.ads_set_banner_allowed(false)
	else:
		_hide_banner()
	get_tree().change_scene_to_file("res://chat.tscn")
