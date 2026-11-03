class_name InterstitialAdLoader
extends MobileSingletonPlugin

static var _plugin = _get_plugin("PoingGodotAdMobInterstitialAd")

var interstitial_ad_load_callback : InterstitialAdLoadCallback
var _uid : int
var _signals_connected := false
var _loading := false

func _init():
	if _plugin:
		_uid = _plugin.create()
		_ensure_connected()

func _ensure_connected() -> void:
	if _signals_connected:
		return
	if not _plugin:
		return

	var c1 := _on_interstitial_ad_loaded
	var c2 := _on_interstitial_ad_failed_to_load

	if not _plugin.is_connected("on_interstitial_ad_loaded", c1):
		_plugin.connect("on_interstitial_ad_loaded", c1, CONNECT_DEFERRED)
	if not _plugin.is_connected("on_interstitial_ad_failed_to_load", c2):
		_plugin.connect("on_interstitial_ad_failed_to_load", c2, CONNECT_DEFERRED)

	_signals_connected = true

func load(ad_unit_id: String, ad_request: AdRequest, interstitial_ad_load_callback := InterstitialAdLoadCallback.new()) -> void:
	if not _plugin or _loading:
		return

	_ensure_connected()
	self.interstitial_ad_load_callback = interstitial_ad_load_callback

	# Keep the temporary loader alive until its native request completes.
	_loading = true
	reference()

	_plugin.load(ad_unit_id, ad_request.convert_to_dictionary(), ad_request.keywords, _uid)

func _finish_load() -> void:
	_loading = false
	if _signals_connected:
		_plugin.disconnect("on_interstitial_ad_loaded", _on_interstitial_ad_loaded)
		_plugin.disconnect("on_interstitial_ad_failed_to_load", _on_interstitial_ad_failed_to_load)
		_signals_connected = false
	_release_reference.call_deferred()

func _release_reference() -> void:
	if unreference():
		free()

func _on_interstitial_ad_loaded(uid: int) -> void:
	if uid != _uid or not _loading:
		return
	_finish_load()
	if interstitial_ad_load_callback != null and interstitial_ad_load_callback.on_ad_loaded.is_valid():
		interstitial_ad_load_callback.on_ad_loaded.call(InterstitialAd.new(uid))
	else:
		# The requesting scene may have disappeared while the ad was loading.
		_plugin.destroy(uid)

func _on_interstitial_ad_failed_to_load(uid: int, load_ad_error_dictionary: Dictionary) -> void:
	if uid != _uid or not _loading:
		return
	_finish_load()
	if interstitial_ad_load_callback != null and interstitial_ad_load_callback.on_ad_failed_to_load.is_valid():
		interstitial_ad_load_callback.on_ad_failed_to_load.call(LoadAdError.create(load_ad_error_dictionary))
