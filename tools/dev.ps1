param(
    [ValidateSet('run', 'test', 'analyze', 'apk', 'release', 'doctor')]
    [string]$Command = 'run'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = $projectRoot

# Flutter's shader compiler and Gradle's Kotlin compiler require ASCII tool paths
# on this Windows setup. The junction keeps the source in its original folder.
if ($projectRoot -match '[^\x00-\x7F]') {
    $buildRoot = Join-Path $env:USERPROFILE 'wangwang-wallet-work'
    if (Test-Path -LiteralPath $buildRoot) {
        $existingAlias = Get-Item -LiteralPath $buildRoot
        if ($existingAlias.LinkType -ne 'Junction' -or
            [string]$existingAlias.Target -ne $projectRoot) {
            throw 'The build alias already points to another folder.'
        }
    } else {
        New-Item -ItemType Junction -Path $buildRoot -Target $projectRoot | Out-Null
    }
}

$flutter = Join-Path $buildRoot '.tooling\flutter\bin\flutter.bat'
$javaRoot = Join-Path $buildRoot '.tooling\java'
$jdk = Get-ChildItem -LiteralPath $javaRoot -Directory | Select-Object -First 1
if (-not (Test-Path -LiteralPath $flutter) -or $null -eq $jdk) {
    throw 'Flutter and JDK must be installed in .tooling before running this script.'
}
$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = Join-Path $buildRoot '.tooling\android-sdk'
$env:JAVA_TOOL_OPTIONS = '-Dfile.encoding=UTF-8'
$env:GRADLE_USER_HOME = Join-Path $env:USERPROFILE '.codex\toolchains\wangwang-gradle'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'

Push-Location -LiteralPath $buildRoot
try {
    if ($Command -eq 'apk') {
        & $flutter build apk --debug
    } elseif ($Command -eq 'release') {
        & $flutter build apk --release
    } else {
        & $flutter $Command
    }
    if ($LASTEXITCODE -ne 0) { throw "Flutter command failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
