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
  # Local QA always uses a debug APK. Production OTA release signing is isolated
  # in the dedicated POTV OTA workflow and must never be emulated here.
  foreach ($required in @(
    'android\app\src\main\AndroidManifest.xml',
    'android\app\src\main\kotlin\com\potv\potv\MainActivity.kt',
    'android\app\src\main\res\xml\potv_update_paths.xml'
  )) {
    if (-not (Test-Path (Join-Path $projectRoot $required))) {
      throw ('Committed Android file missing: ' + $required)
    }
  }
  Invoke-Flutter -Arguments @('build', 'apk', '--debug')
  $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
  if (-not (Test-Path $apk)) { throw 'APK build returned success but no app-debug.apk was found.' }
  Write-Output ('POTV_QA_APK=' + $apk)
  Write-Output ('POTV_QA_APK_SHA256=' + (Get-FileHash $apk -Algorithm SHA256).Hash)
}

Write-Output 'POTV_LOCAL_QA=PASS'
