# res://IAPManager.gd
extends Node
class_name IAPManager

signal purchase_done(result: Dictionary)
signal purchase_applied(result: Dictionary)
signal product_details_updated()

var billing: BillingClient = null
var is_ready: bool = false

# --------------------------
# iOS (migueldeicaza GodotApplePlugins) StoreKitManager
# --------------------------
var sk: Object = null
var _ios_products := {} # product_id -> StoreProduct (object)
var _product_prices := {} # product_id -> localized display price

# Satın alma akışı için state (Android)
var _pending_product_id: String = ""
var _pending_is_premium: bool = false
var _pending_purchase: Dictionary = {}

# Finalize bekleme state (ACK / CONSUME) (Android)
var _finalize_wait_token: String = ""
var _finalize_wait_kind: String = "" # "consume" | "ack"
var _finalize_done_flag: bool = false
var _finalize_last_res: Dictionary = {}

# Ürün ID'lerin
const BOOST_PRODUCTS := [
	"candar.boost.basic.30d",
	"candar.boost.pro.30d",
	"candar.boost.ultra.30d",
]
const PREMIUM_PRODUCTS := [
	"candar.premium.30d",
]
const IOS_PRODUCT_IDS := {
	"candar.boost.basic.30d": "candar.ios.boost.basic.30d",
	"candar.boost.pro.30d": "candar.ios.boost.pro.30d",
	"candar.boost.ultra.30d": "candar.ios.boost.ultra.30d",
	"candar.premium.30d": "candar.ios.premium.30d",
}
const ANDROID_PRODUCT_IDS := {
	"candar.boost.basic.30d": "candar.boost.basic.v2.30d",
	"candar.boost.pro.30d": "candar.boost.pro.v2.30d",
	"candar.boost.ultra.30d": "candar.boost.ultra.v2.30d",
	"candar.premium.30d": "candar.premium.v2.30d",
}

func _store_product_id(product_id: String) -> String:
	if OS.get_name() == "iOS":
		return str(IOS_PRODUCT_IDS.get(product_id, product_id))
	if OS.get_name() == "Android":
		return str(ANDROID_PRODUCT_IDS.get(product_id, product_id))
	return product_id

func _app_product_id_from_store_id(store_product_id: String) -> String:
	for app_id in IOS_PRODUCT_IDS.keys():
		if str(IOS_PRODUCT_IDS[app_id]) == store_product_id:
			return str(app_id)
	for app_id in ANDROID_PRODUCT_IDS.keys():
		if str(ANDROID_PRODUCT_IDS[app_id]) == store_product_id:
			return str(app_id)
	return store_product_id

func _apply_purchase_via_backend(platform: String, product_id: String, token: String, is_premium: bool, transaction_id: String = "") -> Dictionary:
	var firebase := get_node_or_null("/root/Firebase")
	if firebase == null:
		return {"ok": false, "error": "firebase_missing"}

	var backend_res: Dictionary
	var app_version := str(ProjectSettings.get_setting("application/config/version", ""))
	if is_premium:
		backend_res = await firebase.apply_premium(platform, product_id, token, app_version, transaction_id)
	else:
		backend_res = await firebase.verify_and_apply_boost(platform, product_id, token, app_version, transaction_id)

	if bool(backend_res.get("ok", false)):
		return backend_res

	return backend_res

