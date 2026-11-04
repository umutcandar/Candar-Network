	# global.gd — PKCE'li Google ile Giriş + Firebase + Firestore + Kalıcı Oturum
	# Godot 4.5 (GDScript 2.0). Girintiler: TAB veya boşluk, karıştırma :)
extends Node

	# ======================================================================
	#                               A Y A R L A R
	# ======================================================================

	# --------------------------- Firebase ---------------------------
var firebase_api_key := "AIzaSyCikHaR1YfQ5-C2YH-7T8MzjL_HKODyF_Q"
var rest_url := "https://identitytoolkit.googleapis.com/v1"
var firestore_url := "https://firestore.googleapis.com/v1/projects/candar-network-007/databases/(default)/documents/users"

	# Cloud Functions (do_mining, buy_product, vs.)
var FUNCTIONS_BASE_URL := "https://europe-west1-candar-network-007.cloudfunctions.net"

# Oyun/uygulama iş mantığı
var mining_rate := 0.80
signal rewarded_boost_applied(payload: Dictionary)

	# OAuth callback'ı manuel okumak için opsiyonel dosya
var _oauth_file := "user://oauth_callback.txt"
var _state_file := "user://oauth_state.json"

# Legacy plain-text path is migration-only; never written to again.
const _REFRESH_PATH := "user://refresh_token.txt"
const _SECURE_REQUEST_PATH := "user://secure_session_request.json"
const _SECURE_RESPONSE_PATH := "user://secure_session_response.json"
var _secure_session_in_flight := false
const APP_LINK_ANDROID := "https://play.google.com/store/apps/details?id=com.candarnetwork.app"
const APP_LINK_IOS := "https://apps.apple.com/app/id6756212781"
const APP_DOWNLOAD_LINK := "https://candarnetwork.com/download"
const _REVIEW_PROMPT_STATE_PATH := "user://review_prompt.cfg"
const _REVIEW_PROMPT_MIN_POSITIVE_ACTIONS := 3
const _REVIEW_PROMPT_COOLDOWN_SECONDS := 2592000
const _FIRST_OPEN_STATE_PATH := "user://first_open.cfg"
const _PENDING_REFERRAL_PATH := "user://pending_referral.txt"
const _PENDING_REFERRAL_MAX_AGE_SECONDS := 7 * 24 * 60 * 60

	# --------------------------- Google OAuth (PKCE) ---------------------------
var google_client_id_desktop: String = "170015852669-ud5822ia7r7uekjohjk7ntfp7kji5ljb.apps.googleusercontent.com"
var google_client_id_ios: String      = "170015852669-362693n16e88llrtodo6f0b9saem6fp4.apps.googleusercontent.com"
var google_client_id_android: String  = "170015852669-51tflachltnpt11p8fuv8ldv5s5442gt.apps.googleusercontent.com"
var google_client_id_web: String      = "170015852669-prptidbs6sff1d8thfn86vjrnmt54p3g.apps.googleusercontent.com"
# PKCE public istemcide client secret gerektirmez. Mobil/masaüstü pakete gömülü
# bir secret zaten gizli sayılamaz; token değişiminde kullanılmamalıdır.
var google_client_secret_desktop: String = ""

	# Redirect URI'ler
var google_redirect_uri_desktop_default: String = "http://127.0.0.1:8765/callback" # fallback
var google_redirect_uri_ios: String     = "com.googleusercontent.apps.170015852669-362693n16e88llrtodo6f0b9saem6fp4:/oauthredirect"
var google_redirect_uri_android: String = "com.googleusercontent.apps.170015852669-51tflachltnpt11p8fuv8ldv5s5442gt:/oauthredirect"
var google_redirect_uri_web: String     = "https://auth.candar.network/callback"

var google_auth_url: String = "https://accounts.google.com/o/oauth2/v2/auth"
var google_token_url: String = "https://oauth2.googleapis.com/token"
var google_scopes: String = "openid email profile"

	# Desktop'ta dinamik portla oluşan runtime redirect
var _desktop_redirect_uri_runtime: String = ""

	# ======================================================================
	#                           D A H İ L   D U R U M
	# ======================================================================

	# PKCE / redirect yakalama
var _tcp_server: TCPServer = TCPServer.new()
var _code_verifier: String = ""
var _state_token: String = ""
var _app_redirect_url: String = ""  # iOS/Android native taraftan set edilecek (openURL/Intent)

	# Oturum bilgisi
var _current_uid: String = ""
var _firebase_id_token: String = ""  # Firebase idToken (Bearer için)
var _firebase_refresh_token: String = ""  # Firebase refreshToken (cache)
var _is_signed_in := false
var _last_error: String = ""
var pending_referral_code: String = ""

# Ağ/tekrar deneme
var _max_retries := 2
var _retry_backoff_ms := 500
func _gsi_log(msg: String) -> void:
	var t := Time.get_datetime_string_from_system()
	print("[GSI][%s] %s" % [t, msg])

	# ======================================================================
	#                               Y A R D I M C I L A R
	# ======================================================================
func _ready() -> void:
	# User preference overrides the device locale after the first explicit choice.
	current_lang = _determine_initial_lang()
	TranslationServer.set_locale(current_lang)
	_load_ui_locales()
	print("CURRENT LANG = ", current_lang, " | OS locale = ", OS.get_locale())

	# --- MEVCUT INIT KODLARIN ---
	_current_uid = get_uid()
	_clear_oauth_file()
	print("[OAUTH] platform=", _platform_kind(), " user_data_dir=", OS.get_user_data_dir())
	call_deferred("_track_first_open_once")
	call_deferred("_poll_native_launch_url")

	# Yarım kalan akış varsa state/verifier’ı yükle
	_load_oauth_state()

	# Deeplink plugin / autoload bağla
	_find_and_bind_deeplink()

		# Ağ testi
	await _probe_network()

		# Oturumu geri yüklemeyi dene ve periyodik token yenileme başlat
	await try_restore_session()
	await _apply_pending_referral_if_signed_in()
	_start_token_refresh_timer()
	_start_deeplink_plugin_if_needed()

func _current_client_id() -> String:
	var p := _platform_kind()
	if p == "ios":
		return google_client_id_ios
	if p == "android":
		return google_client_id_android
	if p == "web":
		return google_client_id_web
	return google_client_id_desktop

func _current_redirect_uri() -> String:
	var p := _platform_kind()
	if p == "ios":
		return google_redirect_uri_ios
	if p == "android":
		return google_redirect_uri_android
	if p == "web":
		return google_redirect_uri_web
	if _desktop_redirect_uri_runtime != "":
		return _desktop_redirect_uri_runtime
	return google_redirect_uri_desktop_default

func _platform_kind() -> String:
	var n := OS.get_name()
	if n == "iOS":
		return "ios"
	if n == "Android":
		return "android"
	if n == "Web":
		return "web"
	return "desktop"
func _start_deeplink_plugin_if_needed() -> void:
	for n in ["DeeplinkPlugin", "Deeplink", "DeepLinkPlugin", "DeepLink"]:
		if Engine.has_singleton(n):
			var s = Engine.get_singleton(n)
			for m in ["start", "Start", "initialize", "init"]:
				if s.has_method(m):
					var argc = s.get_method_argument_count(m)
					print("[DEEPLINK] calling ", n, ".", m, " argc=", argc)
					if argc == 0:
						s.call(m)
					else:
						# bazıları launchOptions ister; boş geç
						s.call(m, {})
					return

	# --------- Deeplink köprüsü ---------

func _get_deeplink_autoload() -> Variant:
	if has_node("/root/DeeplinkRouter"):
		return get_node("/root/DeeplinkRouter")
	if has_node("/root/DeeplinkSingleton"):
		return get_node("/root/DeeplinkSingleton")
	if has_node("/root/Deeplink"):
		return get_node("/root/Deeplink")
	return null

func _find_and_bind_deeplink() -> void:
	var candidate_names := ["DeeplinkPlugin", "Deeplink", "DeepLinkPlugin", "DeepLink"]
	for n in candidate_names:
		if Engine.has_singleton(n):
			var s = Engine.get_singleton(n)
			var signals := ["deeplink_received", "deep_link_received", "url_received", "on_deep_link"]
			for sig in signals:
				if s.has_signal(sig):
					s.connect(sig, Callable(self, "_on_deep_link"))
					print("[DEEPLINK] singleton found:", n, " signal:", sig)
					return
			var getters := ["get_last_deep_link", "get_last_link", "get_deep_link", "last_link"]
			for m in getters:
				if s.has_method(m):
					var u := str(s.call(m))
					if u != "":
						print("[DEEPLINK] got last link from singleton:", u)
						handle_oauth_redirect(u)
			print("[DEEPLINK] singleton found but no known signal; relying on autoload if any.")
			return
	print("[DEEPLINK] singleton NOT found (plugin devre dışı ya da Custom Build yok).")

func _on_deep_link(payload) -> void:
	var url := ""

	if typeof(payload) == TYPE_DICTIONARY:
		var scheme := str(payload.get("scheme", ""))
		var host := str(payload.get("host", "")) # <<< ÖNEMLİ
		var path := str(payload.get("path", ""))
		var query := str(payload.get("query", ""))

		# bazı pluginler "url" direkt verir
		if payload.has("url") and str(payload["url"]) != "":
			url = str(payload["url"])
		else:
			# host varsa candar://google_signin formatını koru
			if scheme != "" and host != "":
				url = "%s://%s" % [scheme, host]
				# path '/' değilse ekle
				if path != "" and path != "/":
					if not path.begins_with("/"):
						path = "/" + path
					url += path
			elif scheme != "":
				# fallback
				if path != "" and not path.begins_with("/"):
					path = "/" + path
				url = "%s:%s" % [scheme, path]

			if query != "":
				url += "?" + query

	elif typeof(payload) == TYPE_STRING:
		url = String(payload)

	elif payload != null and payload.has_method("get_data"):
		var data: Variant = payload.call("get_data")
		if typeof(data) == TYPE_DICTIONARY:
			_on_deep_link(data)
			return

	elif payload != null and payload.has_method("get_scheme"):
		var scheme := str(payload.call("get_scheme"))
		var host := str(payload.call("get_host")) if payload.has_method("get_host") else ""
		var path := str(payload.call("get_path")) if payload.has_method("get_path") else ""
		var query := str(payload.call("get_query")) if payload.has_method("get_query") else ""
		if scheme != "" and host != "":
			url = "%s://%s" % [scheme, host]
			if path != "" and path != "/":
				if not path.begins_with("/"):
					path = "/" + path
				url += path
		elif scheme != "":
			if path != "" and not path.begins_with("/"):
				path = "/" + path
			url = "%s:%s" % [scheme, path]
		if query != "":
			url += "?" + query

	else:
		push_error("[DEEPLINK] Beklenmeyen payload tipi: %s" % typeof(payload))
		return

	print("[DEEPLINK] on_deep_link url=", url)
	var referral_code := _extract_referral_code(url)
	if referral_code != "":
		set_pending_referral_code(referral_code)
		print("[DEEPLINK] referral captured")
		call_deferred("_apply_pending_referral_if_signed_in")

	# sadece OAuth redirect (code/state) ise handle et
	if url.find("code=") != -1 and url.find("state=") != -1:
		handle_oauth_redirect(url)

func _extract_referral_code(text: String) -> String:
	var re := RegEx.new()
	if re.compile("(?i)(?:candar_ref|ref|referral)(?:=|%3D)([A-Za-z0-9_-]{4,32})") != OK:
		return ""
	var found := re.search(text)
	if found == null:
		return ""
	return _clean_referral_code(found.get_string(1))

func _poll_native_launch_url() -> void:
	# iOS köprüsü Universal Link / özel şema URL'sini bu dosyaya yazar.
	# Plugin sinyali kaçsa bile soğuk başlangıç davet kodu böyle korunur.
	for attempt in range(24):
		var path := OS.get_user_data_dir() + "/launch_url.txt"
		if FileAccess.file_exists(path):
			var launch_url := FileAccess.get_file_as_string(path).strip_edges()
			DirAccess.remove_absolute(path)
			if launch_url != "":
				_on_deep_link(launch_url)
				return
		await get_tree().create_timer(0.25).timeout

func _clean_referral_code(value: String) -> String:
	var re := RegEx.new()
	if re.compile("^[A-Za-z0-9_-]{4,32}$") != OK:
		return ""
	var code := value.strip_edges()
	return code if re.search(code) != null else ""

func set_pending_referral_code(code: String) -> void:
	var clean_code := _clean_referral_code(code)
	if clean_code == "":
		return
	pending_referral_code = clean_code
	var f := FileAccess.open(_PENDING_REFERRAL_PATH, FileAccess.WRITE)
	if f:
		# Kaynağı ve zamanı olmayan eski/sabit kodların yeniden görünmesini önle.
		f.store_string(JSON.stringify({
			"code": clean_code,
			"source": "deep_link",
			"captured_at": int(Time.get_unix_time_from_system())
		}))
		f.close()

func get_pending_referral_code() -> String:
	if pending_referral_code != "":
		return pending_referral_code
	if FileAccess.file_exists(_PENDING_REFERRAL_PATH):
		var txt := FileAccess.get_file_as_string(_PENDING_REFERRAL_PATH).strip_edges()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			# Önceki sürümlerin düz metin/pano kaynaklı kodunu geçersiz say.
			clear_pending_referral_code()
			return ""
		var payload := parsed as Dictionary
		var captured_at := int(payload.get("captured_at", 0))
		var age := int(Time.get_unix_time_from_system()) - captured_at
		var source := str(payload.get("source", ""))
		if source not in ["deep_link", "install_referrer"] or captured_at <= 0 or age < 0 or age > _PENDING_REFERRAL_MAX_AGE_SECONDS:
			clear_pending_referral_code()
			return ""
		pending_referral_code = _clean_referral_code(str(payload.get("code", "")))
	return pending_referral_code

func clear_pending_referral_code() -> void:
	pending_referral_code = ""
	if FileAccess.file_exists(_PENDING_REFERRAL_PATH):
		DirAccess.remove_absolute(_PENDING_REFERRAL_PATH)

func _apply_pending_referral_if_signed_in() -> void:
	# Davet yalnızca onboarding sırasında oluşturulan yeni hesaba uygulanır.
	# Açık/mevcut oturuma sonradan kod bağlamak referans suistimaline yol açar.
	return

func share_invite_text(text: String, title: String, url: String = "") -> bool:
	if OS.has_feature("android") and Engine.has_singleton("AndroidSharePlugin"):
		var android_share = Engine.get_singleton("AndroidSharePlugin")
		if android_share and android_share.has_method("share"):
			var android_text := text
			if url != "" and android_text.find(url) == -1:
				android_text += "\n" + url
			android_share.share(android_text, title, "", "")
			return true
	if OS.has_feature("ios") and Engine.has_singleton("IosSharePlugin"):
		var ios_share = Engine.get_singleton("IosSharePlugin")
		if ios_share and ios_share.has_method("shareText"):
			ios_share.shareText(text, url)
			return true
	if OS.has_feature("ios") or OS.get_name() == "iOS":
		var request_path := OS.get_user_data_dir() + "/share_request.json"
		var request_file := FileAccess.open(request_path, FileAccess.WRITE)
		if request_file:
			request_file.store_string(JSON.stringify({
				"text": text,
				"title": title,
				"url": url,
				"ts": int(Time.get_unix_time_from_system())
			}))
			request_file.close()
			return true
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var clipboard_text := text
		if url != "" and clipboard_text.find(url) == -1:
			clipboard_text += "\n" + url
		DisplayServer.clipboard_set(clipboard_text)
	return false

