extends SceneTree

const OUT_DIR := "res://store-screenshots/raw"
const EMAIL := "candar.demo@example.com"
const PASSWORD := "demo-password"

var _logged_in := false
var _mock_uid := "store-shot-user"


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1290, 2796))
	root.size = Vector2i(1290, 2796)
	TranslationServer.set_locale("en")
	await process_frame
	await process_frame
	_force_english_store_locale()

	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("store-screenshots/raw")

	print("[STORE_SHOTS] runner start")
	print("[STORE_SHOTS] viewport=", root.size)
	print("[STORE_SHOTS] has Global=", root.has_node("/root/Global"))

	await _capture_onboarding()
	await _prepare_mock_session()
	await _capture_scene("01-home", "res://home.tscn", 3.0)
	await _capture_scene("02-market", "res://market.tscn", 2.0)
	await _capture_scene("03-profile", "res://profile.tscn", 2.0)
	await _capture_scene("04-ai", "res://chat.tscn", 2.0)

	print("[STORE_SHOTS] done")
	quit()


func _capture_onboarding() -> void:
	await _capture_scene("00-login", "res://onboarding.tscn", 2.0)


func _login() -> void:
	var global: Node = root.get_node_or_null("/root/Global")
	if global == null or not global.has_method("login"):
		print("[STORE_SHOTS] Global.login unavailable")
		return
	print("[STORE_SHOTS] logging in as ", EMAIL)
	var result: Array = await global.login(EMAIL, PASSWORD)
	print("[STORE_SHOTS] login result=", result)
	_logged_in = result.size() > 0 and bool(result[0])


func _prepare_mock_session() -> void:
	var file := FileAccess.open("user://uid.txt", FileAccess.WRITE)
	if file:
		file.store_string(_mock_uid)
		file.close()
	var global: Node = root.get_node_or_null("/root/Global")
	if global != null and global.has_method("save_uid"):
		await global.call("save_uid", _mock_uid)
	if global != null:
		if "mining_rate" in global:
			global.set("mining_rate", 1.85)
		if "market_is_premium" in global:
			global.set("market_is_premium", true)
	print("[STORE_SHOTS] mock session ready")


func _capture_scene(label: String, scene_path: String, wait_seconds: float) -> void:
	print("[STORE_SHOTS] scene ", label, " -> ", scene_path)
	_force_english_store_locale()
	var err := change_scene_to_file(scene_path)
	if err != OK:
		print("[STORE_SHOTS] scene failed: ", err)
		return
	await process_frame
	await process_frame
	_force_english_store_locale()
	await create_timer(wait_seconds).timeout
	_apply_mock_data(label)
	await process_frame
	await create_timer(0.5).timeout
	await _save_viewport(label)
	if label == "03-profile" and current_scene and current_scene.has_method("_open_achievements"):
		current_scene.call("_open_achievements")
		await process_frame
		await create_timer(0.5).timeout
		await _save_viewport("03a-achievements")


func _force_english_store_locale() -> void:
	TranslationServer.set_locale("en")
	var global: Node = root.get_node_or_null("/root/Global")
	if global != null and "current_lang" in global:
		global.set("current_lang", "en")


func _save_viewport(label: String) -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		print("[STORE_SHOTS] empty image for ", label)
		return
	image.convert(Image.FORMAT_RGBA8)
	var path := "%s/%s.png" % [OUT_DIR, label]
	var err := image.save_png(path)
	print("[STORE_SHOTS] saved ", path, " err=", err, " size=", image.get_size())


func _mock_fields() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var future := Time.get_datetime_string_from_unix_time(now + 86400 * 21)
	return {
		"email": {"stringValue": EMAIL},
		"referralCode": {"stringValue": "CANDAR25"},
		"points": {"doubleValue": 2486.75},
		"lastMiningStart": {"integerValue": 0},
		"dailyStreak": {"integerValue": 8},
		"streakShieldCount": {"integerValue": 1},
		"xp": {"integerValue": 380},
		"level": {"integerValue": 3},
		"achievements": {"arrayValue": {"values": [
			{"stringValue": "first_mining"},
			{"stringValue": "100_points"},
			{"stringValue": "1000_points"},
			{"stringValue": "first_referral"},
			{"stringValue": "7_day_streak"}
		]}},
		"lastLoginDate": {"integerValue": int(now / 86400)},
		"currentMultiplier": {"doubleValue": 3.0},
		"rewardedBoostMultiplier": {"doubleValue": 1.10},
		"isPremium": {"booleanValue": true},
		"boostExpiresAt": {"timestampValue": future},
		"premiumExpiresAt": {"timestampValue": future},
		"mining": {"mapValue": {"fields": {
			"points": {"doubleValue": 2486.75},
			"base_rate": {"doubleValue": 1.0},
			"active_multiplier": {"doubleValue": 3.0},
			"boost_expires_at": {"timestampValue": future}
		}}},
		"premium": {"mapValue": {"fields": {
			"is_active": {"booleanValue": true},
			"expires_at": {"timestampValue": future}
		}}}
	}


