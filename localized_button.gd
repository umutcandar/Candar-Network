extends Button
class_name LocalizedButton

@export var translation_key: String = ""

func _ready() -> void:
	_apply()

func _apply() -> void:
	if translation_key != "":
		text = tr(translation_key)