func _save_oauth_state() -> void:
	var payload := {
		"state": _state_token,
		"verifier": _code_verifier,
		"ts": Time.get_unix_time_from_system()
	}
	var f := FileAccess.open(_state_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
	f.close()

func _load_oauth_state() -> bool:
	if not FileAccess.file_exists(_state_file):
		return false

	var f := FileAccess.open(_state_file, FileAccess.READ)
	if f == null:
		return false

	var txt := f.get_as_text()
	f.close()

	var j := JSON.new()
	if j.parse(txt) != OK:
		return false

	if typeof(j.data) != TYPE_DICTIONARY:
		return false

	var d: Dictionary = j.data
	if d.has("state"):
		_state_token = String(d["state"])
	if d.has("verifier"):
		_code_verifier = String(d["verifier"])

	return _state_token != "" and _code_verifier != ""

func _clear_oauth_state() -> void:
	if FileAccess.file_exists(_state_file):
		DirAccess.remove_absolute(_state_file)

	# ======================================================================
	#                         O A U T H   B E K L E M E
	# ======================================================================

	# iOS/Android native tarafı bu fonksiyonu çağırmalı (openURL / intent)
func handle_oauth_redirect(url: String) -> void:
	_app_redirect_url = url

func _clear_oauth_file() -> void:
	if FileAccess.file_exists(_oauth_file):
		DirAccess.remove_absolute(_oauth_file)

func _read_oauth_file_once() -> String:
	# 1. Öncelikli dosya kontrolü
	if FileAccess.file_exists(_oauth_file):
		print("[OAUTH] file exists at: ", _oauth_file)
		var f := FileAccess.open(_oauth_file, FileAccess.READ)
		if f:
			var url := f.get_as_text().strip_edges()
			f.close()
			DirAccess.remove_absolute(_oauth_file)
			print("[OAUTH] read url: ", url)
			return url

	# 2. iOS Fallback kontrolü (Ana dosya yoksa veya açılamadıysa buraya geçer)
	if _platform_kind() == "ios":
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if docs != "":
			var alt := docs.path_join("oauth_callback.txt")
			if FileAccess.file_exists(alt):
				print("[OAUTH] fallback file at: ", alt)
				var f2 := FileAccess.open(alt, FileAccess.READ)
				if f2:
					var url2 := f2.get_as_text().strip_edges()
					f2.close()
					DirAccess.remove_absolute(alt)
					print("[OAUTH] fallback url: ", url2)
					return url2

	# 3. Hiçbir dosya bulunamadıysa boş string dön
	return ""	# Desktop loopback: 8765 doluysa alternatif portları dener
func _prime_loopback_server_any() -> bool:
	if _tcp_server.is_listening():
		_tcp_server.stop()
	var ports := [8765, 8766, 53117, 53118, 53119, 53200, 53333]
	var i := 0
	while i < ports.size():
		var p := int(ports[i])
		var ok := _tcp_server.listen(p)
		if ok == OK:
			_desktop_redirect_uri_runtime = "http://127.0.0.1:%d/callback" % p
			print(">> OAuth loopback aktif: ", _desktop_redirect_uri_runtime)
			return true
		i += 1
	print(">> UYARI: loopback port acilamadi")
	return false

func _wait_oauth_code_desktop(timeout_sec: int) -> String:
	var code: String = ""

	# 1. Server dinlemiyorsa başlatmayı dene
	if not _tcp_server.is_listening():
		if not _prime_loopback_server_any():
			push_error("TCPServer listen basarisiz (loopback acilamadi)")
			return ""

	# 2. Döngüyü ana blok seviyesine çıkar (server zaten dinliyor olabilir)
	var start_ts := Time.get_unix_time_from_system()
	while Time.get_unix_time_from_system() - start_ts < timeout_sec:
		if _tcp_server.is_connection_available():
			var peer := _tcp_server.take_connection()
			peer.set_no_delay(true)

			var raw := ""
			# Veri gelene kadar çok kısa bekle (peer.is_connected kontrolü eklendi)
			while peer.get_available_bytes() > 0:
				raw += peer.get_utf8_string(peer.get_available_bytes())
				await get_tree().process_frame

			var first_line_end := raw.find("\r\n")
			var first_line := raw
			if first_line_end >= 0:
				first_line = raw.substr(0, first_line_end)

			var space1 := first_line.find(" ")
			var space2 := first_line.rfind(" ")
			var path := first_line
			if space1 >= 0 and space2 > space1:
				path = first_line.substr(space1 + 1, space2 - space1 - 1)

			var route := path
			var query := ""
			var qm := path.find("?")
			if qm >= 0:
				route = path.substr(0, qm)
				query = path.substr(qm + 1, path.length() - qm - 1)

			var got_state := ""
			if query != "":
				var pairs := query.split("&")
				var j := 0
				while j < pairs.size():
					var kv := String(pairs[j]).split("=")
					if kv.size() == 2:
						var kk := String(kv[0])
						var vv := String(kv[1]).uri_decode()
						if kk == "code":
							code = vv
						elif kk == "state":
							got_state = vv
					j += 1

			# Yanıt gönder
			var html := "<html><body style='font-family:sans-serif'>Google girişi tamamlandı. Uygulamaya dönebilirsin.</body></html>"
			var resp := "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: " + str(html.length()) + "\r\n\r\n" + html
			peer.put_utf8_string(resp)
			peer.disconnect_from_host()

			# Doğrulama başarılıysa server'ı kapat ve kodu dön
			if route == "/callback" and code != "" and got_state == _state_token:
				_tcp_server.stop()
				return code

		await get_tree().process_frame

	# Timeout olursa server'ı temizle
	_tcp_server.stop()
	return ""
	# Platforma göre authorization code bekle
func _wait_oauth_code(timeout_sec: int) -> String:
	var kind := _platform_kind()
	if kind == "ios" or kind == "android":
		print("[OAUTH] waiting oauth code on ", kind)
		var start := Time.get_unix_time_from_system()
		while Time.get_unix_time_from_system() - start < timeout_sec:
			var file_url := _read_oauth_file_once()
			if file_url != "":
				_app_redirect_url = file_url
			if _app_redirect_url != "":
				var u := _app_redirect_url
				_app_redirect_url = ""
				var qm := u.find("?")
				if qm >= 0:
					# query parse
					var q := u.substr(qm + 1, u.length() - (qm + 1))
					var parts := q.split("&")
					var code := ""
					var st := ""
					var i := 0
					while i < parts.size():
						var kv := String(parts[i]).split("=")
						if kv.size() == 2:
							var k := String(kv[0])
							var v := String(kv[1]).uri_decode()
							if k == "code":
								code = v
							elif k == "state":
								st = v
						i += 1
					if code != "" and st == _state_token:
						return code
			await get_tree().process_frame
		return ""
	else:
			return await _wait_oauth_code_desktop(timeout_sec)

	# ======================================================================
	#                           H T T P   H E L P E R
	# ======================================================================

func _safe_http_headers_for_log(headers: Array) -> Array:
	var safe_headers := []
	for h in headers:
		var header := String(h)
		if header.to_lower().begins_with("authorization:"):
			safe_headers.append("Authorization: Bearer ***")
		else:
			safe_headers.append(header)
	return safe_headers

func http_request(url, method := HTTPClient.METHOD_GET, headers := [], body := "", retries := _max_retries) -> Array:
	print(">> HTTP request method=", method, " (payload bytes=", body.to_utf8_buffer().size(), ")")
	var attempt := 0

	while attempt <= retries:
		var req := HTTPRequest.new()
		# HTTPRequest'in varsayılanı limitsiz beklemedir. Kötü/portal ağda giriş,
		# günlük ödül ve mağaza ekranlarının sonsuza dek yüklemede kalmasını önle.
		req.timeout = 15.0
		add_child(req)
		var error_code = req.request(url, headers, method, body)

		if error_code != OK:
			print(">> HTTP İSTEK BAŞLATMA HATASI: ", error_code, " (", error_string(error_code), ")")
			req.queue_free()
			if attempt < retries:
				await get_tree().create_timer(float(_retry_backoff_ms) / 1000.0).timeout
				attempt += 1
				continue

			var status_code_for_init_error := 500
			if error_code == ERR_TIMEOUT:
				status_code_for_init_error = 408
			elif error_code == ERR_CANT_CONNECT:
				status_code_for_init_error = 503
			return [false, status_code_for_init_error, "İstek baslatilamadi: " + error_string(error_code)]

		var response = await req.request_completed
		req.queue_free()

		var status = response[0]
		var response_code: int = int(response[1])
		var response_body_bytes = response[3]
		var response_text = response_body_bytes.get_string_from_utf8()

		print(">> HTTP response status=", response_code)

		if status == HTTPRequest.RESULT_SUCCESS:
			var json_parser = JSON.new()
			var parse_error = json_parser.parse(response_text)
			if parse_error != OK:
				print("JSON ayrıştırma hatası: ", json_parser.get_error_message())
				var rc := response_code
				if rc == 0: rc = 400
				return [false, rc, "JSON parse hatasi: " + json_parser.get_error_message()]
			return [true, response_code, json_parser.data]

		# HATA DURUMU: Başarısız bağlantı veya sunucu hatası
		print(">> HTTP BAĞLANTI HATASI: ", status, " (", error_string(status), ")")
		var effective_response_code: int = response_code
		if effective_response_code == 0:
			if status == HTTPRequest.RESULT_CANT_CONNECT: effective_response_code = 503
			elif status == HTTPRequest.RESULT_TIMEOUT: effective_response_code = 408
			elif status == HTTPRequest.RESULT_CONNECTION_ERROR: effective_response_code = 503
			elif status == HTTPRequest.RESULT_NO_RESPONSE: effective_response_code = 504
			else: effective_response_code = 500

		var should_retry := false
		if effective_response_code >= 500 or effective_response_code in [408, 503, 504]:
			should_retry = true

		if attempt < retries and should_retry:
			await get_tree().create_timer(float(_retry_backoff_ms) / 1000.0).timeout
			attempt += 1
			continue # Bir sonraki denemeye geç

		# Deneme hakkı bittiyse veya hata kalıcıysa (4xx gibi) hata dön
		return [false, effective_response_code, "HTTP hatasi: " + error_string(status) + " | Kod: " + str(effective_response_code)]

	return [false, 500, "Bilinmeyen HTTP hata"]
	# Firebase Bearer header
func _auth_headers() -> Array:
	var h: Array = ["Content-Type: application/json"]
	if _firebase_id_token != "":
		h.append("Authorization: Bearer %s" % _firebase_id_token)
	return h

	# Cloud Functions'a yetkili POST helper
func _authorized_post(url: String, body: Dictionary, callback: Callable) -> void:
	await ensure_token_fresh(120)

	var headers := _auth_headers()
	var json_body := JSON.stringify(body)
	var result: Array = await http_request(
		url,
		HTTPClient.METHOD_POST,
		headers,
		json_body
	)

	if callback.is_valid():
		callback.call(result)

	# ======================================================================
	#          Email / Parola ile Giriş & Kayıt (Firebase REST)
	# ======================================================================

func login_or_register(email: String, password: String, referral_code := ""):
	analytics_event("signup_start", {"method": "email"})
	if not _is_valid_email(email):
		analytics_event("signup_error", {"method": "email", "reason": "invalid_email"})
		return [false, "Geçerli bir e-posta adresi gir."]
	var reg_result = await register(email, password, referral_code)
	if reg_result[0]:
		analytics_event("signup_complete", {"method": "email"})
		return reg_result
	elif typeof(reg_result[1]) == TYPE_STRING and reg_result[1] == "EMAIL_EXISTS":
		var login_result = await login(email, password, referral_code)
		if login_result[0]:
			analytics_event("login_complete", {"method": "email"})
		else:
			analytics_event("signup_error", {"method": "email", "reason": "login_failed"})
		return login_result
	else:
		analytics_event("signup_error", {"method": "email", "reason": "register_failed"})
		return reg_result

func _is_valid_email(email: String) -> bool:
	var value := email.strip_edges().to_lower()
	if value.contains(" ") or value.contains("\n") or value.contains("\t"):
		return false
	var at := value.find("@")
	if at <= 0 or at != value.rfind("@"):
		return false
	var domain := value.substr(at + 1)
	var dot := domain.rfind(".")
	if dot <= 0 or dot >= domain.length() - 1:
		return false
	return value.length() <= 254

func _lookup_account(id_token: String) -> Dictionary:
	if id_token == "":
		return {}
	var url = "%s/accounts:lookup?key=%s" % [rest_url, firebase_api_key]
	var body = JSON.stringify({ "idToken": id_token })
	var result: Array = await http_request(url, HTTPClient.METHOD_POST, ["Content-Type: application/json"], body)
	if result[0] and int(result[1]) == 200 and typeof(result[2]) == TYPE_DICTIONARY:
		var users: Variant = result[2].get("users", [])
		if typeof(users) == TYPE_ARRAY and users.size() > 0 and typeof(users[0]) == TYPE_DICTIONARY:
			return users[0]
	return {}

func _is_email_password_account(account: Dictionary) -> bool:
	var providers: Variant = account.get("providerUserInfo", [])
	if typeof(providers) != TYPE_ARRAY or providers.is_empty():
		return true
	for provider in providers:
		if typeof(provider) != TYPE_DICTIONARY:
			continue
		var provider_id := str(provider.get("providerId", ""))
		if provider_id == "google.com" or provider_id == "apple.com":
			return false
		if provider_id == "password":
			return true
	return true

func register(email: String, password: String, referral_code := ""):
	if not _is_valid_email(email):
		return [false, "Geçerli bir e-posta adresi gir."]
	var url = "%s/accounts:signUp?key=%s" % [rest_url, firebase_api_key]
	var data = {
		"email": email,
		"password": password,
		"returnSecureToken": true
	}
	var body = JSON.stringify(data)
	var result: Array = await http_request(url, HTTPClient.METHOD_POST, ["Content-Type: application/json"], body)
	if result[0]:
		var response_code: int = int(result[1])
		var res_data = result[2]
		if response_code == 200:
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("idToken"):
				_firebase_id_token = str(res_data["idToken"])
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("refreshToken"):
				await _save_refresh_token(String(res_data["refreshToken"]))
			_is_signed_in = true
			await save_uid(str(res_data["localId"]))
			var user_doc_ok := await ensure_user_doc(str(res_data["localId"]), email, referral_code)
			if not user_doc_ok:
				return [false, "Hesap açıldı ama profil oluşturulamadı. Lütfen tekrar giriş yap."]
			return [true, res_data]
		else:
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("error") and res_data["error"].has("message"):
				var err_msg = res_data["error"]["message"]
				return [false, err_msg]
			return [false, "Bilinmeyen kayıt hatası"]
	else:
		return [false, result[2]]

func login(email: String, password: String, referral_code := ""):
	if not _is_valid_email(email):
		return [false, "Geçerli bir e-posta adresi gir."]
	var url = "%s/accounts:signInWithPassword?key=%s" % [rest_url, firebase_api_key]
	var data = {
		"email": email,
		"password": password,
		"returnSecureToken": true
	}
	var body = JSON.stringify(data)
	var result: Array = await http_request(url, HTTPClient.METHOD_POST, ["Content-Type: application/json"], body)
	if result[0]:
		var response_code: int = int(result[1])
		var res_data = result[2]
		if response_code == 200:
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("idToken"):
				_firebase_id_token = str(res_data["idToken"])
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("refreshToken"):
				await _save_refresh_token(String(res_data["refreshToken"]))
			_is_signed_in = true
			await save_uid(res_data["localId"])
			# Var olan hesaba sonradan referans bağlanmaz.
			var user_doc_ok := await ensure_user_doc(str(res_data["localId"]), email, "")
			if not user_doc_ok:
				return [false, "Giriş başarılı ama profil yüklenemedi. Lütfen tekrar dene."]
			clear_pending_referral_code()
			return [true, res_data]
		else:
			if typeof(res_data) == TYPE_DICTIONARY and res_data.has("error") and res_data["error"].has("message"):
				var err_msg = res_data["error"]["message"]
				return [false, err_msg]
			return [false, "Bilinmeyen giriş hatası"]
	else:
		return [false, result[2]]

func send_password_reset(email: String) -> Array:
	if not _is_valid_email(email):
		return [false, "Geçerli bir e-posta adresi gir."]
	var url = "%s/accounts:sendOobCode?key=%s" % [rest_url, firebase_api_key]
	var data = { "requestType": "PASSWORD_RESET", "email": email }
	var body = JSON.stringify(data)
	var result: Array = await http_request(url, HTTPClient.METHOD_POST, ["Content-Type: application/json"], body)
	if result[0] and int(result[1]) == 200:
		return [true, "Şifre sıfırlama maili gönderildi!"]
	else:
		var errmsg := "bilinmiyor"
		if result.size() >= 3:
			errmsg = str(result[2])
		return [false, "Şifre sıfırlama başarısız: " + errmsg]

	# ======================================================================
	#                               F I R E S T O R E
	# ======================================================================

func save_new_user(user_data, referral_code := ""):
	var url = "%s?documentId=%s" % [firestore_url, user_data["localId"]]
	var now = int(Time.get_unix_time_from_system())
	var ref_code = str(randi_range(100000, 999999))
	var doc = {
		"fields": {
			"email": { "stringValue": user_data["email"] },
			"referralCode": { "stringValue": ref_code },
			"referredBy": { "stringValue": referral_code },
			"points": { "doubleValue": 0.0 },
			"lastMiningStart": { "integerValue": 0 },
			"createdAt": { "integerValue": now },
			"tutorialSeen": { "booleanValue": false }
		}
	}
	var body = JSON.stringify(doc)
	var result: Array = await http_request(url, HTTPClient.METHOD_POST, _auth_headers(), body)
	if result[0] and int(result[1]) in [200, 201]:
		if referral_code != "":
			await add_refer_bonus(referral_code)
		return true
	else:
		return false

func ensure_user_doc(uid: String, email: String, referral_code := "") -> bool:
	var doc: Dictionary = await get_user_doc(uid)
	var existing_profile := not doc.is_empty()

	var firebase := get_node_or_null("/root/Firebase")
	if firebase and firebase.has_method("ensure_user_profile"):
		var backend_result: Dictionary = await firebase.ensure_user_profile(email, referral_code)
		if bool(backend_result.get("ok", false)):
			if bool(backend_result.get("referralResolved", false)):
				clear_pending_referral_code()
			return true
		push_error("Cloud Function profil oluşturamadı: %s" % str(backend_result))
	else:
		push_error("Cloud Function profil servisi bulunamadı (uid=%s)" % uid)
	return existing_profile
func get_user_doc(uid: String) -> Dictionary:
	var url = "%s/%s" % [firestore_url, uid]
	var result: Array = await http_request(url, HTTPClient.METHOD_GET, _auth_headers())
	if result[0] and int(result[1]) == 200 and typeof(result[2]) == TYPE_DICTIONARY:
		return result[2]
	return {}

func update_user_points_atomic(uid: String, delta: float) -> Array:
	var doc_any: Variant = await get_user_doc(uid)

	if typeof(doc_any) != TYPE_DICTIONARY or doc_any.is_empty():
		return [false, "Kullanıcı dokümanı yok"]

	# Aşağıdaki bloklar üstteki return ile aynı hizada olmalı
	var doc: Dictionary = doc_any
	var fields: Dictionary = {}

	if doc.has("fields") and typeof(doc["fields"]) == TYPE_DICTIONARY:
		fields = doc["fields"]
		var current: float = 0.0

		if fields.has("points") and typeof(fields["points"]) == TYPE_DICTIONARY and fields["points"].has("doubleValue"):
			current = float(fields["points"]["doubleValue"])
			var new_points: float = current + delta

			var url2: String = "%s/%s?updateMask.fieldPaths=points" % [firestore_url, uid]
			var body: Dictionary = {"fields": {"points": {"doubleValue": new_points}}}

			var res: Array = await http_request(url2, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify(body))

			if res.size() >= 2 and bool(res[0]) and int(res[1]) in [200, 201]:
				return [true, new_points]

	return [false, "Güncellenemedi"]
func add_refer_bonus(referral_code: String):
	var run_base := "https://firestore.googleapis.com/v1/projects/candar-network-007/databases/(default)/documents:runQuery"
	var query_body = {
		"structuredQuery": {
			"from": [{"collectionId": "users"}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": "referralCode"},
					"op": "EQUAL",
					"value": {"stringValue": referral_code}
					}
				},
				"limit": 1
			}
		}
	var result: Array = await http_request(run_base, HTTPClient.METHOD_POST, _auth_headers(), JSON.stringify(query_body))
	if result[0] and int(result[1]) == 200 and typeof(result[2]) == TYPE_ARRAY:
		for item in result[2]:
				if item.has("document"):
					var doc = item["document"]
					var doc_name = doc["name"]
					var doc_id = doc_name.split("/").back()
					var fields = doc["fields"]
					var current_points := 0.0
					if fields.has("points") and fields["points"].has("doubleValue"):
						current_points = float(fields["points"]["doubleValue"])
					var new_points := current_points + 10.0
					var update_url = "%s/%s?updateMask.fieldPaths=points" % [firestore_url, doc_id]
					var update_body = {"fields": {"points": {"doubleValue": new_points}}}
					await http_request(update_url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify(update_body))

func get_users_by_referral(referral_code: String) -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("get_referrals"):
		return []
	var result: Dictionary = await firebase.get_referrals()
	if not bool(result.get("ok", false)):
		return []
	var users: Variant = result.get("users", [])
	if typeof(users) != TYPE_ARRAY:
		return []
	var fields_only: Array = []
	for user in users:
		if typeof(user) == TYPE_DICTIONARY and user.has("fields"):
			fields_only.append(user["fields"])
	return fields_only

func get_point_rewards() -> Dictionary:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("get_point_rewards"):
		return {"ok": false, "error": "Puan kullanım servisi kullanılamıyor."}
	return await firebase.get_point_rewards()

func redeem_point_reward(reward_id: String) -> Dictionary:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("redeem_point_reward"):
		return {"ok": false, "error": "Puan kullanım servisi kullanılamıyor."}
	var result: Dictionary = await firebase.redeem_point_reward(reward_id)
	if bool(result.get("ok", false)):
		market_point_ad_free_expires_at = str(result.get("pointsAdFreeUntil", market_point_ad_free_expires_at))
	return result

func get_leaderboard_top(limit := 50) -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("get_leaderboard"):
		return []
	var result: Dictionary = await firebase.get_leaderboard(int(limit))
	if not bool(result.get("ok", false)):
		return []
	var users: Variant = result.get("users", [])
	return users if typeof(users) == TYPE_ARRAY else []

func get_users_sample(limit := 100) -> Array:
	return await get_leaderboard_top(limit)

func patch_user_fields(uid: String, fields: Dictionary) -> Array:
	var url := "%s/%s" % [firestore_url, uid]
	var masks: Array = []
	for k in fields.keys():
		masks.append("updateMask.fieldPaths=%s" % k)
	url += "?" + "&".join(masks)
	var body := {"fields": fields}
	return await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify(body))

# ======================================================================
#                        H E S A P   S İ L M E
# ======================================================================

func delete_my_account() -> Array:
	if _current_uid == "":
		_current_uid = get_uid()
	if _current_uid == "":
		return [false, "AUTH_NO_UID"]

	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("delete_account"):
		return [false, "DELETE_SERVICE_UNAVAILABLE"]

	var result: Dictionary = await firebase.delete_account()
	if not bool(result.get("ok", false)):
		return [false, str(result.get("error", "DELETE_FAILED"))]

	await logout()
	return [true, "OK"]

# ======================================================================
#                               M I N I N G
# ======================================================================

func _firestore_number(fields: Dictionary, key: String, default_value: float = 0.0) -> float:
	if not fields.has(key) or typeof(fields[key]) != TYPE_DICTIONARY:
		return default_value
	var field: Dictionary = fields[key]
	if field.has("doubleValue"):
		return float(field["doubleValue"])
	if field.has("integerValue"):
		return float(field["integerValue"])
	if field.has("stringValue"):
		var s := String(field["stringValue"])
		if s.is_valid_float():
			return float(s)
	return default_value

func _firestore_int(fields: Dictionary, key: String, default_value: int = 0) -> int:
	return int(_firestore_number(fields, key, float(default_value)))

func _firestore_string(fields: Dictionary, key: String, default_value: String = "") -> String:
	if not fields.has(key) or typeof(fields[key]) != TYPE_DICTIONARY:
		return default_value
	var field: Dictionary = fields[key]
	if field.has("stringValue"):
		return String(field["stringValue"])
	if field.has("integerValue"):
		return String(field["integerValue"])
	if field.has("doubleValue"):
		return String(field["doubleValue"])
	if field.has("booleanValue"):
		return "true" if bool(field["booleanValue"]) else "false"
	return default_value

func _firestore_map_fields(fields: Dictionary, key: String) -> Dictionary:
	var value: Variant = fields.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var map_value: Variant = (value as Dictionary).get("mapValue", {})
	if typeof(map_value) != TYPE_DICTIONARY:
		return {}
	var nested_fields: Variant = (map_value as Dictionary).get("fields", {})
	if typeof(nested_fields) == TYPE_DICTIONARY:
		return nested_fields
	return {}

func _firestore_timestamp(fields: Dictionary, key: String, default_value: String = "") -> String:
	var value: Variant = fields.get(key, {})
	if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has("timestampValue"):
		return String((value as Dictionary)["timestampValue"])
	return default_value

func _timestamp_active(timestamp_value: String) -> bool:
	if timestamp_value == "":
		return true
	var unix_exp := Time.get_unix_time_from_datetime_string(timestamp_value)
	if unix_exp <= 0:
		return true
	return unix_exp > Time.get_unix_time_from_system()

