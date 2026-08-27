# Regenerate ignored Flutter configuration after a temporary ASCII build view.
# Uses existing cached packages only; no tool installation or network resolution.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root -WithoutRust
$config = Get-Content -LiteralPath (Join-Path $root '.toolchains\toolchain-paths.json') -Raw | ConvertFrom-Json
$log = Join-Path $root '.tmp\restore-flutter-config.log'
Push-Location -LiteralPath $root
try {
    & (Join-Path $config.flutterSdk 'bin\flutter.bat') pub get --offline --enforce-lockfile *> $log
    if ($LASTEXITCODE -ne 0) { throw "Offline Flutter path restoration failed; see $log" }
    $propertiesFile = Join-Path $root 'android\local.properties'
    $lines = @()
    if (Test-Path -LiteralPath $propertiesFile) {
        $lines = @(Get-Content -LiteralPath $propertiesFile | Where-Object { $_ -notmatch '^(sdk\.dir|flutter\.sdk)=' })
    }
    foreach ($entry in ([ordered]@{ 'sdk.dir' = $config.androidSdk; 'flutter.sdk' = $config.flutterSdk }).GetEnumerator()) {
        # java.util.Properties.load(InputStream) requires Unicode escapes here.
        $value = -join @($entry.Value.Replace('\', '/').ToCharArray() | ForEach-Object {
            if ([int]$_ -gt 127) { '\u{0:x4}' -f [int]$_ } else { [string]$_ }
        })
        $lines += "$($entry.Key)=$value"
    }
    $lines | Set-Content -LiteralPath $propertiesFile -Encoding utf8NoBOM
    Write-Host 'Restored physical workspace paths in Flutter packages/plugins and Android local.properties.'
} finally { Pop-Location }
