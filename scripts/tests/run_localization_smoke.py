"""Run real 12-language client runtime functions in an isolated Godot project."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot"

def method(source, name):
    match = re.search(r"^func " + re.escape(name) + r"\(", source, re.M)
    assert match, f"Missing method: {name}"
    end = re.search(r"^func ", source[match.end():], re.M)
    return source[match.start():match.end() + end.start()] if end else source[match.start():]

global_source = (ROOT / "global.gd").read_text(encoding="utf-8")
profile_source = (ROOT / "profile.gd").read_text(encoding="utf-8")
firebase_source = (ROOT / "scripts/FirebaseClient.gd").read_text(encoding="utf-8")
onboarding_source = (ROOT / "onboarding.gd").read_text(encoding="utf-8")
global_methods = [
    "_load_ui_locales", "localized_ui_text", "localized_named_key",
    "_determine_initial_lang", "set_language", "_save_language_to_disk",
]
with tempfile.TemporaryDirectory(prefix="candar-i18n-ui-") as directory:
    work = Path(directory)
    (work / "localization").mkdir()
    shutil.copy2(ROOT / "localization/ui_strings.json", work / "localization/ui_strings.json")
    stub = """extends Node
const _UI_CATALOG_PATH = "res://localization/ui_strings.json"
var _ui_catalog: Dictionary = {}
var _ui_indexes: Dictionary = {}
var current_lang := "en"
var SUPPORTED_LANGS := [
    "en", "tr", "de", "fr", "es", "pt", "ru", "zh", "ja", "ko", "ar", "hi"
]
func _sync_push_language_if_signed_in() -> void:
    pass
""".replace("    ", "\t")
    (work / "global_actual.gd").write_text(stub + "\n".join(method(global_source, x) for x in global_methods), encoding="utf-8")
    (work / "onboarding_actual.gd").write_text("""extends Control
var root_box: VBoxContainer
func _ready() -> void:
    root_box = VBoxContainer.new()
    add_child(root_box)
""".replace("    ", "\t") + method(onboarding_source, "_build_language_selector"), encoding="utf-8")
    (work / "profile_actual.gd").write_text("""extends Control
func _ui_text(_tr_text: String, en_text: String) -> String:
    return en_text
""".replace("    ", "\t") + method(profile_source, "_show_language_dialog"), encoding="utf-8")
    (work / "firebase_actual.gd").write_text("""extends Node
func _get_global() -> Node:
    return get_node_or_null("/root/Global")
""".replace("    ", "\t") + method(firebase_source, "_friendly_function_error"), encoding="utf-8")
    (work / "test.gd").write_text("""extends SceneTree
var checks := 0
var errors := 0
func check(condition: bool, message: String) -> void:
    checks += 1
    if not condition:
        errors += 1
        push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
    var global = root.get_node("Global")
    global._load_ui_locales()
    var data = JSON.parse_string(FileAccess.get_file_as_string("res://localization/ui_strings.json"))
    check(typeof(data) == TYPE_DICTIONARY, "Could not read locale catalog")
    var firebase = load("res://firebase_actual.gd").new()
    root.add_child(firebase)
    for lang in global.SUPPORTED_LANGS:
        TranslationServer.set_locale(lang)
        var server_error = firebase._friendly_function_error(403, {
            "error": {"status": "PERMISSION_DENIED", "message": "Bu işleme izniniz yok."}
        })
        check(server_error == data["named"]["fn_error_permission_denied"][lang],
            "Backend error not localized in " + lang)
        check(firebase._friendly_function_error(503, {}) == data["named"]["fn_error_unavailable"][lang],
            "Server unavailable not localized in " + lang)
        check(firebase._friendly_function_error(0, {}) == data["named"]["fn_error_unknown"][lang],
            "Unknown server error not localized in " + lang)
        for i in range(data["keys"].size()):
            var result = global.localized_ui_text(data["tr"][i], data["en"][i])
            check(result == data[lang][i], "Missing dynamic locale %s at index %d" % [lang, i])
        for key in data["named"].keys():
            check(global.localized_named_key(key) == data["named"][key][lang], "Missing named locale %s:%s" % [lang, key])
    var onboarding = load("res://onboarding_actual.gd").new()
    root.add_child(onboarding)
    onboarding._build_language_selector()
    var language_select = onboarding.root_box.get_node_or_null("LanguageSelect")
    check(language_select is OptionButton, "Onboarding language picker missing")
    if language_select is OptionButton:
        check(language_select.item_count == 12, "Onboarding should show all 12 languages")
    var profile = load("res://profile_actual.gd").new()
    root.add_child(profile)
    profile._show_language_dialog()
    var dialogs = profile.get_children().filter(func(child): return child is AcceptDialog)
    check(dialogs.size() == 1, "Profile language dialog missing")
    if dialogs.size() == 1:
        var selections = dialogs[0].get_children().filter(func(child): return child is OptionButton)
        check(selections.size() == 1 and selections[0].item_count == 12, "Profile should show 12 languages")
    global.set_language("fr")
    check(global._determine_initial_lang() == "fr", "Saved preference must override device language")
    global.set_language("INVALID")
    check(global._determine_initial_lang() == "en", "Invalid language must fall back to en")
    check(global.localized_ui_text("çeviri", "Unlisted message") == "Unlisted message", "Unknown message should gracefully fall back")
    firebase.free()
    profile.free()
    onboarding.free()
    print("Localized UI smoke: %d assertions, %d failures" % [checks, errors])
    quit(1 if errors else 0)
""".replace("    ", "\t"), encoding="utf-8")
    (work / "project.godot").write_text("""config_version=5
[application]
config/name="Candar I18N"
[autoload]
Global="*res://global_actual.gd"
[rendering]
renderer/rendering_method="gl_compatibility"
""", encoding="utf-8")
    for args in [["--editor", "--import", "--quit"], ["--script", "res://test.gd", "--quit-after", "500"]]:
        result = subprocess.run(
            [GODOT, "--headless", "--path", str(work), *args],
            capture_output=True, text=True, timeout=90,
        )
        output = result.stdout + result.stderr
        print(output)
        if result.returncode or "SCRIPT ERROR" in output or "Parse Error" in output or (
            "--script" in args and "Localized UI smoke:" not in output
        ):
            raise SystemExit(result.returncode or 1)
