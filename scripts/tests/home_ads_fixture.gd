extends Node

var banner_allowed := false
var ad_free := false
var premium := false
var ad_ready := true
var init_calls := 0
var banner_requests := 0
var status_calls := 0
var status_finished := 0
var reserve_calls := 0
var show_calls := 0
var apply_calls := 0
var mining_rate := 1.0
var status: Dictionary = {"can_apply": true}
var reservation: Dictionary = {"ok": false, "error": "rewarded_boost_attempt_service_unavailable"}
var complete_reward := false
var events: Array = []

func ads_init_after_att(_a, _b, _c, _d, _e, _f) -> void:
	init_calls += 1
	await get_tree().process_frame
func ads_set_banner_allowed(allowed: bool) -> void:
	banner_allowed = allowed
func ads_on_focus_in() -> void:
	if banner_allowed and not ad_free:
		banner_requests += 1
func is_ad_free_user() -> bool: return ad_free
func is_user_premium() -> bool: return premium
func analytics_event(name: String, data: Dictionary) -> void: events.append([name, data])
func get_rewarded_boost_status(_uid: String) -> Dictionary:
	status_calls += 1
	await get_tree().create_timer(0.02).timeout
	status_finished += 1
	return status.duplicate(true)
func ads_load_rewarded() -> void: pass
func ads_has_rewarded_ready() -> bool: return ad_ready
func reserve_rewarded_boost_attempt() -> Dictionary:
	reserve_calls += 1
	await get_tree().create_timer(0.03).timeout
	return reservation.duplicate(true)
func is_rewarded_boost_limit_error(code: String) -> bool:
	return code == "rewarded_boost_daily_attempt_limit"
func ads_show_rewarded_and_wait(_timeout: float, _uid: String, _attempt_at: int) -> bool:
	show_calls += 1
	await get_tree().create_timer(0.03).timeout
	return complete_reward
func ads_get_last_rewarded_result() -> Dictionary:
	return {"reason": "dismissed_without_reward", "duration_ms": 30}
func activate_rewarded_boost(_uid: String, _attempt_at: int) -> Array:
	apply_calls += 1
	return [true, {"rewarded_multiplier": 1.05, "total_rate": 1.05}]
func get_user_doc(_uid: String) -> Dictionary: return {"fields": {}}
