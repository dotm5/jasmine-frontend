param(
    [string]$JavaHome,
    [string]$RustToolchain,
    [string]$PythonExecutable
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
Initialize-WorkspaceTemporaryPaths $root
$file = Join-Path $root '.toolchains\toolchain-paths.json'
$previous = if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file -Raw | ConvertFrom-Json } else { $null }
if (-not $JavaHome -and $previous) { $JavaHome = $previous.javaHome }
if (-not $RustToolchain -and $previous) { $RustToolchain = $previous.rustToolchain }
if (-not $PythonExecutable -and $previous) { $PythonExecutable = $previous.pythonExecutable }
if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
if (-not $RustToolchain) {
    $RustToolchain = & rustc.exe --print sysroot
    if ($LASTEXITCODE -ne 0) { throw 'Select an already-installed Rust toolchain with -RustToolchain.' }
}
if (-not $PythonExecutable) { $PythonExecutable = (Get-Command python.exe -ErrorAction Stop).Source }
foreach ($path in @((Join-Path $JavaHome 'bin\java.exe'), (Join-Path $JavaHome 'bin\javac.exe'),
                    (Join-Path $JavaHome 'bin\jlink.exe'), (Join-Path $JavaHome 'bin\jmod.exe'),
                    (Join-Path $JavaHome 'bin\jar.exe'), (Join-Path $JavaHome 'jmods\java.base.jmod'),
                    (Join-Path $RustToolchain 'bin\rustc.exe'), (Join-Path $RustToolchain 'bin\cargo.exe'), $PythonExecutable)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Existing tool not found: $path" }
}
$javaVersion = (& (Join-Path $JavaHome 'bin\java.exe') -version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch 'version "(17|21)\.') { throw 'Select an existing JDK 17/21 with -JavaHome; no JDK is installed by this script.' }
$jlinkVersion = (& (Join-Path $JavaHome 'bin\jlink.exe') --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $jlinkVersion -notmatch '^(17|21)\.') { throw 'The selected JDK must include a working jlink, not only IDE runtime java/javac.' }
$rustVersion = (& (Join-Path $RustToolchain 'bin\rustc.exe') --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $rustVersion -notmatch '^rustc 1\.97\.1 ') { throw 'Select the existing Rust 1.97.1 toolchain used by this checkout.' }
$targetLib = Join-Path $RustToolchain 'lib\rustlib\aarch64-linux-android\lib'
if (-not (Test-Path -LiteralPath $targetLib -PathType Container)) { throw 'Selected existing toolchain lacks the Android target; select the already-prepared toolchain, do not reinstall Rust.' }
$pythonVersion = (& $PythonExecutable --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $pythonVersion -notmatch '^Python (\d+)\.(\d+)\.') { throw 'Python version inspection failed.' }
if ([int]$Matches[1] -lt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -lt 11)) { throw 'The existing Python must be 3.11 or newer.' }
$cargoSource = if ($previous) { $previous.seedSources.cargoHome } elseif ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
$pubSource = if ($previous) { $previous.seedSources.pubCache } elseif ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
$config = [ordered]@{
    schema = 1; strategy = 'reuse existing executables; no tool installation or global settings changes'
    javaHome = [IO.Path]::GetFullPath($JavaHome)
    rustToolchain = [IO.Path]::GetFullPath($RustToolchain)
    pythonExecutable = [IO.Path]::GetFullPath($PythonExecutable)
    flutterSdk = Join-Path $root '.toolchains\flutter'
    androidSdk = Join-Path $root '.toolchains\android-sdk'
    androidCommandTools = '15859902'; ndkVersion = '26.3.11579264'; buildTools = '35.0.0'
    versions = [ordered]@{ java = $javaVersion; rust = $rustVersion; python = $pythonVersion }
    seedSources = [ordered]@{ cargoHome = $cargoSource; pubCache = $pubSource }
}
$json = $config | ConvertTo-Json -Depth 6
if (-not (Test-Path -LiteralPath $file) -or (Get-Content -LiteralPath $file -Raw).Trim() -ne $json.Trim()) {
    $json | Set-Content -LiteralPath $file -Encoding utf8
}
Write-Host "Existing tools bound: $file"
Write-Host $rustVersion
Write-Host $pythonVersion
