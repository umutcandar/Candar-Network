# res://FirebaseClient.gd
extends Node

const REGION := "europe-west1"

var api_key := "AIzaSyCikHaR1YfQ5-C2YH-7T8MzjL_HKODyF_Q"
var project_id := "candar-network-007"

var id_token: String = ""
var refresh_token: String = ""
var uid: String = ""

func _ready() -> void:
	var g := _get_global()
	if g:
		if g.has_method("get_id_token"):
			id_token = String(g.get_id_token())
		if g.has_method("get_uid"):
			uid = String(g.get_uid())

	# Apple Sign-In plugin sinyalini bağla (Godot 4.x uyumlu)
	if Engine.has_singleton("AppleSignIn"):
		var apple = Engine.get_singleton("AppleSignIn")
		if not apple.is_connected("sign_in_completed", Callable(self, "_on_apple_sign_in_completed")):
			apple.connect("sign_in_completed", Callable(self, "_on_apple_sign_in_completed"))

		
func _get_global() -> Node:
	return get_node_or_null("/root/Global")

func set_tokens(_id_token: String, _refresh_token: String, _uid: String) -> void:
	id_token = _id_token
	refresh_token = _refresh_token
	uid = _uid

# ====================== ORTAK HTTP / AUTH ======================

func _auth_headers() -> Array:
	var headers: Array = ["Content-Type: application/json"]

	var g := _get_global()
	var token := ""

	if g and g.has_method("get_id_token"):
		token = String(g.get_id_token())
	if token == "" and id_token != "":
		token = id_token

	if token != "":
		headers.append("Authorization: Bearer %s" % token)

	return headers

func _http_json(
		url: String,
		method: int = HTTPClient.METHOD_GET,
		headers: Array = [],
		body: String = ""
	) -> Array:

	var g := _get_global()
	if g and g.has_method("http_request"):
		# Global.http_request -> [ok:bool, status:int, data:Variant]
		return await g.http_request(url, method, headers, body)

	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)

	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return [false, 0, "HTTP başlatma hatası: %s" % err]

	# BURADA := YOK, normal =
	var result = await req.request_completed
	req.queue_free()

	if result.size() < 4:
		return [false, 0, "HTTP sonucu eksik"]

	var status_code: int = result[1]
	var raw_body: PackedByteArray = result[3]
	var text := raw_body.get_string_from_utf8()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err == OK:
		return [true, status_code, json.data]
	else:
		# JSON değilse düz text dön
		return [true, status_code, text]

# ====================== CALLABLE FUNCTIONS ======================

func _friendly_function_error(status: int, payload: Variant) -> String:
	var text := str(payload)
	var lower := text.to_lower()
	if status in [500, 502, 503, 504] or lower.find("not available") != -1 or lower.find("billing") != -1:
		return "Sunucu servisi şu anda kullanılamıyor. Lütfen biraz sonra tekrar deneyin."
	if typeof(payload) == TYPE_DICTIONARY:
		if payload.has("error"):
			var err_val = payload["error"]
			if typeof(err_val) == TYPE_DICTIONARY and err_val.has("message"):
				return str(err_val["message"])
			return str(err_val)
		if payload.has("message"):
			return str(payload["message"])
	if text.strip_edges() != "":
		return text
	return "Sunucu yanıtı alınamadı."

func _call_fn_raw(fn_name: String, data: Dictionary) -> Dictionary:
	var url := "https://%s-%s.cloudfunctions.net/%s" % [REGION, project_id, fn_name]
	var g := _get_global()
	if g and g.has_method("ensure_token_fresh"):
		await g.ensure_token_fresh(120)
	var headers := _auth_headers()
	var body_dict := {"data": data}
	var body_str := JSON.stringify(body_dict)

	# BURADA DA := YOK
	var res = await _http_json(url, HTTPClient.METHOD_POST, headers, body_str)

	var out := {
		"ok": false,
		"status": 0,
		"data": {},
		"error": ""
	}

	if res.size() < 3:
		out["error"] = "Ağ hatası"
		return out

	var ok := bool(res[0])
	var status := int(res[1])
	# := YOK
	var payload = res[2]
	out["status"] = status

	if not ok:
		out["error"] = _friendly_function_error(status, payload)
		return out

	if typeof(payload) == TYPE_DICTIONARY and payload.has("error"):
		out["error"] = _friendly_function_error(status, payload)
		return out

	# := YOK
	var data_out = payload
	if typeof(payload) == TYPE_DICTIONARY:
		if payload.has("data"):
			data_out = payload["data"]
		elif payload.has("result"):
			data_out = payload["result"]

	out["data"] = data_out
	out["ok"] = status >= 200 and status < 300

	if not out["ok"]:
		out["error"] = _friendly_function_error(status, payload if typeof(payload) == TYPE_DICTIONARY else data_out)

	return out

