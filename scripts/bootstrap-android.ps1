param(
    [switch]$InstallSdkPackages,
    [switch]$AcceptAndroidLicenses,
    [string]$JavaHome
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
Initialize-WorkspaceTemporaryPaths $root
$boundTools = Join-Path $root '.toolchains\toolchain-paths.json'
if (Test-Path -LiteralPath $boundTools) {
    . (Join-Path $PSScriptRoot 'local-env.ps1')
    Enter-LocalToolEnvironment $root
    if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
}
$toolsRoot = Join-Path $root '.toolchains'
$downloads = Join-Path $toolsRoot 'downloads'
$sdk = Join-Path $toolsRoot 'android-sdk'
$curl = if (Test-Path -LiteralPath 'C:\Program Files\Git\mingw64\bin\curl.exe') {
    'C:\Program Files\Git\mingw64\bin\curl.exe'
} else { (Get-Command curl.exe).Source }
New-Item -ItemType Directory -Path $downloads -Force | Out-Null

function Get-VerifiedArchive([string]$Url, [string]$Name, [string]$Sha256, [long]$Size) {
    $destination = Join-Path $downloads $Name
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python -and $Size -gt 0 -and -not (Test-Path -LiteralPath $destination)) {
        & $python.Source (Join-Path $PSScriptRoot 'download_verified.py') $Url $destination --size $Size --sha256 $Sha256 --resume-from "$destination.part" | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "Parallel download failed; verified chunks preserved: $Name" }
    }
    if (-not (Test-Path -LiteralPath $destination)) {
        $partial = "$destination.part"
        $verified = $false
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            if ((Test-Path -LiteralPath $partial) -and
                (Get-FileHash -Algorithm SHA256 -LiteralPath $partial).Hash -eq $Sha256) {
                $verified = $true
                break
            }
            # Each new attempt resumes the same file; curl's internal retries may
            # otherwise truncate useful partial downloads after TLS interruptions.
            Write-Host "Downloading $Name (resumable attempt $attempt/6)"
            & $curl --fail --location --continue-at - --retry 0 --connect-timeout 25 --max-time 240 --silent --show-error --output $partial $Url
            if ((Test-Path -LiteralPath $partial) -and
                (Get-FileHash -Algorithm SHA256 -LiteralPath $partial).Hash -eq $Sha256) {
                $verified = $true
                break
            }
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 3
        }
        if (-not $verified) {
            throw "Checksum mismatch: $Name (partial file preserved)"
        }
        # Both paths are files directly under the verified project toolchain root.
        Move-Item -LiteralPath "$destination.part" -Destination $destination
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne $Sha256) {
        throw "Existing archive has an unexpected checksum: $destination"
    }
    return $destination
}

# Reuse an existing JDK; this script never installs another Java distribution.
if (-not $JavaHome) { throw 'Bind an existing JDK with configure-local-env.ps1, or pass -JavaHome.' }
$jdk = [IO.Path]::GetFullPath($JavaHome)
foreach ($executable in @('java.exe', 'javac.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $jdk "bin\$executable"))) {
        throw "JDK executable missing: $jdk\bin\$executable"
    }
}
$javaVersion = (& (Join-Path $jdk 'bin\java.exe') -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch 'version "(17|21)\.') {
    throw 'This pinned Android build uses JDK 17 or 21; select one with -JavaHome.'
}

$commandTools = Join-Path $sdk 'cmdline-tools\15859902'
if (-not (Test-Path -LiteralPath (Join-Path $commandTools 'bin\sdkmanager.bat'))) {
    $zip = Get-VerifiedArchive `
        'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' `
        'commandlinetools-win-15859902_latest.zip' `
        '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a' 155655386
    $stage = Join-Path $toolsRoot 'command-tools-extraction'
    Expand-Archive -LiteralPath $zip -DestinationPath $stage
    $source = [IO.Path]::GetFullPath((Join-Path $stage 'cmdline-tools'))
    $target = [IO.Path]::GetFullPath($commandTools)
    foreach ($path in @($source, $target)) {
        if (-not $path.StartsWith($toolsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected toolchain move path: $path"
        }
    }
    if (Test-Path -LiteralPath $target) { throw "Target already exists: $target" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $target
}

$env:JAVA_HOME = $jdk
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "$jdk\bin;$env:PATH"
$manager = Join-Path $commandTools 'bin\sdkmanager.bat'
if ($InstallSdkPackages) {
    $components = @(
        @{ name = 'platform-tools'; sentinel = 'platform-tools\adb.exe' },
        @{ name = 'platforms;android-35'; sentinel = 'platforms\android-35\android.jar' },
        @{ name = 'build-tools;35.0.0'; sentinel = 'build-tools\35.0.0\aapt.exe' },
        @{ name = 'ndk;26.3.11579264'; sentinel = 'ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe' }
    )
    $missing = @($components | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sdk $_.sentinel)) })
    if ($missing.Count) {
        if (-not $AcceptAndroidLicenses) { throw 'Pass -AcceptAndroidLicenses to prepare missing SDK packages after reviewing the Android SDK license.' }
        1..20 | ForEach-Object { 'y' } | & $manager "--sdk_root=$sdk" --licenses
        if ($LASTEXITCODE -ne 0) { throw 'Android SDK license setup failed' }
        $packageArgs = @()
        foreach ($component in $missing) { $packageArgs += @('--package', $component.name) }
        & python.exe (Join-Path $PSScriptRoot 'install_android_sdk.py') --sdk $sdk --downloads $downloads @packageArgs
        if ($LASTEXITCODE -ne 0) { throw 'Android SDK package preparation failed' }
    } else { Write-Host 'Reusing all four installed SDK components; no installation or license setup repeated.' }
    $installed = & $manager "--sdk_root=$sdk" --list_installed
    if ($LASTEXITCODE -ne 0) { throw 'SDK Manager did not recognize the local packages' }
    $installed | ForEach-Object { Write-Host $_ }
    foreach ($package in @('platform-tools', 'platforms;android-35', 'build-tools;35.0.0', 'ndk;26.3.11579264')) {
        if (-not ($installed | Select-String -SimpleMatch $package)) { throw "SDK Manager did not list installed package: $package" }
    }
}

[ordered]@{
    javaHome = $jdk; androidSdk = $sdk; commandTools = $commandTools
    ndkVersion = '26.3.11579264'; compileSdk = 35; buildTools = '35.0.0'
    scope = 'workspace only; no global environment changes'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $toolsRoot 'android-env.json') -Encoding utf8
Write-Output "Toolchain ready: $toolsRoot"