func get_user_mining_rate_components(uid: String, fields: Dictionary = {}) -> Dictionary:
	var source_fields := fields
	if source_fields.is_empty() and uid != "":
		var doc: Dictionary = await get_user_doc(uid)
		if doc.has("fields") and typeof(doc["fields"]) == TYPE_DICTIONARY:
			source_fields = doc["fields"]

	var mining_fields := _firestore_map_fields(source_fields, "mining")

	var base_rate := _firestore_number(source_fields, "base_rate", _firestore_number(mining_fields, "base_rate", 1.0))
	if base_rate <= 0.0:
		base_rate = 1.0

	var active_multiplier := _firestore_number(source_fields, "currentMultiplier", _firestore_number(mining_fields, "active_multiplier", 1.0))
	if active_multiplier <= 0.0:
		active_multiplier = 1.0

	var boost_exp := _firestore_timestamp(source_fields, "boostExpiresAt", _firestore_timestamp(mining_fields, "boost_expires_at", ""))
	if not _timestamp_active(boost_exp):
		active_multiplier = 1.0

	var ref_count: int = _firestore_int(source_fields, "referralCount", _firestore_int(source_fields, "refCount", -1))
	if ref_count < 0:
		ref_count = 0
		var ref_code := _firestore_string(source_fields, "referralCode", "")
		if ref_code != "":
			var refs: Array = await get_users_by_referral(ref_code)
			if typeof(refs) == TYPE_ARRAY:
				ref_count = refs.size()
	# Display calculations must not rewrite the server-owned referral counters.
	var ref_multiplier: float = snapped(1.0 + float(ref_count) * 0.05, 0.01)

	var rewarded_multiplier := _active_rewarded_boost_multiplier(source_fields)
	var points_boost_multiplier := maxf(1.0, _firestore_number(source_fields, "pointsBoostMultiplier", 1.0))
	var points_boost_exp := _firestore_timestamp(source_fields, "pointsBoostUntil", "")
	if points_boost_exp == "" or not _timestamp_active(points_boost_exp):
		points_boost_multiplier = 1.0
	var streak_multiplier := maxf(1.0, _firestore_number(source_fields, "streakBonus", 1.0))
	var total_rate := maxf(1.0, snapped(base_rate * active_multiplier * points_boost_multiplier * ref_multiplier * rewarded_multiplier * streak_multiplier, 0.01))

	return {
		"base_rate": base_rate,
		"active_multiplier": active_multiplier,
		"boost_expires_at": boost_exp,
		"ref_count": ref_count,
		"ref_multiplier": ref_multiplier,
		"rewarded_multiplier": rewarded_multiplier,
		"points_boost_multiplier": points_boost_multiplier,
		"points_boost_expires_at": points_boost_exp,
		"streak_multiplier": streak_multiplier,
		"total_rate": total_rate
	}

func _is_backend_temporarily_unavailable(status: int, error_msg: String) -> bool:
	var e := error_msg.to_lower()
	return status in [0, 500, 502, 503, 504] or e.find("not available") != -1 or e.find("billing") != -1 or e.find("service") != -1

func _is_permission_denied(status: int, error_msg: String) -> bool:
	var e := error_msg.to_lower()
	return status in [401, 403] or e.find("permission_denied") != -1 or e.find("insufficient permissions") != -1 or e.find("permission") != -1

func _friendly_reward_error(status: int, error_msg: String) -> String:
	if _is_permission_denied(status, error_msg):
		if OS.has_feature("editor") or OS.get_name() in ["macOS", "Windows", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
			return "Godot editör testinde günlük ödül sunucu izniyle kaydedilemedi. Mobil build/TestFlight veya Cloud Function yetkisiyle tekrar deneyin."
		return "Günlük ödül servisi izin hatası döndürdü. Lütfen çıkış yapıp tekrar giriş yapın; sorun sürerse sunucu kuralı güncellenmeli."
	if _is_backend_temporarily_unavailable(status, error_msg):
		return "Günlük ödül servisi şu anda kullanılamıyor. Lütfen biraz sonra tekrar deneyin."
	if error_msg.strip_edges() != "":
		var trimmed := error_msg.strip_edges()
		if trimmed.length() > 140:
			return "Günlük ödül alınamadı. Lütfen biraz sonra tekrar deneyin."
		return trimmed
	return "Günlük ödül alınamadı. Lütfen biraz sonra tekrar deneyin."

func _claim_daily_reward_firestore() -> Array:
	await ensure_token_fresh(120)

	var uid := get_uid()
	if uid == "":
		return [false, "Oturum bulunamadı. Lütfen tekrar giriş yap."]

	var doc: Dictionary = await get_user_doc(uid)
	if doc.is_empty() or not doc.has("fields") or typeof(doc["fields"]) != TYPE_DICTIONARY:
		return [false, "Kullanıcı verisi okunamadı."]

	var fields: Dictionary = doc["fields"]
	var now := int(Time.get_unix_time_from_system())
	var last := _firestore_int(fields, "lastMiningStart", 0)
	var wait_left := 86400 - (now - last)
	if last > 0 and wait_left > 0:
		var hours: int = int(ceil(float(wait_left) / 3600.0))
		return [false, "Günlük ödül zaten alınmış. Yaklaşık %s saat sonra tekrar dene." % hours]

	var current_points: float = _firestore_number(fields, "points", 0.0)
	var rate_components: Dictionary = await get_user_mining_rate_components(uid, fields)
	var reward: float = maxf(float(rate_components.get("total_rate", mining_rate)), 1.0)
	var new_points: float = snapped(current_points + reward, 0.01)
	var url := "%s/%s?updateMask.fieldPaths=points&updateMask.fieldPaths=lastMiningStart" % [firestore_url, uid]
	var body := {
		"fields": {
			"points": {"doubleValue": new_points},
			"lastMiningStart": {"integerValue": now}
		}
	}

	var patch_res: Array = await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify(body))
	if patch_res.size() >= 2 and bool(patch_res[0]) and int(patch_res[1]) in [200, 201]:
		return [true, {
			"ok": true,
			"points": new_points,
			"reward": reward,
			"fallback": true
		}]

	var detail := str(patch_res[2]) if patch_res.size() >= 3 else str(patch_res)
	var status := int(patch_res[1]) if patch_res.size() >= 2 else 0
	return [false, _friendly_reward_error(status, detail)]

func apply_purchase_firestore_fallback(product_id: String, is_premium: bool, platform: String, proof: String) -> Array:
	await ensure_token_fresh(120)

	var uid := get_uid()
	if uid == "":
		return [false, "Oturum bulunamadı. Lütfen tekrar giriş yap."]

	var now := int(Time.get_unix_time_from_system())
	var expires := Time.get_datetime_string_from_unix_time(now + 30 * 86400, true) + "Z"
	var fields := {
		"lastPurchasePlatform": {"stringValue": platform},
		"lastPurchaseProductId": {"stringValue": product_id},
		"lastPurchaseProof": {"stringValue": proof},
		"lastPurchaseAt": {"integerValue": now}
	}

	if is_premium:
		fields["isPremium"] = {"booleanValue": true}
		fields["premiumExpiresAt"] = {"timestampValue": expires}
		fields["premium"] = {
			"mapValue": {
				"fields": {
					"is_active": {"booleanValue": true},
					"expires_at": {"timestampValue": expires}
				}
			}
		}
	else:
		var multiplier := 2.0
		if product_id.find("pro") != -1:
			multiplier = 3.0
		elif product_id.find("ultra") != -1:
			multiplier = 7.0
		fields["currentMultiplier"] = {"doubleValue": multiplier}
		fields["boostExpiresAt"] = {"timestampValue": expires}
		fields["mining"] = {
			"mapValue": {
				"fields": {
					"active_multiplier": {"doubleValue": multiplier},
					"boost_expires_at": {"timestampValue": expires}
				}
			}
		}

	var masks: Array = []
	for k in fields.keys():
		masks.append("updateMask.fieldPaths=%s" % str(k))
	var url := "%s/%s?%s" % [firestore_url, uid, "&".join(masks)]
	var patch_res: Array = await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": fields}))
	if patch_res.size() >= 2 and bool(patch_res[0]) and int(patch_res[1]) in [200, 201]:
		if is_premium:
			market_is_premium = true
			market_premium_expires_at = expires
		else:
			market_boost_multiplier = float(fields["currentMultiplier"]["doubleValue"])
			market_boost_expires_at = expires
		return [true, {"ok": true, "fallback": true, "expiresAt": expires}]

	var detail := str(patch_res[2]) if patch_res.size() >= 3 else str(patch_res)
	return [false, "Satın alma kaydedilemedi: " + detail]

# Sunucu tarafında kazım yapan Cloud Function'ı saran helper
func kazim_yap() -> Array:
	await ensure_token_fresh(120)

	var res: Dictionary = await Firebase.do_mining()

	if res.has("ok") and bool(res["ok"]):
		return [true, res]

	var status := int(res.get("status", 0))
	var error_msg := str(res.get("error", "Bilinmeyen hata"))
	return [false, _friendly_reward_error(status, error_msg)]


func update_user_points(new_points: float) -> bool:
	return false

# ======================================================================
#                   MARKET / BOOST & PREMIUM DURUMU
# ======================================================================

var market_boost_multiplier: float = 1.0
var market_boost_expires_at: String = ""
var market_is_premium: bool = false
var market_premium_expires_at: String = ""
var market_point_ad_free_expires_at: String = ""

# Cloud Functions (index.ts) tarafının yazdığı:
#  - currentMultiplier (double)
#  - boostExpiresAt (timestamp)
#  - isPremium (bool)
#  - premiumExpiresAt (timestamp)
# alanlarını Firestore'dan okur.

func get_market_state(uid: String) -> Dictionary:
	var result := {
		"boost_multiplier": 1.0,
		"boost_expires_at": "",
		"is_premium": false,
		"premium_expires_at": "",
		"point_ad_free_expires_at": ""
	}

	var doc: Dictionary = await get_user_doc(uid)
	if doc.is_empty():
		return result

	if not doc.has("fields"):
		return result

	var fields: Dictionary = doc["fields"]

	# Boost multiplier. Firebase Admin can store whole-number multipliers as
	# integerValue, so use the shared numeric reader instead of double-only reads.
	var mining_map: Dictionary = {}
	if fields.has("mining") and typeof(fields["mining"]) == TYPE_DICTIONARY:
		mining_map = fields["mining"].get("mapValue", {}).get("fields", {})
	var multiplier := _firestore_number(fields, "currentMultiplier", _firestore_number(mining_map, "active_multiplier", 1.0))
	result["boost_multiplier"] = maxf(1.0, multiplier)

	# Boost bitiş tarihi
	if fields.has("boostExpiresAt") and typeof(fields["boostExpiresAt"]) == TYPE_DICTIONARY:
		var bt: Dictionary = fields["boostExpiresAt"]
		if bt.has("timestampValue"):
			result["boost_expires_at"] = String(bt["timestampValue"])
	elif fields.has("mining") and typeof(fields["mining"]) == TYPE_DICTIONARY:
		var mining_exp: Dictionary = fields["mining"].get("mapValue", {}).get("fields", {})
		if mining_exp.has("boost_expires_at") and mining_exp["boost_expires_at"].has("timestampValue"):
			result["boost_expires_at"] = String(mining_exp["boost_expires_at"]["timestampValue"])

	# Premium aktif mi?
	if fields.has("isPremium") and typeof(fields["isPremium"]) == TYPE_DICTIONARY:
		var p: Dictionary = fields["isPremium"]
		if p.has("booleanValue"):
			result["is_premium"] = bool(p["booleanValue"])
	elif fields.has("premium") and typeof(fields["premium"]) == TYPE_DICTIONARY:
		var premium_map: Dictionary = fields["premium"].get("mapValue", {}).get("fields", {})
		if premium_map.has("is_active") and premium_map["is_active"].has("booleanValue"):
			result["is_premium"] = bool(premium_map["is_active"]["booleanValue"])

	# Premium bitiş tarihi
	if fields.has("premiumExpiresAt") and typeof(fields["premiumExpiresAt"]) == TYPE_DICTIONARY:
		var pt: Dictionary = fields["premiumExpiresAt"]
		if pt.has("timestampValue"):
			result["premium_expires_at"] = String(pt["timestampValue"])
	elif fields.has("premium") and typeof(fields["premium"]) == TYPE_DICTIONARY:
		var premium_exp: Dictionary = fields["premium"].get("mapValue", {}).get("fields", {})
		if premium_exp.has("expires_at") and premium_exp["expires_at"].has("timestampValue"):
			result["premium_expires_at"] = String(premium_exp["expires_at"]["timestampValue"])

	result["point_ad_free_expires_at"] = _firestore_timestamp(fields, "pointsAdFreeUntil", "")

	# Global cache
	market_boost_multiplier = float(result["boost_multiplier"])
	market_boost_expires_at = String(result["boost_expires_at"])
	market_is_premium = bool(result["is_premium"])
	market_premium_expires_at = String(result["premium_expires_at"])
	market_point_ad_free_expires_at = String(result["point_ad_free_expires_at"])

	return result

func is_user_premium() -> bool:
	if not market_is_premium:
		return false
	if market_premium_expires_at == "":
		return true
	var exp := Time.get_unix_time_from_datetime_string(market_premium_expires_at)
	if exp <= 0:
		return true
	return exp > Time.get_unix_time_from_system()

func sync_point_entitlements(fields: Dictionary) -> void:
	market_point_ad_free_expires_at = _firestore_timestamp(fields, "pointsAdFreeUntil", market_point_ad_free_expires_at)

func is_ad_free_user() -> bool:
	if is_user_premium():
		return true
	if market_point_ad_free_expires_at == "":
		return false
	var exp := Time.get_unix_time_from_datetime_string(market_point_ad_free_expires_at)
	return exp > Time.get_unix_time_from_system()

func analytics_page(page_title: String, page_location: String = "") -> void:
	var analytics := get_node_or_null("/root/Analytics")
	if analytics and analytics.has_method("track_page_view"):
		analytics.track_page_view(page_title, page_location)

func analytics_event(event_name: String, params: Dictionary = {}) -> void:
	var analytics := get_node_or_null("/root/Analytics")
	if analytics and analytics.has_method("track_event"):
		analytics.track_event(event_name, params)
	var firebase := get_node_or_null("/root/Firebase")
	if firebase and firebase.has_method("track_event"):
		var client_id := ""
		if analytics and analytics.has_method("get_client_id"):
			client_id = str(analytics.get_client_id())
		if client_id != "":
			var enriched := params.duplicate()
			if not enriched.has("platform"):
				enriched["platform"] = _platform_kind()
			firebase.track_event(event_name, enriched, client_id)

func _track_first_open_once() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_FIRST_OPEN_STATE_PATH)
	if bool(cfg.get_value("install", "first_open_sent", false)):
		return
	var analytics := get_node_or_null("/root/Analytics")
	var firebase := get_node_or_null("/root/Firebase")
	if analytics == null or firebase == null or not analytics.has_method("get_client_id") or not firebase.has_method("track_event_confirmed"):
		return
	var client_id := str(analytics.get_client_id())
	if client_id == "":
		return
	var now := int(Time.get_unix_time_from_system())
	var params := {
		"platform": _platform_kind(),
		"locale": OS.get_locale()
	}
	if analytics.has_method("track_event"):
		analytics.track_event("app_first_open", params)
	var result: Dictionary = await firebase.track_event_confirmed("app_first_open", params, client_id)
	if not bool(result.get("ok", false)):
		push_warning("[ANALYTICS] İlk açılış ölçümü gönderilemedi; sonraki açılışta tekrar denenecek.")
		return
	cfg.set_value("install", "first_open_sent", true)
	cfg.set_value("install", "first_open_unix", now)
	cfg.set_value("install", "platform", _platform_kind())
	cfg.set_value("install", "locale", OS.get_locale())
	cfg.save(_FIRST_OPEN_STATE_PATH)

# ======================================================================
#                         O T U R U M   Y Ö N E T İ M İ
# ======================================================================

func save_uid(uid: String) -> void:
	var f = FileAccess.open("user://uid.txt", FileAccess.WRITE)
	if f:
		f.store_string(uid)
		f.close()
	_current_uid = uid

func get_uid() -> String:
	var path := "user://uid.txt"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var uid := f.get_as_text().strip_edges()
		f.close()
		return uid
	return ""

func logout() -> void:
	# Delete the native refresh credential before navigating to the login
	# screen. The UID is non-secret but must never resurrect a signed-out session.
	await _clear_refresh_token()
	if FileAccess.file_exists("user://uid.txt"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://uid.txt"))
	_current_uid = ""
	_firebase_id_token = ""
	_is_signed_in = false
	var firebase := get_node_or_null("/root/Firebase")
	if firebase and firebase.has_method("set_tokens"):
		firebase.set_tokens("", "", "")
	print("[AUTH] Oturum kapatıldı.")

# ======================================================================
#   Google ile Giriş (PKCE → id_token → Firebase Auth SignIn)
# ======================================================================

func _b64url(bytes: PackedByteArray) -> String:
	var s: String = Marshalls.raw_to_base64(bytes)
	s = s.replace("+", "-")
	s = s.replace("/", "_")
	while s.ends_with("="):
		s = s.substr(0, s.length() - 1)
	return s

func _gen_code_verifier() -> String:
	return _b64url(_random_bytes(32))

func _code_challenge(verifier: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verifier.to_utf8_buffer())
	var digest: PackedByteArray = ctx.finish()
	return _b64url(digest)

func _random_bytes(n: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := PackedByteArray()
	for i in range(n):
		out.append(rng.randi() % 256)
	return out

func _urlencode(params: Dictionary) -> String:
	var parts: Array = []
	for k in params.keys():
		var key := str(k)
		var val := str(params[k])
		parts.append(key.uri_encode() + "=" + val.uri_encode())
	return "&".join(parts)

# OAuth2Plugin sinyallerini bağla (plugin sürümüne göre isimler değişebilir)
func _bind_oauth2plugin_signals(oauth: Object) -> void:
	var cand_signals := [
		"completed", "completion", "success",
		"auth_completed", "authorization_completed",
		"auth_success", "authorized",
		"url_received", "redirect_received",
		"code_received",
		"failed", "error", "auth_failed", "authorization_failed"
	]

	for s in cand_signals:
		if oauth.has_signal(s):
			if not oauth.is_connected(s, Callable(self, "_on_oauth2plugin_event")):
				oauth.connect(s, Callable(self, "_on_oauth2plugin_event"))
				print("[OAUTH2] signal connected:", s)

# Tek handler: ne gelirse logla
func _on_oauth2plugin_event(a = null, b = null, c = null, d = null) -> void:
	print("[OAUTH2] event:", a, b, c, d)
	# Eğer url/string geliyorsa direk handle_oauth_redirect'e sok
	if typeof(a) == TYPE_STRING and String(a).find("code=") != -1:
		handle_oauth_redirect(String(a))
	elif typeof(b) == TYPE_STRING and String(b).find("code=") != -1:
		handle_oauth_redirect(String(b))

# ----------------------------------------------------------------------
# iOS: Google Sign-In (In-App OAuth) — Safari'ye atmaz
# Döndürür: [true, auth_info_dict] veya [false, error_string]
# ----------------------------------------------------------------------
func _google_sign_in_ios_native() -> Array:
	if not (OS.has_feature("ios") or OS.get_name() == "iOS"):
		return [false, "Bu fonksiyon sadece iOS için."]

	# ✅ OAuth2Plugin singleton
	var oauth := Engine.get_singleton("OAuth2Plugin")
	if oauth == null:
		return [false, "OAuth2Plugin bulunamadı (iOS export plugins'te görünmeli ve açık olmalı)."]

	# iOS için PKCE hazırlığı (senin mevcut sistemin)
	var client_id: String = google_client_id_ios
	var redirect_uri: String = google_redirect_uri_ios

	_code_verifier = _gen_code_verifier()
	_state_token = _b64url(_random_bytes(16))
	_save_oauth_state()
	var challenge: String = _code_challenge(_code_verifier)

	var auth_params: Dictionary = {
		"client_id": client_id,
		"redirect_uri": redirect_uri,
		"response_type": "code",
		"scope": google_scopes,
		"code_challenge": challenge,
		"code_challenge_method": "S256",
		"state": _state_token,
		"access_type": "offline",
		"include_granted_scopes": "true",
		"prompt": "select_account"
	}
	var auth_url: String = google_auth_url + "?" + _urlencode(auth_params)
	print("[OAUTH-iOS] auth_url=", auth_url)

	# ✅ OAUTH2 plugin eventleri bağla (çok önemli)
	_bind_oauth2plugin_signals(oauth)

	# ✅ Safari yok: auth'u plugin ile başlat
	var started := false
	for m in ["start", "start_login", "startLogin", "open", "authorize", "begin"]:
		if oauth.has_method(m):
			# bazı pluginler (auth_url, redirect_uri) ister; bazıları sadece url ister
			if oauth.get_method_argument_count(m) >= 2:
				oauth.call(m, auth_url, redirect_uri)
			else:
				oauth.call(m, auth_url)
			started = true
			break

	if not started:
		return [false, "OAuth2Plugin start metodu bulunamadı (start/start_login...)."]


	# ✅ code bekle (senin mevcut deeplink/state akışın)
	var auth_code: String = await _wait_oauth_code(180)
	if auth_code == "":
		return [false, "Google kodu alınamadı (deeplink/redirect)."]

	# ✅ token exchange (id_token al)
	var token_form: Dictionary = {
		"grant_type": "authorization_code",
		"code": auth_code,
		"client_id": client_id,
		"redirect_uri": redirect_uri,
		"code_verifier": _code_verifier
	}

	var token_headers: Array = ["Content-Type: application/x-www-form-urlencoded"]
	var token_body: String = _urlencode(token_form)
	var token_res: Array = await http_request(google_token_url, HTTPClient.METHOD_POST, token_headers, token_body)

	# 1. Önce genel hata kontrolü yapalım
	if token_res.size() < 3 or not bool(token_res[0]) or int(token_res[1]) != 200:
		var detail := str(token_res[2]) if token_res.size() >= 3 else str(token_res)
		return [false, "Google token hatası: " + detail]

	# 2. Değişkeni if bloğunun DIŞINDA tanımla
	var token_any: Variant = token_res[2]

	# 3. Tip kontrolünü yap
	if typeof(token_any) != TYPE_DICTIONARY:
		return [false, "Google token cevabı dictionary değil."]

	var token_dict: Dictionary = token_any
	if not token_dict.has("id_token"):
		return [false, "id_token gelmedi."]
	var id_token: String = str(token_dict["id_token"])

	_clear_oauth_state()

	# ✅ Firebase'e Google ile giriş
	return await firebase_sign_in_with_google(id_token, "")

func _try_get_google_id_token(google) -> String:
	var methods := ["get_id_token","getIdToken","id_token","get_idToken","getToken","get_token"]
	for m in methods:
		if google.has_method(m):
			var v = google.call(m)
			if typeof(v) == TYPE_STRING and str(v).length() > 100:
				return str(v)
	return ""

# Firebase Auth REST: signInWithIdp (Google)
func _firebase_sign_in_with_google_id_token(id_token: String) -> Array:
	var url := rest_url + "/accounts:signInWithIdp?key=" + firebase_api_key
	var body := {
		"postBody": "id_token=" + id_token.uri_encode() + "&providerId=google.com",
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true
	}
	var headers := ["Content-Type: application/json"]
	var resp: Array = await http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(body))
	if resp.size() < 2 or not bool(resp[0]):
		var msg := "Google(Firebase) giriş hatası"
		if resp.size() >= 3: msg = str(resp[2])
		return [false, msg]

	# resp: [true, code, data_dict]
	var data = resp[2]
	if typeof(data) != TYPE_DICTIONARY:
		return [false, "Firebase beklenmeyen cevap"]

	# idToken, refreshToken, localId
	var auth_info := {
		"idToken": str(data.get("idToken","")),
		"refreshToken": str(data.get("refreshToken","")),
		"localId": str(data.get("localId","")),
		"email": str(data.get("email",""))
	}
	# tokenları globalde sakla (mevcut akışınla uyumlu)
	_firebase_id_token = str(auth_info.get("idToken",""))
	_firebase_refresh_token = str(auth_info.get("refreshToken",""))
	_current_uid = str(auth_info.get("localId",""))
	if _firebase_refresh_token != "":
		await _save_refresh_token(_firebase_refresh_token)
	if _current_uid != "":
		save_uid(_current_uid)
	_is_signed_in = (_firebase_id_token != "")

	return [true, auth_info]


func _google_sign_in_ios_sdk(timeout_sec: float = 60.0) -> Array:
	_gsi_log("START | os=" + OS.get_name() + " has_ios=" + str(OS.has_feature("ios")))

	if not (OS.has_feature("ios") or OS.get_name() == "iOS"):
		return [false, "Bu fonksiyon sadece iOS için."]

	# 1) Önce eski callback varsa temizle (eski sonuçla karışmasın)
	var callback_path := "user://google_callback.json"
	if FileAccess.file_exists(callback_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(callback_path))

	# 2) Native tarafa "popup aç" sinyali: signin_request.tmp oluştur
	# AppDelegate.swift her 1 sn bunu kontrol ediyor ve varsa GoogleSignInBridge.shared.signIn() çağırıyor.
	var req_path := "user://signin_request.tmp"
	var f := FileAccess.open(req_path, FileAccess.WRITE)
	if f == null:
		return [false, "signin_request.tmp yazılamadı (FileAccess null)."]
	f.store_string("1")
	f.close()

	var abs_req := ProjectSettings.globalize_path(req_path)
	_gsi_log("Requested native popup via file: " + req_path + " | abs=" + abs_req)

	# 3) Sonuç dosyasını bekle
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) / 1000.0 < timeout_sec:
		if FileAccess.file_exists(callback_path):
			var txt := FileAccess.get_file_as_string(callback_path)
			_gsi_log("Callback file arrived: " + txt)

			# JSON parse
			var j := JSON.new()
			var err := j.parse(txt)
			if err != OK:
				return [false, "google_callback.json JSON parse hata: " + str(err)]

			var d = j.data
			if typeof(d) != TYPE_DICTIONARY:
				return [false, "google_callback.json sözlük değil."]

			if d.get("ok", false) == true:
				# başarılı
				return [true, d]
			else:
				# hata
				return [false, str(d.get("error", "unknown_error"))]

		await get_tree().process_frame

	return [false, "Google Sign-In timeout: " + str(timeout_sec) + "s"]

