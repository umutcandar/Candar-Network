extends Label
class_name LocalizedLabel

@export var translation_key: String = ""

func _ready() -> void:
	_apply()

func _apply() -> void:
	if translation_key != "":
		text = tr(translation_key)
