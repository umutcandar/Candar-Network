extends SceneTree

class NativeConsent extends RefCounted:
	signal on_consent_info_updated_success
	signal on_consent_info_updated_failure(error: Dictionary)
	signal on_consent_form_load_success_listener(uid: int)
	signal on_consent_form_load_failure_listener(error: Dictionary)
	signal on_consent_form_dismissed(uid: int, error: Dictionary)
	var immediate := true
	var fail := false
	var updates := 0
	var loads := 0
	var shows := 0
	func update(_params: Dictionary) -> void:
		updates += 1
		if immediate:
			if fail: on_consent_info_updated_failure.emit({"error_code": 1, "message": "offline"})
			else: on_consent_info_updated_success.emit()
	func load_consent_form() -> void:
		loads += 1
		if immediate:
			if fail: on_consent_form_load_failure_listener.emit({"error_code": 2, "message": "load failed"})
			else: on_consent_form_load_success_listener.emit(loads)
	func show(uid: int) -> void:
		shows += 1
		if immediate: on_consent_form_dismissed.emit(uid, {})

var checks := 0
var failures := 0
var successes := 0
var errors: Array = []
var forms: Array = []
var dismissed: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func success() -> void: successes += 1
func failure(error: FormError) -> void: errors.append(error)
func loaded(form: ConsentForm) -> void: forms.append(form)
func closed(error: FormError) -> void: dismissed.append(error)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var native := NativeConsent.new()
	ConsentInformation._plugin = native
	UserMessagingPlatform._plugin = native
	ConsentForm._plugin = native
	var info := ConsentInformation.new()
	info.update(ConsentRequestParameters.new(), success, failure)
	await process_frame
	check(successes == 1, "Synchronous consent update must reach caller")
	check(native.on_consent_info_updated_failure.get_connections().is_empty(), "Success must disconnect unused failure branch")
	native.fail = true
	info.update(ConsentRequestParameters.new(), success, failure)
	await process_frame
	check(errors.size() == 1 and errors[0].error_code == 1, "Failure must reach caller as FormError")
	check(native.on_consent_info_updated_success.get_connections().is_empty(), "Failure must disconnect unused success branch")
	native.immediate = false
	info.update(ConsentRequestParameters.new(), success, failure)
	info.update(ConsentRequestParameters.new(), success, failure)
	await process_frame
	check(native.updates == 3 and errors.back().error_code == -2, "Concurrent update must not overwrite pending callback")
	native.on_consent_info_updated_success.emit()
	await process_frame
	check(successes == 2, "Original pending update must complete once")
	native.immediate = true
	native.fail = false
	UserMessagingPlatform.load_consent_form(loaded, failure)
	await process_frame
	check(forms.size() == 1, "Synchronous form load must reach caller")
	check(native.on_consent_form_load_failure_listener.get_connections().is_empty(), "Form success must clean failure branch")
	forms[0].show(closed)
	await process_frame
	check(dismissed.size() == 1 and dismissed[0] == null, "Synchronous dismissal must reach caller")
	check(native.on_consent_form_dismissed.get_connections().is_empty(), "Dismissed form must disconnect")
	forms[0].show(closed)
	await process_frame
	check(native.shows == 1 and dismissed.back().error_code == -2, "A consumed form must not show twice")
	native.fail = true
	UserMessagingPlatform.load_consent_form(loaded, failure)
	await process_frame
	check(errors.back().error_code == 2, "Form load failure must reach caller")
	check(native.on_consent_form_load_success_listener.get_connections().is_empty(), "Failed form load must clean success branch")
	native.immediate = false
	UserMessagingPlatform.load_consent_form(loaded, failure)
	UserMessagingPlatform.load_consent_form(loaded, failure)
	await process_frame
	check(native.loads == 3 and errors.back().error_code == -2, "Concurrent form load must preserve original operation")
	native.on_consent_form_load_success_listener.emit(3)
	await process_frame
	forms.back().show(closed)
	native.on_consent_form_dismissed.emit(99, {})
	await process_frame
	check(dismissed.size() == 2, "Unrelated form dismissal must be ignored")
	native.on_consent_form_dismissed.emit(3, {"error_code": 4, "message": "show failed"})
	await process_frame
	check(dismissed.size() == 3 and dismissed.back().error_code == 4, "Matched show failure must complete pending form")
	ConsentInformation._plugin = null
	UserMessagingPlatform._plugin = null
	ConsentForm._plugin = null
	info.update(ConsentRequestParameters.new(), success, failure)
	UserMessagingPlatform.load_consent_form(loaded, failure)
	var missing := ConsentForm.new(8)
	missing.show(closed)
	await process_frame
	check(errors[-1].error_code == -1 and errors[-2].error_code == -1 and dismissed.back().error_code == -1, "Missing plugins must return errors instead of hanging")
	forms.clear()
	print("UMP smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