func _firebase_signin_with_google_tokens(id_token: String, access_token: String, referral_code: String = "") -> Array:
	# Firebase REST: signInWithIdp
	var url := "%s/accounts:signInWithIdp?key=%s" % [rest_url, firebase_api_key]

	# Godot'ta Uri yok -> String.uri_encode() kullan
	var post_body := "id_token=%s&access_token=%s&providerId=google.com" % [
		id_token.uri_encode(),
		access_token.uri_encode()
	]

	var payload := {
		"postBody": post_body,
		"requestUri": "http://localhost",
		"returnSecureToken": true,
		"returnIdpCredential": true
	}

	_gsi_log("HTTP POST " + url)
	_gsi_log("BODY postBody len=" + str(post_body.length()))

	# Sende olan helper: http_request (JSON.stringify ile)
	var res: Array = await http_request(
		url,
		HTTPClient.METHOD_POST,
		["Content-Type: application/json"],
		JSON.stringify(payload)
	)

	# res formatı: [true/false, http_code, data]
	if res.size() < 3:
		return [false, "HTTP response invalid: " + str(res)]

	if not bool(res[0]) or int(res[1]) != 200:
		return [false, "Firebase signInWithIdp failed: " + str(res[2])]

	# başarılıysa idToken/refreshToken/localId al ve globale yaz
	var data_any: Variant = res[2]
	if typeof(data_any) != TYPE_DICTIONARY:
		return [false, "Firebase response not dict: " + str(data_any)]

	var data: Dictionary = data_any

	_firebase_id_token = str(data.get("idToken", ""))
	_current_uid = str(data.get("localId", ""))
	var rt := str(data.get("refreshToken", ""))

	if rt != "":
		await _save_refresh_token(rt)

	if _current_uid != "":
		save_uid(_current_uid)
		if has_node("/root/Firebase"):
			var firebase := get_node("/root/Firebase")
			if firebase and firebase.has_method("set_tokens"):
				firebase.set_tokens(_firebase_id_token, rt, _current_uid)
		var is_new_user := bool(data.get("isNewUser", false))
		var effective_referral := referral_code if is_new_user else ""
		var user_doc_ok := await ensure_user_doc(_current_uid, str(data.get("email", "")), effective_referral)
		if not user_doc_ok:
			return [false, "Google girişi başarılı ama profil oluşturulamadı. Lütfen tekrar dene."]
		if not is_new_user:
			clear_pending_referral_code()

	_is_signed_in = (_firebase_id_token != "")

	return [true, {
		"idToken": _firebase_id_token,
		"refreshToken": rt,
		"localId": _current_uid,
		"email": str(data.get("email", "")),
		"isNewUser": bool(data.get("isNewUser", false))
	}]

func google_sign_in(referral_code: String = "") -> Array:
	if OS.has_feature("ios") or OS.get_name() == "iOS":
		var native_result: Array = await _google_sign_in_ios_sdk()
		if native_result.size() < 2 or not bool(native_result[0]):
			return native_result

		var native_tokens: Variant = native_result[1]
		if typeof(native_tokens) != TYPE_DICTIONARY:
			return [false, "Google native sign-in response invalid"]

		var id_token := str(native_tokens.get("id_token", ""))
		var access_token := str(native_tokens.get("access_token", ""))
		if id_token == "":
			return [false, "Google native sign-in returned no ID token"]
		return await _firebase_signin_with_google_tokens(id_token, access_token, referral_code)

	var client_id: String = _current_client_id()
	if client_id == "":
		return [false, "google_client_id bos"]

	_code_verifier = _gen_code_verifier()
	_state_token = _b64url(_random_bytes(16))
	_save_oauth_state()
	var challenge: String = _code_challenge(_code_verifier)

	if _platform_kind() == "desktop":
		var started := _prime_loopback_server_any()
		if not started:
			return [false, "Loopback port acilamadi"]

	var redirect_uri: String = _current_redirect_uri()

	var auth_params: Dictionary = {
		"client_id": client_id,
		"redirect_uri": redirect_uri,
		"response_type": "code",
		"scope": google_scopes,
		"code_challenge": challenge,
		"code_challenge_method": "S256",
		"state": _state_token,
		"access_type": "offline",
		"include_granted_scopes": "true",
		"prompt": "select_account"
	}
	var auth_url: String = google_auth_url + "?" + _urlencode(auth_params)

	print("[OAUTH] auth_url=", auth_url)
	OS.shell_open(auth_url)

	var auth_code: String = await _wait_oauth_code(180)
	if auth_code == "":
		return [false, "Google kodu alinamadi"]

	var token_form: Dictionary = {
		"grant_type": "authorization_code",
		"code": auth_code,
		"client_id": client_id,
		"redirect_uri": redirect_uri,
		"code_verifier": _code_verifier
	}

	if _platform_kind() == "desktop" and google_client_secret_desktop != "":
		token_form["client_secret"] = google_client_secret_desktop

	var token_headers: Array = ["Content-Type: application/x-www-form-urlencoded"]
	var token_body: String = _urlencode(token_form)
	var token_res: Array = await http_request(google_token_url, HTTPClient.METHOD_POST, token_headers, token_body)

	if token_res.size() < 3:
		return [false, "Google token hatasi"]
	if not token_res[0] or int(token_res[1]) != 200:
		return [false, "Google token hatasi: " + str(token_res[2])]

	var token_any: Variant = token_res[2]
	if typeof(token_any) != TYPE_DICTIONARY:
		return [false, "Google token cevabi dictionary degil"]

	var token_dict: Dictionary = token_any

	if not token_dict.has("id_token"):
		return [false, "id_token gelmedi"]

	var id_token: String = str(token_dict["id_token"])

	# Not: token endpoint genelde "email" dönmez. O yüzden email_hint boş kalabilir.
	var email_hint: String = ""
	if token_dict.has("email"):
		email_hint = str(token_dict["email"])

	# Google OAuth refresh_token, Firebase refreshToken değildir.
	# Google tokenini Firebase oturum deposuna asla yazma.
	# ✅ Her durumda Firebase'e Google ile giriş yap
	return await firebase_sign_in_with_google(id_token, email_hint, referral_code)
# ======================================================================
#   GOOGLE İLE GİRİŞ (Firebase signInWithIdp - providerId = "google.com")
# ======================================================================

func firebase_sign_in_with_google(id_token: String, email_hint: String = "", referral_code: String = "") -> Array:
	var url := "%s/accounts:signInWithIdp?key=%s" % [rest_url, firebase_api_key]

	# Google id_token'u Firebase'e gönderiyoruz
	var post_body_str := "id_token=%s&providerId=google.com" % [id_token.uri_encode()]

	var payload := {
		"postBody": post_body_str,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true
	}

	var headers: Array = ["Content-Type: application/json"]
	var res: Array = await http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))

	if res.size() < 3:
		return [false, "Firebase Google IDP hatası: bilinmiyor"]

	if res[0]:
		var code: int = int(res[1])
		var any_data: Variant = res[2]
		var data: Dictionary = {}
		if typeof(any_data) == TYPE_DICTIONARY:
			data = any_data

		if code == 200:
			var uid: String = ""
			if data.has("localId"):
				uid = str(data["localId"])

			if data.has("idToken"):
				_firebase_id_token = str(data["idToken"])

			if data.has("refreshToken"):
				await _save_refresh_token(str(data["refreshToken"]))

			var email_val: String = email_hint
			if data.has("email"):
				email_val = str(data["email"])

			if uid != "":
				await save_uid(uid)
				if has_node("/root/Firebase"):
					var firebase := get_node("/root/Firebase")
					if firebase and firebase.has_method("set_tokens"):
						firebase.set_tokens(_firebase_id_token, await _load_refresh_token(), uid)
				var is_new_user := bool(data.get("isNewUser", false))
				await firestore_load_or_create_user(uid, email_val, referral_code if is_new_user else "")
				if not is_new_user:
					clear_pending_referral_code()
				_is_signed_in = true
				_clear_oauth_state()

				var auth_info := {
					"idToken": _firebase_id_token,
					"refreshToken": await _load_refresh_token(),
					"localId": uid,
					"email": email_val,
					"isNewUser": is_new_user
				}
				return [true, auth_info]

			return [false, "Firebase dönüşünde UID yok (Google)"]
		else:
			var msg: String = "Firebase Google hata"
			if data.has("error") and typeof(data["error"]) == TYPE_DICTIONARY and data["error"].has("message"):
				msg = str(data["error"]["message"])
			return [false, msg]
	else:
		var err_detail: String = "bilinmiyor"
		if res.size() >= 3:
			err_detail = str(res[2])
		return [false, "Ağ hatası (Google): " + err_detail]

# ======================================================================
#   APPLE İLE GİRİŞ (Firebase signInWithIdp - providerId = "apple.com")
# ======================================================================

func firebase_sign_in_with_apple(id_token: String, email_hint: String = "", referral_code: String = "") -> Array:
	var url := "%s/accounts:signInWithIdp?key=%s" % [rest_url, firebase_api_key]

	# Apple'dan gelen identityToken'ı Firebase'e gönderiyoruz
	var post_body_str := "id_token=%s&providerId=apple.com" % [id_token.uri_encode()]

	var payload := {
		"postBody": post_body_str,
		"requestUri": "http://localhost",         # Firebase dokümantasyonunda böyle
		"returnIdpCredential": true,
		"returnSecureToken": true
	}

	var headers: Array = ["Content-Type: application/json"]
	var res: Array = await http_request(url, HTTPClient.METHOD_POST, headers, JSON.stringify(payload))

	if res.size() < 3:
		return [false, "Firebase Apple IDP hatası: bilinmiyor"]

	if res[0]:
		var code: int = int(res[1])
		var any_data: Variant = res[2]
		var data: Dictionary = {}
		if typeof(any_data) == TYPE_DICTIONARY:
			data = any_data

		if code == 200:
			var uid: String = ""
			if data.has("localId"):
				uid = str(data["localId"])

			if data.has("idToken"):
				_firebase_id_token = str(data["idToken"])

			if data.has("refreshToken"):
				await _save_refresh_token(str(data["refreshToken"]))

			var email_val: String = email_hint
			if data.has("email"):
				email_val = str(data["email"])

			if uid != "":
				await save_uid(uid)
				if has_node("/root/Firebase"):
					var firebase := get_node("/root/Firebase")
					if firebase and firebase.has_method("set_tokens"):
						firebase.set_tokens(_firebase_id_token, await _load_refresh_token(), uid)
				var is_new_user := bool(data.get("isNewUser", false))
				await firestore_load_or_create_user(uid, email_val, referral_code if is_new_user else "")
				if not is_new_user:
					clear_pending_referral_code()
				_is_signed_in = true
				_clear_oauth_state()  # Google ile ortak state’i de temizle

				# onboarding.gd için auth_info sözlüğü döndürelim
				var auth_info := {
					"idToken": _firebase_id_token,
					"refreshToken": await _load_refresh_token(),
					"localId": uid,
					"email": email_val,
					"isNewUser": is_new_user
				}

				return [true, auth_info]

			return [false, "Firebase dönüşünde UID yok (Apple)"]
		else:
			var msg: String = "Firebase Apple hata"
			if data.has("error") and typeof(data["error"]) == TYPE_DICTIONARY and data["error"].has("message"):
				msg = str(data["error"]["message"])
			return [false, msg]
	else:
		var err_detail: String = "bilinmiyor"
		if res.size() >= 3:
			err_detail = str(res[2])
		return [false, "Ağ hatası (Apple): " + err_detail]

func apple_sign_in(referral_code: String = "") -> Array:
	if OS.get_name() != "iOS":
		return [false, "Apple girişi sadece iOS'ta."]

	var native_res: Array = await _apple_native_sign_in()
	if native_res.size() < 2 or not bool(native_res[0]):
		return [false, (native_res[1] if native_res.size() >= 2 else "Apple native hata")]

	var data_any: Variant = native_res[1]
	if typeof(data_any) != TYPE_DICTIONARY:
		return [false, "Apple native data dictionary değil."]

	var data: Dictionary = data_any

	if not bool(data.get("success", false)):
		return [false, str(data.get("error", "Apple login iptal/başarısız"))]

	var identity_token := str(data.get("identity_token", ""))
	if identity_token == "":
		identity_token = str(data.get("identityToken", ""))

	if identity_token == "":
		return [false, "Apple identity_token gelmedi."]

	var email_hint := str(data.get("email", ""))
	return await firebase_sign_in_with_apple(identity_token, email_hint, referral_code)

# --- Apple native bekleme state ---
var _apple_waiting: bool = false
var _apple_result: Dictionary = {}
var _apple_controller: Object = null

func _apple_value_to_string(value: Variant) -> String:
	if typeof(value) == TYPE_PACKED_BYTE_ARRAY:
		var bytes: PackedByteArray = value
		if bytes.size() == 0:
			return ""
		return bytes.get_string_from_utf8()
	if value == null:
		return ""
	var s := str(value)
	if s == "<null>" or s == "null":
		return ""
	return s

func _on_apple_auth_completed(credential: Variant) -> void:
	# GodotApplePlugins: credential genelde bir Object (AppleID credential) döner.
	# identity_token / authorization_code çoğunlukla PackedByteArray gelir.
	var out: Dictionary = {"success": true}

	if credential == null:
		out["success"] = false
		out["error"] = "Credential null"
		_apple_result = out
		_apple_waiting = false
		return

	var obj: Object = credential as Object
	if obj == null:
		# Bazı sürümlerde Dictionary gelebilir
		if typeof(credential) == TYPE_DICTIONARY:
			out.merge(credential, true)
			if not out.has("identity_token") and out.has("identityToken"):
				out["identity_token"] = _apple_value_to_string(out["identityToken"])
			else:
				out["identity_token"] = _apple_value_to_string(out.get("identity_token", ""))
			if not out.has("authorization_code") and out.has("authorizationCode"):
				out["authorization_code"] = _apple_value_to_string(out["authorizationCode"])
			else:
				out["authorization_code"] = _apple_value_to_string(out.get("authorization_code", ""))
			_apple_result = out
			_apple_waiting = false
			return
		out["success"] = false
		out["error"] = "Credential tipi desteklenmiyor"
		_apple_result = out
		_apple_waiting = false
		return

	# Güvenli property okuma: Object.get("prop")
	var id_token := _apple_value_to_string(obj.get("identity_token"))
	if id_token == "":
		id_token = _apple_value_to_string(obj.get("identityToken"))

	var auth_code := _apple_value_to_string(obj.get("authorization_code"))
	if auth_code == "":
		auth_code = _apple_value_to_string(obj.get("authorizationCode"))

	out["identity_token"] = id_token
	out["authorization_code"] = auth_code
	out["user"] = str(obj.get("user"))
	out["email"] = str(obj.get("email"))
	out["full_name"] = str(obj.get("full_name"))
	if out["full_name"] == "null" or out["full_name"] == "":
		out["full_name"] = str(obj.get("fullName"))

	_apple_result = out
	_apple_waiting = false

func _on_apple_auth_failed(message: Variant) -> void:
	var raw_error := str(message)
	print("[APPLE] Authorization failed: ", raw_error)
	_apple_result = {
		"success": false,
		"error": _friendly_apple_error(raw_error)
	}
	_apple_waiting = false

func _friendly_apple_error(raw_error: String) -> String:
	var lower := raw_error.to_lower()
	if lower.contains("canceled") or lower.contains("cancelled") or lower.contains("1001"):
		return "Apple girişi iptal edildi."
	if lower.contains("authenticationservices") or lower.contains("authorizationerror"):
		return "Apple oturumu tamamlanamadı. Lütfen Apple hesabınızın cihazda açık olduğundan emin olup tekrar deneyin."
	if raw_error.strip_edges() == "":
		return "Apple oturumu tamamlanamadı."
	return raw_error

func _on_apple_signin_completed(data: Dictionary, error: String = "") -> void:
	if error != "":
		_apple_result = {
			"success": false,
			"error": error
		}
	else:
		data["success"] = true
		data["identity_token"] = _apple_value_to_string(data.get("identity_token", data.get("identityToken", "")))
		data["authorization_code"] = _apple_value_to_string(data.get("authorization_code", data.get("authorizationCode", "")))
		_apple_result = data
	_apple_waiting = false

