"""Build a Beaver-native SDF request; no Blender process is launched here."""

import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def build_request(recipe_dir, workspace=None):
    RECIPE = Path(recipe_dir)
    style = json.loads((RECIPE / "face_style.json").read_text())
    code = "import sys,types\n"
    for name, path in [
        ("face", RECIPE / "face.py"),
        ("distance_field", HERE / "distance_field.py"),
    ]:
        code += f'm=types.ModuleType({name!r});sys.modules[{name!r}]=m;m.STYLE={style!r}\nexec(compile({path.read_text()!r},{name!r},"exec"),m.__dict__)\n'
    code += (HERE / "bake.py").read_text()
    paths = [
        "assets/aster/sdf_664/face_sdf360.png",
        "assets/aster/head_recovery_664/aster_definition.tres",
        "assets/aster/sdf_664/bake_report.json",
    ]
    for name in ["bake.py", "distance_field.py"]:
        path = "assets/aster/sdf_664/" + name
        code += (
            f"Path(beaver_output({path!r})).write_text({(HERE/name).read_text()!r})\n"
        )
        paths.append(path)
    outputs = []
    for path in paths:
        local = Path(workspace) / path if workspace else None
        digest = (
            hashlib.sha256(local.read_bytes()).hexdigest()
            if local and local.is_file()
            else None
        )
        outputs.append({"path": path, "expectedSha256": digest})
    compile(code, "<Beaver SDF recipe>", "exec")
    return {"code": code, "outputs": outputs, "timeoutSeconds": 240}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--recipe-dir",
        type=Path,
        required=True,
        help="Authorized current head recipe directory containing face.py and face_style.json",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--workspace", type=Path, help="Existing workspace for optimistic output hashes"
    )
    args = parser.parse_args()
    args.output.write_text(json.dumps(build_request(args.recipe_dir, args.workspace)))
