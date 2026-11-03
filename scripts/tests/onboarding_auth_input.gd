extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var global := root.get_node("Global")
	root.size = Vector2i(720, 1280)
	TranslationServer.set_locale("tr")
	var scene = load("res://onboarding.tscn").instantiate()
	root.add_child(scene)
	# Let the normal launch-context task finish before testing controlled races.
	await create_timer(0.85).timeout
	scene.email_edit.text = "  person@example.com  "
	scene.password_edit.text = "  My Password  "
	await scene._on_login_pressed_common(false, false)
	check(global.last_email == "person@example.com", "Email whitespace should still be trimmed")
	check(global.last_password == "  My Password  ", "Password bytes must reach auth unchanged, including edge spaces")
	check(not scene._auth_in_progress, "Failed password authentication must allow retry")

	# Deferred invitation handling must not overwrite a pending auth request.
	global.pending_code = "INVITE7"
	global.login_delay = 1.1
	scene.referral_edit.text = ""
	scene._on_login_pressed_common(false, false)
	var pending_status: String = scene.status_label.text
	await scene._prefill_referral_from_launch_context()
	check(scene._auth_in_progress, "Controlled request remains pending during referral detection")
	check(scene.referral_edit.text == "", "Launch-context task must not mutate a locked form")
	check(scene.status_label.text == pending_status, "Referral detection must preserve in-flight authentication status")
	check(global.last_referral == "INVITE7", "Pending referral must still be submitted even before field prefill")
	await create_timer(0.4).timeout
	var failed_status: String = scene.status_label.text
	check(failed_status.contains("Test request failed"), "Authentication failure is shown")
	await scene._prefill_referral_from_launch_context()
	check(scene.referral_edit.text == "INVITE7", "Idle form may populate the invitation field")
	check(scene.status_label.text == failed_status, "Late referral detection must not hide an authentication error")

	# On a pristine form, the existing invitation feedback remains available.
	scene.referral_edit.text = ""
	scene.status_label.text = ""
	await scene._prefill_referral_from_launch_context()
	check(scene.status_label.text == TranslationServer.translate("referral_detected") % "INVITE7", "Pristine form should announce its detected invitation")
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("Onboarding auth input passed: exact password, referral/auth races, retry and invitation feedback.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