func _ready() -> void:
	# =======================
	# iOS init (Miguel GodotApplePlugins)
	# =======================
	if OS.get_name() == "iOS":
		# StoreKitManager yalnızca iOS eklentisi yüklüyken ClassDB'de bulunur.
		# Sınıfa doğrudan tip/constructor referansı Android dışa aktarımında
		# betiğin tamamen parse edilememesine neden olur.
		if not ClassDB.class_exists("StoreKitManager"):
			push_error("[IAP] StoreKitManager iOS eklentisi bulunamadı.")
			return
		sk = ClassDB.instantiate("StoreKitManager")
		if sk == null:
			push_error("[IAP] StoreKitManager oluşturulamadı.")
			return

		# Sinyaller
		sk.products_request_completed.connect(_on_ios_products_request_completed)
		sk.purchase_completed.connect(_on_ios_purchase_completed)
		sk.restore_completed.connect(_on_ios_restore_completed)
		sk.transaction_updated.connect(_on_ios_transaction_updated)
		# StoreKit 2'nin açılışta ve bekleyen işlemlerde ürettiği transaction
		# olaylarını dinlemeye başla. Bazı eski eklenti sürümlerinde bu metot yoktur.
		if sk.has_method("start"):
			sk.call("start")

		is_ready = true

		# Ürünleri Apple’dan iste
		var all_ids: PackedStringArray = PackedStringArray()
		for x in BOOST_PRODUCTS: all_ids.append(_store_product_id(x))
		for x in PREMIUM_PRODUCTS: all_ids.append(_store_product_id(x))

		sk.request_products(all_ids)
		print("[IAP] iOS StoreKitManager hazir, products isteniyor.")
		return

	# =======================
	# Android init
	# =======================
	if OS.get_name() != "Android":
		print("[IAP] Desteklenmeyen platform: ", OS.get_name())
		return

	billing = BillingClient.new()
	add_child(billing)

	billing.connected.connect(_on_connected)
	billing.disconnected.connect(_on_disconnected)
	billing.connect_error.connect(_on_connect_error)
	billing.query_product_details_response.connect(_on_query_product_details_response)
	billing.query_purchases_response.connect(_on_query_purchases_response)
	billing.on_purchase_updated.connect(_on_purchase_updated)
	billing.consume_purchase_response.connect(_on_consume_purchase_response)
	billing.acknowledge_purchase_response.connect(_on_acknowledge_purchase_response)

	billing.start_connection()
	print("[IAP] start_connection cagrildi")


# ============================================================
# iOS HELPERS (Miguel GodotApplePlugins)
# ============================================================
func ios_request_products(product_ids: Array) -> void:
	if sk == null:
		print("[IAP] sk yok, ios_request_products atlandi")
		return
	var ids: PackedStringArray = PackedStringArray()
	for x in product_ids:
		ids.append(_store_product_id(str(x)))
	sk.request_products(ids)

func ios_buy(product_id: String) -> bool:
	if sk == null:
		print("[IAP] sk yok, ios_buy atlandi")
		return false

	if not _ios_products.has(product_id):
		print("[IAP] iOS product bulunamadi (ürün listesi gelmedi olabilir): ", product_id)
		return false

	var prod = _ios_products[product_id]
	sk.purchase(prod)
	return true

func get_display_price(product_id: String, fallback: String = "") -> String:
	var store_id := _store_product_id(product_id)
	return str(_product_prices.get(product_id, _product_prices.get(store_id, fallback)))

func ios_restore() -> void:
	if sk == null:
		print("[IAP] sk yok, ios_restore atlandi")
		return
	sk.restore_purchases()

func _on_ios_products_request_completed(products: Array, status: int) -> void:
	print("[IAP] iOS products_request_completed status=", status, " products_count=", products.size())
	if status != 0:
		emit_signal("product_details_updated")
		return

	for p in products:
		if p == null:
			continue

		var pid := ""

		# StoreProduct alanları build'e göre değişebilir; birkaç ihtimali deniyoruz
		# 1) Dictionary gibi get edilebiliyorsa:
		if p is Dictionary:
			pid = str(p.get("id", p.get("product_id", p.get("productId", ""))))
		else:
			# 2) Object property denemeleri (Godot bazen property erişimine izin verir)
			# güvenli olması için try/catch yok, o yüzden sırayla 'in' kontrolü yapıyoruz
			if "id" in p:
				pid = str(p.id)
			elif "product_id" in p:
				pid = str(p.product_id)
			elif "productId" in p:
				pid = str(p.productId)

		if pid != "":
			_ios_products[pid] = p
			_ios_products[_app_product_id_from_store_id(pid)] = p
			var display_price := _extract_ios_display_price(p)
			if display_price != "":
				_product_prices[pid] = display_price
				_product_prices[_app_product_id_from_store_id(pid)] = display_price

	print("[IAP] iOS product map size=", _ios_products.size())
	emit_signal("product_details_updated")

