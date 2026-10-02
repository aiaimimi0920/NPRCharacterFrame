param(
    [string]$GodotPath = $env:NPR_GODOT_PATH,
    [string]$OutputPath = "",
    [string]$TestScript = "",
    [ValidateSet("inspect", "capture", "import", "lab", "startup")][string]$Mode = "capture",
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120,
    [switch]$MonitorMemory
)
$ErrorActionPreference = "Stop"
$project = $PSScriptRoot
while (-not (Test-Path -LiteralPath (Join-Path $project "project.godot"))) {
    $parent = Split-Path -Parent $project
    if (-not $parent -or $parent -eq $project) { throw "Cannot find host project.godot" }
    $project = $parent
}
if (-not $GodotPath) { throw "Pass -GodotPath or set NPR_GODOT_PATH to the supplied Godot executable" }
if (-not $OutputPath) { $OutputPath = Join-Path $project (".temp/framework/" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
$output = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$stdout = Join-Path $output "$Mode.stdout.log"
$stderr = Join-Path $output "$Mode.stderr.log"
$arguments = @("--path", ('"' + $project + '"'), "--audio-driver", "Dummy")
if ($Mode -eq "import") {
    $arguments += @("--headless", "--editor", "--import", "--quit")
} elseif ($Mode -eq "startup") {
    # Exercise project.godot's real main scene, with the actual GPU renderer.
    $arguments += @("--rendering-method", "forward_plus", "--quit-after", "90")
} else {
    if ($Mode -eq "inspect") { $arguments += "--headless" }
    else { $arguments += @("--rendering-method", "forward_plus", "--resolution", $(if ($Mode -eq "lab") { "1440x900" } else { "1152x648" })) }
    $script = if ($Mode -eq "lab") { "res://addons/npr_character_frame/.ci_script/framework/lab_regression.gd" } else { "res://addons/npr_character_frame/.ci_script/framework/render_regression.gd" }
    if ($TestScript) { $script = $TestScript }
    $arguments += @("--script", $script, "--", $Mode, ('"' + $output + '"'))
}
$proc = $null
$memoryProcess = $null
$memoryRows = [System.Collections.Generic.List[object]]::new()
try {
    $proc = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $proc.Handle
    if ($MonitorMemory -and [IO.Path]::GetFileName($GodotPath) -notlike "*.console.exe") { $memoryProcess = $proc }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.WaitForExit(500)) {
        if ($MonitorMemory) {
            if (-not $memoryProcess) {
                # Godot's Windows console executable is only a tiny forwarding
                # wrapper. Measure its renderer child, never the wrapper's RSS.
                $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" | Where-Object { $_.Name -like "godot*.exe" })
                if ($children.Count -gt 1) { throw "Ambiguous renderer process for memory sampling" }
                if ($children.Count -eq 1) { $memoryProcess = Get-Process -Id $children[0].ProcessId }
            }
            if ($memoryProcess) { $memoryProcess.Refresh() }
            if ($memoryProcess -and -not $memoryProcess.HasExited) {
                $memoryRows.Add([ordered]@{
                    elapsed_ms=$timer.ElapsedMilliseconds
                    renderer_pid=$memoryProcess.Id
                    renderer_name=$memoryProcess.ProcessName
                    private_bytes=$memoryProcess.PrivateMemorySize64
                    working_set_bytes=$memoryProcess.WorkingSet64
                    peak_working_set_bytes=$memoryProcess.PeakWorkingSet64
                })
            }
        }
        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "Godot timed out ($Mode)" }
    }
    $proc.Refresh()
    $log = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
    # re-spirv writes directly to stderr, without Godot's ERROR/WARNING prefix.
    $issues = @($log -split "`n" | Where-Object { $_ -match "ERROR:|SCRIPT ERROR:|SHADER ERROR:|Parse Error|WARNING:|Op\w+ is not supported yet\.|SPIR-V Parsing error\." })
    Write-Output "MODE=$Mode EXIT=$($proc.ExitCode) ISSUES=$($issues.Count) OUTPUT=$output"
    if ($issues.Count) { $issues | Select-Object -First 12 }
    if ($Mode -eq "inspect") { $log -split "`n" | Where-Object { $_ -match "^MESH |^COLORS |^\{|REGRESSION_OK" } }
    if ($proc.ExitCode -ne 0 -or $issues.Count -gt 0) { throw "Validation failed; see $output" }
    if ($Mode -in @("inspect", "capture", "lab") -and $log -notmatch "REGRESSION_OK") { throw "Regression did not finish" }
} finally {
    # Capture owned renderer children before stopping the console wrapper.
    if ($proc) {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" | Where-Object { $_.Name -like "godot*.exe" })
        foreach ($child in $children) {
            Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    if ($memoryProcess -and $proc -and $memoryProcess.Id -ne $proc.Id) {
        $memoryProcess.Refresh()
        if (-not $memoryProcess.HasExited) { Stop-Process -Id $memoryProcess.Id -Force }
        $memoryProcess.Dispose()
    }
    if ($proc) {
        $proc.Refresh()
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        $pidToCheck = $proc.Id
        $proc.Dispose()
        $remaining = @(Get-Process -Id $pidToCheck -ErrorAction SilentlyContinue)
        Write-Output "TEST_PROCESS_REMAINING=$($remaining.Count)"
    }
    if ($MonitorMemory) {
        # Preserve partial measurements on timeout or shader/runtime failure too.
        ConvertTo-Json -InputObject $memoryRows.ToArray() -Depth 4 | Set-Content -LiteralPath (Join-Path $output "process_memory.json") -Encoding UTF8
    }
}
