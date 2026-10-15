"""Generate a definition using only the fixed, published plugin location."""

MATERIAL_SCRIPT = (
    "res://addons/npr_character_frame/shaders/face/sdf360/sdf_materials.gd"
)
BASE_SCRIPT = "res://addons/npr_character_frame/npr_character_materials.gd"


def bind_directional_atlas(source, atlas_path):
    marker = '[sub_resource type="Resource" id="Materials"]'
    for required in (BASE_SCRIPT, marker, "sdf_on_uv2 = true"):
        if source.count(required) != 1:
            raise ValueError("Expected exactly one definition field: " + required)
    if 'id="sdf360_atlas"' in source or "face_sdf360 =" in source:
        raise ValueError("Definition already contains a directional atlas binding")
    if (
        not atlas_path
        or any(c in atlas_path for c in '\n\r"')
        or ".." in atlas_path.split("/")
    ):
        raise ValueError("Atlas path must be a project-relative resource path")
    if atlas_path.startswith(("/", "res://")) or ":" in atlas_path:
        raise ValueError("Atlas path must be project relative")
    source = source.replace(BASE_SCRIPT, MATERIAL_SCRIPT)
    source = source.replace(
        marker,
        '[ext_resource type="Texture2D" path="res://'
        + atlas_path
        + '" id="sdf360_atlas"]\n\n'
        + marker,
    )
    return source.replace(
        "sdf_on_uv2 = true",
        'sdf_on_uv2 = true\nface_sdf360 = ExtResource("sdf360_atlas")',
    )
