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

class_name ConsentInformation
extends MobileSingletonPlugin

static var _plugin := _get_plugin("PoingGodotAdMobConsentInformation")

enum ConsentStatus {
	UNKNOWN,
	NOT_REQUIRED,
	REQUIRED,
	OBTAINED
}

func get_consent_status() -> ConsentStatus:
	if _plugin:
		return _plugin.get_consent_status()
	return ConsentStatus.UNKNOWN

func get_is_consent_form_available() -> bool:
	if _plugin:
		return _plugin.get_is_consent_form_available()
	return false

var _on_consent_info_updated_success_callback: Callable
var _on_consent_info_updated_failure_callback: Callable
var _updating := false

func update(consent_request: ConsentRequestParameters,
		on_consent_info_updated_success := func(): pass,
		on_consent_info_updated_failure := func(_error: FormError): pass) -> void:
	if not _plugin:
		on_consent_info_updated_failure.call_deferred(FormError.new(-1, "Consent plugin unavailable"))
		return
	if _updating:
		on_consent_info_updated_failure.call_deferred(FormError.new(-2, "Consent update already pending"))
		return
	_updating = true
	_on_consent_info_updated_success_callback = on_consent_info_updated_success
	_on_consent_info_updated_failure_callback = on_consent_info_updated_failure
	# Native implementations may complete synchronously. Subscribe first.
	_plugin.connect("on_consent_info_updated_success", _on_consent_info_updated_success)
	_plugin.connect("on_consent_info_updated_failure", _on_consent_info_updated_failure)
	_plugin.update(consent_request.convert_to_dictionary())

func reset() -> void:
	if _plugin and not _updating:
		_plugin.reset()

func _finish_update() -> void:
	_updating = false
	for pair in [["on_consent_info_updated_success", _on_consent_info_updated_success],
		["on_consent_info_updated_failure", _on_consent_info_updated_failure]]:
		if _plugin.is_connected(pair[0], pair[1]):
			_plugin.disconnect(pair[0], pair[1])
	_on_consent_info_updated_success_callback = Callable()
	_on_consent_info_updated_failure_callback = Callable()

func _on_consent_info_updated_success() -> void:
	if not _updating: return
	var callback := _on_consent_info_updated_success_callback
	_finish_update()
	if callback.is_valid(): callback.call_deferred()

func _on_consent_info_updated_failure(error: Dictionary) -> void:
	if not _updating: return
	var callback := _on_consent_info_updated_failure_callback
	_finish_update()
	if callback.is_valid(): callback.call_deferred(FormError.create(error))