func _extract_ios_display_price(product) -> String:
	if product is Dictionary:
		return str(product.get("display_price", product.get("displayPrice", product.get("localized_price", ""))))
	if product != null:
		if "display_price" in product:
			return str(product.display_price)
		if "displayPrice" in product:
			return str(product.displayPrice)
		if "localized_price" in product:
			return str(product.localized_price)
	return ""

func _on_ios_purchase_completed(transaction, status: int, error_message: String) -> void:
	print("[IAP] iOS purchase_completed status=", status)

	# Miguel plugininde StoreKitStatus.ok genelde 0 olur.
	if status != 0:
		var pending := status == 5
		emit_signal("purchase_done", {
			"ok": false,
			"platform": "ios",
			"pending": pending,
			"error": "purchase_pending" if pending else error_message,
			"status": status
		})
		return

	var product_id := ""
	var transaction_id := ""

	# transaction StoreTransaction olabilir; alan adları sürüme göre değişebilir
	if transaction is Dictionary:
		product_id = str(transaction.get("product_id", transaction.get("productId", "")))
		transaction_id = str(transaction.get("id", transaction.get("transaction_id", transaction.get("transactionId", ""))))
	else:
		if transaction != null:
			if "product_id" in transaction:
				product_id = str(transaction.product_id)
			elif "productId" in transaction:
				product_id = str(transaction.productId)

			transaction_id = _ios_extract_tx_id(transaction)

	# Transaction kimliği Apple Server API ile doğrudan doğrulanabildiği için
	# yeni makbuzun diske yazılmasını beklemiyoruz. Kimliksiz/eski işlemlerde
	# uygulama makbuzu fallback'i korunur.
	var proof := transaction_id
	if proof == "":
		proof = await _ios_get_app_receipt()
	if proof == "":
		emit_signal("purchase_done", {
			"ok": false,
			"platform": "ios",
			"error": "ios_missing_app_store_receipt",
			"transaction_id": transaction_id
		})
		return

	print("[IAP][IOS] sending verified receipt product=", product_id, " tx_id=", transaction_id)

	emit_signal("purchase_done", {
		"ok": true,
		"platform": "ios",
		"product_id": product_id,
		"token": proof,
		"transaction_id": transaction_id,
		"raw": transaction
	})

func _on_ios_restore_completed(status: int, error_message: String) -> void:
	print("[IAP] iOS restore_completed status=", status, " err=", error_message)

func _on_ios_transaction_updated(transaction) -> void:
	print("[IAP] iOS transaction_updated")


# ============================================================
# ANDROID BAGLANTI / QUERY
# ============================================================
func _on_connected() -> void:
	print("[IAP] connected")
	is_ready = true

	var all_ids: PackedStringArray = PackedStringArray()
	for x in BOOST_PRODUCTS:
		all_ids.append(_store_product_id(x))
	for x in PREMIUM_PRODUCTS:
		all_ids.append(_store_product_id(x))

	billing.query_product_details(all_ids, BillingClient.ProductType.INAPP)
	billing.query_purchases(BillingClient.ProductType.INAPP)

func _on_disconnected() -> void:
	print("[IAP] disconnected")
	is_ready = false

func _on_connect_error(code: int, msg: String) -> void:
	print("[IAP] connect_error: ", code, " / ", msg)
	is_ready = false

func _on_query_product_details_response(response: Dictionary) -> void:
	print("[IAP] query_product_details_response: ", response)
	var arr: Array = response.get("result_array", response.get("product_details", []))
	for item in arr:
		if not (item is Dictionary):
			continue
		var pid := str(item.get("product_id", item.get("productId", item.get("id", ""))))
		if pid == "":
			continue
		var price := _extract_android_display_price(item)
		if price != "":
			_product_prices[pid] = price
			_product_prices[_app_product_id_from_store_id(pid)] = price
	emit_signal("product_details_updated")

