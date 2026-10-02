"""Regenerate the public GDScript declaration index from the plugin sources."""

from pathlib import Path
import re

addon = Path(__file__).resolve().parents[2]
destination = addon / 'docs/developer/api_reference.md'
lines = ['# API 声明索引', '', '由 `.ci_script/tools/generate_api.py` 从实际源码生成。',
         '此表列出公开类的方法与导出属性；内部下划线方法不作为公开 API。', '']
for path in sorted(addon.rglob('*.gd')):
    if '.ci_script' in path.parts:
        continue
    text = path.read_text(encoding='utf-8')
    match = re.search(r'^class_name (\w+)', text, re.M)
    if not match:
        continue
    relative = path.relative_to(addon).as_posix()
    lines += [f'## {match.group(1)}', '', f'[源代码](../../{relative})', '', '```gdscript']
    source = text.splitlines()
    for i, line in enumerate(source):
        if re.match(r'(?:static )?func [^_\W]\w*\(', line):
            signature = line
            while not signature.rstrip().endswith(':') and i + 1 < len(source):
                i += 1
                signature += '\n' + source[i]
            lines.append(signature)
        elif line.startswith('@export') and ' var ' in line:
            lines.append(line)
    lines += ['```', '']
destination.write_text('\n'.join(lines), encoding='utf-8')
print(destination.relative_to(addon).as_posix())
