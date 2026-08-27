# Dot-source for helpers; call Enter-LocalToolEnvironment from a fresh process.
function Enter-LocalToolEnvironment([string]$WorkspaceRoot, [switch]$WithoutRust) {
    $root = [IO.Path]::GetFullPath($WorkspaceRoot)
    . (Join-Path $root 'scripts\workspace-paths.ps1')
    Initialize-WorkspaceTemporaryPaths $root
    $file = Join-Path $root '.toolchains\toolchain-paths.json'
    if (-not (Test-Path -LiteralPath $file)) { throw 'Run scripts/configure-local-env.ps1 to bind existing tools first.' }
    $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $paths = [ordered]@{
        CARGO_HOME = '.toolchains\cargo-home'
        RUSTUP_HOME = '.toolchains\rustup-state'
        PUB_CACHE = '.toolchains\pub-cache'
        GRADLE_USER_HOME = '.toolchains\gradle-cache'
        PIP_CACHE_DIR = '.toolchains\pip-cache'
        HOME = '.toolchains\user-home'
        USERPROFILE = '.toolchains\user-home'
        APPDATA = '.toolchains\user-home\AppData\Roaming'
        LOCALAPPDATA = '.toolchains\user-home\AppData\Local'
    }
    if ($WithoutRust) {
        $paths.Remove('CARGO_HOME')
        $paths.Remove('RUSTUP_HOME')
    }
    foreach ($entry in $paths.GetEnumerator()) {
        $path = Join-Path $root $entry.Value
        # Inspect every existing ancestor rather than following a cache junction.
        $cursor = $root
        foreach ($part in $entry.Value.Split('\')) {
            $cursor = Join-Path $cursor $part
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Cache path is not a plain directory: $cursor" }
            } else { New-Item -ItemType Directory -Path $cursor | Out-Null }
        }
        [Environment]::SetEnvironmentVariable($entry.Key, $path, 'Process')
    }
    $env:JAVA_HOME = $config.javaHome
    $env:ANDROID_HOME = $config.androidSdk
    $env:ANDROID_SDK_ROOT = $config.androidSdk
    $env:ANDROID_NDK_HOME = Join-Path $config.androidSdk ('ndk\' + $config.ndkVersion)
    $env:ANDROID_NDK_ROOT = $env:ANDROID_NDK_HOME
    if (-not $WithoutRust) {
        $env:RUSTC = Join-Path $config.rustToolchain 'bin\rustc.exe'
        $env:RUSTDOC = Join-Path $config.rustToolchain 'bin\rustdoc.exe'
        $env:CARGO_TARGET_DIR = Join-Path $root 'native\target'
    }
    $env:JASMINE_PYTHON = $config.pythonExecutable
    $env:PYTHONNOUSERSITE = '1'
    $env:PYTHONDONTWRITEBYTECODE = '1'
    $env:PYTHONUTF8 = '1'
    $env:PIP_REQUIRE_VIRTUALENV = 'true'
    $env:CI = 'true'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    $env:DART_SUPPRESS_ANALYTICS = 'true'
    # Scope JVM preferences/debug keystore defaults to the project profile too.
    $env:JAVA_TOOL_OPTIONS = '-Duser.home="' + $env:HOME + '"'
    $prefix = @((Join-Path $config.javaHome 'bin'),
                (Split-Path -Parent $config.pythonExecutable), (Join-Path $config.flutterSdk 'bin'),
                (Join-Path $config.androidSdk 'platform-tools'),
                (Join-Path $config.androidSdk ('cmdline-tools\' + $config.androidCommandTools + '\bin')))
    if (-not $WithoutRust) { $prefix = @((Join-Path $config.rustToolchain 'bin')) + $prefix }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = @($prefix + @($env:PATH.Split(';')) | Where-Object { $_ -and $seen.Add($_) })
    $env:PATH = $entries -join ';'
    $requiredTools = @($env:JASMINE_PYTHON,
                        (Join-Path $env:JAVA_HOME 'bin\java.exe'), (Join-Path $env:JAVA_HOME 'bin\javac.exe'),
                        (Join-Path $env:JAVA_HOME 'bin\jlink.exe'), (Join-Path $env:JAVA_HOME 'bin\jmod.exe'),
                        (Join-Path $env:JAVA_HOME 'bin\jar.exe'), (Join-Path $env:JAVA_HOME 'jmods\java.base.jmod'))
    if (-not $WithoutRust) { $requiredTools += @($env:RUSTC, $env:RUSTDOC) }
    foreach ($path in $requiredTools) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Previously bound tool is missing: $path" }
    }
}
