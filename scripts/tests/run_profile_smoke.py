"""Render and exercise the real profile with isolated data and no backend access."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('CANDAR_PROFILE_TEST_OUTPUT', ROOT/'test-artifacts/profile-review-20260909'))
WORK=OUT/'harness'
WORK.mkdir(parents=True,exist_ok=True)
(OUT/'.gdignore').touch()
for name in ['profile.gd','localized_label.gd','localized_button.gd','candar_translations.csv']:
    shutil.copy2(ROOT/name,WORK/name)
for p in ROOT.glob('candar_translations.*.translation'): shutil.copy2(p,WORK/p.name)
shutil.copy2(ROOT/'scripts/CandarUI.gd',WORK/'ui.gd')
shutil.copy2(ROOT/'scripts/tests/profile_fixture.gd',WORK/'global.gd')
shutil.copy2(ROOT/'scripts/tests/profile_smoke.gd',WORK/'test.gd')
# Exercise the actual shared rate calculation without any production services.
global_source=(ROOT/'global.gd').read_text()
names=['_firestore_number','_firestore_int','_firestore_string','_firestore_map_fields','_firestore_timestamp','_timestamp_active','_active_rewarded_boost_multiplier','get_user_mining_rate_components']
methods=[]
for name in names:
    match=re.search(r'^func '+name+r'\([^\n]*',global_source,re.M)
    end=re.search(r'^func |^# ={10,}',global_source[match.end():],re.M)
    methods.append(global_source[match.start():match.end()+end.start()] if end else global_source[match.start():])
constant=re.search(r'^const REWARDED_BOOST_MAX_MULTIPLIER[^\n]*',global_source,re.M).group(0)
(WORK/'rate_actual.gd').write_text('extends Node\n'+constant+'\nvar referral_queries := 0\nvar writes := 0\nfunc get_user_doc(_uid) -> Dictionary: return {}\nfunc get_users_by_referral(_code) -> Array:\n\treferral_queries += 1\n\treturn [{},{},{}]\nfunc patch_user_fields(_uid, _fields) -> Array:\n\twrites += 1\n\treturn [true]\n'+'\n'.join(methods))
scene=re.sub(r' uid="[^"]+"','',(ROOT/'profile.tscn').read_text())
(WORK/'profile.tscn').write_text(scene)
translations=', '.join('"res://candar_translations.'+lang+'.translation"' for lang in ['tr','en','de','fr','es','pt','ru','zh','ja','ko','ar','hi'])
(WORK/'project.godot').write_text(f'''config_version=5
[application]
config/name="Candar Profile Review"
config/version="2.0.21"
[autoload]
Global="*res://global.gd"
CandarUI="*res://ui.gd"
[display]
window/size/viewport_width=720
window/size/viewport_height=1560
window/size/window_width_override=360
window/size/window_height_override=780
window/stretch/mode="canvas_items"
[internationalization]
locale/translations=PackedStringArray({translations})
[rendering]
renderer/rendering_method="gl_compatibility"
''')
GODOT=shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
render='--render' in sys.argv
for args in [['--headless','--editor','--import','--quit'], ([] if render else ['--headless'])+['--script','res://test.gd','--quit-after','1600','--',str(OUT), 'render' if render else 'test']]:
    result=subprocess.run([GODOT,'--path',str(WORK),*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=60)
    print(result.stdout,flush=True)
    if result.returncode or 'SCRIPT ERROR' in result.stdout: raise SystemExit(result.returncode or 1)
