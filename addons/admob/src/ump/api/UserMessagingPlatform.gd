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

class_name UserMessagingPlatform
extends MobileSingletonPlugin

static var _plugin := _get_plugin("PoingGodotAdMobUserMessagingPlatform")

static var consent_information := ConsentInformation.new()

static var _on_consent_form_load_success_listener_callback: Callable
static var _on_consent_form_load_failure_listener_callback: Callable
static var _loading := false

static func load_consent_form(
		on_success := func(_form: ConsentForm): pass,
		on_failure := func(_error: FormError): pass) -> void:
	if not _plugin:
		on_failure.call_deferred(FormError.new(-1, "Consent plugin unavailable"))
		return
	if _loading:
		on_failure.call_deferred(FormError.new(-2, "Consent form load already pending"))
		return
	_loading = true
	_on_consent_form_load_success_listener_callback = on_success
	_on_consent_form_load_failure_listener_callback = on_failure
	_plugin.connect("on_consent_form_load_success_listener", _on_consent_form_load_success_listener)
	_plugin.connect("on_consent_form_load_failure_listener", _on_consent_form_load_failure_listener)
	_plugin.load_consent_form()

static func _finish_load() -> void:
	_loading = false
	for pair in [["on_consent_form_load_success_listener", _on_consent_form_load_success_listener],
		["on_consent_form_load_failure_listener", _on_consent_form_load_failure_listener]]:
		if _plugin.is_connected(pair[0], pair[1]):
			_plugin.disconnect(pair[0], pair[1])
	_on_consent_form_load_success_listener_callback = Callable()
	_on_consent_form_load_failure_listener_callback = Callable()

static func _on_consent_form_load_success_listener(uid: int) -> void:
	if not _loading: return
	var callback := _on_consent_form_load_success_listener_callback
	_finish_load()
	if callback.is_valid(): callback.call_deferred(ConsentForm.new(uid))

static func _on_consent_form_load_failure_listener(error: Dictionary) -> void:
	if not _loading: return
	var callback := _on_consent_form_load_failure_listener_callback
	_finish_load()
	if callback.is_valid(): callback.call_deferred(FormError.create(error))