func _on_apple_sign_in_completed(result: Dictionary):
	if not result.get("success", false):
		push_error("Apple login failed")
		return

	var identity_token = result.get("identity_token")
	var auth_code = result.get("authorization_code")

	_firebase_sign_in_with_apple(identity_token, auth_code)
	
func _firebase_sign_in_with_apple(identity_token: String, auth_code: String) -> void:
	var body_dict := {
		"postBody": "id_token=%s&providerId=apple.com" % identity_token,
		"requestUri": "http://localhost",
		"returnSecureToken": true
	}
	var body_str := JSON.stringify(body_dict)

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % api_key
	var res = await _http_json(url, HTTPClient.METHOD_POST, ["Content-Type: application/json"], body_str)

	# res = [ok(bool), status(int), data(Variant)]
	if res.size() < 3 or not bool(res[0]) or int(res[1]) < 200 or int(res[1]) >= 300:
		push_error("Firebase Apple sign-in failed: " + str(res))
		return

	var data = res[2]
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Firebase Apple sign-in unexpected response: " + str(data))
		return

	# Tokenları set et (Firebase response: idToken, refreshToken, localId)
	var idt := str(data.get("idToken", ""))
	var rft := str(data.get("refreshToken", ""))
	var u := str(data.get("localId", ""))

	if idt != "" and u != "":
		set_tokens(idt, rft, u)

		# Global'a da bas (projende oturum oradan yönetiliyor)
		var g := _get_global()
		if g and g.has_method("set_tokens"):
			g.set_tokens(idt, rft, u)

func chat_send(data: Variant) -> Dictionary:
	var payload: Dictionary = {}

	# Eski kullanım: chat_send("sadece metin")
	if typeof(data) == TYPE_STRING:
		payload = {
			"prompt": String(data)
		}
	# Yeni kullanım: chat_send({"prompt": "...", "lang": "tr_TR"})
	elif typeof(data) == TYPE_DICTIONARY:
		payload = data
	else:
		return {
			"ok": false,
			"error": "chat_send: Geçersiz parametre tipi",
			"status": 0
		}

	var raw := await _call_fn_raw("chat_send", payload)

	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "chat_send hatası"),
		"status": raw.get("status", 0)
	}

func verify_and_apply_boost(platform: String, product_id: String, receipt: String, client_version: String = "", transaction_id: String = "") -> Dictionary:
	var payload := {
		"platform": platform,
		"productId": product_id,
		"receipt": receipt,
		"clientVersion": client_version,
		"transactionId": transaction_id,
	}
	var raw := await _call_fn_raw("verify_and_apply_boost", payload)

	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "verify_and_apply_boost hatası"),
		"status": raw.get("status", 0)
	}

func ensure_user_profile(email: String = "", referral_code: String = "") -> Dictionary:
	var raw := await _call_fn_raw("ensure_user_profile", {
		"email": email,
		"referralCode": referral_code
	})

	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "ensure_user_profile hatası"),
		"status": raw.get("status", 0)
	}

func get_referrals() -> Dictionary:
	var raw := await _call_fn_raw("get_referrals", {})
	if raw["ok"]:
		var d: Dictionary = raw["data"] if typeof(raw["data"]) == TYPE_DICTIONARY else {}
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "get_referrals hatası"),
		"status": raw.get("status", 0)
	}

func get_point_rewards() -> Dictionary:
	var raw := await _call_fn_raw("get_point_rewards", {})
	if raw["ok"]:
		var d: Dictionary = raw["data"] if typeof(raw["data"]) == TYPE_DICTIONARY else {}
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "Puan kullanım merkezi yüklenemedi."),
		"status": raw.get("status", 0)
	}

func redeem_point_reward(reward_id: String) -> Dictionary:
	var raw := await _call_fn_raw("redeem_point_reward", {"rewardId": reward_id})
	if raw["ok"]:
		var d: Dictionary = raw["data"] if typeof(raw["data"]) == TYPE_DICTIONARY else {}
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "Puan avantajı etkinleştirilemedi."),
		"status": raw.get("status", 0)
	}

func get_leaderboard(limit: int = 25) -> Dictionary:
	var raw := await _call_fn_raw("get_leaderboard", {"limit": clampi(limit, 1, 80)})
	if raw["ok"]:
		var d: Dictionary = raw["data"] if typeof(raw["data"]) == TYPE_DICTIONARY else {}
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "get_leaderboard hatası"),
		"status": raw.get("status", 0)
	}

