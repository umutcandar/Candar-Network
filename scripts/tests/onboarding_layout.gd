extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for i in range(10):
		await process_frame

func run() -> void:
	TranslationServer.set_locale("tr")
	for viewport in [Vector2i(720, 1560), Vector2i(720, 1280), Vector2i(393, 852)]:
		root.size = viewport
		var scene = load("res://onboarding.tscn").instantiate()
		scene.set_script(load("res://onboarding_ios_test.gd"))
		root.add_child(scene)
		# Check the FIRST layout, without calling the layout method a second time.
		await settle()
		check(scene._apple_button != null and scene._google_button != null, "real iOS sign-in buttons exist")
		check(scene._ref_row.visible, "referral is always visible")
		check(scene._apple_button.get_index() == scene.login_buttonn.get_index() + 1, "Apple follows email sign-in")
		check(scene._google_button.get_index() == scene._apple_button.get_index() + 1, "Google follows Apple")
		var form: Rect2 = scene.root_box.get_global_rect()
		for button in [scene._apple_button, scene._google_button, scene.login_buttonn, scene.forgot_button]:
			var style: StyleBoxFlat = button.get_theme_stylebox("normal")
			check(style.expand_margin_left == 0 and style.expand_margin_right == 0, "painted button edges match input edges")
		for field in [scene.email_edit, scene.password_edit, scene.referral_edit]:
			check(absf(field.get_global_rect().position.x - form.position.x) <= 1.0, "input left edge aligns with buttons")
			check(absf(field.get_global_rect().end.x - form.end.x) <= 1.0, "input right edge aligns with buttons")
			check(field.get_theme_stylebox("normal").content_margin_left >= 18, "input text has inner padding")
		check(scene._eye_btn.icon != null, "visibility control uses a renderable icon")
		check(scene.password_edit.get_global_rect().encloses(scene._eye_btn.get_global_rect()), "visibility control stays inside password field")
		var hidden: bool = scene.password_edit.secret
		scene._eye_btn.pressed.emit()
		check(scene.password_edit.secret != hidden, "password visibility toggle works")
		scene._eye_btn.pressed.emit()
		var scroll: ScrollContainer = scene.get_node("MarginContainer/OnboardingScroll")
		check(form.position.x >= 15 and form.end.x <= viewport.x - 15, "form stays inside horizontal margins %s" % viewport)
		check(scene.title_label.get_global_rect().position.y >= 18, "title remains accessible %s" % viewport)
		if form.size.y <= viewport.y - 36:
			check(absf(form.get_center().y - viewport.y / 2.0) <= 1.0, "first-open form is vertically centered %s" % viewport)
			check(scene.root_box.get_parent().size.y <= viewport.y - 36, "no phantom content height %s" % viewport)
			check(scene.forgot_button.get_global_rect().end.y < viewport.y, "sign-in and reset visible on first open %s" % viewport)
		else:
			check(absf(form.position.y - 18) <= 1.0, "overflow starts at top, not below fold %s" % viewport)
			scroll.ensure_control_visible(scene.status_label)
			await settle()
			check(scene.status_label.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1, "bottom of form reachable %s" % viewport)
			scroll.scroll_vertical = 0
		# A second layout or foreground callback must not jump the form.
		scene._apply_responsive_layout()
		await settle()
		check(scene.root_box.get_global_rect().position.distance_to(form.position) <= 1.0, "repeat layout does not shift form %s" % viewport)
		scene.queue_free()
		await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("Onboarding smoke layout passed: first-open iOS buttons, centering, horizontal bounds, scroll reachability, repeat layout.")
		quit(0)