func _apply_mock_data(label: String) -> void:
	var scene := current_scene
	if scene == null:
		return
	if label == "00-login":
		_apply_login_mock(scene)
	elif label == "01-home":
		_apply_home_mock(scene)
	elif label == "02-market":
		_apply_market_mock(scene)
	elif label == "03-profile":
		_apply_profile_mock(scene)
	elif label == "04-ai":
		await _apply_chat_mock(scene)


func _apply_login_mock(scene: Node) -> void:
	if "email_edit" in scene and scene.get("email_edit"):
		scene.get("email_edit").text = EMAIL
	if "password_edit" in scene and scene.get("password_edit"):
		scene.get("password_edit").text = "••••••"
	if "status_label" in scene and scene.get("status_label"):
		scene.get("status_label").text = "Secure email sign-in with daily Candar rewards."


func _apply_home_mock(scene: Node) -> void:
	var fields := _mock_fields()
	scene.set("current_user_id", _mock_uid)
	scene.set("user_data", fields)
	if "welcome_label" in scene and scene.get("welcome_label"):
		scene.get("welcome_label").text = "Welcome, Testuser"
	if "mining_button" in scene and scene.get("mining_button"):
		scene.get("mining_button").visible = true
		scene.get("mining_button").disabled = false
		scene.get("mining_button").text = "Claim Daily Candar"
	if scene.has_method("_update_dashboard"):
		scene.call("_update_dashboard", 2486.75, 3.85, 3.0, 1.10, true, 7)
	if scene.has_method("_set_mining_ready"):
		scene.call("_set_mining_ready")
	_close_modal_if_any(scene)


func _apply_market_mock(scene: Node) -> void:
	scene.set("market_context", {
		"points": 2486.75,
		"refs": 7,
		"base_rate": 1.0,
		"current_multiplier": 3.0,
		"rewarded_multiplier": 1.10,
		"total_rate": 3.85,
		"is_premium": true
	})
	if scene.has_method("_update_market_cards"):
		scene.call("_update_market_cards")
	if "status_label" in scene and scene.get("status_label"):
		scene.get("status_label").text = "Choose a boost to grow faster."


func _apply_profile_mock(scene: Node) -> void:
	var fields := _mock_fields()
	scene.set("current_user_id", _mock_uid)
	scene.set("user_data", fields)
	scene.set("referans_sayisi", 7)
	if "email_label" in scene and scene.get("email_label"):
		scene.get("email_label").text = "Email: " + EMAIL
	if "puan_label" in scene and scene.get("puan_label"):
		scene.get("puan_label").text = "Candar: 2486.75"
	if "referral_label" in scene and scene.get("referral_label"):
		scene.get("referral_label").text = "Referral code: CANDAR25"
	if "stat_candar_v" in scene and scene.get("stat_candar_v"):
		scene.get("stat_candar_v").text = "2486.75"
	if scene.has_method("_set_rate_and_refs"):
		scene.call("_set_rate_and_refs", 1.35, 7)
	if scene.has_method("_update_membership_card"):
		scene.call("_update_membership_card")
	if scene.has_method("_update_progress_ui"):
		scene.call("_update_progress_ui")
	if scene.has_method("_update_badge_and_avatar"):
		scene.call("_update_badge_and_avatar")


func _apply_chat_mock(scene: Node) -> void:
	if "status_label" in scene and scene.get("status_label"):
		scene.get("status_label").text = "Candar AI is ready."
	if scene.has_method("_add_chat_bubble"):
		await scene.call("_add_chat_bubble", "user", "How can I grow my referral network?")
		await scene.call("_add_chat_bubble", "ai", "Share your code, keep your daily streak, and use boosts when your referral rate is active.")


func _close_modal_if_any(scene: Node) -> void:
	if "app_modal_overlay" in scene and scene.get("app_modal_overlay"):
		var overlay: Node = scene.get("app_modal_overlay")
		if is_instance_valid(overlay):
			overlay.queue_free()
		scene.set("app_modal_overlay", null)