func _extract_android_display_price(item: Dictionary) -> String:
	if item.has("one_time_purchase_offer_details") and item["one_time_purchase_offer_details"] is Dictionary:
		var d: Dictionary = item["one_time_purchase_offer_details"]
		var p := str(d.get("formatted_price", d.get("formattedPrice", "")))
		if p != "":
			return p
	if item.has("oneTimePurchaseOfferDetails") and item["oneTimePurchaseOfferDetails"] is Dictionary:
		var d2: Dictionary = item["oneTimePurchaseOfferDetails"]
		var p2 := str(d2.get("formattedPrice", d2.get("formatted_price", "")))
		if p2 != "":
			return p2
	for key in ["formatted_price", "formattedPrice", "price", "localized_price"]:
		if item.has(key) and str(item[key]) != "":
			return str(item[key])
	return ""

func _on_query_purchases_response(response: Dictionary) -> void:
	print("[IAP] query_purchases_response: ", response)

	var code: int = int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if code != BillingClient.BillingResponseCode.OK:
		return

	var arr: Array = response.get("result_array", [])
	for p in arr:
		var state: int = int(p.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE))
		if state != BillingClient.PurchaseState.PURCHASED:
			continue

		var is_ack := bool(p.get("is_acknowledged", false)) or bool(p.get("acknowledged", false))
		if is_ack:
			continue

		var pids: PackedStringArray = p.get("product_ids", PackedStringArray())
		var pid := ""
		if pids.size() > 0:
			pid = String(pids[0])

		var app_pid := _app_product_id_from_store_id(pid)
		if app_pid == "":
			push_warning("[IAP] Pending purchase has no product id; leaving it unconsumed.")
			continue
		var token := _extract_token(p)
		if token == "":
			push_warning("[IAP] Pending purchase has no token; leaving it unconsumed: %s" % app_pid)
			continue
		var prem := PREMIUM_PRODUCTS.has(app_pid)
		print("[IAP] recovering pending purchase: ", app_pid)
		var backend_res := await _apply_purchase_via_backend("android", app_pid, token, prem)
		if not bool(backend_res.get("ok", false)):
			# Ödeme doğrulanmadan consume edilirse kullanıcı parasını ödediği ürünü
			# yeniden uygulama şansını kaybeder. Bir sonraki açılışta tekrar denensin.
			push_warning("[IAP] Pending purchase recovery failed; leaving unconsumed: %s" % backend_res)
			continue
		var finalize_res := await _finalize_purchase(p, prem)
		var payload := backend_res.duplicate(true)
		payload["ok"] = true
		payload["product_id"] = app_pid
		payload["is_premium"] = prem
		payload["recovered"] = true
		payload["finalize_ok"] = bool(finalize_res.get("ok", false))
		payload["message"] = "Premium aktif edildi" if prem else "Boost aktif edildi"
		emit_signal("purchase_applied", payload)


# ============================================================
# TOKEN YARDIMCI
# ============================================================
func _extract_token(d: Dictionary) -> String:
	var t := String(d.get("purchase_token", ""))
	if t == "":
		t = String(d.get("purchaseToken", ""))
	return t


# ============================================================
# FINALIZE CALLBACKS (ANDROID)
# ============================================================
func _on_consume_purchase_response(response: Dictionary) -> void:
	print("[IAP] consume_purchase_response: ", response)
	var tok := _extract_token(response)
	if _finalize_wait_kind == "consume" and tok == _finalize_wait_token:
		_finalize_done_flag = true
		_finalize_last_res = {"ok": true, "kind": "consume", "raw": response}

func _on_acknowledge_purchase_response(response: Dictionary) -> void:
	print("[IAP] acknowledge_purchase_response: ", response)
	var tok := _extract_token(response)
	if _finalize_wait_kind == "ack" and tok == _finalize_wait_token:
		_finalize_done_flag = true
		_finalize_last_res = {"ok": true, "kind": "ack", "raw": response}


# ============================================================
# DISARIDAN CAGIRILAN
# ============================================================
func buy_boost(product_id: String) -> Dictionary:
	return await _buy_and_apply(product_id, false)

func buy_premium(product_id: String) -> Dictionary:
	return await _buy_and_apply(product_id, true)


