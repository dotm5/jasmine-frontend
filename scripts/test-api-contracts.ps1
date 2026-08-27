param([string]$AuditDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root
if (-not $AuditDirectory) {
    $AuditDirectory = Join-Path $root ('.tmp\api-contract-runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$AuditDirectory = [IO.Path]::GetFullPath($AuditDirectory, $root)
if (-not $AuditDirectory.StartsWith((Join-Path $root '.tmp') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'API audit output must stay in workspace .tmp'
}
New-Item -ItemType Directory -Path $AuditDirectory -Force | Out-Null
function Check-NativeExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed with exit code $LASTEXITCODE" }
}
Push-Location $root
try {
    & cargo test --manifest-path native/Cargo.toml -p jmcomic -p jmbackend -p rust --lib --locked --offline 2>&1 |
        Tee-Object -FilePath (Join-Path $AuditDirectory 'rust-tests.log')
    Check-NativeExit 'Rust contracts'
    & cargo build --manifest-path native/Cargo.toml -p jmbackend --example bridge_stdio_fixture --locked --offline 2>&1 |
        Tee-Object -FilePath (Join-Path $AuditDirectory 'native-fixture-build.log')
    Check-NativeExit 'Native test bridge'
    & $env:JASMINE_PYTHON scripts/sync_downloader_profile.py --check
    Check-NativeExit 'Pinned protocol profile'
    & $env:JASMINE_PYTHON scripts/check_backend_contract.py
    Check-NativeExit 'Published backend contract'
    & $env:JASMINE_PYTHON -m unittest discover -s scripts/tests -v 2>&1 |
        Tee-Object -FilePath (Join-Path $AuditDirectory 'python-tests.log')
    Check-NativeExit 'Tool tests'
    $env:JASMINE_TEST_BRIDGE_BINARY = Join-Path $root 'native\target\debug\examples\bridge_stdio_fixture.exe'
    $env:JASMINE_API_AUDIT_REPORT = Join-Path $AuditDirectory 'runtime-coverage.json'
    $env:JASMINE_REQUIRE_API_COVERAGE = '1'
    & flutter.bat test --no-pub --concurrency=1 test tool_tests/native_startup_test.dart tool_tests/backend_api_contract_test.dart --reporter expanded 2>&1 |
        Tee-Object -FilePath (Join-Path $AuditDirectory 'flutter-tests.log')
    Check-NativeExit 'Dart / native API scenarios'
    & $env:JASMINE_PYTHON scripts/check_api_contract_surface.py --runtime-report $env:JASMINE_API_AUDIT_REPORT --out (Join-Path $AuditDirectory 'surface-and-runtime.json') 2>&1 |
        Tee-Object -FilePath (Join-Path $AuditDirectory 'contract-surface.log')
    Check-NativeExit 'Full interface coverage'
    Write-Output "API_CONTRACTS_OK: $AuditDirectory"
} finally {
    Pop-Location
}