func _apple_native_sign_in() -> Array:
	if not OS.has_feature("ios"):
		return [false, "Apple girişi sadece iOS'ta."]

	_apple_waiting = true
	_apple_result = {}

	if ClassDB.class_exists("ASAuthorizationController"):
		_apple_controller = ClassDB.instantiate("ASAuthorizationController")

		if _apple_controller.has_signal("authorization_completed"):
			_apple_controller.authorization_completed.connect(Callable(self, "_on_apple_auth_completed"))
		elif _apple_controller.has_signal("authorizationCompleted"):
			_apple_controller.authorizationCompleted.connect(Callable(self, "_on_apple_auth_completed"))

		if _apple_controller.has_signal("authorization_failed"):
			_apple_controller.authorization_failed.connect(Callable(self, "_on_apple_auth_failed"))
		elif _apple_controller.has_signal("authorizationFailed"):
			_apple_controller.authorizationFailed.connect(Callable(self, "_on_apple_auth_failed"))

		if _apple_controller.has_method("signin_with_scopes"):
			_apple_controller.signin_with_scopes(["full_name", "email"])
		elif _apple_controller.has_method("signin"):
			_apple_controller.signin()
		elif _apple_controller.has_method("sign_in"):
			_apple_controller.sign_in()
		else:
			_apple_waiting = false
			return [false, "ASAuthorizationController.signin metodu bulunamadı. Plugin sürümü uyumsuz olabilir."]
	elif ClassDB.class_exists("GodotAppleSignIn"):
		_apple_controller = ClassDB.instantiate("GodotAppleSignIn")
		if _apple_controller.has_signal("signin_completed"):
			_apple_controller.signin_completed.connect(Callable(self, "_on_apple_signin_completed"))
		else:
			_apple_waiting = false
			return [false, "AppleSignIn signin_completed sinyali bulunamadı."]
		if _apple_controller.has_method("initiate_signin"):
			_apple_controller.initiate_signin()
		else:
			_apple_waiting = false
			return [false, "AppleSignIn initiate_signin metodu bulunamadı."]
	else:
		_apple_waiting = false
		return [false, "Apple Sign-In plugin bulunamadı."]

	# 20sn bekle
	var start := Time.get_unix_time_from_system()
	while _apple_waiting and (Time.get_unix_time_from_system() - start) < 20:
		await get_tree().process_frame

	if _apple_waiting:
		_apple_waiting = false
		return [false, "Apple popup timeout (20sn)."]

	return [true, _apple_result]

# Ağ testi
func _probe_network() -> void:
	var url := "https://accounts.google.com/.well-known/openid-configuration"
	var res: Array = await http_request(url, HTTPClient.METHOD_GET, [], "")
	if res[0]:
		print("[PROBE] OK internet var, code=", res[1])
	else:
		print("[PROBE] BAŞARISIZ -> ", res)

# ======================================================================
#                     O T O M A T İ K  O T U R U M  &  T O K E N
# ======================================================================

func _remove_legacy_refresh_file() -> void:
	if FileAccess.file_exists(_REFRESH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_REFRESH_PATH))

func _ios_secure_session_exchange(operation: String, token: String = "") -> Dictionary:
	# Existing Swift bridge handles this on iOS. The IPC files are transient;
	# the persistent secret belongs to Keychain (never to user://).
	while _secure_session_in_flight:
		await get_tree().process_frame
	_secure_session_in_flight = true
	if FileAccess.file_exists(_SECURE_RESPONSE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SECURE_RESPONSE_PATH))
	var request_id := str(Time.get_ticks_usec()) + "-" + str(Crypto.new().generate_random_bytes(8).hex_encode())
	var request: Dictionary = {
		"operation": operation,
		"request_id": request_id,
		"created_at": int(Time.get_unix_time_from_system())
	}
	if operation == "save":
		request["token"] = token
	var file := FileAccess.open(_SECURE_REQUEST_PATH, FileAccess.WRITE)
	if file == null:
		_secure_session_in_flight = false
		return {"ok": false}
	file.store_string(JSON.stringify(request))
	file.close()
	# Swift removes each input immediately, and Godot removes each output.
	# Inaccessible Keychain or a missing native bridge must fail closed.
	var timeout_at := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < timeout_at:
		if FileAccess.file_exists(_SECURE_RESPONSE_PATH):
			var body := FileAccess.get_file_as_string(_SECURE_RESPONSE_PATH)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_SECURE_RESPONSE_PATH))
			var response: Variant = JSON.parse_string(body)
			if typeof(response) == TYPE_DICTIONARY and str(response.get("request_id", "")) == request_id:
				_secure_session_in_flight = false
				return response
		await get_tree().process_frame
	# Clear the in-flight plaintext on timeout; do not leak it to logs.
	if FileAccess.file_exists(_SECURE_REQUEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SECURE_REQUEST_PATH))
	_secure_session_in_flight = false
	return {"ok": false}

func _save_refresh_token(rt: String) -> bool:
	if rt == "":
		return false
	_firebase_refresh_token = rt
	var saved := false
	if OS.get_name() == "Android":
		if Engine.has_singleton("CandarSecureStore"):
			var secure = Engine.get_singleton("CandarSecureStore")
			if secure.has_method("saveRefreshToken"):
				saved = bool(secure.call("saveRefreshToken", rt))
	elif OS.get_name() == "iOS":
		var reply: Dictionary = await _ios_secure_session_exchange("save", rt)
		saved = bool(reply.get("ok", false))
	# No fallbacks to unencrypted or locally derived encryption keys.
	_remove_legacy_refresh_file()
	if not saved:
		push_warning("[AUTH] Güvenli saklama yok: oturum yalnızca uygulama açıkken korunabilir.")
	return saved

func _load_refresh_token() -> String:
	if _firebase_refresh_token != "":
		return _firebase_refresh_token
	var stored := ""
	if OS.get_name() == "Android":
		if Engine.has_singleton("CandarSecureStore"):
			var secure = Engine.get_singleton("CandarSecureStore")
			if secure.has_method("loadRefreshToken"):
				stored = str(secure.call("loadRefreshToken"))
	elif OS.get_name() == "iOS":
		var reply: Dictionary = await _ios_secure_session_exchange("load")
		if bool(reply.get("ok", false)):
			stored = str(reply.get("token", ""))
	if stored != "":
		_firebase_refresh_token = stored
		_remove_legacy_refresh_file()
		return stored
	# Upgrade: a previous release stored Firebase refresh tokens as plain
	# text. Migrate once, then remove the legacy file even when no native
	# backend is available (re-login is safer than persisting plaintext).
	if FileAccess.file_exists(_REFRESH_PATH):
		var legacy := FileAccess.get_file_as_string(_REFRESH_PATH).strip_edges()
		if legacy != "":
			await _save_refresh_token(legacy)
			return legacy
		_remove_legacy_refresh_file()
	return ""

func _clear_refresh_token() -> void:
	_firebase_refresh_token = ""
	if OS.get_name() == "Android":
		if Engine.has_singleton("CandarSecureStore"):
			var secure = Engine.get_singleton("CandarSecureStore")
			if secure.has_method("clearRefreshToken"):
				secure.call("clearRefreshToken")
	elif OS.get_name() == "iOS":
		await _ios_secure_session_exchange("clear")
	_remove_legacy_refresh_file()

# Firebase idToken yenileme (Secure Token)
func firebase_refresh_id_token() -> bool:
	var rt := await _load_refresh_token()
	if rt == "":
		return false
	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % firebase_api_key
	var body := _urlencode({
		"grant_type": "refresh_token",
		"refresh_token": rt
	})
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var res := await http_request(url, HTTPClient.METHOD_POST, headers, body)
	if res[0] and int(res[1]) == 200 and typeof(res[2]) == TYPE_DICTIONARY:
		var d: Dictionary = res[2]
		# Do not accept a refresh response for a different stored UID.
		var returned_uid := str(d.get("user_id", _current_uid))
		if _current_uid != "" and returned_uid != _current_uid:
			await _clear_refresh_token()
			return false
		if d.has("id_token"):
			_firebase_id_token = str(d["id_token"])
		if d.has("refresh_token"):
			await _save_refresh_token(str(d["refresh_token"]))
		var firebase := get_node_or_null("/root/Firebase")
		if firebase and firebase.has_method("set_tokens"):
			firebase.set_tokens(_firebase_id_token, await _load_refresh_token(), _current_uid)
		return true
	return false

# JWT exp alanını çöz (imzasız parse)
func _jwt_exp(unverified_jwt: String) -> int:
	var parts := unverified_jwt.split(".")
	if parts.size() < 2:
		return 0
	var payload_b64 := parts[1]
	payload_b64 = payload_b64.replace("-", "+").replace("_", "/")
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="
	var bytes := Marshalls.base64_to_raw(payload_b64)
	var txt := bytes.get_string_from_utf8()
	var j := JSON.new()
	if j.parse(txt) == OK and typeof(j.data) == TYPE_DICTIONARY and j.data.has("exp"):
		return int(j.data["exp"])
	return 0

# exp yaklaşınca yenile
func ensure_token_fresh(threshold_sec := 120) -> void:
	if _firebase_id_token == "":
		var refreshed := await firebase_refresh_id_token()
		if not refreshed:
			print("[AUTH] idToken yok ve refresh başarısız.")
		return
	var exp := _jwt_exp(_firebase_id_token)
	var now := Time.get_unix_time_from_system()
	if exp > 0 and exp - now < threshold_sec:
		var ok := await firebase_refresh_id_token()
		if not ok:
			print("[AUTH] idToken yenileme başarısız, oturum yakında düşebilir.")

# Uygulama açılışında oturumu geri yükle
func try_restore_session() -> void:
	_current_uid = get_uid()
	var has_uid := _current_uid != ""
	var has_rt := await _load_refresh_token() != ""

	if has_uid and has_rt:
		var ok := await firebase_refresh_id_token()
		if ok:
			_is_signed_in = true
			print("[AUTH] Oturum geri yüklendi: uid=", _current_uid)
			await ensure_user_doc(_current_uid, "")
			if has_method("go_home"):
				go_home()
			return
		else:
			print("[AUTH] Refresh başarısız; login ekranında kalınacak.")

	_is_signed_in = false

func go_home() -> void:
	var current := get_tree().current_scene
	if current and current.scene_file_path.ends_with("home.tscn"):
		return
	var path := "res://home.tscn"
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("go_home(): sahneye geçilemedi -> %s" % [path])

# 5 dakikada bir token tazele (exp'e yaklaşınca)
func _start_token_refresh_timer() -> void:
	var t := Timer.new()
	t.wait_time = 300.0
	t.autostart = true
	t.one_shot = false
	add_child(t)
	t.timeout.connect(func():
		await ensure_token_fresh(180)
	)

func get_id_token() -> String:
	return _firebase_id_token

# ===================== DİL AYARLARI =====================
var current_lang := "en"

# Uygulamanın desteklediği diller
var SUPPORTED_LANGS := [
	"en", # English
	"tr", # Türkçe
	"de", # Deutsch
	"fr", # Français
	"es", # Español
	"pt", # Português
	"ru", # Русский
	"zh", # 中文
	"ja", # 日本語
	"ko", # 한국어
	"ar", # العربية
	"hi"  # हिन्दी
]

const _UI_CATALOG_PATH := "res://localization/ui_strings.json"
var _ui_catalog: Dictionary = {}
var _ui_indexes: Dictionary = {}

func _load_ui_locales() -> void:
	var raw := FileAccess.get_file_as_string(_UI_CATALOG_PATH)
	var result: Variant = JSON.parse_string(raw)
	if typeof(result) != TYPE_DICTIONARY:
		push_error("[I18N] UI locale catalog unavailable")
		return
	_ui_catalog = result
	_ui_indexes.clear()
	var keys: Array = _ui_catalog.get("keys", [])
	for i in range(keys.size()):
		_ui_indexes[str(keys[i])] = i

func localized_ui_text(turkish: String, english: String) -> String:
	var locale := TranslationServer.get_locale().replace("-", "_").get_slice("_", 0).to_lower()
	if locale == "tr":
		return turkish
	if locale == "en":
		return english
	if _ui_indexes.is_empty():
		_load_ui_locales()
	if not _ui_indexes.has(english):
		return english
	var entries: Array = _ui_catalog.get(locale, [])
	var index := int(_ui_indexes[english])
	if index < entries.size() and str(entries[index]) != "":
		return str(entries[index])
	return english

func localized_named_key(key: String) -> String:
	if _ui_catalog.is_empty():
		_load_ui_locales()
	var named: Dictionary = _ui_catalog.get("named", {})
	if named.has(key):
		var values: Dictionary = named[key]
		var lang := TranslationServer.get_locale().replace("-", "_").get_slice("_", 0).to_lower()
		return str(values.get(lang, values.get("en", key)))
	return TranslationServer.translate(key)

func _determine_initial_lang() -> String:
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") == OK:
		var chosen := str(saved.get_value("general", "lang", "")).to_lower()
		if chosen in SUPPORTED_LANGS:
			return chosen
	var code := OS.get_locale().replace("-", "_").get_slice("_", 0).to_lower()
	return code if code in SUPPORTED_LANGS else "en"


func set_language(lang_code: String) -> void:
	# Şu anlık UI'den çağırmıyoruz ama ilerde lazım olur
	if lang_code in SUPPORTED_LANGS:
		current_lang = lang_code
	else:
		current_lang = "en" # veya "tr"

	TranslationServer.set_locale(current_lang)
	_save_language_to_disk()
	call_deferred("_sync_push_language_if_signed_in")

func _sync_push_language_if_signed_in() -> void:
	if get_uid() == "":
		return
	await ensure_token_fresh(60)
	var fields := {
		"language": {"stringValue": current_lang},
		"locale": {"stringValue": OS.get_locale()},
		"pushPlatform": {"stringValue": _platform_kind()}
	}
	var masks := []
	for key in fields.keys():
		masks.append("updateMask.fieldPaths=%s" % key)
	var url := "%s/%s?%s" % [firestore_url, get_uid(), "&".join(masks)]
	await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": fields}))


func _save_language_to_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	if err != OK:
		cfg = ConfigFile.new()

	cfg.set_value("general", "lang", current_lang)
	cfg.save("user://settings.cfg")
func apply_safe_area(ctrl: Control) -> void:
	if OS.get_name() != "iOS" and OS.get_name() != "Android":
		return
	if ctrl == null:
		return

	await get_tree().process_frame

	# Root'u safe area kadar küçültmek iOS'ta üst/alt boşluk bırakıyordu.
	# Ekranlar kendi iç margin/header düzenini zaten yönetiyor.
	ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_top = 0
	ctrl.offset_left = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0

	print("[SAFE AREA] Root full rect applied")

# ======================================================================
#                           ADMOB MANAGER (GLOBAL)
# ======================================================================

var ads_initialized := false

var _banner_view      : AdView
var _interstitial_ad  : InterstitialAd
var _rewarded_ad      : RewardedAd

var _interstitial_cb  : InterstitialAdLoadCallback
var _rewarded_cb      : RewardedAdLoadCallback

var _ads_ios_banner_id        := ""
var _ads_ios_interstitial_id  := ""
var _ads_ios_rewarded_id      := ""
var _ads_and_banner_id        := ""
var _ads_and_interstitial_id  := ""
var _ads_and_rewarded_id      := ""

var _ads_last_interstitial_time := 0
var _ads_banner_retrying := false
var _interstitial_loading := false
var _rewarded_loading := false
var _active_interstitial_ad: InterstitialAd
var _rewarded_showing := false
var _ads_banner_allowed := true
var _ads_last_rewarded_result: Dictionary = {}
var _ads_reward_apply_attempt_at := 0
var _ads_reward_apply_in_flight := false
var _ads_reward_apply_result: Array = []

func _ads_is_mobile() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

func ads_init(
	ios_banner_id: String,
	ios_interstitial_id: String,
	ios_rewarded_id: String,
	and_banner_id: String,
	and_interstitial_id: String,
	and_rewarded_id: String
) -> void:
	if ads_initialized:
		return
	if not _ads_is_mobile():
		return

	_ads_ios_banner_id = ios_banner_id
	_ads_ios_interstitial_id = ios_interstitial_id
	_ads_ios_rewarded_id = ios_rewarded_id
	_ads_and_banner_id = and_banner_id
	_ads_and_interstitial_id = and_interstitial_id
	_ads_and_rewarded_id = and_rewarded_id

	print("[ADS] MobileAds.initialize() (Global)")
	analytics_event("ad_sdk_init_requested", {})
	MobileAds.initialize()

	# --- CALLBACK OBJELERİ ---
	_interstitial_cb = InterstitialAdLoadCallback.new()
	_interstitial_cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		print("[ADS] interstitial failed_to_load: ", err.message)
		analytics_event("ad_load_failed", {"format": "interstitial", "code": err.code, "domain": err.domain})
		_interstitial_ad = null
		_interstitial_loading = false

	_interstitial_cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		print("[ADS] interstitial loaded (Global)")
		analytics_event("ad_load_succeeded", {"format": "interstitial"})
		_interstitial_ad = ad
		_interstitial_loading = false

	_rewarded_cb = RewardedAdLoadCallback.new()
	_rewarded_cb.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		print("[ADS] rewarded failed_to_load: ", err.message)
		analytics_event("ad_load_failed", {"format": "rewarded", "code": err.code, "domain": err.domain})
		_rewarded_ad = null
		_rewarded_loading = false

	_rewarded_cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		print("[ADS] rewarded loaded (Global)")
		analytics_event("ad_load_succeeded", {"format": "rewarded"})
		_rewarded_ad = ad
		_rewarded_loading = false

	_ads_load_banner()
	_ads_load_interstitial()
	_ads_load_rewarded()
	_ads_schedule_banner_retry()

	_ads_last_interstitial_time = 0
	ads_initialized = true


# ---------------- ID SEÇİMİ ----------------
func _ads_get_banner_unit_id() -> String:
	if OS.get_name() == "Android": return _ads_and_banner_id
	elif OS.get_name() == "iOS": return _ads_ios_banner_id
	return ""

func _ads_get_interstitial_unit_id() -> String:
	if OS.get_name() == "Android": return _ads_and_interstitial_id
	elif OS.get_name() == "iOS": return _ads_ios_interstitial_id
	return ""

func _ads_get_rewarded_unit_id() -> String:
	if OS.get_name() == "Android": return _ads_and_rewarded_id
	elif OS.get_name() == "iOS": return _ads_ios_rewarded_id
	return ""


# ---------------- LOAD FONKSİYONLARI ----------------
func _ads_load_banner() -> void:
	if not _ads_is_mobile(): return
	if is_ad_free_user(): return
	if not _ads_banner_allowed: return
	var unit_id := _ads_get_banner_unit_id()
	if unit_id == "":
		print("[ADS] Banner unit id bos")
		return

	if _banner_view:
		return

	print("[ADS] Banner load: ", unit_id)
	analytics_event("ad_load_requested", {"format": "banner"})
	_banner_view = AdView.new(unit_id, AdSize.BANNER, AdPosition.Values.BOTTOM)
	_banner_view.ad_listener.on_ad_loaded = func() -> void:
		print("[ADS] banner loaded")
		analytics_event("ad_load_succeeded", {"format": "banner"})
	_banner_view.ad_listener.on_ad_impression = func() -> void:
		print("[ADS] banner impression")
		analytics_event("ad_impression_confirmed", {"format": "banner"})
	_banner_view.ad_listener.on_ad_failed_to_load = func(err: LoadAdError) -> void:
		print("[ADS] banner failed_to_load: ", err.message)
		analytics_event("ad_load_failed", {"format": "banner", "code": err.code, "domain": err.domain})
		if _banner_view:
			_banner_view.destroy()
			_banner_view = null
		_ads_schedule_banner_retry()
	_banner_view.load_ad(AdRequest.new())

func _ads_schedule_banner_retry() -> void:
	if _ads_banner_retrying:
		return
	_ads_banner_retrying = true
	await get_tree().create_timer(4.0).timeout
	_ads_banner_retrying = false
	if _ads_is_mobile() and _ads_banner_allowed and not is_ad_free_user() and _banner_view == null:
		print("[ADS] Banner retry")
		_ads_load_banner()

func _ads_load_interstitial() -> void:
	if not _ads_is_mobile(): return
	if is_ad_free_user(): return
	if _interstitial_ad != null: return
	if _interstitial_loading: return
	var unit_id := _ads_get_interstitial_unit_id()
	if unit_id == "": return
	print("[ADS] Interstitial load: ", unit_id)
	analytics_event("ad_load_requested", {"format": "interstitial"})
	_interstitial_loading = true
	InterstitialAdLoader.new().load(unit_id, AdRequest.new(), _interstitial_cb)

func _ads_load_rewarded() -> void:
	if not _ads_is_mobile(): return
	if is_user_premium(): return
	if _rewarded_ad != null or _rewarded_loading or _rewarded_showing: return
	var unit_id := _ads_get_rewarded_unit_id()
	if unit_id == "": return
	print("[ADS] Rewarded load: ", unit_id)
	analytics_event("ad_load_requested", {"format": "rewarded"})
	_rewarded_loading = true
	RewardedAdLoader.new().load(unit_id, AdRequest.new(), _rewarded_cb)


# ---------------- DIŞARIDAN KULLANILAN API ----------------
func ads_on_focus_in() -> void:
	if not _ads_is_mobile(): return
	if not _ads_banner_allowed:
		ads_hide_banner()
		return
	if is_ad_free_user():
		ads_hide_banner()
		return
	if _banner_view:
		return
	else:
		_ads_load_banner()
		_ads_schedule_banner_retry()

func ads_hide_banner() -> void:
	if _banner_view:
		_banner_view.destroy()
		_banner_view = null

func ads_set_banner_allowed(allowed: bool) -> void:
	_ads_banner_allowed = allowed
	if not allowed:
		ads_hide_banner()
	elif _ads_is_mobile() and not is_ad_free_user():
		_ads_load_banner()

