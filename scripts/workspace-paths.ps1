# Dot-source only. All filesystem writes stay under the supplied workspace.
function Initialize-WorkspaceTemporaryPaths([string]$WorkspaceRoot) {
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot)
    foreach ($relative in @('.tmp', '.tmp\runtime', '.toolchains', '.toolchains\android-user')) {
        $path = Join-Path $workspace $relative
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Workspace cache path is not a plain directory: $path"
            }
        } else {
            New-Item -ItemType Directory -Path $path | Out-Null
        }
    }
    $env:TEMP = Join-Path $workspace '.tmp\runtime'
    $env:TMP = $env:TEMP
    $env:ANDROID_USER_HOME = Join-Path $workspace '.toolchains\android-user'
}

function Initialize-WorkspacePathInterop {
    if ('JasmineLocal.WorkspaceNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace JasmineLocal {
    public static class WorkspaceNative {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint GetShortPathName(string path, StringBuilder output, uint size);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint QueryDosDevice(string name, StringBuilder output, uint size);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DefineDosDevice(uint flags, string name, string target);
    }
}
'@
}

function Get-WorkspaceDosTarget([string]$Drive) {
    Initialize-WorkspacePathInterop
    $buffer = [Text.StringBuilder]::new(32768)
    $length = [JasmineLocal.WorkspaceNative]::QueryDosDevice($Drive, $buffer, $buffer.Capacity)
    if ($length) { return $buffer.ToString() }
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($errorCode -ne 2) { throw [ComponentModel.Win32Exception]::new($errorCode) }
    return $null
}

function New-WorkspaceBuildView([string]$WorkspaceRoot) {
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot)
    if ($workspace.Length -gt 3) { $workspace = $workspace.TrimEnd('\') }
    if (-not (Test-Path -LiteralPath $workspace -PathType Container)) { throw 'Workspace does not exist.' }
    if ($workspace -notmatch '[^\x00-\x7f]') {
        return [pscustomobject]@{ Path = $workspace; Drive = $null; Target = $workspace; RawTarget = $null; Kind = 'native' }
    }
    Initialize-WorkspacePathInterop
    $shortPath = [Text.StringBuilder]::new(32768)
    $length = [JasmineLocal.WorkspaceNative]::GetShortPathName($workspace, $shortPath, $shortPath.Capacity)
    if ($length -gt 0 -and $length -lt $shortPath.Capacity -and $shortPath.ToString() -notmatch '[^\x00-\x7f]') {
        return [pscustomobject]@{ Path = $shortPath.ToString(); Drive = $null; Target = $workspace; RawTarget = $null; Kind = 'short-path' }
    }
    # A checked temporary DOS drive (subst equivalent), not an external junction,
    # copy or directory. The caller must remove this view in a finally block.
    $rawTarget = '\??\' + $workspace
    foreach ($code in 90..68) {
        $drive = ([char]$code).ToString() + ':'
        if ($null -ne (Get-WorkspaceDosTarget $drive)) { continue }
        if (-not [JasmineLocal.WorkspaceNative]::DefineDosDevice(9, $drive, $rawTarget)) {
            throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
        return [pscustomobject]@{ Path = $drive + '\'; Drive = $drive; Target = $workspace; RawTarget = $rawTarget; Kind = 'temporary-dos-drive' }
    }
    throw 'No unused drive letter is available for an in-place ASCII build view.'
}

function Remove-WorkspaceBuildView($View) {
    if ($null -eq $View -or -not $View.Drive) { return }
    $target = Get-WorkspaceDosTarget $View.Drive
    if ($null -eq $target) { return }
    if ($target -ne $View.RawTarget) { throw "Drive target changed; leaving it untouched: $($View.Drive)" }
    # RAW_TARGET_PATH | REMOVE_DEFINITION | EXACT_MATCH_ON_REMOVE | NO_BROADCAST.
    if (-not [JasmineLocal.WorkspaceNative]::DefineDosDevice(15, $View.Drive, $View.RawTarget)) {
        throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}