# ============================================================
# ORTAK SATIN ALMA + FIREBASE
# ============================================================
func _buy_and_apply(product_id: String, is_premium: bool) -> Dictionary:
	# =======================
	# iOS
	# =======================
	if OS.get_name() == "iOS":
		if sk == null:
			return {"ok": false, "error": "ios_store_not_ready"}

		var store_product_id := _store_product_id(product_id)
		if not _ios_products.has(store_product_id):
			ios_request_products([store_product_id])
			var started_at := Time.get_ticks_msec()
			while not _ios_products.has(store_product_id) and Time.get_ticks_msec() - started_at < 5000:
				await get_tree().process_frame

		if not ios_buy(store_product_id):
			return {"ok": false, "error": "ios_product_not_loaded"}

		var result: Dictionary = await purchase_done
		if not bool(result.get("ok", false)):
			return result

		var token := String(result.get("token", ""))
		if token == "":
			return {"ok": false, "error": "ios_missing_proof"}

		var transaction_id := String(result.get("transaction_id", ""))
		if transaction_id == "":
			return {"ok": false, "error": "ios_missing_transaction_id"}

		var backend_res: Dictionary = await _apply_purchase_via_backend(
			"ios",
			product_id,
			token,
			is_premium,
			transaction_id
		)

		if not bool(backend_res.get("ok", false)):
			return backend_res

		var msg_ios := "Boost aktif edildi"
		if is_premium:
			msg_ios = "Premium aktif edildi"

		var purchase_payload_ios := backend_res.duplicate(true)
		purchase_payload_ios["ok"] = true
		purchase_payload_ios["product_id"] = product_id
		purchase_payload_ios["is_premium"] = is_premium
		purchase_payload_ios["message"] = msg_ios
		emit_signal("purchase_applied", purchase_payload_ios)

		return backend_res

	# =======================
	# Android
	# =======================
	if OS.get_name() != "Android":
		return {"ok": false, "error": "unsupported_platform"}

	if billing == null or not is_ready:
		return {"ok": false, "error": "billing_not_ready"}

	_pending_product_id = product_id
	_pending_is_premium = is_premium
	_pending_purchase = {}

	var store_product_id_a := _store_product_id(product_id)
	var launch_res: Dictionary = billing.purchase(store_product_id_a)
	print("[IAP] purchase() returned status=", launch_res.get("status", launch_res.get("response_code", "unknown")))
	if launch_res.is_empty():
		return {"ok": false, "error": "purchase_launch_failed"}
	if launch_res.has("status") and int(launch_res.get("status", OK)) != OK:
		return {"ok": false, "error": "purchase_launch_failed", "details": launch_res}
	if launch_res.has("response_code") and int(launch_res.get("response_code", 0)) != 0:
		return {"ok": false, "error": "purchase_launch_failed", "details": launch_res}

	var result_a: Dictionary = await purchase_done
	if not bool(result_a.get("ok", false)):
		return result_a

	var token_a := String(result_a.get("token", ""))
	if token_a == "":
		return {"ok": false, "error": "missing_token"}

	var purchase := Dictionary(result_a.get("purchase", {}))
	if purchase.is_empty():
		return {"ok": false, "error": "missing_purchase_obj"}

	var backend_res_a: Dictionary = await _apply_purchase_via_backend("android", product_id, token_a, is_premium)

	if not bool(backend_res_a.get("ok", false)):
		return backend_res_a

	var fin_res := await _finalize_purchase(purchase, is_premium)
	if not bool(fin_res.get("ok", false)):
		backend_res_a["warning"] = "finalize_failed"
	backend_res_a["finalize"] = fin_res

	var msg_android := "Boost aktif edildi"
	if is_premium:
		msg_android = "Premium aktif edildi"

	var purchase_payload_android := backend_res_a.duplicate(true)
	purchase_payload_android["ok"] = true
	purchase_payload_android["product_id"] = product_id
	purchase_payload_android["is_premium"] = is_premium
	purchase_payload_android["message"] = msg_android
	purchase_payload_android["finalize_ok"] = bool(fin_res.get("ok", false))
	emit_signal("purchase_applied", purchase_payload_android)

	return backend_res_a


