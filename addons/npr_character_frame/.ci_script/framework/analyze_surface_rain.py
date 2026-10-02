"""Visible surface-rain checks: paired material captures and exact dry restoration."""
import json,sys
from pathlib import Path
from PIL import Image
import numpy as np

p=Path(sys.argv[1])
checks={}
report=json.loads((p/"surface_rain.json").read_text())
checks["runtime"]=all(x["pass"] for x in report["checks"])
metrics={}
for material in [2,9]:
    for yaw in [-60,0,60]:
        key=f"close_{material}_{yaw}"
        a=np.asarray(Image.open(p/(key+"_stage.png")).convert("RGB")).astype(int)
        b=np.asarray(Image.open(p/(key+"_off_stage.png")).convert("RGB")).astype(int)
        d=np.max(np.abs(a-b),axis=2)
        metrics[key]={"changed_over_3":int((d>3).sum()),"maximum":int(d.max())}
        checks[key+"_visible"]=bool((d>3).sum()>50)
        checks[key+"_not_global_white"]=bool(((a-b).mean(axis=2)>10).mean()<.03)
a=np.asarray(Image.open(p/"dry_stage.png").convert("RGB"))
b=np.asarray(Image.open(p/"restored_stage.png").convert("RGB"))
checks["dry_restore_exact"]=bool(np.array_equal(a,b))
result={"checks":checks,"metrics":metrics,"pass":all(checks.values())}
(p/"surface_rain_analysis.json").write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
sys.exit(0 if result["pass"] else 1)
