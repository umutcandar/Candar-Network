extends SceneTree

class FakeReward extends RewardedAd:
	var mode := "earned"
	var destroys := 0
	func _init(): super(101)
	func show(listener: OnUserEarnedRewardListener = null) -> void:
		full_screen_content_callback.on_ad_showed_full_screen_content.call()
		full_screen_content_callback.on_ad_impression.call()
		if mode == "earned":
			listener.on_user_earned_reward.call(RewardedItem.new(1, "test"))
		if mode == "failed":
			full_screen_content_callback.on_ad_failed_to_show_full_screen_content.call(AdError.new(1, "test", "show failed", null))
		else:
			full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	func destroy() -> void: destroys += 1

class FakeInterstitial extends InterstitialAd:
	var shows := 0
	var destroys := 0
	func _init(): super(102)
	func show() -> void: shows += 1
	func destroy() -> void: destroys += 1

class NativeLoader extends RefCounted:
	signal on_rewarded_ad_loaded(uid: int)
	signal on_rewarded_ad_failed_to_load(uid: int, error: Dictionary)
	var next_uid := 0
	var requests: Array[int] = []
	func create() -> int:
		next_uid += 1
		return next_uid
	func load(_unit: String, _request: Dictionary, _keywords: Array, uid: int) -> void:
		requests.append(uid)
	func destroy(_uid: int) -> void: pass

var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager = load("res://manager.gd").new()
	root.add_child(manager)
	# Loading suppressed in these presentation cases; real loader is separately tested.
	manager._rewarded_loading = true
	manager._interstitial_loading = true
	var earned := FakeReward.new()
	manager._rewarded_ad = earned
	var start := Time.get_ticks_msec()
	check(await manager.ads_show_rewarded_and_wait(2.0, "test-user", 123), "Earn callback must reach the outer waiter")
	check(Time.get_ticks_msec() - start < 500, "Earn+dismiss must not wait for the timeout")
	var result: Dictionary = manager.ads_get_last_rewarded_result()
	check(result.reason == "earned" and result.impression and result.closed, "Confirmed callbacks must be reported")
	check(manager.apply_count == 1 and earned.destroys == 1, "One completed ad applies once and destroys once")
	check(not manager._rewarded_showing, "Completed presentation must release its lock")
	var skipped := FakeReward.new()
	skipped.mode = "dismissed"
	manager._rewarded_ad = skipped
	check(not await manager.ads_show_rewarded_and_wait(2.0, "test-user", 124), "Closing without reward must not award")
	check(manager.ads_get_last_rewarded_result().reason == "dismissed_without_reward", "Dismiss callback must reach the waiter")
	check(manager.apply_count == 1, "Dismissal must not call the reward backend")
	var failed := FakeReward.new()
	failed.mode = "failed"
	manager._rewarded_ad = failed
	check(not await manager.ads_show_rewarded_and_wait(2.0), "Show failure must return false")
	check(manager.ads_get_last_rewarded_result().reason == "failed_to_show", "Show failure must not become a timeout")
	var interstitial := FakeInterstitial.new()
	manager._interstitial_ad = interstitial
	check(manager.ads_try_show_interstitial(1.0, 0), "Ready interstitial must present")
	check(manager._active_interstitial_ad == interstitial, "Shown interstitial must stay owned until closed")
	check(not manager.ads_try_show_interstitial(1.0, 0), "Parallel full-screen presentations must be blocked")
	manager._rewarded_ad = FakeReward.new()
	check(not await manager.ads_show_rewarded_and_wait(0.1), "Rewarded must not overlap interstitial")
	interstitial.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(interstitial.destroys == 1 and manager._active_interstitial_ad == null, "Dismissal cleans the active native ad")
	manager.ad_free = true
	manager._interstitial_ad = FakeInterstitial.new()
	check(not manager.ads_try_show_interstitial(1.0, 0), "Ad-free entitlement must stay respected")
	manager.premium = true
	check(not await manager.ads_show_rewarded_and_wait(0.1), "Premium must stay free of rewarded prompts")
	manager.free()
	var native := NativeLoader.new()
	RewardedAdLoader._plugin = native
	var loading = load("res://manager.gd").new()
	root.add_child(loading)
	loading._ads_banner_allowed = false
	loading._interstitial_loading = true
	loading.ads_init("", "", "test-unit", "", "", "test-unit")
	loading.ads_load_rewarded()
	loading.ads_load_rewarded()
	check(native.requests.size() == 1, "Repeated preloads must coalesce into one native request")
	native.on_rewarded_ad_failed_to_load.emit(1, {"code": 3, "domain": "test", "message": "no fill", "cause": {}, "response_info": {}})
	await process_frame
	await process_frame
	check(not loading._rewarded_loading, "Load failure must release the pending flag")
	loading.ads_load_rewarded()
	check(native.requests.size() == 2, "Retry after failure must reach native SDK")
	native.on_rewarded_ad_loaded.emit(2)
	await process_frame
	await process_frame
	loading.ads_load_rewarded()
	check(native.requests.size() == 2 and loading.ads_has_rewarded_ready(), "A cached ad must not be overwritten by another load")
	loading._rewarded_ad.destroy()
	# Drain the manager's startup banner retry timer before freeing the fixture.
	await create_timer(4.1).timeout
	loading.free()
	RewardedAdLoader._plugin = null
	print("Ad manager smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
