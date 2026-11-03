extends SceneTree
class NativeATT extends RefCounted:
	var status := 0
	var answer = 2
	var requests := 0
	func get_status() -> int: return status
	func request():
		requests += 1
		return answer
class VoidATT extends RefCounted:
	var status := 0
	func get_status() -> int: return status
	func request() -> void: status = 2
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var manager = load("res://att.gd").new()
	root.add_child(manager)
	check(await manager.request_att_permission() == -1, "Absent bridge must not fabricate tracking authorization")
	var native := NativeATT.new()
	manager.native = native
	native.status = 3
	check(await manager.request_att_permission() == 3 and native.requests == 0, "Existing native grant should not prompt again")
	native.status = 2
	check(await manager.request_att_permission() == 2 and native.requests == 0, "Settings revocation must replace a prior grant")
	native.status = 1
	check(await manager.request_att_permission() == 1 and native.requests == 0, "Restricted tracking must not prompt")
	native.status = 0
	native.answer = [2]
	check(await manager.request_att_permission() == 2 and native.requests == 1, "Request array result must be honored")
	native.answer = 3
	check(await manager.request_att_permission() == 3, "Explicit native grant must be honored")
	native.answer = null
	check(await manager.request_att_permission() == 0, "Missing request result must not become authorized")
	native.answer = true
	check(await manager.request_att_permission() == 0, "Boolean request result is not an ATT enum")
	native.status = 99
	native.answer = 99
	check(await manager.request_att_permission() == -1, "Out-of-range results must remain unknown")
	manager.native = VoidATT.new()
	check(await manager.request_att_permission() == 2, "Void bridge must reread system status after request")
	manager.ios = false
	check(await manager.request_att_permission() == -1, "Non-iOS runtime must not request ATT")
	manager.free()
	print("ATT smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
