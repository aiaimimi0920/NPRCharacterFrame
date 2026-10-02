param(
    [string]$GodotPath = $env:NPR_GODOT_PATH,
    [string]$OutputPath = "",
    [string]$PythonPath = "python"
)
$ErrorActionPreference = "Stop"
# Check the selected Python environment before spending time on GPU captures.
# APPDATA isolation can hide Windows per-user numpy/Pillow installations.
try {
    & $PythonPath -c "import numpy; import PIL"
    if ($LASTEXITCODE -ne 0) { throw "Python dependency probe exited $LASTEXITCODE" }
} catch {
    throw "Wardrobe image analysis requires numpy and Pillow in -PythonPath. Use a self-contained environment or preserve its package search path before APPDATA isolation. $_"
}
if (-not $OutputPath) {
    $project = $PSScriptRoot
    while (-not (Test-Path -LiteralPath (Join-Path $project "project.godot"))) {
        $parent = Split-Path -Parent $project
        if (-not $parent -or $parent -eq $project) { throw "Cannot find host project.godot" }
        $project = $parent
    }
    $OutputPath = Join-Path $project (".temp/framework-suite/" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
$runner = Join-Path $PSScriptRoot "run_validation.ps1"
& $runner -GodotPath $GodotPath -OutputPath (Join-Path $OutputPath "import") -Mode import -TimeoutSeconds 300
& $runner -GodotPath $GodotPath -OutputPath (Join-Path $OutputPath "startup") -Mode startup
$tests = @(
    "capture_clock_regression", # Fixed simulation ticks survive render waits and recreation.
    "capture_pointer_regression", # Non-hover capture cancels pending and visible tooltips.
    "wardrobe_regression",
    "visual_directions_regression", # Evaluated neutral pose, fixed rain and exact RGBA reset.
    "wardrobe_display_regression", # Real display controls, fitted shader restoration and saves.
    "showcase_identity_regression", # Explicit character input, owner-scoped schemes and demo clip.
    "showcase_camera_regression", # Authored camera calibration, exact sample views and isolation.
    "palette_contract_regression", # Original/custom sentinels, saved RGB and legacy defaults.
    "showcase_palette_profile_regression", # Author defaults, snapshots and real alternate palette UI.
    "showcase_height_profile_regression", # Authored bounds, snapshots and historical migration.
    "hosiery_height_contract_regression", # Rest height, saved boundaries and Body/fitted/rain agreement.
    "face_atlas_profile_regression", # Authored Face sampling, strict GPU domains and isolation.
    "pupil_scale_persistence_regression", # Actual vector endpoints survive save and scene reload.
    "eye_geometry_profile_regression", # Includes symbol, performance, face and expression checks.
    "soft_tissue_data_regression", # Includes production pressure geometry and lifecycle checks.
    "hair_dynamics_data_regression", # Includes sample hair style and dynamic palette checks.
    "rig_layout_data_regression", # Authored diagnostic endpoints and exact display restoration.
    "speech_lifecycle_regression", # Actual mixer clock, playback ownership and delayed sequence cancellation.
    "realtime_lifecycle_regression", # Engine-delta pause/resume/reset and repeated scene disposal.
    "rain_realtime_regression", # Natural retirement, exact GPU freeze/clear and residual material decay.
    "visibility_lifecycle_regression", # Hidden actor/ancestor preserves explicit pauses and exact GPU restoration.
    "framework_workbench_regression",
    "framework_quality_comic_regression",
    "comic_spawn_pin_regression",
    "comic_pinned_occlusion_regression", # Same-token PINNED depth, real hair and edge negative control.
    "comic_profile_regression", # Authored placement, instance isolation and physical role queries.
    "module_regression",
    "render_regression"
)
$failures = @()
foreach ($test in $tests) {
    try {
        & $runner -GodotPath $GodotPath -OutputPath (Join-Path $OutputPath $test) -Mode capture -TimeoutSeconds 300 -TestScript "res://addons/npr_character_frame/.ci_script/framework/$test.gd"
        if ($test -eq "wardrobe_regression") {
            & $PythonPath (Join-Path $PSScriptRoot "analyze_wardrobe.py") (Join-Path $OutputPath $test)
            if ($LASTEXITCODE -ne 0) { throw "Wardrobe strict image analysis failed ($LASTEXITCODE)" }
        }
        if ($test -eq "visual_directions_regression") {
            & $PythonPath (Join-Path $PSScriptRoot "analyze_visual_directions.py") (Join-Path $OutputPath $test)
            if ($LASTEXITCODE -ne 0) { throw "Visual directions strict image analysis failed ($LASTEXITCODE)" }
        }
    } catch {
        $failures += $test
        Write-Warning "$test failed: $_"
    }
}
if ($failures.Count) {
    throw "NPR Character Frame regressions failed: $($failures -join ', ')"
}
Write-Output "NPR_CHARACTER_FRAME_SUITE_OK"
