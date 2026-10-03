param(
    [string]$SdkPath = $env:ANDROID_HOME,
    [string]$GradlePath,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE" }
}

if (-not $SdkPath) { $SdkPath = $env:ANDROID_SDK_ROOT }
if (-not $SdkPath -or -not (Test-Path -LiteralPath $SdkPath)) {
    throw 'Set ANDROID_HOME or pass -SdkPath for your Android SDK.'
}
$SdkPath = (Resolve-Path -LiteralPath $SdkPath).Path
$env:ANDROID_HOME = $SdkPath
$env:ANDROID_SDK_ROOT = $SdkPath
$env:JAVA_HOME = Split-Path (Split-Path (Get-Command java).Source -Parent) -Parent
foreach ($component in @('platforms/android-35', 'build-tools/35.0.0', 'ndk/27.2.12479018', 'cmake/3.22.1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SdkPath $component))) {
        throw "Install the pinned SDK component before building: $component"
    }
}

Invoke-Checked $Python @('scripts/bootstrap.py', '--whisper-only')
if (-not $GradlePath) {
    $GradlePath = Join-Path $projectRoot '.tooling/gradle-8.11.1/bin/gradle.bat'
    if (-not (Test-Path -LiteralPath $GradlePath)) {
        Invoke-Checked $Python @('scripts/bootstrap.py', '--gradle-only')
    }
}
$GradlePath = (Resolve-Path -LiteralPath $GradlePath).Path

$checkDirectory = Join-Path $projectRoot '.tooling/core-check'
New-Item -ItemType Directory -Path $checkDirectory -Force | Out-Null
$sources = @(Get-ChildItem 'app/src/main/java/org/tabletalk/core/*.java' | ForEach-Object FullName)
$sources += 'app/src/main/java/org/tabletalk/inference/WhisperEngine.java', 'tests/CoreTests.java'
Invoke-Checked 'java' (@('com.sun.tools.javac.Main', '-source', '17', '-target', '17', '-encoding', 'UTF-8', '-d', $checkDirectory) + $sources)
Invoke-Checked 'java' @('-cp', $checkDirectory, 'CoreTests')

$signingDirectory = Join-Path $projectRoot '.tooling/android-user'
New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
$env:TABLETALK_DEBUG_KEYSTORE = Join-Path $signingDirectory 'debug.keystore'
if (-not (Test-Path -LiteralPath $env:TABLETALK_DEBUG_KEYSTORE)) {
    Invoke-Checked 'keytool' @('-genkeypair', '-noprompt', '-keystore', $env:TABLETALK_DEBUG_KEYSTORE,
        '-storepass', 'android', '-keypass', 'android', '-alias', 'androiddebugkey',
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=TableTalk Development,O=TableTalk,C=US')
}
Invoke-Checked $GradlePath @('--no-daemon', '--console=plain', '--max-workers=2', '-p', $projectRoot,
    ':app:assembleSetupDebug', ':app:assembleOfflineDebug', ':app:assemblePocoRelease',
    ':app:lintSetupDebug', ':app:lintOfflineDebug', ':app:lintPocoRelease')

$outputDirectory = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$aapt = Join-Path $SdkPath 'build-tools/35.0.0/aapt.exe'
$apksigner = Join-Path $SdkPath 'build-tools/35.0.0/apksigner.bat'
$zipalign = Join-Path $SdkPath 'build-tools/35.0.0/zipalign.exe'
$summary = [ordered]@{}
foreach ($flavor in @('setup', 'offline', 'poco')) {
    $buildType = if ($flavor -eq 'poco') { 'release' } else { 'debug' }
    $apk = Join-Path $projectRoot "app/build/outputs/apk/$flavor/$buildType/app-$flavor-$buildType.apk"
    $signature = & $apksigner verify --verbose --print-certs $apk
    if ($LASTEXITCODE -ne 0) { throw "Invalid APK signature: $flavor" }
    $certificate = ($signature | Select-String 'certificate SHA-256 digest:').Line.Split(':', 2)[1].Trim()
    Invoke-Checked $zipalign @('-c', '-P', '16', '4', $apk)
    if ($flavor -eq 'offline') {
        Invoke-Checked $Python @('scripts/check_apk_permissions.py', '--aapt', $aapt, $apk)
    }
    $name = "tabletalk-$flavor.apk"
    $destination = Join-Path $outputDirectory $name
    Copy-Item -LiteralPath $apk -Destination $destination
    $summary[$name] = [ordered]@{
        bytes = (Get-Item -LiteralPath $destination).Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
        signing_certificate_sha256 = $certificate
    }
}
if (@($summary.Values.signing_certificate_sha256 | Select-Object -Unique).Count -ne 1) {
    throw 'The APK signing certificates differ.'
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDirectory 'build-info.json') -Encoding UTF8
$summary.GetEnumerator() | ForEach-Object { "$($_.Value.sha256)  $($_.Key)" } |
    Set-Content -LiteralPath (Join-Path $outputDirectory 'SHA256SUMS.txt') -Encoding ASCII
Write-Output "Verified APKs are ready in $outputDirectory"
