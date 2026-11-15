# Face clip-position selection regression

Face, eye stencil and SDF360 vertex paths select either the calculated clip position or an offscreen position. Use the Boolean-vector `mix` overload, not a floating-point factor: the latter performs arithmetic between distant values and can lose precision relevant to closely separated surfaces. Visibility conditions, projection and material semantics are unchanged.

## Reproduction

Run with the project's supported engine and a real Forward+ GPU (not headless):

```text
<engine> --path <project> --rendering-method forward_plus --resolution 128x128 --script res://addons/npr_character_frame/.ci_script/framework/face_clip_selection_regression.gd
```

The test builds two colored quads separated by 2 micrometers, with no external model or texture. It reads the selection expression from each of the three production shader sources and tests shown/hidden states under orthographic and perspective projection against a conditional-selection control. Sixteen required pixel assertions cover these four paths. Four additional old-arithmetic samples are diagnostic: not every GPU/compiler reproduces the rounding error. Results and twenty images are written under `.temp/face_clip_selection/`.

## Recorded scope

On AMD Radeon Graphics, Vulkan Forward+, MiDot `4.8.beta3.custom_build.8ae4b7dd2`, all sixteen required assertions passed. The old expression selected the rear green quad incorrectly in orthographic projection; the Boolean selection retained the red front quad. Perspective did not reproduce the old defect. Full Face, eye-stencil and SDF360 shaders were additionally loaded and drawn without shader errors. An isolated real character comparison confirmed the Face correction removed the eye-layer artifact.

This is a precision/visibility regression, not full character, stencil-composition, SDF-artistic-quality or cross-device acceptance. No character assets or private screenshots are included. The repository-specific `gdscript-post-check` wrapper was unavailable on the test machine; the script is checked with the available formatter and executed by the actual engine instead.

## Responsibility split

The Face entry shader retains declarations, vertex processing and fragment orchestration. Lighting helpers own occlusion, line/makeup and illumination; surface-effects helpers own bloom, height/LUT/fog finishing and expression ink. Includes remain at the original declaration position. Expanding the two includes exactly reproduces the pre-split source. Three complete shaders loaded successfully, 16 GPU assertions passed, and 36 isolated character views matched the pre-split pixels exactly. No material or model contract changed.
