extends SceneTree

class NativeAds extends RefCounted:
	signal on_interstitial_ad_loaded(uid: int)
	signal on_interstitial_ad_failed_to_load(uid: int, error: Dictionary)
	signal on_interstitial_ad_clicked(uid: int)
	signal on_interstitial_ad_dismissed_full_screen_content(uid: int)
	signal on_interstitial_ad_failed_to_show_full_screen_content(uid: int, error: Dictionary)
	signal on_interstitial_ad_impression(uid: int)
	signal on_interstitial_ad_showed_full_screen_content(uid: int)
	signal on_rewarded_ad_loaded(uid: int)
	signal on_rewarded_ad_failed_to_load(uid: int, error: Dictionary)
	signal on_rewarded_ad_user_earned_reward(uid: int, reward: Dictionary)
	signal on_rewarded_ad_clicked(uid: int)
	signal on_rewarded_ad_dismissed_full_screen_content(uid: int)
	signal on_rewarded_ad_failed_to_show_full_screen_content(uid: int, error: Dictionary)
	signal on_rewarded_ad_impression(uid: int)
	signal on_rewarded_ad_showed_full_screen_content(uid: int)
	var next_uid := 0
	var requests: Array[int] = []
	var destroyed: Array[int] = []
	func create() -> int:
		next_uid += 1
		return next_uid
	func load(_unit: String, _request: Dictionary, _keywords: Array, uid: int) -> void:
		requests.append(uid)
	func destroy(uid: int) -> void:
		destroyed.append(uid)
	func show(uid: int) -> void:
		on_interstitial_ad_showed_full_screen_content.emit(uid)

