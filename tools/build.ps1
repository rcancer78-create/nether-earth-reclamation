param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
$templatePath = Join-Path $projectRoot '.tools/templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $godotPath -PathType Leaf)) { throw 'Godot 4.5.1 not found. Run tools/setup.ps1 first.' }
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'Windows export template not found. Run tools/setup.ps1 first.' }

# A clean clone has no imported resources or global script class cache.
& $godotPath --headless --path $projectRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Import failed.' }
if (-not $SkipTests) {
    & $godotPath --headless --path $projectRoot --script tests/test_simulation.gd
    if ($LASTEXITCODE -ne 0) { throw 'Simulation tests failed.' }
}
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
$exePath = Join-Path $buildRoot 'NetherEarth.exe'
& $godotPath --headless --path $projectRoot --export-release 'Windows Desktop' $exePath
if ($LASTEXITCODE -ne 0) { throw 'Export failed.' }
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw 'Export did not produce NetherEarth.exe.' }

# A fresh staging folder avoids stale files and nested docs on repeated builds.
$stagePath = [System.IO.Path]::GetFullPath((Join-Path $buildRoot ('package-' + [guid]::NewGuid().ToString('N'))))
if (-not $stagePath.StartsWith($buildRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Package staging directory is outside build/.'
}
New-Item -ItemType Directory -Path $stagePath | Out-Null
try {
    Copy-Item -LiteralPath $exePath -Destination (Join-Path $stagePath 'NetherEarth.exe')
    foreach ($name in @('README.md', 'THIRD_PARTY.md', 'LICENSE')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination (Join-Path $stagePath $name)
    }
    foreach ($name in @('GODOT_LICENSE.txt', 'APACHE-2.0.txt', 'GODOT_COPYRIGHT.txt')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot ('docs/' + $name)) -Destination (Join-Path $stagePath $name)
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination (Join-Path $stagePath 'docs') -Recurse
    @'
@echo off
start "" "%~dp0NetherEarth.exe" --rendering-method gl_compatibility
'@ | Set-Content -LiteralPath (Join-Path $stagePath 'Compatibility.cmd') -Encoding ascii
    $archivePath = Join-Path $buildRoot 'NetherEarth-Windows-x64.zip'
    $packageFiles = @(Get-ChildItem -LiteralPath $stagePath | Select-Object -ExpandProperty FullName)
    Compress-Archive -LiteralPath $packageFiles -DestinationPath $archivePath -Force
}
finally {
    # This unique directory was created above and its absolute boundary was checked.
    if (Test-Path -LiteralPath $stagePath) {
        Remove-Item -LiteralPath $stagePath -Recurse -Force
    }
}
Get-Item -LiteralPath $exePath, $archivePath | Select-Object FullName, Length
