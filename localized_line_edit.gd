extends LineEdit
class_name LocalizedLineEdit

@export var placeholder_key: String = ""

func _ready() -> void:
	_apply()

func _apply():
	if placeholder_key != "":
		placeholder_text = tr(placeholder_key)
