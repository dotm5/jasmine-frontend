Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root
$config = Get-Content -LiteralPath (Join-Path $root '.toolchains\toolchain-paths.json') -Raw | ConvertFrom-Json
$relative = '.tmp\toolchain-prep\smoke-' + [Guid]::NewGuid().ToString('N')
$physical = Join-Path $root $relative
New-Item -ItemType Directory -Path $physical | Out-Null
$view = $null
$profileHome = $env:HOME
function Check([string]$Step) { if ($LASTEXITCODE -ne 0) { throw "$Step failed ($LASTEXITCODE)" } }
try {
    $view = New-WorkspaceBuildView $root
    $work = Join-Path $view.Path $relative
    $sdk = Join-Path $view.Path '.toolchains\android-sdk'
    $llvm = Join-Path $sdk ('ndk\' + $config.ndkVersion + '\toolchains\llvm\prebuilt\windows-x86_64\bin')
    $clang = Join-Path $llvm 'clang.exe'
    $env:TEMP = Join-Path $view.Path '.tmp\runtime'
    $env:TMP = $env:TEMP
    $javaHomeView = Join-Path $view.Path '.toolchains\user-home'
    $env:JAVA_TOOL_OPTIONS = '-Duser.home="' + $javaHomeView + '"'
    foreach ($path in @($clang, (Join-Path $sdk 'platforms\android-35\android.jar'),
                        (Join-Path $sdk 'build-tools\35.0.0\apksigner.bat'),
                        (Join-Path $sdk 'build-tools\35.0.0\zipalign.exe'))) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing prepared component: $path" }
    }
    $clangVersion = (& (Join-Path $llvm 'clang.exe') --version | Out-String).Trim()
    Check 'NDK compiler version'
    'int jasmine_c_smoke(int a, int b) { return a + b; }' | Set-Content -LiteralPath (Join-Path $work 'smoke.c') -Encoding utf8NoBOM
    & $clang --target=aarch64-linux-android21 -shared -fPIC '-Wl,-z,max-page-size=16384' (Join-Path $work 'smoke.c') -o (Join-Path $work 'libc_smoke.so')
    Check 'Android C cross-compile'
    '#[no_mangle] pub extern "C" fn jasmine_rust_smoke(a: i32, b: i32) -> i32 { a + b }' |
        Set-Content -LiteralPath (Join-Path $work 'smoke.rs') -Encoding utf8NoBOM
    & $env:RUSTC --edition=2021 --crate-type=cdylib --target=aarch64-linux-android -O `
        -C "linker=$clang" -C 'link-arg=--target=aarch64-linux-android21' -C 'link-arg=-Wl,-z,max-page-size=16384' `
        (Join-Path $work 'smoke.rs') -o (Join-Path $work 'librust_smoke.so')
    Check 'Android Rust cross-compile using the existing target'
    @'
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
public class EnvProbe {
    static String quote(String value) { return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""; }
    public static void main(String[] args) throws Exception {
        String home = System.getProperty("user.home");
        if (!Path.of(home).normalize().equals(Path.of(args[1]).normalize())) throw new IllegalStateException("JVM profile escaped workspace");
        String json = "{\"javaHome\":" + quote(System.getProperty("java.home")) + ",\"userHome\":" + quote(home) + "}";
        Files.writeString(Path.of(args[0]), json, StandardCharsets.UTF_8);
    }
}
'@ | Set-Content -LiteralPath (Join-Path $work 'EnvProbe.java') -Encoding utf8NoBOM
    & (Join-Path $env:JAVA_HOME 'bin\javac.exe') -encoding UTF-8 -d $work (Join-Path $work 'EnvProbe.java')
    Check 'Existing javac compilation'
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $work EnvProbe (Join-Path $work 'java-profile.json') $javaHomeView
    Check 'JVM workspace-only profile'
    @'
import json, pathlib, sys
sys.path.insert(0, sys.argv[1])
from verify_local_apk import inspect_elf
folder = pathlib.Path(sys.argv[2])
report = {}
for name in ("libc_smoke.so", "librust_smoke.so"):
    details, exports = inspect_elf((folder / name).read_bytes())
    expected = "jasmine_c_smoke" if name == "libc_smoke.so" else "jasmine_rust_smoke"
    assert expected in exports, (name, exports)
    report[name] = details
(folder / "elf-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("ANDROID_ELF_OK: C and Rust ARM64 libraries, exported smoke functions, 16-KiB load alignment")
'@ | Set-Content -LiteralPath (Join-Path $work 'inspect.py') -Encoding utf8NoBOM
    & $env:JASMINE_PYTHON (Join-Path $work 'inspect.py') (Join-Path $view.Path 'scripts') $work
    Check 'Actual ARM64 ELF inspection'
    & cargo.exe fetch --offline --locked --manifest-path (Join-Path $root 'native\Cargo.toml') `
        --target x86_64-pc-windows-msvc --target aarch64-linux-android
    Check 'Local Cargo cache, offline'
    $flutter = & (Join-Path $root '.toolchains\flutter\bin\flutter.bat') --version --machine | ConvertFrom-Json
    Check 'Existing Flutter SDK inspection'
    if ($flutter.frameworkVersion -ne '3.29.3') { throw 'Unexpected Flutter version.' }
    $packages = Get-Content -LiteralPath (Join-Path $root '.dart_tool\package_config.json') -Raw | ConvertFrom-Json
    $base = [Uri]::new((Join-Path $root '.dart_tool\package_config.json'))
    foreach ($package in $packages.packages) {
        $path = [Uri]::new($base, $package.rootUri).LocalPath
        if (-not [IO.Path]::GetFullPath($path).StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFullPath($path).TrimEnd('\') -ne $root.TrimEnd('\')) { throw "Pub package points outside workspace: $($package.name) $path" }
    }
    $environment = [ordered]@{}
    foreach ($name in @('CARGO_HOME','RUSTUP_HOME','PUB_CACHE','GRADLE_USER_HOME','ANDROID_USER_HOME','PIP_CACHE_DIR','HOME','USERPROFILE','APPDATA','LOCALAPPDATA')) {
        $path = [Environment]::GetEnvironmentVariable($name, 'Process')
        if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Writable path outside workspace: $name" }
        $environment[$name] = $path
    }
    $rustVersion = & $env:RUSTC --version
    Check 'Existing Rust version'
    $jlinkVersion = (& (Join-Path $env:JAVA_HOME 'bin\jlink.exe') --version | Out-String).Trim()
    Check 'Complete JDK jlink'
    [ordered]@{
        verifiedAt = (Get-Date).ToString('o')
        strategy = 'reuse existing tools; isolated project caches/profile; no installers invoked by this verification'
        javaHome = $config.javaHome; jlinkVersion = $jlinkVersion; rustToolchain = $config.rustToolchain; pythonExecutable = $config.pythonExecutable
        rustVersion = $rustVersion; flutter = $flutter.frameworkVersion; dart = $flutter.dartSdkVersion
        ndk = $config.ndkVersion; clang = $clangVersion; sdk = 35; buildTools = $config.buildTools
        gradle = Get-Content -LiteralPath (Join-Path $root '.toolchains\gradle-ready.json') -Raw | ConvertFrom-Json
        caches = $environment; pubPackagesWithinWorkspace = $packages.packages.Count; cargoOfflineReady = $true
        androidCrossCompile = Get-Content -LiteralPath (Join-Path $physical 'elf-report.json') -Raw | ConvertFrom-Json
        javaProfile = Get-Content -LiteralPath (Join-Path $physical 'java-profile.json') -Raw | ConvertFrom-Json
        smokeArtifacts = $physical; apkBuild = 'not run by this verifier; separate application build evidence is in dist/build-manifest.json when present'
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $root '.toolchains\toolchain-verification.json') -Encoding utf8
    Write-Host 'LOCAL_ENV_VERIFIED: reused tools, local caches, Java profile, actual C/Rust Android cross-compilation'
} finally {
    $env:TEMP = Join-Path $root '.tmp\runtime'
    $env:TMP = $env:TEMP
    $env:JAVA_TOOL_OPTIONS = '-Duser.home="' + $profileHome + '"'
    Remove-WorkspaceBuildView $view
}
