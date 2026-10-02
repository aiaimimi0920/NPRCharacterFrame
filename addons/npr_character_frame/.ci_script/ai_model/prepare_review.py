"""Prepare compact visual evidence for an external AI; never call a model service."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageFilter, ImageStat


def prepare(directory):
    report = json.loads((directory / 'report.json').read_text(encoding='utf-8'))
    views = report.get('views', [])
    if sorted(v['yaw_degrees'] for v in views) != [-90, -45, 0, 45, 90, 180]:
        raise ValueError('Six unique standard views are required; capture_views.gd creates them')
    evidence = []
    for view in views:
        image_path = (directory / view['image']).resolve()
        if not image_path.is_relative_to(directory.resolve()):
            raise ValueError('Image must remain inside the evidence directory')
        with Image.open(image_path) as image:
            if image.size != (768, 768):
                raise ValueError('Capture resolution must match the documented 768 x 768 protocol')
            gray = image.convert('L')
            stats = ImageStat.Stat(gray)
            edge = ImageStat.Stat(gray.filter(ImageFilter.FIND_EDGES).crop((1, 1, 767, 767)))
            evidence.append({**view, 'sha256': hashlib.sha256(image_path.read_bytes()).hexdigest(),
                             'luminance_mean': round(stats.mean[0], 3),
                             'luminance_stddev': round(stats.stddev[0], 3),
                             'edge_response_mean': round(edge.mean[0], 3)})
    addon = Path(__file__).resolve().parents[2]
    prompt = (addon / 'docs/model_authoring/tests/face_softness_prompt.md').read_text(encoding='utf-8')
    result = {
        'schema_version': 1, 'case_id': 'appearance.face_softness', 'status': 'prepared_for_external_ai',
        'definition': report.get('definition'), 'capture': report.get('capture', {}),
        'compliance_errors': report.get('compliance_errors', []),
        'geometry_measurements': report.get('measurements', {}), 'views': evidence,
        'metric_limits': 'Whole-image summaries only; not isolated face curvature or a softness score.',
        'prompt': prompt,
        'expected_response': {'compliance_errors': [], 'visual_suggestions': [], 'not_evaluated': []},
    }
    (directory / 'ai_request.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    prepare(args.evidence)
    print('AI_REVIEW_PREPARED (no API calls)')
