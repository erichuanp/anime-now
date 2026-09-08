# Builds the Windows release and packs both artifacts into dist\:
#   anime-now-<version>-windows-x64.zip     portable, unzip and run
#   anime-now-<version>-windows-setup.exe   installer (Inno Setup)
#
# Needs: Flutter, Visual Studio 2022 with the "Desktop development with C++"
# workload, and Inno Setup 6 (winget install JRSoftware.InnoSetup).
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File tools\make-windows.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

# pubspec "version: 2026.9.3+1" -> "2026.9.3.1"
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value).Trim() -replace '\+', '.'
Write-Host "version $version"

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

$release = "build\windows\x64\runner\Release"
if (-not (Test-Path "$release\anime_now.exe")) { throw "missing $release\anime_now.exe" }
New-Item -ItemType Directory -Force -Path dist | Out-Null

$zip = "dist\anime-now-$version-windows-x64.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$release\*" -DestinationPath $zip

$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
  # Inno Setup 6.7+ installs per-user under %LOCALAPPDATA%\Programs by default
  # (winget), and does not put ISCC.exe on PATH.
  foreach ($p in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
    if (Test-Path $p) { $iscc = $p; break }
  }
}
if (-not $iscc) { throw "Inno Setup not found. winget install JRSoftware.InnoSetup" }

& $iscc "/DAppVersion=$version" tools\anime-now.iss
if ($LASTEXITCODE -ne 0) { throw "iscc failed" }

Write-Host ""
Get-ChildItem dist\*windows* | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}
