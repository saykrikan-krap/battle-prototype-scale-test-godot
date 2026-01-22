$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$GodotRoot = Join-Path $ScriptDir "tools/godot/4.5.1"

$IsWindowsLocal = $false
$IsMacOSLocal = $false
$IsLinuxLocal = $false

if ($PSVersionTable.PSEdition -eq "Core") {
  $IsWindowsLocal = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
  $IsMacOSLocal = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
  $IsLinuxLocal = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
} else {
  $IsWindowsLocal = $true
}

if ($IsWindowsLocal) {
  $GodotBin = Join-Path $GodotRoot "windows/Godot_v4.5.1-stable_win64_console.exe"
} elseif ($IsMacOSLocal) {
  $GodotBin = Join-Path $GodotRoot "macos/Godot.app/Contents/MacOS/Godot"
} elseif ($IsLinuxLocal) {
  $GodotBin = Join-Path $GodotRoot "linux/Godot_v4.5.1-stable_linux.x86_64"
} else {
  Write-Error "Unsupported OS."
  exit 1
}

if (!(Test-Path $GodotBin)) {
  Write-Error "Godot binary not found: $GodotBin"
  Write-Error "Place the 4.5.1 binaries under tools/godot/4.5.1/."
  exit 1
}

& $GodotBin --path $ScriptDir @args
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
  exit $exitCode
}
