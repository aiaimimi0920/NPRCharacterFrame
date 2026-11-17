# Optional mesh-local nose line

The fixed Face shader supports an opt-in authored nose-line domain. Set ShaderMaterial
parameters on the canonical Face base material; source-material mode preserves them.
No replacement shader or extra role is needed. This does not alter model validation.

- `u_npr_nose_local_enabled`: defaults to false. The historical ILM/view-dependent
  nose line remains unchanged while disabled.
- `u_npr_nose_local_curve`: `(center_y, curvature, x_scale, y_width)` in Face mesh
  coordinates. The center curve is `y = center_y + curvature * (x/x_scale)^2`.
- `u_npr_nose_local_domain`: `(x_inner, x_outer, z_lower, z_upper)`. Absolute X
  fades out between the first two values; Z fades in between the last two.
- `u_npr_nose_local_color`: sRGB color with alpha as blend strength, not transparency.

Enabling replaces the historical nose blend, including outside the local domain,
where unmodified base albedo is retained. It does not multiply the ILM B mask.
The Gaussian Y band has tails, rather than a strict finite Y boundary.
Calibrate finite values per asset in Y-up, Z-forward, X-right coordinates, centered
on X=0. Use positive scale/width and ordered fade endpoints. Shader guards avoid
zero denominators and equal smoothstep edges; they are not authoring validation.
No character dimensions are embedded in the framework defaults.

The position comes from VERTEX at the start of the vertex stage, after morphing.
This is not a rest-space landmark, bone-attached mask or arbitrary-model adapter.
Nose-changing morphs, skinning and different asset origins need separate visual
validation. Texture coordinates, existing vertex channels, eye/lip rendering and
SDF are not reassigned. No posterior-patch merge or hair change is included.

## Verification

Run the portable source contract checks from any host directory:
`python addons/npr_character_frame/.ci_script/framework/test_nose_local_contract.py`

Source checks do not establish visual quality. The development regression used
MiDot 4.8 beta3 Forward+ with an isolated three-role Faye front-nose fixture:
16 baseline-disabled views, 48 mode/pose views and a saved-resource round trip.
The fixture excludes the separate research posterior patch, so this evidence is
not complete-character, export-package, skeletal-animation or dynamic acceptance.
No model assets or local test renders are distributed with this change.
