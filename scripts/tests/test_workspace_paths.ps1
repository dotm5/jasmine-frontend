param([string]$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $WorkspaceRoot 'scripts\workspace-paths.ps1')
Initialize-WorkspaceTemporaryPaths $WorkspaceRoot
$parent = [IO.Path]::GetDirectoryName($WorkspaceRoot.TrimEnd('\'))
$beforeNames = @(Get-ChildItem -LiteralPath $parent -Force | ForEach-Object Name | Sort-Object)
$relative = '.tmp\workspace-path-test-' + [Guid]::NewGuid().ToString('N')
$probe = Join-Path $WorkspaceRoot $relative
New-Item -ItemType Directory -Path $probe | Out-Null
'workspace-only probe' | Set-Content -LiteralPath (Join-Path $probe 'before.txt') -Encoding utf8
$view = $null
try {
    $view = New-WorkspaceBuildView $WorkspaceRoot
    if ($view.Path -match '[^\x00-\x7f]') { throw 'Build view is not ASCII.' }
    $mapped = Join-Path $view.Path $relative
    if ((Get-Content -LiteralPath (Join-Path $mapped 'before.txt') -Raw).Trim() -ne 'workspace-only probe') { throw 'View does not resolve to the workspace.' }
    'written through in-place view' | Set-Content -LiteralPath (Join-Path $mapped 'after.txt') -Encoding utf8
    if ((Get-Content -LiteralPath (Join-Path $probe 'after.txt') -Raw).Trim() -ne 'written through in-place view') { throw 'View writes escaped the workspace.' }
    if (-not $env:TEMP.StartsWith($WorkspaceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or $env:TMP -ne $env:TEMP) {
        throw 'Temporary paths escaped the workspace.'
    }
    Write-Host "Workspace build view: $($view.Kind), $($view.Path) -> $($view.Target)"
} finally {
    Remove-WorkspaceBuildView $view
}
if ($view.Drive -and $null -ne (Get-WorkspaceDosTarget $view.Drive)) { throw 'Temporary drive was not removed.' }
$failedView = $null
try {
    try {
        $failedView = New-WorkspaceBuildView $WorkspaceRoot
        throw 'intentional-build-preflight-failure'
    } finally {
        Remove-WorkspaceBuildView $failedView
    }
} catch {
    if ($_.Exception.Message -ne 'intentional-build-preflight-failure') { throw }
}
if ($failedView.Drive -and $null -ne (Get-WorkspaceDosTarget $failedView.Drive)) { throw 'Failed build left a temporary drive behind.' }
$afterNames = @(Get-ChildItem -LiteralPath $parent -Force | ForEach-Object Name | Sort-Object)
if (Compare-Object $beforeNames $afterNames) { throw 'Parent directory entries changed during the path test.' }
Write-Host 'WORKSPACE_PATHS_OK: local temp, in-place read/write, success/failure drive cleanup, unchanged parent entries'
