"""Run the real onboarding scene with isolated auth doubles; never contact production."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get('GODOT_BIN') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
with tempfile.TemporaryDirectory(prefix='candar-onboarding-test-') as work:
    work = Path(work)
    for name in ['onboarding.gd', 'localized_label.gd', 'localized_line_edit.gd', 'localized_button.gd', 'candar_translations.csv']:
        shutil.copy2(ROOT / name, work / name)
    for translation in ROOT.glob('candar_translations.*.translation'):
        shutil.copy2(translation, work / translation.name)
    (work / 'assets').mkdir()
    for name in ['google_g.png', 'logoyazili.png', 'apple_logo_white.png', 'onboarding_eye.svg', 'onboarding_eye_hidden.svg']:
        source = ROOT / 'assets' / name
        if source.exists(): shutil.copy2(source, work / 'assets' / name)
    scene = (ROOT / 'onboarding.tscn').read_text()
    scene = re.sub(r' uid="[^"]+"', '', scene).replace('res://addons/DeeplinkPlugin/Deeplink.gd', 'res://deeplink_stub.gd')
    (work / 'onboarding.tscn').write_text(scene)
    shutil.copy2(ROOT / 'scripts/tests/onboarding_smoke.gd', work / 'test.gd')
    shutil.copy2(ROOT / 'scripts/tests/onboarding_auth_input.gd', work / 'auth_input_test.gd')
    shutil.copy2(ROOT / 'scripts/tests/onboarding_layout.gd', work / 'layout_test.gd')
    (work / 'onboarding_ios_test.gd').write_text('extends "res://onboarding.gd"\nfunc _is_ios_runtime() -> bool: return true\n')
    shutil.copy2(ROOT / 'scripts/i18n_smoke_test.gd', work / 'i18n_test.gd')
    (work / 'deeplink_stub.gd').write_text('extends Node\n@export var scheme: String\n@export var host: String\n')
    (work / 'ui_stub.gd').write_text('extends Node\nfunc add_gradient_bg(_parent, _name):\n\tpass\n')
    (work / 'firebase_stub.gd').write_text('extends Node\nfunc set_tokens(_id, _refresh, _uid):\n\tpass\n')
    (work / 'global_stub.gd').write_text('''extends Node
var login_calls := 0
var login_delay := 0.1
var last_email := ""
var last_password := ""
var last_referral := ""
var reset_calls := 0
var pending_code := ""
var events: Array = []
func analytics_page(_a, _b): pass
func analytics_event(name, params): events.append({"event": name, "params": params})
func apply_safe_area(_scene): pass
func get_pending_referral_code() -> String: return pending_code
func save_uid(_uid): pass
func login_or_register(_email, _password, _ref) -> Array:
	login_calls += 1
	last_email = _email
	last_password = _password
	last_referral = _ref
	await get_tree().create_timer(login_delay).timeout
	return [false, "Test request failed"]
func apple_sign_in(_ref) -> Array: return [false, "Test"]
func google_sign_in(_ref) -> Array: return [false, "Test"]
func send_password_reset(_email) -> Array:
	reset_calls += 1
	return [false, "Test"]
''')
    translations = ', '.join('"res://candar_translations.' + lang + '.translation"' for lang in ['en','tr','de','fr','es','pt','ru','zh','ja','ko','ar','hi'])
    (work / 'project.godot').write_text(f'''config_version=5
[application]
config/name="Candar Isolated Onboarding Test"
[autoload]
Global="*res://global_stub.gd"
Firebase="*res://firebase_stub.gd"
CandarUI="*res://ui_stub.gd"
[internationalization]
locale/translations=PackedStringArray({translations})
[rendering]
renderer/rendering_method="gl_compatibility"
''')
    for args in [['--editor', '--import', '--quit'], ['--script', 'res://test.gd'], ['--script', 'res://auth_input_test.gd'], ['--script', 'res://layout_test.gd'], ['--script', 'res://i18n_test.gd']]:
        result = subprocess.run([GODOT, '--headless', '--path', str(work), '--quit-after', '600', *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        errors = [line for line in result.stdout.splitlines() if any(term in line for term in ['SCRIPT ERROR', 'Parse Error', 'Onboarding smoke', 'Onboarding auth input', 'i18n smoke', 'ERROR:'])]
        print('\n'.join(errors) if errors else 'Godot isolated import completed.')
        incomplete = 'res://auth_input_test.gd' in args and 'Onboarding auth input passed:' not in result.stdout
        if result.returncode or incomplete or any('SCRIPT ERROR' in line or 'Parse Error' in line for line in errors):
            print(result.stdout)
            raise SystemExit(result.returncode or 1)
