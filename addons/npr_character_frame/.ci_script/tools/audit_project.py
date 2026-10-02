"""Check portable documentation links and literal runtime resource references."""

import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote

addon = Path(__file__).resolve().parents[2]
root = next(p for p in addon.parents if (p / 'project.godot').is_file())
errors = []
documents = list((addon / 'docs').rglob('*.md'))
if (root / 'AGENTS.md').is_file():
    documents.append(root / 'AGENTS.md')
for path in documents:
    for link in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
        if link.startswith(('http:', 'https:', '#')):
            continue
        target = (path.parent / unquote(link.split('#')[0])).resolve()
        if not target.exists():
            errors.append(f'{path.relative_to(root)}: missing link {link}')
sources = [root / 'project.godot']
sources += [p for p in addon.rglob('*') if p.is_file() and
            p.suffix in {'.gd', '.tscn', '.tres', '.gdshader', '.gdshaderinc', '.cfg'} and
            not any(part in {'.ci_script', 'import_sources'} for part in p.parts)]
for path in sources:
    text = path.read_text(encoding='utf-8-sig')
    text = re.sub(r'"\s*\+\s*"', '', text)
    for reference in re.findall(r'"res://([^"\n]+)"', text):
        if any(character in reference for character in ('%', '*', '{')):
            continue
        if not (root / reference).exists():
            errors.append(f'{path.relative_to(root)}: missing resource {reference}')
    if re.search(r'[A-Za-z]:[\\/](?:Users|project)[\\/]', text):
        errors.append(f'{path.relative_to(root)}: machine-specific path')
result = {'documents': len(documents), 'runtime_text_sources': len(sources), 'errors': errors}
print(json.dumps(result, ensure_ascii=False, indent=2))
sys.exit(bool(errors))
