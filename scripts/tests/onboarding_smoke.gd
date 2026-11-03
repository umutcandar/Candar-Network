extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var global = root.get_node("Global")
	root.size = Vector2i(720, 1280)
	TranslationServer.set_locale("tr")
	var scene = load("res://onboarding.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene._ref_row.visible, "optional referral is visible on first open")
	check(scene.referral_edit.placeholder_text == "Davet kodu (isteğe bağlı)", "optional invitation hint is inside the input")
	check(scene.root_box.get_node_or_null("ReferralToggle") == null, "no referral expansion button")
	check(scene._tagline.text == "Serini başlat. İlk günlük puanını topla.", "Turkish benefit text loads")
	scene.referral_edit.text = "candar_ref=FRIEND7"
	check(scene._current_referral_code() == "FRIEND7", "copied invitation parses correctly")
	# Inject buttons to verify repeated native order calls on a desktop runner.
	scene._apple_button = Button.new()
	scene._google_button = Button.new()
	scene.root_box.add_child(scene._apple_button)
	scene.root_box.add_child(scene._google_button)
	for i in range(3):
		scene._ensure_social_buttons_order()
		check(scene._apple_button.get_index() < scene._google_button.get_index(), "Apple precedes Google")
		check(scene._apple_button.get_index() == scene.login_buttonn.get_index() + 1, "Apple immediately follows email sign-in")
		check(scene._google_button.get_index() == scene._apple_button.get_index() + 1, "Google immediately follows Apple")
	scene.email_edit.text = "test@example.com"
	scene.password_edit.text = "test-password"
	scene._on_login_pressed_common(false, false)
	scene._on_login_pressed_common(false, false)
	scene._on_forgot_password_pressed()
	check(global.login_calls == 1, "duplicate email request is blocked")
	check(global.reset_calls == 0, "reset cannot overlap login")
	check(scene._google_button.disabled and scene._apple_button.disabled, "all providers disabled during request")
	check(not scene.email_edit.editable, "form cannot change during request")
	await create_timer(0.3).timeout
	check(not scene._auth_in_progress, "failed request releases lock")
	check(not scene._google_button.disabled and scene.email_edit.editable, "failed request permits retry")
	await scene._on_login_pressed_common(true, false)
	check(global.events.any(func(e): return e.event == "signup_start" and e.params.get("method") == "google"), "social start is measured")
	check(global.events.any(func(e): return e.event == "signup_error" and e.params.get("method") == "google"), "social failure is measured")
	global.pending_code = "PENDING7"
	scene.referral_edit.text = ""
	await scene._prefill_referral_from_launch_context()
	check(scene._ref_row.visible, "deep link preserves visible invitation field")
	check(scene.referral_edit.text == "PENDING7", "deep link fills code")
	for viewport in [Vector2i(360, 780), Vector2i(720, 1280), Vector2i(1024, 1366)]:
		root.size = viewport
		scene._apply_responsive_layout()
		await process_frame
		await process_frame
		check(scene.root_box.size.x <= viewport.x, "form fits viewport %s (actual %s)" % [viewport, scene.root_box.size])
	for locale in ["en", "tr", "de", "fr", "es", "pt", "ru", "zh", "ja", "ko", "ar", "hi"]:
		TranslationServer.set_locale(locale)
		for key in ["onboarding_first_step", "referral_placeholder"]:
			check(TranslationServer.translate(key) != key, "translation %s:%s" % [locale, key])
	scene.queue_free()
	await process_frame
	if failures.size() > 0:
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("Onboarding smoke passed: social order, invite flows, concurrent auth guard, retry, 3 widths, 12 locales.")
		quit(0)
