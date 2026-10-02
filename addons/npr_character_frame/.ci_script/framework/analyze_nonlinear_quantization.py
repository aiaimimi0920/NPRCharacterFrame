"""Required-state oracle. A deliberately disabled lighting branch must fail."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("root", type=Path)
parser.add_argument("--expected-pairs", type=int, default=12)
args = parser.parse_args()
assert args.expected_pairs > 0
root = args.root
report = json.loads((root / "nonlinear_checks.json").read_text(encoding="utf-8"))
assert report["checks"] and all(row["pass"] for row in report["checks"])
assert len(report["oracle"]) == args.expected_pairs
assert len({(pair["first"], pair["second"]) for pair in report["oracle"]}) == args.expected_pairs
checks = []
for pair in report["oracle"]:
    with Image.open(root / (pair["first"] + ".png")) as a:
        with Image.open(root / (pair["second"] + ".png")) as b:
            assert a.size == b.size
            r, g, blue = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).split()
            peak = ImageChops.lighter(ImageChops.lighter(r, g), blue)
            hist = peak.histogram()
            maximum = peak.getextrema()[1]
            checks.append(dict(pair, maximum=maximum, changed_over_3=sum(hist[4:]),
                               **{"pass": maximum <= 1}))
(root / "nonlinear_image_checks.json").write_text(json.dumps(checks, indent=2), encoding="utf-8")
responses = []
for pair in report.get("responses", []):
    with Image.open(root / (pair["first"] + ".png")) as a:
        with Image.open(root / (pair["second"] + ".png")) as b:
            assert a.size == b.size
            r, g, blue = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).split()
            hist = ImageChops.lighter(ImageChops.lighter(r, g), blue).histogram()
            changed = sum(hist[4:])
    responses.append(dict(pair, changed_over_3=changed, **{"pass": changed >= pair["minimum"]}))
if "responses" in report:
    assert len(responses) == 6, "Hair chain requires four legacy controls and both post-light passes"
    (root / "nonlinear_response_checks.json").write_text(json.dumps(responses, indent=2), encoding="utf8")
failed = [row for row in checks if not row["pass"]]
print("NONLINEAR_REQUIRED", len(checks), "failed", len(failed))
for row in failed:
    print(row["first"], "max", row["maximum"], "pixels>3", row["changed_over_3"])
assert not failed, "Unfinished HDR nonlinear migration: lighting disabled or evaluated in wrong order"
print("NONLINEAR_RESPONSES", len(responses), "failed", [row for row in responses if not row["pass"]])
assert all(row["pass"] for row in responses), "Nonlinear fixtures or individual passes are not observable"
