param(
    [switch]$SkipTests,
    [string]$BackendBundle
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
Initialize-WorkspaceTemporaryPaths $root
. (Join-Path $PSScriptRoot 'local-env.ps1')
$builtBackend = [string]::IsNullOrWhiteSpace($BackendBundle)
if ($builtBackend) {
    $BackendBundle = Join-Path $root ('dist\jmbackend-android-arm64-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    & (Join-Path $PSScriptRoot 'build-backend.ps1') -OutputDirectory $BackendBundle -SkipTests:$SkipTests
}
$BackendBundle = [IO.Path]::GetFullPath($BackendBundle, $root)
# Prebuilt mode never enters the Rust toolchain or reads native source/locks.
Enter-LocalToolEnvironment $root -WithoutRust
$environmentFile = Join-Path $root '.toolchains\android-env.json'
if (-not (Test-Path -LiteralPath $environmentFile)) {
    throw 'Run scripts/bootstrap-android.ps1 -InstallSdkPackages -AcceptAndroidLicenses first.'
}
$config = Get-Content -LiteralPath $environmentFile -Raw | ConvertFrom-Json

# Flutter writes UTF-8 local.properties, while some Java readers use ISO-8859-1.
# A short path or temporary DOS drive gives an ASCII view of these same files.
# No external directory/junction is created, even if dependency checks fail.
$buildView = $null
$flutterConfigurationWritten = $false
$buildCompleted = $false
$previousGradleOpts = $env:GRADLE_OPTS
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
$previousPath = $env:PATH
$mappedEnvironment = @{}
foreach ($name in @('CARGO_HOME','RUSTUP_HOME','PUB_CACHE','GRADLE_USER_HOME','PIP_CACHE_DIR','HOME','USERPROFILE','APPDATA','LOCALAPPDATA',
                    'TEMP','TMP','JAVA_HOME','ANDROID_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_NDK_HOME','ANDROID_NDK_ROOT','CARGO_TARGET_DIR')) {
    $mappedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
$buildView = New-WorkspaceBuildView $root
$buildRoot = $buildView.Path
$env:TEMP = Join-Path $buildRoot '.tmp\runtime'
$env:TMP = $env:TEMP
$env:ANDROID_USER_HOME = Join-Path $buildRoot '.toolchains\android-user'
# Do not leave a Gradle daemon using a drive mapping after this script ends.
$env:GRADLE_OPTS = ($previousGradleOpts + ' -Dorg.gradle.daemon=false').Trim()
function In-BuildView([string]$Path) {
    $path = [IO.Path]::GetFullPath($Path)
    if ($path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $buildRoot $path.Substring($root.Length).TrimStart('\')
    }
    return $path
}
function Check-Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}
foreach ($name in $mappedEnvironment.Keys) {
    if ($mappedEnvironment[$name]) {
        [Environment]::SetEnvironmentVariable($name, (In-BuildView $mappedEnvironment[$name]), 'Process')
    }
}
$env:JAVA_TOOL_OPTIONS = '-Duser.home="' + $env:HOME + '"'

$sdk = In-BuildView $config.androidSdk
$jdk = In-BuildView $config.javaHome
$flutterRoot = Join-Path $buildRoot '.toolchains\flutter'
$flutter = Join-Path $flutterRoot 'bin\flutter.bat'
$ndk = Join-Path $sdk ('ndk\' + $config.ndkVersion)
$llvm = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$clang = Join-Path $llvm 'clang.exe'
foreach ($path in @($flutter, $clang, (Join-Path $jdk 'bin\java.exe'), (Join-Path $jdk 'bin\jlink.exe'),
                    (Join-Path $jdk 'bin\jmod.exe'), (Join-Path $jdk 'bin\jar.exe'), (Join-Path $sdk 'platforms\android-35\android.jar'))) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing build dependency: $path" }
}
$env:JAVA_HOME = $jdk
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_NDK_HOME = $ndk
$env:ANDROID_NDK_ROOT = $ndk
$env:GRADLE_USER_HOME = Join-Path $buildRoot '.toolchains\gradle-cache'
$env:PATH = "$jdk\bin;$llvm;$(Join-Path $sdk 'platform-tools');$env:PATH"

Push-Location -LiteralPath $buildRoot
try {
    New-Item -ItemType Directory -Path '.tmp', 'dist' -Force | Out-Null
    $flutterInfo = & $flutter --version --machine | ConvertFrom-Json
    Check-Exit 'Flutter version inspection'
    if ($flutterInfo.frameworkVersion -ne '3.29.3') { throw 'This build is pinned to Flutter 3.29.3.' }
    $bundle = In-BuildView $BackendBundle
    & python.exe 'scripts\check_backend_contract.py' --bundle $bundle
    Check-Exit 'Frontend/backend bundle compatibility'
    $backendManifestFile = Join-Path $bundle 'backend-manifest.json'
    $backendManifest = Get-Content -LiteralPath $backendManifestFile -Raw | ConvertFrom-Json
    $library = Join-Path $bundle $backendManifest.library
    # Use the same checksum-pinned, resumable downloader for the wrapper archive.
    # The cache key is Gradle's URL hash for this exact distribution URL.
    $wrapperProperties = Get-Content -LiteralPath 'android\gradle\wrapper\gradle-wrapper.properties' -Raw
    $gradleSha256 = '31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26'
    if (-not $wrapperProperties.Contains('distributionUrl=https\://services.gradle.org/distributions/gradle-8.10.2-bin.zip') -or
        -not $wrapperProperties.Contains("distributionSha256Sum=$gradleSha256")) {
        throw 'Update the verified Gradle download and wrapper cache key together with the wrapper version.'
    }
    $gradleZip = Join-Path $buildRoot '.toolchains\downloads\gradle-8.10.2-bin.zip'
    & python.exe 'scripts\download_verified.py' `
        'https://services.gradle.org/distributions/gradle-8.10.2-bin.zip' $gradleZip `
        --size 136715430 --sha256 $gradleSha256
    Check-Exit 'Verified Gradle distribution'
    $wrapperCache = Join-Path $env:GRADLE_USER_HOME 'wrapper\dists\gradle-8.10.2-bin\a04bxjujx95o3nb99gddekhwo'
    New-Item -ItemType Directory -Path $wrapperCache -Force | Out-Null
    $cachedZip = Join-Path $wrapperCache 'gradle-8.10.2-bin.zip'
    if (-not (Test-Path -LiteralPath $cachedZip) -or
        (Get-FileHash -LiteralPath $cachedZip -Algorithm SHA256).Hash -ne $gradleSha256) {
        Copy-Item -LiteralPath $gradleZip -Destination $cachedZip
    }
    # Local configuration and generated version asset are deliberately ignored.
    @("sdk.dir=$($sdk.Replace('\', '/'))", "flutter.sdk=$($flutterRoot.Replace('\', '/'))") |
        Set-Content -LiteralPath 'android\local.properties' -Encoding utf8NoBOM
    '1.7.21-local' | Set-Content -LiteralPath 'lib\assets\version.txt' -Encoding utf8NoBOM
    & $flutter pub get --enforce-lockfile
    Check-Exit 'Locked Flutter dependencies'
    $flutterConfigurationWritten = $true
    if (-not $SkipTests) {
        & python.exe -m unittest discover -s 'scripts\tests' -v
        Check-Exit 'Build artifact helper tests'
        & $flutter test --no-pub --reporter expanded
        Check-Exit 'Flutter tests'
        if ($builtBackend) {
            $env:JASMINE_TEST_BRIDGE_BINARY = Join-Path $buildRoot 'native\target\debug\examples\bridge_stdio_fixture.exe'
            & $flutter test 'tool_tests\native_startup_test.dart' --no-pub --reporter expanded
            Check-Exit 'Full Flutter startup with source-built native backend'
        }
        # Legacy warnings are retained; analyzer errors still fail the build.
        & $flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
        Check-Exit 'Flutter analyzer'
    }
    $jniDir = 'android\app\src\main\jniLibs\arm64-v8a'
    New-Item -ItemType Directory -Path $jniDir -Force | Out-Null
    Copy-Item -LiteralPath $library -Destination (Join-Path $jniDir 'librust.so')
    & $flutter build apk --release --no-pub --no-android-gradle-daemon --target-platform android-arm64
    Check-Exit 'Flutter APK'
    $apk = 'build\app\outputs\flutter-apk\app-release.apk'
    & python.exe 'scripts\verify_local_apk.py' $apk --library $library --out '.tmp\apk-verification.json'
    Check-Exit 'APK/native binary verification'
    $buildTools = Join-Path $sdk ('build-tools\' + $config.buildTools)
    & (Join-Path $buildTools 'apksigner.bat') verify --verbose $apk
    Check-Exit 'APK signature verification'
    & (Join-Path $buildTools 'zipalign.exe') -c -P 16 4 $apk
    Check-Exit 'APK 16-KiB ZIP alignment'
    $badging = & (Join-Path $buildTools 'aapt.exe') dump badging $apk
    Check-Exit 'APK manifest inspection'
    if (-not ($badging | Select-String -SimpleMatch "name='opensource.jasmine.local'")) { throw 'APK application ID is not the local build ID' }
    $badging | Set-Content -LiteralPath '.tmp\apk-badging.txt' -Encoding utf8
    $artifact = 'dist\jasmine-local-1.7.21-arm64.apk'
    Copy-Item -LiteralPath $apk -Destination $artifact
    $commit = & git rev-parse HEAD
    Check-Exit 'Source revision'
    $dirty = @(& git status --porcelain).Count -gt 0
    Check-Exit 'Source status'
    [ordered]@{
        artifact = [IO.Path]::GetFullPath((Join-Path $root $artifact))
        sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        size = (Get-Item -LiteralPath $artifact).Length
        sourceRevision = $commit; dirtyWorkspace = $dirty
        backend = [ordered]@{
            mode = $(if ($builtBackend) { 'source-build' } else { 'prebuilt-bundle' })
            bundle = $BackendBundle
            manifestSha256 = (Get-FileHash -LiteralPath $backendManifestFile -Algorithm SHA256).Hash.ToLowerInvariant()
            name = $backendManifest.backend.name; version = $backendManifest.backend.version
            protocol = $backendManifest.contract.protocol; protocolVersion = $backendManifest.contract.version
            librarySha256 = $backendManifest.library_sha256
            testsRunByProducer = $backendManifest.build.offline_tests_run
        }
        sourceLockSha256 = $backendManifest.build.source_lock_sha256
        cargoLockSha256 = $backendManifest.build.cargo_lock_sha256
        pubLockSha256 = (Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash.ToLowerInvariant()
        packageId = 'opensource.jasmine.local'; abi = 'arm64-v8a'
        signing = 'local Android debug key; not the upstream release key'
        flutter = $flutterInfo.frameworkVersion; flutterRevision = $flutterInfo.frameworkRevision
        dart = $flutterInfo.dartSdkVersion; rust = $backendManifest.build.rust; ndk = $config.ndkVersion
        javaHome = $config.javaHome
        java = (& (Join-Path $jdk 'bin\java.exe') -version 2>&1 | Out-String).Trim()
        offlineTestsRun = -not $SkipTests
        nativeStartupTestRun = $builtBackend -and -not $SkipTests
        deviceValidation = 'pending'; liveApiValidation = 'pending'
        binaryVerification = Get-Content -LiteralPath '.tmp\apk-verification.json' -Raw | ConvertFrom-Json
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath 'dist\build-manifest.json' -Encoding utf8
    "$((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($artifact))" |
        Set-Content -LiteralPath 'dist\SHA256SUMS.txt' -Encoding utf8NoBOM
    Write-Host "Built and verified: $(Join-Path $root $artifact)"
    $buildCompleted = $true
} finally {
    Pop-Location
}
} finally {
    foreach ($name in $mappedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $mappedEnvironment[$name], 'Process') }
    $env:GRADLE_OPTS = $previousGradleOpts
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
    $env:PATH = $previousPath
    Remove-WorkspaceBuildView $buildView
    if ($flutterConfigurationWritten) {
        try { & (Join-Path $PSScriptRoot 'restore-local-config.ps1') }
        catch {
            if ($buildCompleted) { throw }
            Write-Warning "Preserving the original build error; generated-path restoration also failed: $_"
        }
    }
}
