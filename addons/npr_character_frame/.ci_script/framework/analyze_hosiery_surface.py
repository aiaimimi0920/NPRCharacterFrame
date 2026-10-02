"""Check single-layer alpha composition independently of the production shader."""
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image


def image(root, name):
    return np.asarray(Image.open(root / (name + '.png')).convert('RGB'), dtype=np.float64) / 255


def linear(value):
    return np.where(value <= .04045, value / 12.92, ((value + .055) / 1.055) ** 2.4)


def srgb(value):
    return np.where(value <= .0031308, value * 12.92, 1.055 * value ** (1 / 2.4) - .055)


def main(root):
    results = []
    for angle in range(0, 360, 30):
        off = image(root, f'rotation_off_{angle}')
        on = image(root, f'rotation_on_{angle}')
        zero = image(root, f'rotation_zero_{angle}')
        changed = int((np.max(abs(on-off), axis=2)*255 > 3).sum())
        results.append({'view': angle, 'production_visible_pixels': changed,
                        'pass': changed > 100})
        results.append({'view': angle, 'zero_equals_disabled': bool(np.array_equal(off, zero)),
                        'pass': bool(np.array_equal(off, zero))})
    restored = np.array_equal(image(root, 'rotation_on_0'), image(root, 'rotation_restored'))
    results.append({'rotation_restored': bool(restored), 'pass': bool(restored)})
    for angle in (0, 65, 180):
        base, mask = image(root, f'base_{angle}'), image(root, f'mask_{angle}')
        # White coverage identifies the actual visible shell. Exclude raster
        # edges and clipped HDR channels, which cannot be reconstructed from PNG.
        region = (mask.min(2) > .98) & (base.max(2) < .85) & (base.min(2) > .06)
        region[1:-1, 1:-1] &= region[:-2, 1:-1] & region[2:, 1:-1] & region[1:-1, :-2] & region[1:-1, 2:]
        for alpha in (.2, .5):
            expected = srgb(linear(base) * (1 - alpha))
            actual = image(root, f'alpha_{angle}_{round(alpha * 100)}')
            error = np.max(abs(actual - expected), axis=2) * 255
            wrong = int((error[region] > 3).sum())
            count = int(region.sum())
            row = {'view': angle, 'alpha': alpha, 'pixels': count, 'wrong_over_3': wrong,
                   'p99_error': float(np.percentile(error[region], 99)) if count else 255,
                   'pass': count > 1000 and wrong / count < .01}
            results.append(row)
        if angle == 0:
            back_error = np.max(abs(image(root, 'backfaces_depth_on') - base), axis=2)*255
            results.append({'backfaces_occluded_in_front_roi': int((back_error[region] > 3).sum()),
                            'pass': int((back_error[region] > 3).sum()) == 0})
            occluded = image(root, 'occluder_off')
            blocker = (occluded[:, :, 0] > .98) & (occluded[:, :, 1] < .02) & (occluded[:, :, 2] > .98)
            blocker[1:-1, 1:-1] &= blocker[:-2, 1:-1] & blocker[2:, 1:-1] & blocker[1:-1, :-2] & blocker[1:-1, 2:]
            for name, negative in [('occluder_on', False), ('occluder_depth_disabled', True)]:
                error = np.max(abs(image(root, name) - occluded), axis=2)*255
                wrong = int((error[blocker] > 3).sum())
                results.append({'occluder': name, 'roi_pixels': int(blocker.sum()), 'changed': wrong,
                                'pass': int(blocker.sum()) > 1000 and (wrong > 1000 if negative else wrong == 0)})
            error = np.max(abs(image(root, 'backface_depth_disabled') - expected), axis=2) * 255
            wrong = int((error[region] > 3).sum())
            results.append({'negative': 'backface_depth_disabled', 'wrong_over_3': wrong, 'pass': wrong > 1000})
    report = {'checks': results, 'failures': sum(not row['pass'] for row in results)}
    (root / 'surface_analysis.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('HOSIERY_SURFACE', len(results), 'failures', report['failures'])
    for row in results:
        print(row)
    return bool(report['failures'])


if __name__ == '__main__':
    raise SystemExit(main(Path(sys.argv[1])))
