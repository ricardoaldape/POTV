param(
  [switch]$BuildApk,
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Execute on the user's Windows HP or in the POTV self-hosted Actions runner.
# Never calls GitHub-hosted compute, uploads secrets or touches other projects.
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutter = 'C:\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) {
  $found = Get-Command flutter -ErrorAction SilentlyContinue
  if ($null -eq $found) { throw 'Flutter SDK is not available on this Windows PC.' }
  $flutter = $found.Source
}

Set-Location $projectRoot
[Environment]::SetEnvironmentVariable('ProgramFiles(x86)', 'C:\Program Files (x86)', 'Process')
Write-Output ('POTV_QA_ROOT=' + $projectRoot)
Write-Output ('POTV_QA_BRANCH=' + (git branch --show-current))
Write-Output 'POTV_QA_MODE=LOCAL_SELF_HOSTED_NO_GITHUB_RUNNER_CREDITS'

function Invoke-Flutter {
  param([string[]]$Arguments)
  Write-Output ('PHASE=flutter ' + ($Arguments -join ' '))
  & $flutter @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw ('Flutter failed (exit ' + $LASTEXITCODE + '): ' + ($Arguments -join ' '))
  }
}

Invoke-Flutter -Arguments @('pub', 'get')
Invoke-Flutter -Arguments @('analyze', '--no-fatal-infos', '--no-fatal-warnings')
if (-not $SkipTests) {
  Invoke-Flutter -Arguments @('test', '--concurrency=1', '--reporter', 'expanded')
}

if ($BuildApk) {
  # POTV does not store signing secrets inside this script. A locally built APK
  # is for QA only, not an official OTA release signed for end users.
  Invoke-Flutter -Arguments @('create', '--platforms=android', '--org', 'com.potv', '--project-name', 'potv', '.')
  $manifest = Join-Path $projectRoot 'tool\AndroidManifest.xml'
  if (Test-Path $manifest) {
    Copy-Item $manifest (Join-Path $projectRoot 'android\app\src\main\AndroidManifest.xml') -Force
  }
  foreach ($density in @('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')) {
    $from = Join-Path $projectRoot ('tool\icons\mipmap-' + $density + '\ic_launcher.png')
    $to = Join-Path $projectRoot ('android\app\src\main\res\mipmap-' + $density + '\ic_launcher.png')
    if (Test-Path $from) { Copy-Item $from $to -Force }
  }
  $banner = Join-Path $projectRoot 'tool\tv_banner.png'
  if (Test-Path $banner) {
    Copy-Item $banner (Join-Path $projectRoot 'android\app\src\main\res\drawable\tv_banner.png') -Force
  }
  Invoke-Flutter -Arguments @('build', 'apk', '--release')
  $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
  if (-not (Test-Path $apk)) { throw 'APK build returned success but no app-release.apk was found.' }
  Write-Output ('POTV_QA_APK=' + $apk)
  Write-Output ('POTV_QA_APK_SHA256=' + (Get-FileHash $apk -Algorithm SHA256).Hash)
}

Write-Output 'POTV_LOCAL_QA=PASS'