func ads_try_show_interstitial(chance: float, min_seconds_between: int) -> bool:
	if not _ads_is_mobile(): return false
	if is_ad_free_user(): return false
	if _active_interstitial_ad != null or _rewarded_showing: return false
	if _interstitial_ad == null:
		_ads_load_interstitial()
		return false

	var now := Time.get_unix_time_from_system()
	if (now - _ads_last_interstitial_time) < min_seconds_between:
		return false
	if randf() >= chance:
		return false

	print("[ADS] Interstitial show (Global)")
	_active_interstitial_ad = _interstitial_ad
	_interstitial_ad = null
	var ad_instance := _active_interstitial_ad.get_instance_id()
	_active_interstitial_ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = _ads_finish_interstitial.bind(ad_instance)
	_active_interstitial_ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = _ads_interstitial_failed.bind(ad_instance)
	_active_interstitial_ad.full_screen_content_callback.on_ad_impression = func() -> void:
		analytics_event("ad_impression_confirmed", {"format": "interstitial"})
	_active_interstitial_ad.show()
	@warning_ignore("narrowing_conversion")
	_ads_last_interstitial_time = now
	_ads_load_interstitial()
	return true

func _ads_finish_interstitial(ad_instance: int) -> void:
	if _active_interstitial_ad == null or _active_interstitial_ad.get_instance_id() != ad_instance:
		return
	_active_interstitial_ad.destroy()
	_active_interstitial_ad = null
	_ads_load_interstitial()

func _ads_interstitial_failed(error: AdError, ad_instance: int) -> void:
	analytics_event("ad_show_failed", {"format": "interstitial", "code": error.code, "domain": error.domain})
	_ads_finish_interstitial(ad_instance)

func ads_preload_interstitial() -> void:
	_ads_load_interstitial()

func ads_has_interstitial_ready() -> bool:
	return _interstitial_ad != null

func ads_show_interstitial_when_ready(timeout_seconds: float = 4.0) -> bool:
	if not _ads_is_mobile(): return false
	if is_ad_free_user(): return false

	if _interstitial_ad == null:
		_ads_load_interstitial()

	var started_ms := Time.get_ticks_msec()
	var timeout_ms := int(maxf(timeout_seconds, 0.0) * 1000.0)
	while _interstitial_ad == null and Time.get_ticks_msec() - started_ms < timeout_ms:
		await get_tree().create_timer(0.1).timeout

	if _interstitial_ad == null:
		print("[ADS] Interstitial not ready after wait")
		_ads_load_interstitial()
		return false

	return ads_try_show_interstitial(1.0, 0)

func ads_has_rewarded_ready() -> bool:
	return _rewarded_ad != null

func ads_load_rewarded() -> void:
	_ads_load_rewarded()

func ads_show_rewarded() -> bool:
	if not _ads_is_mobile(): return false
	if is_user_premium(): return false
	if _rewarded_showing or _active_interstitial_ad != null: return false
	if _rewarded_ad == null:
		print("[ADS] Rewarded yok, yeniden yükleniyor")
		_ads_load_rewarded()
		return false
	# Keep the non-awaiting API while sharing presentation ownership and cleanup.
	ads_show_rewarded_and_wait()
	return true

func _ads_apply_rewarded_boost_once(uid: String, attempt_at: int, reason: String) -> void:
	if uid == "" or attempt_at <= 0:
		return
	if _ads_reward_apply_attempt_at == attempt_at and (_ads_reward_apply_in_flight or not _ads_reward_apply_result.is_empty()):
		return
	_ads_reward_apply_attempt_at = attempt_at
	_ads_reward_apply_in_flight = true
	_ads_reward_apply_result = []
	_ads_reward_apply_result = await activate_rewarded_boost(uid, attempt_at)
	_ads_reward_apply_in_flight = false
	print("[ADS] Rewarded server apply reason=", reason, " ok=", _ads_reward_apply_result.size() > 0 and bool(_ads_reward_apply_result[0]))
	if _ads_reward_apply_result.size() > 1 and bool(_ads_reward_apply_result[0]):
		var payload: Dictionary = {}
		if typeof(_ads_reward_apply_result[1]) == TYPE_DICTIONARY:
			payload = (_ads_reward_apply_result[1] as Dictionary).duplicate(true)
		payload["attempt_at"] = attempt_at
		payload["reason"] = reason
		mining_rate = float(payload.get("total_rate", mining_rate))
		rewarded_boost_applied.emit(payload)

func ads_show_rewarded_and_wait(
	timeout_seconds: float = 180.0,
	reward_uid: String = "",
	attempt_at: int = 0
) -> bool:
	if not _ads_is_mobile(): return false
	if is_user_premium(): return false
	if _rewarded_showing or _active_interstitial_ad != null: return false
	_ads_last_rewarded_result = {}
	if _rewarded_ad == null:
		print("[ADS] Rewarded yok, yeniden yükleniyor")
		_ads_load_rewarded()
		return false

	# Dictionaries are shared by GDScript callbacks; scalar captures are copies.
	var state := {"completed": false, "closed": false, "failed_to_show": false,
		"showed": false, "impression": false, "closed_at_ms": -1, "earned_at_ms": -1}
	_rewarded_showing = true
	var ad := _rewarded_ad
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_rewarded_item: RewardedItem) -> void:
		print("[ADS] Rewarded earned (Global)")
		state.completed = true
		state.earned_at_ms = Time.get_ticks_msec()
		# Signed AdMob SSV callback applies the reward on the server.

	ad.full_screen_content_callback.on_ad_dismissed_full_screen_content = func() -> void:
		print("[ADS] Rewarded dismissed (Global)")
		state.closed = true
		state.closed_at_ms = Time.get_ticks_msec()
	ad.full_screen_content_callback.on_ad_showed_full_screen_content = func() -> void:
		print("[ADS] Rewarded showed (Global)")
		state.showed = true
	ad.full_screen_content_callback.on_ad_impression = func() -> void:
		print("[ADS] Rewarded impression (Global)")
		state.impression = true
		analytics_event("ad_impression_confirmed", {"format": "rewarded"})
	ad.full_screen_content_callback.on_ad_failed_to_show_full_screen_content = func(ad_error: AdError) -> void:
		print("[ADS] Rewarded failed_to_show (Global)")
		analytics_event("ad_show_failed", {"format": "rewarded", "code": ad_error.code, "domain": ad_error.domain})
		state.failed_to_show = true
		state.closed = true
		state.closed_at_ms = Time.get_ticks_msec()

	var started := Time.get_ticks_msec()
	print("[ADS] Rewarded show and wait (Global)")
	_rewarded_ad = null
	if reward_uid != "" and attempt_at > 0:
		var ssv_options := ServerSideVerificationOptions.new()
		ssv_options.user_id = reward_uid
		ssv_options.custom_data = str(attempt_at)
		ad.set_server_side_verification_options(ssv_options)
	ad.show(listener)

	var timeout_ms := int(maxf(timeout_seconds, 0.0) * 1000.0)
	var result_reason := "timeout"
	while Time.get_ticks_msec() - started < timeout_ms:
		if state.failed_to_show:
			result_reason = "failed_to_show"
			break
		if state.closed:
			if state.completed:
				result_reason = "earned"
				break
			if state.closed_at_ms > 0 and Time.get_ticks_msec() - state.closed_at_ms > 1000:
				result_reason = "dismissed_without_reward"
				break
		await get_tree().process_frame

	if state.completed and result_reason == "timeout":
		result_reason = "earned_without_dismiss_callback"
	var finished_at_ms := Time.get_ticks_msec()
	_ads_last_rewarded_result = {
		"completed": state.completed,
		"reason": result_reason,
		"duration_ms": finished_at_ms - started,
		"earned_after_ms": state.earned_at_ms - started if state.earned_at_ms >= started else -1,
		"closed": state.closed,
		"showed": state.showed,
		"impression": state.impression
	}
	print("[ADS] Rewarded result: ", _ads_last_rewarded_result)

	if ad != null:
		ad.destroy()
	_rewarded_showing = false
	_ads_load_rewarded()
	return bool(state.completed)

func ads_get_last_rewarded_result() -> Dictionary:
	return _ads_last_rewarded_result.duplicate(true)

func start_apple_login() -> void:
	print("IOS feature=", OS.has_feature("ios"))
	print("APPLE SINGLETON AppleSignIn:", Engine.has_singleton("AppleSignIn"))

	if Engine.has_singleton("AppleSignIn"):
		var apple = Engine.get_singleton("AppleSignIn")
		print("AppleSignIn methods: sign_in=", apple.has_method("sign_in"))
		print("AppleSignIn signal sign_in_completed=", apple.has_signal("sign_in_completed"))


var current_user: Dictionary = {}

func firestore_get_user(uid: String) -> Array:
	await ensure_token_fresh(60)
	var url := "%s/%s" % [firestore_url, uid]
	return await http_request(url, HTTPClient.METHOD_GET, _auth_headers(), "")

func firestore_load_or_create_user(uid: String, email: String, referral_code: String = "") -> bool:
	var ok := await ensure_user_doc(uid, email, _clean_referral_code(referral_code))
	if not ok:
		return false
	var loaded: Dictionary = await get_user_doc(uid)
	if loaded.is_empty():
		return false
	current_user = loaded
	return true

# ===================== ATT (iOS Tracking Permission) =====================

func _att_is_ios() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("ios")

func _att_get_plugin() -> Object:
	for singleton_name in ["AppTrackingTransparency", "ATTrackingManager", "ATT"]:
		if Engine.has_singleton(singleton_name):
			return Engine.get_singleton(singleton_name)
	return null

func _att_read_status(plugin: Object) -> int:
	for method in ["get_tracking_authorization_status", "getStatus", "get_status", "tracking_authorization_status"]:
		if plugin.has_method(method):
			var value = plugin.call(method)
			if typeof(value) == TYPE_INT and value >= 0 and value <= 3:
				return value
	return -1

func request_att_permission() -> int:
	# -1=unknown/unavailable, 0=not determined, 1=restricted, 2=denied, 3=authorized.
	if not _att_is_ios():
		return -1
	var plugin := _att_get_plugin()
	if plugin == null:
		return -1
	# Read iOS on every call: users can change their choice in Settings.
	# A local cached value (including old fallback "3") is not authorization.
	var status := _att_read_status(plugin)
	if status == -1 or status == 0:
		for method in ["request_tracking_authorization", "requestAuthorization", "request_authorization", "requestTrackingAuthorization", "request"]:
			if not plugin.has_method(method):
				continue
			var result = await plugin.call(method)
			if typeof(result) == TYPE_ARRAY and not result.is_empty():
				result = result[0]
			if typeof(result) == TYPE_INT and result >= 0 and result <= 3:
				status = result
			else:
				status = _att_read_status(plugin)
			break
	return status

func ads_init_after_att(
	ios_banner_id: String,
	ios_interstitial_id: String,
	ios_rewarded_id: String,
	and_banner_id: String,
	and_interstitial_id: String,
	and_rewarded_id: String
) -> void:
	# iOS'ta önce ATT sor, sonra ads_init
	if OS.get_name() == "iOS" or OS.has_feature("ios"):
		var st := await request_att_permission()
		print("[ATT] status=", st, " (0=notDetermined,2=denied,3=authorized)")
		# Denied olsa bile AdMob çalışır, sadece IDFA olmaz → yine init edebiliriz.
	ads_init(ios_banner_id, ios_interstitial_id, ios_rewarded_id, and_banner_id, and_interstitial_id, and_rewarded_id)

	# global.gd içindeki yeni fonksiyon
func trigger_ios_google_login() -> void:
	if OS.get_name() == "iOS":
		var path = OS.get_user_data_dir() + "/signin_request.tmp"
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string("login")
			file.close()
			print("[Global] iOS Giriş sinyali dosyaya yazıldı.")
	else:
		# iOS değilse (Android veya Desktop) mevcut PKCE akışını başlatabilirsin
		print("[Global] iOS dışı platform tetiklendi.")

func maybe_request_store_review(reason: String = "positive_action") -> bool:
	if not _is_store_review_platform():
		return false

	var cfg := ConfigFile.new()
	cfg.load(_REVIEW_PROMPT_STATE_PATH)
	var now := int(Time.get_unix_time_from_system())
	var positive_actions := int(cfg.get_value("review", "positive_actions", 0)) + 1
	var last_prompt := int(cfg.get_value("review", "last_prompt_unix", 0))
	cfg.set_value("review", "positive_actions", positive_actions)

	if positive_actions < _REVIEW_PROMPT_MIN_POSITIVE_ACTIONS:
		cfg.save(_REVIEW_PROMPT_STATE_PATH)
		return false

	if last_prompt > 0 and now - last_prompt < _REVIEW_PROMPT_COOLDOWN_SECONDS:
		cfg.save(_REVIEW_PROMPT_STATE_PATH)
		return false

	var prompted := false
	if _is_ios_platform():
		prompted = _trigger_ios_store_review(reason, now)
	elif _is_android_platform():
		prompted = _trigger_android_store_review_if_available()

	if prompted:
		cfg.set_value("review", "last_prompt_unix", now)
		analytics_event("store_review_prompt_request", {
			"reason": reason,
			"positive_actions": positive_actions
		})
	cfg.save(_REVIEW_PROMPT_STATE_PATH)
	return prompted

func open_store_listing() -> void:
	if _is_android_platform():
		OS.shell_open(APP_LINK_ANDROID)
	elif _is_ios_platform():
		OS.shell_open(APP_LINK_IOS)

func _is_store_review_platform() -> bool:
	return _is_ios_platform() or _is_android_platform()

func _is_ios_platform() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("ios")

func _is_android_platform() -> bool:
	return OS.get_name() == "Android" or OS.has_feature("android")

func _trigger_ios_store_review(reason: String, timestamp: int) -> bool:
	var path := OS.get_user_data_dir() + "/review_request.tmp"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[STORE] iOS review request file could not be opened.")
		return false
	file.store_string(JSON.stringify({
		"reason": reason,
		"ts": timestamp
	}))
	file.close()
	print("[STORE] iOS review request queued.")
	return true

func _trigger_android_store_review_if_available() -> bool:
	var singleton_names := [
		"InAppReview",
		"InappReviewPlugin",
		"InAppReviewPlugin",
		"GodotInAppReview",
		"ReviewPlugin"
	]
	var method_names := [
		"request_review",
		"requestReview",
		"launch_review_flow",
		"launchReviewFlow",
		"show",
		"request"
	]

	for singleton_name in singleton_names:
		if not Engine.has_singleton(singleton_name):
			continue
		var plugin := Engine.get_singleton(singleton_name)
		for method_name in method_names:
			if plugin != null and plugin.has_method(method_name):
				plugin.call(method_name)
				print("[STORE] Android review request sent via ", singleton_name, ".", method_name)
				return true

	print("[STORE] Android in-app review plugin not available; prompt skipped.")
	OS.shell_open(APP_LINK_ANDROID)
	print("[STORE] Android review fallback opened Play Store listing.")
	return true

	# ======================================================================
	#                           R O Z E T   S İ S T E M İ
	# ======================================================================

const BADGE_STARTER = "starter"
const BADGE_PRO = "pro"
const BADGE_MASTER = "master"
const BADGE_VETERAN = "veteran"
const BADGE_LEGEND = "legend"

func get_badge_from_points(points: float) -> String:
	if points >= 100000:
		return BADGE_LEGEND
	elif points >= 50000:
		return BADGE_MASTER
	elif points >= 10000:
		return BADGE_PRO
	elif points >= 1000:
		return BADGE_STARTER
	return ""

func get_badge_display_name(badge: String) -> String:
	match badge:
		BADGE_STARTER: return localized_named_key("badge_starter")
		BADGE_PRO: return localized_named_key("badge_pro")
		BADGE_MASTER: return localized_named_key("badge_master")
		BADGE_VETERAN: return localized_named_key("badge_veteran")
		BADGE_LEGEND: return localized_named_key("badge_legend")
		_: return ""

func get_badge_color(badge: String) -> Color:
	match badge:
		BADGE_STARTER: return Color("#22c55e")
		BADGE_PRO: return Color("#3b82f6")
		BADGE_MASTER: return Color("#a855f7")
		BADGE_VETERAN: return Color("#f59e0b")
		BADGE_LEGEND: return Color("#ef4444")
		_: return Color("#94a3b8")

# ======================================================================
#                           S E V İ Y E / X P   S İ S T E M İ
# ======================================================================

func get_xp_for_level(level: int) -> int:
	return int(100 * pow(1.5, level - 1))

func get_level_from_xp(xp: int) -> int:
	var level := 1
	var total_xp := 0
	while total_xp <= xp:
		total_xp += get_xp_for_level(level)
		if total_xp > xp:
			return level
		level += 1
	return level

func get_xp_progress(xp: int) -> Dictionary:
	var level := get_level_from_xp(xp)
	var prev_level_xp := 0
	for i in range(1, level):
		prev_level_xp += get_xp_for_level(i)
	var current_level_xp := xp - prev_level_xp
	var needed_xp := get_xp_for_level(level)
	var progress := float(current_level_xp) / float(needed_xp)
	return {
		"level": level,
		"current_xp": current_level_xp,
		"needed_xp": needed_xp,
		"progress": progress
	}

func add_xp(uid: String, xp_amount: int) -> Array:
	await ensure_token_fresh(60)

	var doc := await get_user_doc(uid)
	if doc.is_empty() or not doc.has("fields"):
		return [false, "User doc not found"]

	var fields: Dictionary = doc["fields"]
	var current_xp := _firestore_int(fields, "xp", 0)
	var new_xp := current_xp + xp_amount
	var old_level := get_level_from_xp(current_xp)
	var new_level := get_level_from_xp(new_xp)

	var update_fields := {
		"xp": {"integerValue": new_xp},
		"level": {"integerValue": new_level}
	}

	var masks := ["updateMask.fieldPaths=xp", "updateMask.fieldPaths=level"]
	var url := "%s/%s?%s" % [firestore_url, uid, "&".join(masks)]
	var res: Array = await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": update_fields}))

	if res[0] and int(res[1]) in [200, 201]:
		var level_up := new_level > old_level
		return [true, {
			"xp": new_xp,
			"level": new_level,
			"level_up": level_up,
			"old_level": old_level
		}]

	return [false, "XP update failed"]

# ======================================================================
#                   D A I L Y   S T R E A K   B O N U S
# ======================================================================

func get_streak_bonus(streak: int) -> float:
	if streak >= 100:
		return 3.0
	elif streak >= 30:
		return 2.0
	elif streak >= 7:
		return 1.5
	return 1.0

func update_daily_streak(uid: String) -> Array:
	await ensure_token_fresh(60)

	var doc: Dictionary = await get_user_doc(uid)
	if doc.is_empty() or not doc.has("fields"):
		return [false, "User doc not found"]

	var fields: Dictionary = doc["fields"]
	var now := int(Time.get_unix_time_from_system())
	var last_login := _firestore_int(fields, "lastLoginDate", 0)
	var current_streak := _firestore_int(fields, "dailyStreak", 0)

	var days_since_last := 0
	if last_login > 0:
		days_since_last = (now - last_login) / 86400

	var new_streak := current_streak
	var streak_bonus := 1.0
	var bonus_message := ""

	if days_since_last <= 1:
		new_streak += 1
		streak_bonus = get_streak_bonus(new_streak)

		if new_streak == 7:
			bonus_message = localized_named_key("streak_7_bonus")
		elif new_streak == 30:
			bonus_message = localized_named_key("streak_30_bonus")
		elif new_streak == 100:
			bonus_message = localized_named_key("streak_100_bonus")
	else:
		new_streak = 1
		streak_bonus = 1.0
		bonus_message = localized_named_key("streak_reset")

	var update_fields := {
		"lastLoginDate": {"integerValue": now},
		"dailyStreak": {"integerValue": new_streak},
		"streakBonus": {"doubleValue": streak_bonus}
	}

	var masks := ["updateMask.fieldPaths=lastLoginDate", "updateMask.fieldPaths=dailyStreak", "updateMask.fieldPaths=streakBonus"]
	var url := "%s/%s?%s" % [firestore_url, uid, "&".join(masks)]
	var res: Array = await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": update_fields}))

	if res[0] and int(res[1]) in [200, 201]:
		return [true, {
			"streak": new_streak,
			"bonus": streak_bonus,
			"message": bonus_message
		}]

	return [false, "Streak update failed"]

# ======================================================================
#                     A C H I E V E M E N T   S İ S T E M İ
# ======================================================================

const ACH_FIRST_MINING = "first_mining"
const ACH_100_POINTS = "100_points"
const ACH_1000_POINTS = "1000_points"
const ACH_10000_POINTS = "10000_points"
const ACH_FIRST_REFERRAL = "first_referral"
const ACH_10_REFERRALS = "10_referrals"
const ACH_7_DAY_STREAK = "7_day_streak"
const ACH_30_DAY_STREAK = "30_day_streak"
const ACH_PREMIUM_MEMBER = "premium_member"