# ============================================================
# ANDROID PURCHASE CALLBACK
# ============================================================
func _on_purchase_updated(response: Dictionary) -> void:
	print("[IAP] on_purchase_updated: ", response)

	var code: int = int(response.get("response_code", BillingClient.BillingResponseCode.ERROR))
	if code != BillingClient.BillingResponseCode.OK:
		emit_signal("purchase_done", {
			"ok": false,
			"error": "billing_response",
			"response_code": code,
			"raw": response
		})
		return

	var arr: Array = response.get("result_array", [])
	if arr.is_empty():
		emit_signal("purchase_done", {"ok": false, "error": "no_purchases"})
		return

	var picked: Dictionary = {}
	for p in arr:
		var pids: PackedStringArray = p.get("product_ids", PackedStringArray())
		var pid := ""
		if pids.size() > 0:
			pid = String(pids[0])
		if pid == _store_product_id(_pending_product_id):
			picked = p
			break

	if picked.is_empty():
		picked = arr[0]

	var state: int = int(picked.get("purchase_state", BillingClient.PurchaseState.UNSPECIFIED_STATE))
	if state != BillingClient.PurchaseState.PURCHASED:
		emit_signal("purchase_done", {"ok": false, "error": "not_purchased", "state": state, "raw": picked})
		return

	var token := String(picked.get("purchase_token", ""))
	if token == "":
		token = String(picked.get("purchaseToken", ""))

	if token == "":
		emit_signal("purchase_done", {"ok": false, "error": "missing_token_in_callback", "raw": picked})
		return

	var pids2: PackedStringArray = picked.get("product_ids", PackedStringArray())
	var pid2 := ""
	if pids2.size() > 0:
		pid2 = _app_product_id_from_store_id(String(pids2[0]))

	_pending_purchase = picked

	emit_signal("purchase_done", {
		"ok": true,
		"product_id": pid2,
		"token": token,
		"purchase": picked
	})
func _ios_extract_tx_id(tx) -> String:
	var value := ""
	if tx is Dictionary:
		value = str(tx.get("id", tx.get("transaction_id", tx.get("transactionId", ""))))
	if tx != null:
		if "id" in tx: value = str(tx.id)
		elif "transaction_id" in tx: value = str(tx.transaction_id)
		elif "transactionId" in tx: value = str(tx.transactionId)
		elif tx.has_method("get_transaction_id"): value = str(tx.call("get_transaction_id"))
	return "" if value == "0" else value

func _ios_get_app_receipt() -> String:
	var response_path := "user://app_store_receipt.txt"
	var request_path := "user://receipt_request.tmp"
	if FileAccess.file_exists(response_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(response_path))

	var request_file := FileAccess.open(request_path, FileAccess.WRITE)
	if request_file == null:
		return ""
	request_file.store_string(str(Time.get_unix_time_from_system()))
	request_file.close()

	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		if FileAccess.file_exists(response_path):
			var receipt := FileAccess.get_file_as_string(response_path).strip_edges()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(response_path))
			return receipt
		await get_tree().create_timer(0.1).timeout
	return ""

# ============================================================
# FINALIZE: Bu ürünlerin hepsi 30 günlük süreli tek seferlik paket.
# Tekrar satın alınabilmeleri için Android tarafında consume edilir.
# ============================================================
func _finalize_purchase(purchase: Dictionary, is_premium: bool) -> Dictionary:
	var token := String(purchase.get("purchase_token", ""))
	if token == "":
		token = String(purchase.get("purchaseToken", ""))

	if token == "":
		return {"ok": false, "error": "finalize_missing_token"}

	var acknowledged := bool(purchase.get("is_acknowledged", false))
	if not acknowledged:
		acknowledged = bool(purchase.get("acknowledged", false))

	_finalize_wait_token = token
	_finalize_wait_kind = "consume"

	_finalize_done_flag = false
	_finalize_last_res = {}

	billing.consume_purchase(token)

	var start := Time.get_ticks_msec()
	while not _finalize_done_flag and (Time.get_ticks_msec() - start) < 6000:
		await get_tree().process_frame

	if _finalize_done_flag:
		return _finalize_last_res

	return {"ok": false, "error": "finalize_timeout", "kind": _finalize_wait_kind, "token": token}
