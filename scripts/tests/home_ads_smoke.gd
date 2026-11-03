extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error(message)

func run() -> void:
	var global := root.get_node("Global")
	var home = load("res://home_actual.gd").new()
	root.add_child(home)
	home.rewarded_button = Button.new()
	home.add_child(home.rewarded_button)
	await home._init_admob()
	check(global.banner_allowed and global.banner_requests == 1, "Returning from chat must restore home banners")
	global.ad_free = true
	await home._init_admob()
	check(global.banner_requests == 1, "Ad-free users must not request a home banner")
	global.ad_free = false
	home.mobile = false
	await home._init_admob()
	check(global.init_calls == 2, "Desktop must not initialize the ad SDK")
	home.mobile = true

	# Both a hidden-button caller and Candar Center can invoke the entrypoint.
	home._on_rewarded_button_pressed()
	home._on_rewarded_button_pressed()
	check(home._rewarded_flow_in_progress, "Rewarded flow must lock before its first await")
	home._set_rewarded_button_idle()
	check(home.rewarded_button.disabled, "Background mining refresh must not unlock an active ad flow")
	var deadline := Time.get_ticks_msec() + 3000
	while home._rewarded_flow_in_progress and Time.get_ticks_msec() < deadline:
		await process_frame
	check(global.reserve_calls == 1, "Repeated center taps must reserve at most one ad attempt")
	check(global.show_calls == 0, "Reservation failure must not show a rewarded ad")
	check(not home._rewarded_flow_in_progress, "Failure must release the flow lock")

	# A stale status response must not change the active flow's button text/state.
	var finished_before: int = global.status_finished
	home._refresh_rewarded_button_state()
	home._rewarded_flow_in_progress = true
	home.rewarded_button.disabled = true
	home.rewarded_button.text = "Preparing ad..."
	deadline = Time.get_ticks_msec() + 3000
	while global.status_finished == finished_before and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	check(home.rewarded_button.disabled and home.rewarded_button.text == "Preparing ad...", "Stale status response must not unlock the ad flow")
	home._rewarded_flow_in_progress = false

	global.reservation = {"ok": true, "attempt_at": 123}
	await home._on_rewarded_button_pressed()
	check(global.show_calls == 1 and global.apply_calls == 0, "Incomplete ad must never apply a boost")
	check(not home._rewarded_flow_in_progress, "Incomplete ad must release the flow lock")
	global.complete_reward = true
	await home._on_rewarded_button_pressed()
	check(global.show_calls == 2 and global.apply_calls == 1, "Completed ad must apply its boost once through the home flow")
	check(not home._rewarded_flow_in_progress, "Successful ad must release the flow lock")
	global.premium = true
	await home._on_rewarded_button_pressed()
	check(global.show_calls == 2, "Premium users must not show rewarded ads")
	home.free()
	print("Home ads smoke: %d checks, %d failures" % [checks, failed])
	quit(1 if failed else 0)
