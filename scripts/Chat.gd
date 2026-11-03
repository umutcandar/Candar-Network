extends Control
@onready var chat_box: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/ChatBox
@onready var input: LineEdit = $PanelContainer/VBoxContainer/HBoxContainer/Input
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel

func _ready():
	status_label.text = "Günlük mesaj hakkı: yükleniyor..."
	# İlk açıldığında güncelle
	await update_remaining()

func _on_SendButton_pressed():
	var msg := input.text.strip_edges()
	if msg == "":
		return
	add_chat("👤", msg)
	input.text = ""

	status_label.text = "Candar Asistan yazıyor..."
	var res := await Firebase.chat_send(msg)
	if res.has("answer"):
		add_chat("🤖", res.answer)
		if res.has("remaining") and typeof(res.remaining) == TYPE_INT:
			status_label.text = "Kalan hak: %s" % str(res.remaining)
	elif str(res).find("resource-exhausted") != -1:
		status_label.text = "⚠️ Günlük hakkın bitti. Premium al."
	else:
		status_label.text = "Bağlantı veya token hatası."

func add_chat(prefix: String, text: String):
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.text = "%s: %s" % [prefix, text]
	lbl.theme_type_variation = "ChatMessage"
	chat_box.add_child(lbl)

func update_remaining():
	var res := await Firebase.chat_send({"prompt": "ping"})
	if res.has("remaining"):
		status_label.text = "Kalan hak: %s" % str(res.remaining)
