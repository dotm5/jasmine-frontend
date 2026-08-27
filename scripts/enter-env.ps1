# Run from a fresh PowerShell process; closing it restores the original session.
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root
Write-Host "Project-local environment: $root"
Write-Host 'Existing executables reused; all configured writable caches/profile paths are inside this workspace.'