var _achievements_data := {
	ACH_FIRST_MINING: {"name": "ach_first_mining", "xp": 10},
	ACH_100_POINTS: {"name": "ach_100_points", "xp": 20},
	ACH_1000_POINTS: {"name": "ach_1000_points", "xp": 50},
	ACH_10000_POINTS: {"name": "ach_10000_points", "xp": 100},
	ACH_FIRST_REFERRAL: {"name": "ach_first_referral", "xp": 30},
	ACH_10_REFERRALS: {"name": "ach_10_referrals", "xp": 100},
	ACH_7_DAY_STREAK: {"name": "ach_7_day_streak", "xp": 50},
	ACH_30_DAY_STREAK: {"name": "ach_30_day_streak", "xp": 200},
	ACH_PREMIUM_MEMBER: {"name": "ach_premium_member", "xp": 150}
}

func unlock_achievement(uid: String, achievement_id: String) -> Array:
	await ensure_token_fresh(60)

	if not _achievements_data.has(achievement_id):
		return [false, "Invalid achievement"]

	var doc: Dictionary = await get_user_doc(uid)
	if doc.is_empty() or not doc.has("fields"):
		return [false, "User doc not found"]

	var fields: Dictionary = doc["fields"]
	var achievements: Dictionary = {}
	if fields.has("achievements") and fields["achievements"].has("arrayValue"):
		var arr: Array = fields["achievements"]["arrayValue"].get("values", [])
		for item in arr:
			if item.has("stringValue"):
				achievements[item["stringValue"]] = true

	if achievements.has(achievement_id):
		return [true, {"already_unlocked": true}]

	achievements[achievement_id] = true
	var ach_data: Dictionary = _achievements_data[achievement_id]
	var xp_reward: int = int(ach_data.get("xp", 0))

	var achievements_array := []
	for key in achievements.keys():
		achievements_array.append({"stringValue": key})

	var update_fields := {
		"achievements": {"arrayValue": {"values": achievements_array}}
	}

	var masks := ["updateMask.fieldPaths=achievements"]
	var url := "%s/%s?%s" % [firestore_url, uid, "&".join(masks)]
	var res: Array = await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": update_fields}))

	if res[0] and int(res[1]) in [200, 201]:
		if xp_reward > 0:
			await add_xp(uid, xp_reward)
		return [true, {
			"achievement": achievement_id,
			"name": ach_data["name"],
			"xp": xp_reward,
			"new": true
		}]

	return [false, "Achievement unlock failed"]

func check_and_unlock_achievements(uid: String) -> Array:
	await ensure_token_fresh(60)

	if Firebase == null or not Firebase.has_method("sync_achievements"):
		return [false, "Achievement service unavailable"]
	var result: Dictionary = await Firebase.sync_achievements()
	if not bool(result.get("ok", false)):
		return [false, str(result.get("error", "Achievement sync failed"))]
	var unlocked: Variant = result.get("unlocked", [])
	return [true, unlocked if typeof(unlocked) == TYPE_ARRAY else []]

# ======================================================================
#                     R A T E   L I M I T I N G
# ======================================================================

var _rate_limits := {}
var _rate_limit_config := {
	"mining": {"max_calls": 1, "window_ms": 86400000},
	"login": {"max_calls": 5, "window_ms": 300000},
	"register": {"max_calls": 3, "window_ms": 3600000},
	"password_reset": {"max_calls": 3, "window_ms": 3600000},
	"referral_check": {"max_calls": 10, "window_ms": 60000}
}

func check_rate_limit(action: String, uid: String = "") -> bool:
	var key := action
	if uid != "":
		key = "%s_%s" % [action, uid]

	var now := int(Time.get_unix_time_from_system() * 1000)

	if not _rate_limits.has(key):
		_rate_limits[key] = {"calls": [], "config": _rate_limit_config.get(action, {"max_calls": 10, "window_ms": 60000})}

	var limit_data: Dictionary = _rate_limits[key]
	var config: Dictionary = limit_data["config"]
	var calls := limit_data["calls"] as Array

	var window_start: int = now - int(config["window_ms"])
	calls = calls.filter(func(timestamp: Variant) -> bool: return int(timestamp) > window_start)
	limit_data["calls"] = calls

	if calls.size() >= config["max_calls"]:
		print("[RATE_LIMIT] %s blocked for %s (limit: %d/%d)" % [action, uid if uid != "" else "global", calls.size(), config["max_calls"]])
		return false

	calls.append(now)
	return true

func get_rate_limit_remaining(action: String, uid: String = "") -> int:
	var key := action
	if uid != "":
		key = "%s_%s" % [action, uid]

	if not _rate_limits.has(key):
		return _rate_limit_config.get(action, {"max_calls": 10, "window_ms": 60000})["max_calls"]

	var limit_data: Dictionary = _rate_limits[key]
	var config: Dictionary = limit_data["config"]
	var calls := limit_data["calls"] as Array

	var now := int(Time.get_unix_time_from_system() * 1000)
	var window_start: int = now - int(config["window_ms"])
	calls = calls.filter(func(timestamp: Variant) -> bool: return int(timestamp) > window_start)

	return max(0, config["max_calls"] - calls.size())

func reset_rate_limit(action: String, uid: String = "") -> void:
	var key := action
	if uid != "":
		key = "%s_%s" % [action, uid]

	if _rate_limits.has(key):
		_rate_limits.erase(key)

# ======================================================================
#                     G R U P / T E A M   S İ S T E M İ
# ======================================================================

func create_team(team_name: String, _team_code: String = "") -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("team_create"):
		return [false, "Team service unavailable"]
	var result: Dictionary = await firebase.team_create(team_name)
	return [bool(result.get("ok", false)), result]

func join_team(team_code: String) -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("team_join"):
		return [false, "Team service unavailable"]
	var result: Dictionary = await firebase.team_join(team_code)
	return [bool(result.get("ok", false)), result]

func leave_team() -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("team_leave"):
		return [false, "Team service unavailable"]
	var result: Dictionary = await firebase.team_leave()
	return [bool(result.get("ok", false)), result]

func get_team_leaderboard(limit := 50) -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("team_leaderboard"):
		return []
	var result: Dictionary = await firebase.team_leaderboard(limit)
	return result.get("teams", []) if bool(result.get("ok", false)) else []

func get_my_team() -> Dictionary:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("team_info"):
		return {"ok": false, "error": "Team service unavailable"}
	return await firebase.team_info()

# ======================================================================
#                     A C T I V I T Y   F E E D
# ======================================================================

func log_activity(activity_type: String, data: Dictionary = {}) -> Array:
	await ensure_token_fresh(60)

	var my_uid := get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	var activity_url := "https://firestore.googleapis.com/v1/projects/candar-network-007/databases/(default)/documents/activities/%s_%d" % [my_uid, int(Time.get_unix_time_from_system() * 1000)]

	var fields: Dictionary = {
		"userId": {"stringValue": my_uid},
		"activityType": {"stringValue": activity_type},
		"timestamp": {"integerValue": int(Time.get_unix_time_from_system())},
		"data": {"stringValue": JSON.stringify(data)}
	}

	var body := JSON.stringify({"fields": fields})
	var res: Array = await http_request(activity_url, HTTPClient.METHOD_POST, _auth_headers(), body)

	if res[0] and int(res[1]) in [200, 201]:
		var activity_parts := activity_url.split("/")
		return [true, {"activity_id": activity_parts[activity_parts.size() - 1]}]

	return [false, "Activity log failed"]

# ======================================================================
#                 P U S H   N O T I F I C A T I O N S
# ======================================================================

func register_push_token(token: String, platform: String) -> Array:
	await ensure_token_fresh(60)

	var my_uid := get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	var doc := await get_user_doc(my_uid)
	if doc.is_empty():
		return [false, "User not found"]

	var fields := {
		"pushToken": {"stringValue": token},
		"pushPlatform": {"stringValue": platform},
		"pushTokenUpdatedAt": {"integerValue": int(Time.get_unix_time_from_system())},
		"language": {"stringValue": current_lang},
		"locale": {"stringValue": OS.get_locale()}
	}

	var masks := [
		"updateMask.fieldPaths=pushToken",
		"updateMask.fieldPaths=pushPlatform",
		"updateMask.fieldPaths=pushTokenUpdatedAt",
		"updateMask.fieldPaths=language",
		"updateMask.fieldPaths=locale"
	]
	var url := "%s/%s?%s" % [firestore_url, my_uid, "&".join(masks)]
	var res := await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": fields}))

	if res[0] and int(res[1]) in [200, 201]:
		return [true, {"token_registered": true}]

	return [false, "Token registration failed"]

func sync_user_engagement_metadata(uid: String = "", known_fields: Dictionary = {}) -> Array:
	await ensure_token_fresh(60)

	var my_uid := uid if uid != "" else get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	var source_fields := known_fields
	if source_fields.is_empty():
		var doc := await get_user_doc(my_uid)
		if typeof(doc) == TYPE_DICTIONARY and doc.has("fields"):
			source_fields = doc["fields"]

	var platform := _platform_kind()
	var now := int(Time.get_unix_time_from_system())
	var today := int(now / 86400)
	var first_open := _firestore_int(source_fields, "firstAppOpenAt", 0)
	var first_open_day := _firestore_int(source_fields, "firstOpenDay", 0)
	var previous_open_day := _firestore_int(source_fields, "lastOpenDay", 0)
	var already_retained_day_1 := _firestore_string(source_fields, "retainedDay1", "false") == "true"
	var already_retained_day_7 := _firestore_string(source_fields, "retainedDay7", "false") == "true"
	var app_open_count := _firestore_int(source_fields, "appOpenCount", 0) + 1
	var fields := {
		"language": {"stringValue": current_lang},
		"locale": {"stringValue": OS.get_locale()},
		"pushPlatform": {"stringValue": platform},
		"lastAppOpenAt": {"integerValue": now},
		"lastOpenDay": {"integerValue": today},
		"appOpenCount": {"integerValue": app_open_count},
		"lastKnownVersion": {"stringValue": ProjectSettings.get_setting("application/config/version", "2.0.1")}
	}

	if first_open <= 0:
		fields["firstAppOpenAt"] = {"integerValue": now}
	if first_open_day <= 0:
		first_open_day = today
		fields["firstOpenDay"] = {"integerValue": today}
	if first_open_day > 0 and today >= first_open_day + 1:
		fields["retainedDay1"] = {"booleanValue": true}
	if first_open_day > 0 and today >= first_open_day + 7:
		fields["retainedDay7"] = {"booleanValue": true}
	if previous_open_day > 0 and previous_open_day != today:
		fields["returningSessionAt"] = {"integerValue": now}

	var masks := []
	for k in fields.keys():
		masks.append("updateMask.fieldPaths=%s" % k)
	var url := "%s/%s?%s" % [firestore_url, my_uid, "&".join(masks)]
	var res := await http_request(url, HTTPClient.METHOD_PATCH, _auth_headers(), JSON.stringify({"fields": fields}))
	if res.size() >= 2 and bool(res[0]) and int(res[1]) in [200, 201]:
		var days_since_first_open: int = maxi(0, today - first_open_day)
		analytics_event("app_engagement_sync", {
			"app_open_count": app_open_count,
			"days_since_first_open": days_since_first_open,
			"returning_session": previous_open_day > 0 and previous_open_day != today
		})
		if days_since_first_open >= 1 and not already_retained_day_1:
			analytics_event("day_1_return", {"days_since_first_open": days_since_first_open})
		if days_since_first_open >= 7 and not already_retained_day_7:
			analytics_event("day_7_return", {"days_since_first_open": days_since_first_open})
		return [true, {"synced": true, "app_open_count": app_open_count}]
	return [false, "Engagement metadata sync failed"]

var _native_push_token_retry_active := false

func sync_native_push_token_if_available() -> Array:
	var token_file := "user://fcm_token.json"
	if not FileAccess.file_exists(token_file):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if docs != "":
			var alt := docs.path_join("fcm_token.json")
			if FileAccess.file_exists(alt):
				token_file = alt

	if not FileAccess.file_exists(token_file):
		_schedule_native_push_token_retry()
		return [false, "No native push token"]

	var f := FileAccess.open(token_file, FileAccess.READ)
	if f == null:
		return [false, "Push token file could not be opened"]
	var txt := f.get_as_text()
	f.close()

	var parsed := JSON.new()
	if parsed.parse(txt) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return [false, "Push token file is invalid"]

	var data: Dictionary = parsed.data
	var token := String(data.get("token", "")).strip_edges()
	var platform := String(data.get("platform", _platform_kind())).strip_edges()
	if token == "":
		return [false, "Push token is empty"]

	var result := await register_push_token(token, platform)
	if result.size() > 0 and bool(result[0]):
		_native_push_token_retry_active = false
	return result

func _schedule_native_push_token_retry() -> void:
	if _native_push_token_retry_active or not (OS.has_feature("android") or OS.has_feature("ios")) or get_uid() == "":
		return
	_native_push_token_retry_active = true
	call_deferred("_retry_native_push_token_sync")

func _retry_native_push_token_sync() -> void:
	# İlk kurulumda FCM tokenı oturum açma/veri yükleme akışından sonra
	# üretilebilir. Tek seferlik kontrol bu cihazı sonsuza dek push dışında
	# bırakıyordu; UI'ı bloklamadan kısa süre yeniden dene.
	for _attempt in range(30):
		if get_uid() == "":
			break
		var token_file := "user://fcm_token.json"
		if FileAccess.file_exists(token_file):
			var result := await sync_native_push_token_if_available()
			if result.size() > 0 and bool(result[0]):
				_native_push_token_retry_active = false
				return
		await get_tree().create_timer(1.0).timeout
	_native_push_token_retry_active = false

func send_push_notification(target_uid: String, title: String, body: String, data: Dictionary = {}) -> Array:
	await ensure_token_fresh(60)

	var target_doc: Dictionary = await get_user_doc(target_uid)
	if target_doc.is_empty():
		return [false, "Target user not found"]

	var fields: Dictionary = target_doc["fields"]
	var push_token := ""
	if fields.has("pushToken") and fields["pushToken"].has("stringValue"):
		push_token = fields["pushToken"]["stringValue"]

	if push_token == "":
		return [false, "No push token for user"]

	var notification_data := {
		"to": push_token,
		"notification": {
			"title": title,
			"body": body
		},
		"data": data
	}

	var fcm_url := "https://fcm.googleapis.com/fcm/send"
	var headers := _auth_headers()
	headers.append("Content-Type: application/json")
	headers.append("Authorization: key=YOUR_FCM_SERVER_KEY")

	var res := await http_request(fcm_url, HTTPClient.METHOD_POST, headers, JSON.stringify(notification_data))

	if res[0] and int(res[1]) in [200, 201]:
		return [true, {"notification_sent": true}]

	return [false, "Notification send failed"]

# ======================================================================
#                   F I R E B A S E   C R A S H L Y T I C S
# ======================================================================

var _crashlytics_enabled := false

func init_crashlytics() -> void:
	if OS.has_feature("android") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("init"):
			crashlytics.init()
			_crashlytics_enabled = true
			print("[CRASHLYTICS] Initialized on Android")
	elif OS.has_feature("ios") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("init"):
			crashlytics.init()
			_crashlytics_enabled = true
			print("[CRASHLYTICS] Initialized on iOS")
	else:
		print("[CRASHLYTICS] Plugin not found or not supported on this platform")

func log_crash(message: String, stack_trace: String = "") -> void:
	if not _crashlytics_enabled:
		print("[CRASHLYTICS] Not enabled, logging to console: %s" % message)
		print(stack_trace)
		return

	if OS.has_feature("android") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("log"):
			crashlytics.log(message)
			if stack_trace != "":
				crashlytics.log(stack_trace)
	elif OS.has_feature("ios") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("log"):
			crashlytics.log(message)
			if stack_trace != "":
				crashlytics.log(stack_trace)

func set_crashlytics_user_id(uid: String) -> void:
	if not _crashlytics_enabled:
		return

	if OS.has_feature("android") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("setUserId"):
			crashlytics.setUserId(uid)
	elif OS.has_feature("ios") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("setUserId"):
			crashlytics.setUserId(uid)

func set_crashlytics_custom_key(key: String, value: String) -> void:
	if not _crashlytics_enabled:
		return

	if OS.has_feature("android") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("setCustomKey"):
			crashlytics.setCustomKey(key, value)
	elif OS.has_feature("ios") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("setCustomKey"):
			crashlytics.setCustomKey(key, value)

func record_custom_exception(exception_name: String, reason: String) -> void:
	if not _crashlytics_enabled:
		print("[CRASHLYTICS] Exception: %s - %s" % [exception_name, reason])
		return

	if OS.has_feature("android") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("recordException"):
			crashlytics.recordException(exception_name, reason)
	elif OS.has_feature("ios") and Engine.has_singleton("FirebaseCrashlytics"):
		var crashlytics = Engine.get_singleton("FirebaseCrashlytics")
		if crashlytics and crashlytics.has_method("recordException"):
			crashlytics.recordException(exception_name, reason)

# ======================================================================
#                     O F F L I N E   M O D E
# ======================================================================

const CACHE_FILE := "user://offline_cache.json"
var _offline_cache := {}
var _is_offline := false

func load_offline_cache() -> void:
	if FileAccess.file_exists(CACHE_FILE):
		var file := FileAccess.open(CACHE_FILE, FileAccess.READ)
		if file:
			var json_str := file.get_as_text()
			file.close()
			var json := JSON.new()
			var parse_result := json.parse(json_str)
			if parse_result == OK:
				_offline_cache = json.data
				print("[OFFLINE] Cache loaded with %d entries" % _offline_cache.size())
			else:
				print("[OFFLINE] Failed to parse cache")

func save_offline_cache() -> void:
	var file := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_offline_cache))
		file.close()
		print("[OFFLINE] Cache saved")

func cache_user_data(uid: String, data: Dictionary) -> void:
	_offline_cache["user_%s" % uid] = {
		"data": data,
		"timestamp": int(Time.get_unix_time_from_system())
	}
	save_offline_cache()

func get_cached_user_data(uid: String) -> Dictionary:
	var cache_key := "user_%s" % uid
	if _offline_cache.has(cache_key):
		var cached: Dictionary = _offline_cache[cache_key]
		var age: int = int(Time.get_unix_time_from_system()) - int(cached.get("timestamp", 0))
		if age < 3600:
			return cached["data"]
		else:
			_offline_cache.erase(cache_key)
			save_offline_cache()
	return {}

func check_offline_mode() -> bool:
	var test_url := "https://www.google.com"
	var http := HTTPRequest.new()
	add_child(http)
	http.request(test_url)
	await http.request_completed
	remove_child(http)
	http.queue_free()

	_is_offline = (http.get_response_code() == 0)
	return _is_offline

func sync_offline_data() -> Array:
	if _offline_cache.is_empty():
		return [true, {"synced": 0}]

	var synced_count := 0

	for key in _offline_cache.keys():
		if key.begins_with("user_"):
			var uid: String = String(key).substr(5)
			var cached: Dictionary = _offline_cache[key]
			var data: Dictionary = cached.get("data", {})

			var res := await firestore_load_or_create_user(uid, "")
			if res:
				synced_count += 1

	if synced_count > 0:
		_offline_cache.clear()
		save_offline_cache()

	return [true, {"synced": synced_count}]

# ======================================================================
#                     M I N I   O Y U N L A R
# ======================================================================

var _mini_game_boost_multiplier := 1.0
var _mini_game_boost_end_time := 0

func play_lucky_spin() -> Array:
	var my_uid := get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	if not check_rate_limit("mini_game", my_uid):
		return [false, "Rate limit exceeded"]

	var rewards: Array[Dictionary] = [
		{"multiplier": 1.0, "duration": 0, "probability": 0.5},
		{"multiplier": 1.2, "duration": 300, "probability": 0.3},
		{"multiplier": 1.5, "duration": 600, "probability": 0.15},
		{"multiplier": 2.0, "duration": 900, "probability": 0.05}
	]

	var rand_val := randf()
	var cumulative := 0.0
	var selected_reward: Dictionary = rewards[0]

	for reward in rewards:
		cumulative += reward["probability"]
		if rand_val <= cumulative:
			selected_reward = reward
			break

	if selected_reward["duration"] > 0:
		_mini_game_boost_multiplier = selected_reward["multiplier"]
		_mini_game_boost_end_time = int(Time.get_unix_time_from_system()) + selected_reward["duration"]
		mining_rate *= selected_reward["multiplier"]

	await log_activity("mini_game", {"game": "lucky_spin", "reward": selected_reward})

	return [true, selected_reward]

func get_mini_game_status() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var remaining: int = max(0, _mini_game_boost_end_time - now)

	return {
		"active": remaining > 0,
		"multiplier": _mini_game_boost_multiplier,
		"remaining_seconds": remaining
	}

func update_mini_game_boost() -> void:
	var now := int(Time.get_unix_time_from_system())
	if now >= _mini_game_boost_end_time and _mini_game_boost_multiplier > 1.0:
		mining_rate /= _mini_game_boost_multiplier
		_mini_game_boost_multiplier = 1.0
		_mini_game_boost_end_time = 0