var checks := 0
var failures := 0
var loaded_ads: Array[InterstitialAd] = []
var errors: Array[LoadAdError] = []
var shown := 0
var dismissed := 0
var presentation_errors := 0
var loaded_rewarded_ads: Array[RewardedAd] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("AdMob smoke: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var native := NativeAds.new()
	InterstitialAdLoader._plugin = native
	InterstitialAd._plugin = native
	RewardedAdLoader._plugin = native
	RewardedAd._plugin = native
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void: loaded_ads.append(ad)
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void: errors.append(error)
	var first := InterstitialAdLoader.new()
	var second := InterstitialAdLoader.new()
	var first_ref: WeakRef = weakref(first)
	var second_ref: WeakRef = weakref(second)
	first.load("test-interstitial", AdRequest.new(), callback)
	second.load("test-interstitial", AdRequest.new(), callback)
	var first_uid := native.requests[0]
	var second_uid := native.requests[1]
	first = null
	second = null
	check(first_ref.get_ref() != null, "pending loader must survive its caller")
	native.on_interstitial_ad_loaded.emit(99999)
	await process_frame
	check(loaded_ads.is_empty(), "foreign UID must not complete a request")
	native.on_interstitial_ad_loaded.emit(second_uid)
	await process_frame
	await process_frame
	check(loaded_ads.size() == 1, "native success must deliver exactly one ready interstitial")
	check(second_ref.get_ref() == null, "completed loader must be released")
	check(first_ref.get_ref() != null, "other pending request must remain alive")
	var error_data := {"code": 1, "domain": "test.admob", "message": "No fill", "cause": {}, "response_info": {}}
	native.on_interstitial_ad_failed_to_load.emit(first_uid, error_data)
	await process_frame
	await process_frame
	check(errors.size() == 1, "native failure must reach typed LoadAdError callback")
	if not errors.is_empty():
		check(errors[0].message == "No fill" and errors[0].code == 1, "failure details must be preserved")
	check(first_ref.get_ref() == null, "failed loader must be released for retry")
	native.on_interstitial_ad_loaded.emit(second_uid)
	await process_frame
	check(loaded_ads.size() == 1, "late duplicate result must not redeliver")
	if not loaded_ads.is_empty():
		var ad := loaded_ads[0]
		check(ad._uid == second_uid, "ready ad must retain native UID")
		ad.full_screen_content_callback.on_ad_showed_full_screen_content = func() -> void: shown += 1
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void: dismissed += 1
		ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void: presentation_errors += 1
		ad.show()
		native.on_interstitial_ad_dismissed_full_screen_content.emit(second_uid)
		native.on_interstitial_ad_failed_to_show_full_screen_content.emit(second_uid, error_data)
		await process_frame
		check(shown == 1 and dismissed == 1 and presentation_errors == 1, "show/dismiss/failure callbacks must reach the app")
		ad.destroy()
		check(native.destroyed.has(second_uid), "native ad must be destroyable")
		loaded_ads.clear()
		ad = null
	var retry := InterstitialAdLoader.new()
	var retry_ref: WeakRef = weakref(retry)
	retry.load("test-interstitial", AdRequest.new(), callback)
	var retry_uid: int = native.requests.back()
	retry = null
	native.on_interstitial_ad_loaded.emit(retry_uid)
	await process_frame
	await process_frame
	check(loaded_ads.size() == 1, "loading after a failure must still succeed")
	check(retry_ref.get_ref() == null, "retry loader must be released")
	for ad in loaded_ads:
		ad.destroy()
	loaded_ads.clear()
	var rewarded_callback := RewardedAdLoadCallback.new()
	rewarded_callback.on_ad_failed_to_load = func(error: LoadAdError) -> void: errors.append(error)
	var rewarded := RewardedAdLoader.new()
	var rewarded_ref: WeakRef = weakref(rewarded)
	rewarded.load("test-rewarded", AdRequest.new(), rewarded_callback)
	var rewarded_uid: int = native.requests.back()
	rewarded = null
	native.on_rewarded_ad_failed_to_load.emit(rewarded_uid, error_data)
	await process_frame
	await process_frame
	check(errors.size() == 2, "rewarded failure must convert the native dictionary to LoadAdError")
	check(rewarded_ref.get_ref() == null, "rewarded failure must release the loader")
	# A retained loader must finish once, disconnect, and remain safe to reuse.
	rewarded_callback.on_ad_loaded = func(ad: RewardedAd) -> void: loaded_rewarded_ads.append(ad)
	var retained := RewardedAdLoader.new()
	retained.load("test-rewarded", AdRequest.new(), rewarded_callback)
	var retained_uid: int = native.requests.back()
	native.on_rewarded_ad_loaded.emit(99999)
	await process_frame
	check(loaded_rewarded_ads.is_empty(), "foreign UID must not complete a rewarded request")
	native.on_rewarded_ad_loaded.emit(retained_uid)
	native.on_rewarded_ad_loaded.emit(retained_uid)
	await process_frame
	await process_frame
	check(loaded_rewarded_ads.size() == 1, "rewarded success must deliver one native ad")
	check(not native.is_connected("on_rewarded_ad_loaded", retained._on_rewarded_ad_loaded), "rewarded success must disconnect its native load signal")
	check(not native.is_connected("on_rewarded_ad_failed_to_load", retained._on_rewarded_ad_failed_to_load), "rewarded success must disconnect its native failure signal")
	native.on_rewarded_ad_loaded.emit(retained_uid)
	await process_frame
	check(loaded_rewarded_ads.size() == 1, "completed rewarded request must ignore duplicate callbacks")
	retained.load("test-rewarded", AdRequest.new(), rewarded_callback)
	var request_count := native.requests.size()
	retained.load("test-rewarded", AdRequest.new(), rewarded_callback)
	check(native.requests.size() == request_count, "a pending rewarded load must not issue a duplicate request")
	native.on_rewarded_ad_failed_to_load.emit(retained_uid, error_data)
	await process_frame
	await process_frame
	check(errors.size() == 3, "a reused rewarded loader must deliver one typed failure")
	retained = null
	for ad in loaded_rewarded_ads:
		ad.destroy()
	loaded_rewarded_ads.clear()
	var orphan := RewardedAdLoader.new()
	var orphan_callback := RewardedAdLoadCallback.new()
	orphan_callback.on_ad_loaded = Callable()
	orphan.load("test-rewarded", AdRequest.new(), orphan_callback)
	var orphan_uid: int = native.requests.back()
	var orphan_ref: WeakRef = weakref(orphan)
	orphan = null
	native.on_rewarded_ad_loaded.emit(orphan_uid)
	await process_frame
	await process_frame
	check(native.destroyed.has(orphan_uid), "an unclaimed rewarded ad must release its native resources")
	check(orphan_ref.get_ref() == null, "an unclaimed rewarded load must release its loader")
	InterstitialAdLoader._plugin = null
	InterstitialAd._plugin = null
	RewardedAdLoader._plugin = null
	RewardedAd._plugin = null
	print("AdMob smoke: %d checks, %d failures" % [checks, failures])
	# Let coroutine locals and deferred plugin callbacks release before shutdown.
	quit.call_deferred(1 if failures else 0)
