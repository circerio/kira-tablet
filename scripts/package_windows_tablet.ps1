. "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'
Write-Host "=== Kira Tablet Windows Release ===" -ForegroundColor Green

try {
    Push-Location (Join-Path $PSScriptRoot '..')

    if (-not ${env:ProgramFiles(x86)} -and (Test-Path 'D:\DevTools\ProgramFilesX86')) {
        ${env:ProgramFiles(x86)} = 'D:\DevTools\ProgramFilesX86'
    }
    if (-not (Get-Command nuget.exe -ErrorAction SilentlyContinue)) {
        $nuget = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter nuget.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'Microsoft\.NuGet_' } |
            Select-Object -First 1
        if ($nuget) {
            $env:PATH = "$($nuget.Directory.FullName);$env:PATH"
        }
    }

    $pubspec = Get-Content 'pubspec.yaml' -Raw
    if ($pubspec -notmatch '(?m)^version:\s*(\S+)') {
        throw 'Cannot parse version from pubspec.yaml'
    }
    $versionFull = $Matches[1] -replace '\+', '-'
    $exeName = 'KiraTablet.exe'
    $productName = 'Kira Tablet'

    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $flutter = $flutterCmd.Source
    } elseif (Test-Path 'D:\DevTools\flutter\bin\flutter.bat') {
        $flutter = 'D:\DevTools\flutter\bin\flutter.bat'
    } else {
        throw 'Flutter not found'
    }
    $windowsBuildRoot = Join-Path (Get-Location) 'build\windows'
    if (Test-Path $windowsBuildRoot) {
        Remove-Item $windowsBuildRoot -Recurse -Force
    }
    $releaseDir = Join-Path (Get-Location) 'build\windows\x64\runner\Release'

    Write-Host "Building $productName v$versionFull..." -ForegroundColor Yellow
    & $flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows failed: $LASTEXITCODE"
    }
    if (-not (Test-Path (Join-Path $releaseDir $exeName))) {
        throw "Missing Windows executable: $exeName"
    }

    foreach ($file in @('LICENSE','THIRD_PARTY_NOTICES.md','README.md','RELEASE_NOTES_v0.1.0.md')) {
        Copy-Item $file (Join-Path $releaseDir $file) -Force
    }
    Get-ChildItem $releaseDir -Directory -Filter '*.WebView2' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force

    $outputDir = Join-Path (Get-Location) 'build\windows\release'
    $stageDir = Join-Path $outputDir "kira-tablet-v$versionFull-windows-x64"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    Copy-Item (Join-Path $releaseDir '*') $stageDir -Recurse -Force

    $zipPath = Join-Path $outputDir "kira-tablet-v$versionFull-windows-x64-portable.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Portable ZIP: $zipPath" -ForegroundColor Green

    $iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if (-not $iscc) {
        foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
            'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
            'C:\Program Files\Inno Setup 6\ISCC.exe'
        )) {
            if (Test-Path $candidate) {
                $iscc = Get-Item $candidate
                break
            }
        }
    }

    $setupPath = $null
    if ($iscc) {
        $issPath = Join-Path $outputDir 'kira-tablet-installer.iss'
        $iconPath = (Resolve-Path 'windows\runner\resources\app_icon.ico').Path
        $licensePath = (Resolve-Path 'LICENSE').Path
        $notesPath = (Resolve-Path 'RELEASE_NOTES_v0.1.0.md').Path
        $iss = @"
#define MyAppName "Kira Tablet"
#define MyAppVersion "$versionFull"
#define MyAppPublisher "Kira Tablet contributors"
#define MyAppExeName "$exeName"

[Setup]
AppId={{6E2978AA-9B7E-4CBA-B32F-512091CF70FE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Kira Tablet
DefaultGroupName=Kira Tablet
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=$outputDir
OutputBaseFilename=kira-tablet-v$versionFull-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=$iconPath
LicenseFile=$licensePath
InfoBeforeFile=$notesPath

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked
[Files]
Source: "$stageDir\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kira Tablet"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Kira Tablet"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,Kira Tablet}"; Flags: nowait postinstall skipifsilent
"@
        Set-Content -Path $issPath -Value $iss -Encoding UTF8
        & $iscc.FullName $issPath
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup failed: $LASTEXITCODE"
        }
        $setupPath = Join-Path $outputDir "kira-tablet-v$versionFull-windows-x64-setup.exe"
        Write-Host "Installer: $setupPath" -ForegroundColor Green
    } else {
        Write-Host 'Inno Setup not installed; installer skipped.' -ForegroundColor DarkYellow
    }

    $artifacts = @($zipPath)
    if ($setupPath -and (Test-Path $setupPath)) { $artifacts += $setupPath }
    $hashFile = Join-Path $outputDir 'SHA256SUMS.txt'
    $hashLines = foreach ($artifact in $artifacts) {
        $hash = (Get-FileHash $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path $artifact -Leaf)"
    }
    Set-Content -Path $hashFile -Value $hashLines -Encoding UTF8

    Write-Host "Release artifacts:" -ForegroundColor Green
    $artifacts + $hashFile | ForEach-Object { Write-Host "  $_" }
}
catch {
    Write-Host "Release build failed: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
