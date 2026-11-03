"""Exercise production ATT decisions with native doubles and no device/file state."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GODOT = os.environ.get('GODOT_BIN') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
source = (ROOT / 'global.gd').read_text()
source = source[source.index('func _att_is_ios()'):source.index('func ads_init_after_att(')]
source = re.sub(r'func _att_is_ios\(\).*?(?=\nfunc )', 'func _att_is_ios() -> bool:\n\treturn ios\n', source, flags=re.S)
source = re.sub(r'func _att_get_plugin\(\).*?(?=\nfunc )', 'func _att_get_plugin() -> Object:\n\treturn native\n', source, flags=re.S)
with tempfile.TemporaryDirectory(prefix='candar-att-test-') as directory:
    work = Path(directory)
    (work / 'att.gd').write_text('extends Node\nvar ios := true\nvar native: Object\n' + source)
    shutil.copy2(ROOT / 'scripts/tests/att_smoke.gd', work / 'test.gd')
    (work / 'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    result = subprocess.run([GODOT, '--headless', '--path', str(work), '--script', 'res://test.gd', '--quit-after', '300'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    if result.returncode or 'ERROR:' in result.stdout or 'ATT smoke:' not in result.stdout:
        raise SystemExit(result.returncode or 1)
