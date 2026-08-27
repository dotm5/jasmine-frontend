# Workspace convenience wrapper. The exported backend owns its actual builder.
param(
    [string]$SourceDirectory,
    [string]$OutputDirectory,
    [switch]$SkipTests,
    [switch]$Offline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $root 'native' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root ('dist\jmbackend-android-arm64-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory, $root)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory, $root)
foreach ($path in @($SourceDirectory, $OutputDirectory)) {
    if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Backend source/output must remain inside this workspace: $path"
    }
}
$view = $null
try {
    $view = New-WorkspaceBuildView $root
    function In-BuildView([string]$Path) {
        if ($Path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return Join-Path $view.Path $Path.Substring($root.Length).TrimStart('\')
        }
        return $Path
    }
    & (Join-Path (In-BuildView $SourceDirectory) 'scripts\build-android.ps1') `
        -NdkHome (In-BuildView $env:ANDROID_NDK_HOME) `
        -PythonExecutable $env:JASMINE_PYTHON `
        -CacheDirectory (Join-Path $view.Path '.toolchains') `
        -TargetDirectory (Join-Path $view.Path 'native\target') `
        -TemporaryDirectory (Join-Path $view.Path '.tmp\runtime') `
        -OutputDirectory (In-BuildView $OutputDirectory) -SkipTests:$SkipTests -Offline:$Offline
} finally { Remove-WorkspaceBuildView $view }