func delete_account() -> Dictionary:
	var raw := await _call_fn_raw("delete_account", {})
	if raw["ok"]:
		var d: Dictionary = raw["data"] if typeof(raw["data"]) == TYPE_DICTIONARY else {}
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "Hesap silinemedi."),
		"status": raw.get("status", 0)
	}

func track_event(event_name: String, params: Dictionary, client_id: String) -> void:
	call_deferred("_track_event_async", event_name, params, client_id)

func track_event_confirmed(event_name: String, params: Dictionary, client_id: String) -> Dictionary:
	var raw := await _call_fn_raw("track_event", {
		"eventName": event_name,
		"params": params,
		"clientId": client_id
	})
	if raw["ok"]:
		return {"ok": true}
	return {
		"ok": false,
		"error": raw.get("error", "Ölçüm gönderilemedi."),
		"status": raw.get("status", 0)
	}

func _track_event_async(event_name: String, params: Dictionary, client_id: String) -> void:
	var raw := await _call_fn_raw("track_event", {
		"eventName": event_name,
		"params": params,
		"clientId": client_id
	})
	if not raw["ok"]:
		push_warning("[ANALYTICS] Backend event failed: %s" % raw.get("error", "unknown"))

# ====================== İŞLEVLER ======================

func apply_premium(platform: String, product_id: String, receipt: String, client_version: String = "", transaction_id: String = "") -> Dictionary:
	var payload := {
		"platform": platform,
		"productId": product_id,
		"receipt": receipt,
		"clientVersion": client_version,
		"transactionId": transaction_id,
	}
	var raw := await _call_fn_raw("apply_premium", payload)

	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "apply_premium hatası"),
		"status": raw.get("status", 0)
	}

func apply_rewarded_boost(attempt_at: int = 0) -> Dictionary:
	var payload := {}
	if attempt_at > 0:
		payload["attempt_at"] = attempt_at
	var raw := await _call_fn_raw("apply_rewarded_boost", payload)
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		if not d.has("ok"):
			d["ok"] = true
		return d

	var error_payload := {
		"ok": false,
		"error": raw.get("error", "apply_rewarded_boost hatası"),
		"status": raw.get("status", 0)
	}
	if typeof(raw.get("data", {})) == TYPE_DICTIONARY:
		for key in raw["data"].keys():
			if not error_payload.has(key):
				error_payload[key] = raw["data"][key]
	return error_payload

func reserve_rewarded_boost_attempt() -> Dictionary:
	var raw := await _call_fn_raw("reserve_rewarded_boost_attempt", {})
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		if not d.has("ok"):
			d["ok"] = true
		return d

	var error_payload := {
		"ok": false,
		"error": raw.get("error", "Reklam deneme hakkı ayrılamadı."),
		"status": raw.get("status", 0)
	}
	if typeof(raw.get("data", {})) == TYPE_DICTIONARY:
		for key in raw["data"].keys():
			if not error_payload.has(key):
				error_payload[key] = raw["data"][key]
	return error_payload

func do_mining() -> Dictionary:
	var raw := await _call_fn_raw("do_mining", {})
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "do_mining hatası"),
		"status": raw.get("status", 0)
	}

func sync_achievements() -> Dictionary:
	var raw := await _call_fn_raw("sync_achievements", {})
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d
	return {
		"ok": false,
		"error": raw.get("error", "sync_achievements hatası"),
		"status": raw.get("status", 0)
	}

func apply_referral(referral_code: String) -> Dictionary:
	var raw := await _call_fn_raw("apply_referral", {
		"referralCode": referral_code
	})
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		if not d.has("ok"):
			d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "apply_referral hatası"),
		"status": raw.get("status", 0)
	}

func recalc_multiplier() -> Dictionary:
	var raw := await _call_fn_raw("recalc_multiplier", {})
	if raw["ok"]:
		var d := {}
		if typeof(raw["data"]) == TYPE_DICTIONARY:
			d = raw["data"]
		d["ok"] = true
		return d

	return {
		"ok": false,
		"error": raw.get("error", "recalc_multiplier hatası"),
		"status": raw.get("status", 0)
	}

func sign_in_with_apple_ios():
	if not Engine.has_singleton("AppleSignIn"):
		push_error("AppleSignIn plugin not found")
		return

	var apple = Engine.get_singleton("AppleSignIn")
	apple.sign_in()
