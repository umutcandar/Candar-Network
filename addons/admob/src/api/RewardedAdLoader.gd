# MIT License

# Copyright (c) 2023-present Poing Studios

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

class_name RewardedAdLoader
extends MobileSingletonPlugin

static var _plugin = _get_plugin("PoingGodotAdMobRewardedAd")

var rewarded_ad_load_callback : RewardedAdLoadCallback
var _uid : int
var _loading := false

func _init():
	if _plugin:
		_uid = _plugin.create()

func load(
	ad_unit_id : String, 
	ad_request : AdRequest, 
	rewarded_ad_load_callback := RewardedAdLoadCallback.new()) -> void:

	if not _plugin or _loading:
		return
	self.rewarded_ad_load_callback = rewarded_ad_load_callback
	_plugin.connect("on_rewarded_ad_loaded", _on_rewarded_ad_loaded, CONNECT_DEFERRED)
	_plugin.connect("on_rewarded_ad_failed_to_load", _on_rewarded_ad_failed_to_load, CONNECT_DEFERRED)
	_loading = true
	reference()
	_plugin.load(ad_unit_id, ad_request.convert_to_dictionary(), ad_request.keywords, _uid)

func _finish_load() -> void:
	_loading = false
	_plugin.disconnect("on_rewarded_ad_loaded", _on_rewarded_ad_loaded)
	_plugin.disconnect("on_rewarded_ad_failed_to_load", _on_rewarded_ad_failed_to_load)
	_release_reference.call_deferred()

func _on_rewarded_ad_loaded(uid: int) -> void:
	if uid != _uid or not _loading:
		return
	_finish_load()

	# Kullanıcı tarafında set edilen callback
	if rewarded_ad_load_callback == null:
		_plugin.destroy(uid)
		return

	var callback: Callable = rewarded_ad_load_callback.on_ad_loaded

	# 1) Gerçekten callable mı?
	if typeof(callback) != TYPE_CALLABLE:
		_plugin.destroy(uid)
		return

	# 2) Callback'in bağlı olduğu obje
	var cb_obj := callback.get_object()
	if cb_obj == null or not is_instance_valid(cb_obj):
		# Sahne değişmiş, obje silinmiş → sessizce vazgeç
		_plugin.destroy(uid)
		return

	# 3) Metod hâlâ geçerli mi?
	if not callback.is_valid():
		_plugin.destroy(uid)
		return

	# 4) Artık güvenli: RewardedAd nesnesini oluştur ve callback'e gönder
	var ad_obj := RewardedAd.new(uid)

	if callback.get_argument_count() >= 1:
		callback.call(ad_obj)
	else:
		callback.call()
		ad_obj.destroy()

func _on_rewarded_ad_failed_to_load(uid: int, load_ad_error_dictionary: Dictionary) -> void:
	if uid != _uid or not _loading:
		return
	_finish_load()

	if rewarded_ad_load_callback == null:
		return

	var callback: Callable = rewarded_ad_load_callback.on_ad_failed_to_load

	if typeof(callback) != TYPE_CALLABLE:
		return

	var cb_obj := callback.get_object()
	if cb_obj == null or not is_instance_valid(cb_obj):
		return

	if not callback.is_valid():
		return

	if callback.get_argument_count() >= 1:
		callback.call(LoadAdError.create(load_ad_error_dictionary))
	else:
		callback.call()

func _release_reference() -> void:
	if unreference():
		free()
