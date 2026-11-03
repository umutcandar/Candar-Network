extends Node

func _ready() -> void:
	print("[DeeplinkRouter] ready")

	if Engine.has_singleton("DeeplinkPlugin"):
		var dp = Engine.get_singleton("DeeplinkPlugin")
		# Sinyal adı logda "deeplink_received"
		if not dp.is_connected("deeplink_received", Callable(self, "_on_deeplink_received")):
			dp.connect("deeplink_received", Callable(self, "_on_deeplink_received"))
		print("[DeeplinkRouter] DeeplinkPlugin connected")
	else:
		print("[DeeplinkRouter] DeeplinkPlugin singleton yok!")

func _on_deeplink_received(data) -> void:
	var url: String = ""
	
	# Gelen veri Sözlük ise içinden 'url' anahtarını alıyoruz
	if typeof(data) == TYPE_DICTIONARY:
		url = data.get("url", "")
	# Gelen veri zaten metin ise direkt kullanıyoruz
	elif typeof(data) == TYPE_STRING:
		url = data
		
	print("[DeeplinkRouter] İşlenen URL: ", url)

	# Google Sign-In tetikleyici kontrolü
	if url == "candar://google_signin":
		_start_google_signin()
		return

	if url.begins_with("candar://"):
		print("[DeeplinkRouter] Özel şema yakalandı:", url)
func _start_google_signin() -> void:
	# Bazı pluginlerde singleton adı farklı olabilir, o yüzden birkaç ihtimali deniyoruz.
	var candidates := ["GoogleSignIn", "GSI", "GoogleAuth", "GoogleOAuth"]

	for name in candidates:
		if Engine.has_singleton(name):
			var gsi = Engine.get_singleton(name)
			print("[DeeplinkRouter] Found singleton:", name)

			# Bazı plugin logu: "connect your signals and call 'start'"
			if gsi.has_method("start"):
				gsi.call("start")
				print("[DeeplinkRouter] %s.start() called" % name)
				return

			if gsi.has_method("login"):
				gsi.call("login")
				print("[DeeplinkRouter] %s.login() called" % name)
				return

			if gsi.has_method("sign_in"):
				gsi.call("sign_in")
				print("[DeeplinkRouter] %s.sign_in() called" % name)
				return

			print("[DeeplinkRouter] Singleton var ama start/login/sign_in yok:", name)
			return

	print("[DeeplinkRouter] Google Sign-In singleton bulunamadı! (Google plugin ismi farklı)")
