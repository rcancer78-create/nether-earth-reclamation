$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
New-Item -ItemType Directory -Force .tools/godot | Out-Null
$version = '4.5.1-stable'
$archivePath = Join-Path $projectRoot '.tools/godot.zip'
if (-not (Test-Path -LiteralPath '.tools/godot/Godot_v4.5.1-stable_win64_console.exe')) {
    Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/$version/Godot_v${version}_win64.exe.zip" -OutFile $archivePath
    Expand-Archive -LiteralPath $archivePath -DestinationPath .tools/godot -Force
}
if (-not (Test-Path -LiteralPath '.tools/templates/windows_release_x86_64.exe')) {
    python tools/fetch_windows_template.py
    if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve Windows export template.' }
}
foreach ($requiredPath in @('.tools/godot/Godot_v4.5.1-stable_win64_console.exe', '.tools/templates/windows_release_x86_64.exe')) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw ('Setup did not produce ' + $requiredPath) }
}
Write-Output 'Godot and the Windows export template are ready. Run tools/build.ps1.'