func play_quick_math() -> Array:
	var my_uid := get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	if not check_rate_limit("mini_game", my_uid):
		return [false, "Rate limit exceeded"]

	var a := randi_range(1, 20)
	var b := randi_range(1, 20)
	var operation := randi_range(0, 2)
	var correct_answer := 0

	match operation:
		0:
			correct_answer = a + b
		1:
			correct_answer = a - b
		2:
			correct_answer = a * b

	var reward_multiplier := 1.0
	var reward_duration := 300

	if randf() < 0.3:
		reward_multiplier = 1.3
		reward_duration = 600

	if reward_multiplier > 1.0:
		_mini_game_boost_multiplier = reward_multiplier
		_mini_game_boost_end_time = int(Time.get_unix_time_from_system()) + reward_duration
		mining_rate *= reward_multiplier

	await log_activity("mini_game", {"game": "quick_math", "reward_multiplier": reward_multiplier})

	return [true, {
		"question": "%d %c %d = ?" % [a, "+" if operation == 0 else "-" if operation == 1 else "*", b],
		"answer": correct_answer,
		"reward_multiplier": reward_multiplier,
		"reward_duration": reward_duration
	}]

# ======================================================================
#               I N T E R A C T I V E   T U T O R I A L
# ======================================================================

var _tutorial_completed := false
var _tutorial_step := 0

const TUTORIAL_STEPS := [
	{"title": "tutorial_welcome_title", "text": "tutorial_welcome_text"},
	{"title": "tutorial_mining_title", "text": "tutorial_mining_text"},
	{"title": "tutorial_rewards_title", "text": "tutorial_rewards_text"},
	{"title": "tutorial_friends_title", "text": "tutorial_friends_text"},
	{"title": "tutorial_complete_title", "text": "tutorial_complete_text"}
]

func is_tutorial_completed() -> bool:
	return _tutorial_completed

func get_tutorial_step() -> int:
	return _tutorial_step

func start_tutorial() -> void:
	_tutorial_step = 0
	_tutorial_completed = false
	_save_tutorial_progress()

func advance_tutorial() -> void:
	_tutorial_step += 1
	if _tutorial_step >= TUTORIAL_STEPS.size():
		_tutorial_completed = true
	_save_tutorial_progress()

func get_current_tutorial_step() -> Dictionary:
	if _tutorial_step < TUTORIAL_STEPS.size():
		return TUTORIAL_STEPS[_tutorial_step]
	return {}

func _save_tutorial_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("tutorial", "completed", _tutorial_completed)
	config.set_value("tutorial", "step", _tutorial_step)
	config.save("user://tutorial.cfg")

func load_tutorial_progress() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://tutorial.cfg")
	if err == OK:
		_tutorial_completed = config.get_value("tutorial", "completed", false)
		_tutorial_step = config.get_value("tutorial", "step", 0)

func reset_tutorial() -> void:
	_tutorial_completed = false
	_tutorial_step = 0
	_save_tutorial_progress()

# ======================================================================
#                   D A R K / L I G H T   T H E M E
# ======================================================================

enum ThemeMode { DARK, LIGHT, AUTO }

var _current_theme := ThemeMode.DARK
var _theme_config_file := "user://theme.cfg"

func get_theme_mode() -> int:
	return _current_theme

func set_theme_mode(mode: int) -> void:
	_current_theme = mode
	_save_theme_config()
	_apply_theme()

func _save_theme_config() -> void:
	var config := ConfigFile.new()
	config.set_value("theme", "mode", _current_theme)
	config.save(_theme_config_file)

func load_theme_config() -> void:
	var config := ConfigFile.new()
	var err := config.load(_theme_config_file)
	if err == OK:
		_current_theme = config.get_value("theme", "mode", ThemeMode.DARK)
	else:
		_current_theme = ThemeMode.DARK
	_apply_theme()

func _apply_theme() -> void:
	var use_light := false

	match _current_theme:
		ThemeMode.LIGHT:
			use_light = true
		ThemeMode.AUTO:
			var hour: int = int(Time.get_datetime_dict_from_system().get("hour", 12))
			use_light = (hour >= 6 and hour < 18)

	if use_light:
		_apply_light_theme()
	else:
		_apply_dark_theme()

func _apply_dark_theme() -> void:
	var root := get_tree().root
	var theme := ResourceLoader.load("res://themes/dark_theme.tres") as Theme
	if theme:
		root.theme = theme

func _apply_light_theme() -> void:
	var root := get_tree().root
	var theme := ResourceLoader.load("res://themes/light_theme.tres") as Theme
	if theme:
		root.theme = theme

# ======================================================================
#                     A / B   T E S T I N G
# ======================================================================

var _ab_test_variants := {}
var _ab_test_config_file := "user://ab_tests.cfg"

func init_ab_testing() -> void:
	_ab_test_variants = {
		"mining_rate": {"A": 1.0, "B": 1.2, "C": 1.5},
		"reward_multiplier": {"A": 1.0, "B": 1.1},
		"ui_layout": {"A": "classic", "B": "modern"}
	}
	load_ab_test_config()

func get_ab_variant(test_name: String) -> String:
	if not _ab_test_variants.has(test_name):
		return "A"

	var config := ConfigFile.new()
	var err := config.load(_ab_test_config_file)
	if err == OK:
		var assigned: String = str(config.get_value("variants", test_name, ""))
		if assigned != "":
			return assigned

	var variants: Array = _ab_test_variants[test_name].keys()
	var selected: String = str(variants[randi() % variants.size()])

	var cfg := ConfigFile.new()
	cfg.load(_ab_test_config_file)
	cfg.set_value("variants", test_name, selected)
	cfg.save(_ab_test_config_file)

	return selected

func get_ab_test_value(test_name: String) -> Variant:
	var variant: String = get_ab_variant(test_name)
	if _ab_test_variants.has(test_name) and _ab_test_variants[test_name].has(variant):
		return _ab_test_variants[test_name][variant]
	return null

func log_ab_test_event(test_name: String, event: String, value: float = 0.0) -> void:
	var variant := get_ab_variant(test_name)
	var data := {
		"test": test_name,
		"variant": variant,
		"event": event,
		"value": value,
		"timestamp": int(Time.get_unix_time_from_system())
	}
	await log_activity("ab_test", data)

func load_ab_test_config() -> void:
	var config := ConfigFile.new()
	var err := config.load(_ab_test_config_file)
	if err == OK:
		var variants: PackedStringArray = config.get_section_keys("variants")
		for key in variants:
			if _ab_test_variants.has(key):
				pass

func reset_ab_tests() -> void:
	var config := ConfigFile.new()
	config.load(_ab_test_config_file)
	config.erase_section("variants")
	config.save(_ab_test_config_file)

# ======================================================================
#                   S E A S O N A L   E V E N T S
# ======================================================================

var _active_events := []
var _event_config_file := "user://seasonal_events.cfg"

const SEASONAL_EVENTS := [
	{
		"id": "summer_fest",
		"name": "Summer Festival",
		"start_month": 6,
		"start_day": 1,
		"end_month": 8,
		"end_day": 31,
		"bonus_multiplier": 1.5,
		"special_rewards": ["summer_badge", "bonus_xp"]
	},
	{
		"id": "winter_wonderland",
		"name": "Winter Wonderland",
		"start_month": 12,
		"start_day": 1,
		"end_month": 12,
		"end_day": 31,
		"bonus_multiplier": 2.0,
		"special_rewards": ["winter_badge", "double_mining"]
	},
	{
		"id": "spring_bloom",
		"name": "Spring Bloom",
		"start_month": 3,
		"start_day": 20,
		"end_month": 6,
		"end_day": 20,
		"bonus_multiplier": 1.3,
		"special_rewards": ["spring_badge"]
	},
	{
		"id": "autumn_harvest",
		"name": "Autumn Harvest",
		"start_month": 9,
		"start_day": 1,
		"end_month": 11,
		"end_day": 30,
		"bonus_multiplier": 1.4,
		"special_rewards": ["autumn_badge"]
	}
]

func check_seasonal_events() -> void:
	var date := Time.get_datetime_dict_from_system()
	var current_month: int = int(date.get("month", 1))
	var current_day: int = int(date.get("day", 1))

	_active_events.clear()

	for event in SEASONAL_EVENTS:
		var start_ok := false
		var end_ok := false

		if current_month > event["start_month"] or (current_month == event["start_month"] and current_day >= event["start_day"]):
			start_ok = true

		if current_month < event["end_month"] or (current_month == event["end_month"] and current_day <= event["end_day"]):
			end_ok = true

		if start_ok and end_ok:
			_active_events.append(event)

	_apply_seasonal_bonuses()

func get_active_events() -> Array:
	return _active_events

func is_event_active(event_id: String) -> bool:
	for event in _active_events:
		if event["id"] == event_id:
			return true
	return false

func get_event_bonus_multiplier() -> float:
	var total_multiplier := 1.0
	for event in _active_events:
		total_multiplier *= event["bonus_multiplier"]
	return total_multiplier

func _apply_seasonal_bonuses() -> void:
	var multiplier := get_event_bonus_multiplier()
	if multiplier > 1.0:
		mining_rate *= multiplier

func claim_event_reward(event_id: String) -> Array:
	var my_uid := get_uid()
	if my_uid == "":
		return [false, "Not logged in"]

	var event_config := ConfigFile.new()
	var err := event_config.load(_event_config_file)

	if err == OK:
		var claimed: bool = bool(event_config.get_value("claimed", event_id, false))
		if claimed:
			return [false, "Already claimed"]

	for event in SEASONAL_EVENTS:
		if event["id"] == event_id and is_event_active(event_id):
			var cfg := ConfigFile.new()
			cfg.load(_event_config_file)
			cfg.set_value("claimed", event_id, true)
			cfg.save(_event_config_file)

			var rewards: Array = event["special_rewards"]
			await log_activity("event_claim", {"event": event_id, "rewards": rewards})

			return [true, {"rewards": rewards}]

	return [false, "Event not active or not found"]

func get_event_claimed_status(event_id: String) -> bool:
	var event_config := ConfigFile.new()
	var err := event_config.load(_event_config_file)
	if err == OK:
		return event_config.get_value("claimed", event_id, false)
	return false

# ======================================================================
#               H O M E   S C R E E N   W I D G E T
# ======================================================================

var _widget_enabled := false
var _widget_config_file := "user://widget.cfg"

func init_widget_system() -> void:
	load_widget_config()

func load_widget_config() -> void:
	var config := ConfigFile.new()
	var err := config.load(_widget_config_file)
	if err == OK:
		_widget_enabled = config.get_value("widget", "enabled", false)

func set_widget_enabled(enabled: bool) -> void:
	_widget_enabled = enabled
	var config := ConfigFile.new()
	config.set_value("widget", "enabled", _widget_enabled)
	config.save(_widget_config_file)

func is_widget_enabled() -> bool:
	return _widget_enabled

func get_widget_data() -> Dictionary:
	var my_uid := get_uid()
	if my_uid == "":
		return {}

	var user_doc: Dictionary = await get_user_doc(my_uid)
	if user_doc.is_empty():
		return {}

	var fields: Dictionary = user_doc["fields"]
	var points: float = _firestore_number(fields, "points", 0.0)
	var mining: Dictionary = fields.get("mining", {}).get("mapValue", {}).get("fields", {})
	var last_mining: int = _firestore_int(fields, "lastMiningStart", _firestore_int(mining, "lastMiningStart", 0))
	var now := int(Time.get_unix_time_from_system())
	var remaining: int = max(0, 86400 - (now - last_mining))

	return {
		"points": points,
		"mining_ready": remaining <= 0,
		"remaining_seconds": remaining,
		"level": _firestore_int(fields, "level", 1),
		"badge": _firestore_string(fields, "badge", "Starter")
	}

func update_widget() -> void:
	if not _widget_enabled:
		return

	if OS.has_feature("android") and Engine.has_singleton("HomeScreenWidget"):
		var widget := Engine.get_singleton("HomeScreenWidget")
		if widget and widget.has_method("updateWidget"):
			var data := await get_widget_data()
			widget.updateWidget(data)
	elif OS.has_feature("ios") and Engine.has_singleton("HomeScreenWidget"):
		var widget := Engine.get_singleton("HomeScreenWidget")
		if widget and widget.has_method("updateWidget"):
			var data := await get_widget_data()
			widget.updateWidget(data)

# ======== REWARDED BOOST SİSTEMİ ========
const REWARDED_BOOST_PERCENTAGE := 0.05  # Tamamlanan reklam başına %5 oran artışı
const REWARDED_BOOST_DAILY_LIMIT := 2
const REWARDED_BOOST_COOLDOWN_SECONDS := 0
const REWARDED_BOOST_MAX_MULTIPLIER := 10.0
const REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS := 24 * 60 * 60

func _rewarded_boost_last_at(fields: Dictionary) -> int:
	var last_at := _firestore_int(fields, "rewardedBoostLastAt", 0)
	if last_at > 0:
		return last_at
	var timestamp_value := _firestore_timestamp(fields, "lastRewardedBoostAt", "")
	if timestamp_value != "":
		return max(0, int(Time.get_unix_time_from_datetime_string(timestamp_value)))
	return 0

func _active_rewarded_boost_multiplier(fields: Dictionary, now_sec: int = -1) -> float:
	# Kazanılan çarpan kalıcıdır; yalnız reklam izleme hakları 24 saatliktir.
	# now_sec parametresi eski çağrılarla uyumluluk için korunuyor.
	var _unused_now_sec := now_sec
	var stored_multiplier := clampf(
		_firestore_number(fields, "rewardedBoostMultiplier", 1.0),
		1.0,
		REWARDED_BOOST_MAX_MULTIPLIER
	)
	return stored_multiplier

func _rewarded_boost_remaining_seconds(fields: Dictionary, now_sec: int = -1) -> int:
	# Kalıcı çarpanın bitiş süresi yoktur.
	var _unused_fields := fields
	var _unused_now_sec := now_sec
	return 0

func _rewarded_boost_day_key(now_sec: int = -1) -> int:
	var ts := now_sec
	if ts < 0:
		ts = int(Time.get_unix_time_from_system())
	return int(ts / 86400)

func _rewarded_boost_limit_payload(error_code: String, current_multiplier: float, daily_count: int, remaining_seconds: int = 0) -> Dictionary:
	return {
		"ok": false,
		"error": error_code,
		"rewarded_multiplier": current_multiplier,
		"daily_count": daily_count,
		"daily_limit": REWARDED_BOOST_DAILY_LIMIT,
		"max_multiplier": REWARDED_BOOST_MAX_MULTIPLIER,
		"remaining_seconds": remaining_seconds
	}

func _is_rewarded_boost_limit_error(error_code: String) -> bool:
	return error_code in [
		"rewarded_boost_daily_limit",
		"rewarded_boost_daily_attempt_limit",
		"rewarded_boost_cooldown",
		"rewarded_boost_max_reached"
	]

func is_rewarded_boost_limit_error(error_code: String) -> bool:
	return _is_rewarded_boost_limit_error(error_code)

func reserve_rewarded_boost_attempt() -> Dictionary:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase and firebase.has_method("reserve_rewarded_boost_attempt"):
		return await firebase.reserve_rewarded_boost_attempt()
	return {
		"ok": false,
		"error": "rewarded_boost_attempt_service_unavailable",
		"attempt_count": 0,
		"daily_limit": REWARDED_BOOST_DAILY_LIMIT
	}

func activate_rewarded_boost(uid: String, attempt_at: int = 0) -> Array:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null or not firebase.has_method("apply_rewarded_boost"):
		return [false, {"ok": false, "error": "rewarded_boost_service_unavailable"}]

	# Local SDK reward callbacks are not trusted. Only a Google-signed AdMob
	# callback grants the reward; poll the backend to confirm delivery.
	var last_result: Dictionary = {}
	for poll in range(20):
		last_result = await firebase.apply_rewarded_boost(attempt_at)
		if bool(last_result.get("ok", false)):
			var latest_doc: Dictionary = await get_user_doc(uid)
			var latest_fields: Dictionary = latest_doc.get("fields", {}) if latest_doc.has("fields") else {}
			var components: Dictionary = await get_user_mining_rate_components(uid, latest_fields)
			var rewarded_multiplier := float(last_result.get("rewarded_multiplier", components.get("rewarded_multiplier", 1.0)))
			return [true, {
				"rewarded_multiplier": rewarded_multiplier,
				"total_rate": float(last_result.get("total_rate", components.get("total_rate", rewarded_multiplier))),
				"components": components
			}]
		if str(last_result.get("error", "")) != "rewarded_boost_verification_pending":
			return [false, last_result]
		await get_tree().create_timer(2.0).timeout
	return [false, {
		"ok": false,
		"error": "rewarded_boost_verification_pending",
		"message": "Reklam doğrulaması gecikti. Ödül sunucuda onaylandığında otomatik olarak hesabına işlenecek."
	}]

func get_rewarded_boost_status(uid: String) -> Dictionary:
	var user_doc: Dictionary = await get_user_doc(uid)
	if user_doc.is_empty():
		return {
			"active": false,
			"can_apply": false,
			"error": "rewarded_boost_user_not_found",
			"multiplier": 1.0,
			"daily_count": 0,
			"attempt_count": 0,
			"daily_limit": REWARDED_BOOST_DAILY_LIMIT,
			"max_multiplier": REWARDED_BOOST_MAX_MULTIPLIER,
			"remaining_seconds": 0
		}

	var fields: Dictionary = user_doc["fields"]
	var now := int(Time.get_unix_time_from_system())
	var today := _rewarded_boost_day_key(now)
	var multiplier := _active_rewarded_boost_multiplier(fields, now)
	var stored_day := _firestore_int(fields, "rewardedBoostDay", -1)
	var daily_count := 0
	if stored_day == today:
		daily_count = max(0, _firestore_int(fields, "rewardedBoostDailyCount", 0))
	var attempt_times: Array[int] = []
	var attempt_cutoff := now - REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS
	for attempt_at in [
		_firestore_int(fields, "rewardedBoostAttemptFirstAt", 0),
		_firestore_int(fields, "rewardedBoostAttemptSecondAt", 0)
	]:
		if attempt_at > attempt_cutoff and attempt_at <= now:
			attempt_times.append(attempt_at)
	var legacy_attempt_day := _firestore_int(fields, "rewardedBoostAttemptDay", -1)
	var legacy_attempt_count := 0
	if legacy_attempt_day == today:
		legacy_attempt_count = max(0, _firestore_int(fields, "rewardedBoostAttemptCount", 0))
	var legacy_attempt_last_at := _firestore_int(fields, "rewardedBoostAttemptLastAt", 0)
	while attempt_times.size() < mini(REWARDED_BOOST_DAILY_LIMIT, legacy_attempt_count) and legacy_attempt_last_at > attempt_cutoff:
		attempt_times.append(legacy_attempt_last_at)
	var last_at := _rewarded_boost_last_at(fields)
	while attempt_times.size() < mini(REWARDED_BOOST_DAILY_LIMIT, daily_count) and last_at > attempt_cutoff:
		attempt_times.append(last_at)
	attempt_times.sort()
	var attempt_count := attempt_times.size()
	var attempt_remaining := 0
	if attempt_count >= REWARDED_BOOST_DAILY_LIMIT:
		attempt_remaining = max(1, attempt_times[0] + REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS - now)
	var elapsed: int = now - last_at if last_at > 0 else REWARDED_BOOST_COOLDOWN_SECONDS
	var cooldown_remaining: int = max(0, REWARDED_BOOST_COOLDOWN_SECONDS - elapsed)
	var remaining := 0
	var can_apply: bool = true
	var error_code: String = ""

	if attempt_count >= REWARDED_BOOST_DAILY_LIMIT:
		can_apply = false
		error_code = "rewarded_boost_daily_attempt_limit"
		remaining = attempt_remaining
	elif daily_count >= REWARDED_BOOST_DAILY_LIMIT:
		can_apply = false
		error_code = "rewarded_boost_daily_limit"
	elif multiplier >= REWARDED_BOOST_MAX_MULTIPLIER:
		can_apply = false
		error_code = "rewarded_boost_max_reached"
		remaining = _rewarded_boost_remaining_seconds(fields, now)
	elif cooldown_remaining > 0:
		can_apply = false
		error_code = "rewarded_boost_cooldown"
		remaining = cooldown_remaining

	return {
		"active": multiplier > 1.0,
		"can_apply": can_apply,
		"error": error_code,
		"multiplier": multiplier,
		"rewarded_multiplier": multiplier,
		"daily_count": daily_count,
		"attempt_count": attempt_count,
		"daily_limit": REWARDED_BOOST_DAILY_LIMIT,
		"window_seconds": REWARDED_BOOST_ATTEMPT_WINDOW_SECONDS,
		"max_multiplier": REWARDED_BOOST_MAX_MULTIPLIER,
		"remaining_seconds": remaining
	}

func should_show_tutorial_for_fields(fields: Dictionary) -> bool:
	if fields.has("tutorialSeen") and typeof(fields["tutorialSeen"]) == TYPE_DICTIONARY:
		var value: Dictionary = fields["tutorialSeen"]
		if value.has("booleanValue"):
			return not bool(value["booleanValue"])
	return false

func mark_tutorial_seen(uid: String = "") -> void:
	var my_uid := uid if uid != "" else get_uid()
	if my_uid == "":
		return
	await patch_user_fields(my_uid, {"tutorialSeen": {"booleanValue": true}})
