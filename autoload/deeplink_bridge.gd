extends Node

func _ready() -> void:
	print("[DeeplinkBridge] ready")

	# DeeplinkRouter zaten autoload: oradan sinyali yakalayacağız
	# Ama bazı pluginler “Autoload var mı?” diye bakıp “bulamadı” basıyor.
	# Burada sadece var olduğumuzu garanti ediyoruz.

	# İstersen burada da DeeplinkPlugin sinyalini bağlayıp aynı fonksiyonu çağırabilirsin:
	if Engine.has_singleton("DeeplinkPlugin"):
		var dp = Engine.get_singleton("DeeplinkPlugin")
		if not dp.is_connected("deeplink_received", Callable(self, "_on_deeplink_received")):
			dp.connect("deeplink_received", Callable(self, "_on_deeplink_received"))
		print("[DeeplinkBridge] DeeplinkPlugin connected")
	else:
		print("[DeeplinkBridge] DeeplinkPlugin singleton yok!")

func _on_deeplink_received(data) -> void:
	# Veriyi sadece logla ve Router'a olduğu gibi pasla
	print("[DeeplinkBridge] Ham veri alındı, Router'a iletiliyor.")

	if has_node("/root/DeeplinkRouter"):
		var router = get_node("/root/DeeplinkRouter")
		if router.has_method("_on_deeplink_received"):
			# Veriyi (Data) tipini değiştirmeden (String'e zorlamadan) gönderiyoruz
			router.call("_on_deeplink_received", data)
