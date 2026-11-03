extends Node
var mining_rate := 1.0
var reset_calls := 0
var delete_calls := 0
var fail_load := false
var leaderboard_delay := 0.05
var ad_free := false
var events: Array = []
var data := {
 "email": {"stringValue": "candar.ornek.kullanici@example.com"},
 "points": {"doubleValue": 12345.67}, "referralCode": {"stringValue": "CANDAR26"},
 "referralCount": {"integerValue": "12"}, "xp": {"integerValue": "350"},
 "achievements": {"arrayValue": {"values": [{"stringValue": "first_mining"}, {"stringValue": "first_referral"}]}},
 "isPremium": {"booleanValue": true}, "premiumExpiresAt": {"timestampValue": "2020-01-01T00:00:00Z"},
 "currentMultiplier": {"doubleValue": 2.0}, "boostExpiresAt": {"timestampValue": "2020-01-01T00:00:00Z"},
 "pointsAdFreeUntil": {"timestampValue": "2020-01-01T00:00:00Z"},
 "aiBonusCredits": {"integerValue": "3"}
}
func analytics_page(_a, _b): pass
func analytics_event(a, b): events.append([a,b])
func apply_safe_area(_ctrl): pass
func is_ad_free_user() -> bool: return ad_free
func sync_point_entitlements(_fields): pass
func ads_hide_banner(): pass
func ads_set_banner_allowed(_allowed): pass
func get_user_doc(_uid):
 await get_tree().process_frame
 return {} if fail_load else {"fields": data.duplicate(true)}
func check_and_unlock_achievements(_uid) -> Array: return [true, []]
func get_users_by_referral(_code) -> Array: return []
func get_user_mining_rate_components(_uid, _fields) -> Dictionary: return {"ref_count": 12, "total_rate": 1.6}
func get_xp_progress(_xp) -> Dictionary: return {"level": 3, "current_xp": 50, "needed_xp": 150}
func get_users_sample(_limit) -> Array:
 await get_tree().create_timer(leaderboard_delay).timeout
 return [{"fields": data.duplicate(true)}]
func get_leaderboard_top(limit) -> Array: return await get_users_sample(limit)
func share_invite_text(_text, _title, _url) -> bool: return true
func send_password_reset(_mail) -> Array:
 reset_calls += 1
 await get_tree().create_timer(0.1).timeout
 return [false, "TEST_FAILURE"]
func delete_my_account() -> Array:
 delete_calls += 1
 await get_tree().create_timer(0.1).timeout
 return [false, "TEST_FAILURE"]
func logout(): pass
