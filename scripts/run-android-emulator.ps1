param(
    [switch]$SmokeTest,
    [switch]$ShowWindow,
    [ValidateSet('swiftshader', 'swangle', 'host', 'auto')][string]$Gpu = 'host',
    [ValidateRange(5554, 5584)][int]$Port = 5554,
    [ValidateRange(1024, 65535)][int]$AdbPort = 5038
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root -WithoutRust
. (Join-Path $PSScriptRoot 'workspace-paths.ps1')
if ($Port % 2 -ne 0 -or $AdbPort -in @($Port, ($Port + 1))) { throw 'Use an even emulator port and a separate adb server port.' }
foreach ($relative in @('.tmp\emulator-runs', '.toolchains\avd')) {
    $directory = Join-Path $root $relative
    if ((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Emulator state path must not be a reparse point: $directory"
    }
}

$avdName = 'jasmine_api30_smoke'
$package = 'system-images;android-30;google_apis;x86_64'
$run = Join-Path $root ('.tmp\emulator-runs\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $run | Out-Null
$run | Set-Content -LiteralPath (Join-Path $root '.tmp\current-emulator-run.txt') -Encoding utf8
$view = $null
$emulatorProcess = $null
$adbOwned = $false
$adb = $null
$networkRestoreFailure = $null
$result = [ordered]@{ startedAt = (Get-Date -Format o); status = 'preparing'; avd = $avdName; port = $Port; adbPort = $AdbPort; runDirectory = $run; headless = (-not $ShowWindow); gpu = $Gpu; systemConfigurationChanged = $false }

function Save-RunStatus { $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'status.json') -Encoding utf8 }
function Test-FreePort([int]$Number) {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Number)
    try { $listener.Start() } finally { $listener.Stop() }
}
function Set-IniValue([string]$File, [string]$Key, [string]$Value) {
    if ((Get-Item -LiteralPath $File -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'AVD config must not be a reparse point.' }
    $lines = @(Get-Content -LiteralPath $File | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($Key) + '\s*=') })
    @($lines + "$Key=$Value") | Set-Content -LiteralPath $File -Encoding utf8
}

try {
    Save-RunStatus
    foreach ($number in @($Port, ($Port + 1), $AdbPort)) { Test-FreePort $number }
    $view = New-WorkspaceBuildView $root
    $viewRoot = $view.Path
    # Keep all native tool paths ASCII, but on the same workspace files. The
    # temporary DOS view is owned for the full emulator lifetime and then removed.
    foreach ($entry in @(Get-ChildItem Env:)) {
        if ($entry.Value -eq $root -or $entry.Value.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $relative = $entry.Value.Substring($root.Length).TrimStart('\')
            [Environment]::SetEnvironmentVariable($entry.Name, (Join-Path $viewRoot $relative), 'Process')
        }
    }
    $env:JAVA_TOOL_OPTIONS = '-Duser.home="' + $env:HOME + '"'
    $env:ANDROID_AVD_HOME = Join-Path $viewRoot '.toolchains\avd'
    $env:ANDROID_EMULATOR_HOME = $env:ANDROID_USER_HOME
    $env:ANDROID_SDK_HOME = $env:HOME
    $env:ANDROID_ADB_SERVER_PORT = "$AdbPort"
    $env:ADB_SERVER_SOCKET = "tcp:127.0.0.1:$AdbPort"
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $env:QT_LOGGING_RULES = '*.debug=false'
    New-Item -ItemType Directory -Path $env:ANDROID_AVD_HOME -Force | Out-Null
    $sdk = $env:ANDROID_HOME
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $emulator = Join-Path $sdk 'emulator\emulator.exe'
    $image = Join-Path $sdk 'system-images\android-30\google_apis\x86_64'
    foreach ($file in @($adb, $emulator, (Join-Path $image 'system.img'))) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing local component (prepare once, do not reinstall): $file" }
    }
    $accel = & $emulator -accel-check 2>&1
    $accel | Set-Content -LiteralPath (Join-Path $run 'acceleration.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or ($accel -join "`n") -notmatch 'WHPX.*usable') { throw 'WHPX is not usable; no system setting or driver was changed.' }
    $result.acceleration = 'WHPX'
    $result.workspaceView = $view

    $avdDirectory = Join-Path $env:ANDROID_AVD_HOME ($avdName + '.avd')
    $ownerFile = Join-Path $avdDirectory '.jasmine-avd.json'
    if (Test-Path -LiteralPath $avdDirectory) {
        if ((Get-Item -LiteralPath $avdDirectory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'AVD directory must not be a reparse point.' }
        if (-not (Test-Path -LiteralPath $ownerFile)) { throw 'Existing AVD lacks the project ownership marker; preserved unchanged.' }
        $owner = Get-Content -LiteralPath $ownerFile -Raw | ConvertFrom-Json
        if ($owner.workspace -ne $root -or $owner.package -ne $package) { throw 'AVD ownership/package differs; preserved unchanged.' }
        Write-Host "Reusing project AVD: $avdName"
    } else {
        # An AVD is an index .ini plus config.ini and writable guest data. The
        # installed avdmanager 15859902 passes a null Android user folder during
        # creation on this host; use the minimal native emulator format instead.
        # This neither patches the SDK nor downloads/reinstalls another version.
        New-Item -ItemType Directory -Path $avdDirectory | Out-Null
        @{ workspace = $root; package = $package; createdAt = (Get-Date -Format o) } | ConvertTo-Json | Set-Content -LiteralPath $ownerFile -Encoding utf8
    }
    $avdIni = Join-Path $env:ANDROID_AVD_HOME ($avdName + '.ini')
    @('avd.ini.encoding=UTF-8', "path=$avdDirectory", 'target=android-30') | Set-Content -LiteralPath $avdIni -Encoding utf8
    $hardware = Join-Path $avdDirectory 'config.ini'
    if (-not (Test-Path -LiteralPath $hardware)) { 'avd.ini.encoding=UTF-8' | Set-Content -LiteralPath $hardware -Encoding utf8 }
    $settings = [ordered]@{
        'AvdId' = $avdName; 'avd.ini.displayname' = 'Jasmine Local Smoke'
        'abi.type' = 'x86_64'; 'hw.cpu.arch' = 'x86_64'
        'tag.id' = 'google_apis'; 'tag.display' = 'Google APIs'
        'image.sysdir.1' = 'system-images\android-30\google_apis\x86_64\'
        'hw.ramSize' = '2048'; 'hw.cpu.ncore' = '2'
        'hw.lcd.width' = '720'; 'hw.lcd.height' = '1280'; 'hw.lcd.density' = '320'
        'hw.gpu.enabled' = 'yes'; 'hw.gpu.mode' = $Gpu
        'hw.camera.back' = 'none'; 'hw.camera.front' = 'none'
        'hw.audioInput' = 'no'; 'hw.keyboard' = 'yes'
        'disk.dataPartition.size' = '2G'; 'hw.sdCard' = 'no'
        'showDeviceFrame' = 'no'; 'skin.name' = '720x1280'; 'skin.path' = '_no_skin'
        'fastboot.forceColdBoot' = 'yes'; 'fastboot.forceFastBoot' = 'no'
        'PlayStore.enabled' = 'false'
    }
    foreach ($entry in $settings.GetEnumerator()) { Set-IniValue $hardware $entry.Key $entry.Value }

    & $adb -P $AdbPort start-server 2>&1 | Tee-Object -FilePath (Join-Path $run 'adb-server.log')
    if ($LASTEXITCODE -ne 0) { throw 'Dedicated local adb server failed to start.' }
    $adbOwned = $true
    $result.adbExecutable = $adb
    $result.serial = "emulator-$Port"
    $arguments = @('-avd', $avdName, '-port', "$Port", '-accel', 'on', '-gpu', $Gpu,
                   '-memory', '2048', '-cores', '2', '-no-audio', '-no-boot-anim', '-no-snapshot', '-no-metrics',
                   '-camera-back', 'none', '-camera-front', 'none')
    if (-not $ShowWindow) { $arguments += '-no-window' }
    $windowStyle = if ($ShowWindow) { 'Normal' } else { 'Hidden' }
    $emulatorProcess = Start-Process -FilePath $emulator -ArgumentList $arguments -WorkingDirectory $viewRoot -PassThru -WindowStyle $windowStyle -RedirectStandardOutput (Join-Path $run 'emulator.stdout.log') -RedirectStandardError (Join-Path $run 'emulator.stderr.log')
    $result.pid = $emulatorProcess.Id
    $result.arguments = $arguments
    $result.status = 'running'
    Save-RunStatus
    Write-Host "Headless=$(-not $ShowWindow); serial=emulator-$Port; adbPort=$AdbPort; logs=$run"
    if ($SmokeTest) {
        & $env:JASMINE_PYTHON (Join-Path $root 'scripts\android_emulator_smoke.py') --adb $adb --adb-port $AdbPort --serial "emulator-$Port" --output $run
        if ($LASTEXITCODE -ne 0) { throw 'Emulator smoke test failed; inspect the preserved report and logcat.' }
        $result.smokeTest = (Get-Content -LiteralPath (Join-Path $run 'smoke-report.json') -Raw | ConvertFrom-Json).status
    } else {
        Write-Host 'Waiting for the emulator to close, or for stop.request in this run directory.'
        while (-not $emulatorProcess.HasExited -and -not (Test-Path -LiteralPath (Join-Path $run 'stop.request'))) { Start-Sleep -Seconds 2; $emulatorProcess.Refresh() }
        if ($emulatorProcess.HasExited -and $emulatorProcess.ExitCode -ne 0) { throw "Emulator exited with code $($emulatorProcess.ExitCode)" }
    }
    $result.status = 'completed'
} catch {
    $result.status = 'failed'
    $result.error = $_.Exception.Message
    throw
} finally {
    if ($null -ne $emulatorProcess) {
        $emulatorProcess.Refresh()
        if (-not $emulatorProcess.HasExited) {
            $snapshotPath = Join-Path $run 'network-state-before.json'
            $smokeReportPath = Join-Path $run 'smoke-report.json'
            $pythonAlreadyRestored = $false
            $pythonNetworkNotNeeded = $false
            if (Test-Path -LiteralPath $smokeReportPath -PathType Leaf) {
                try {
                    $smokeReport = Get-Content -LiteralPath $smokeReportPath -Raw | ConvertFrom-Json
                    $networkProperty = $smokeReport.PSObject.Properties['network']
                    if ($null -ne $networkProperty -and $null -ne $networkProperty.Value) {
                        $restoredProperty = $networkProperty.Value.PSObject.Properties['restored']
                        $pythonAlreadyRestored = $null -ne $restoredProperty -and [bool]$restoredProperty.Value
                        $restoreProperty = $networkProperty.Value.PSObject.Properties['restore']
                        $pythonNetworkNotNeeded = $null -ne $restoreProperty -and [string]$restoreProperty.Value -eq 'not-needed'
                    }
                } catch {
                    $pythonAlreadyRestored = $false
                    $pythonNetworkNotNeeded = $false
                }
            }
            if ($pythonAlreadyRestored) {
                $result.networkRestoreFallback = [ordered]@{ status = 'already-restored'; snapshot = $snapshotPath; source = $smokeReportPath }
            } elseif ($pythonNetworkNotNeeded) {
                $result.networkRestoreFallback = [ordered]@{ status = 'not-needed'; snapshot = $snapshotPath; source = $smokeReportPath }
            } elseif (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
                $restoreReportPath = Join-Path $run 'network-restore-report.json'
                try {
                    $restoreOutput = & $env:JASMINE_PYTHON (Join-Path $root 'scripts\android_emulator_smoke.py') --adb $adb --adb-port $AdbPort --serial ("emulator-" + $Port) --output $run --restore-network --network-snapshot $snapshotPath 2>&1
                    $restoreExit = $LASTEXITCODE
                    $restoreOutput | Out-File -LiteralPath (Join-Path $run 'network-restore-fallback.log') -Encoding utf8
                    $restoreStatus = if ($restoreExit -eq 0) { 'restored' } else { 'failed' }
                    if (Test-Path -LiteralPath $restoreReportPath -PathType Leaf) {
                        try {
                            $restoreDocument = Get-Content -LiteralPath $restoreReportPath -Raw | ConvertFrom-Json
                            $statusProperty = $restoreDocument.PSObject.Properties['status']
                            if ($null -ne $statusProperty) { $restoreStatus = [string]$statusProperty.Value }
                        } catch {
                            $restoreStatus = 'failed'
                        }
                    }
                    $result.networkRestoreFallback = [ordered]@{ status = $restoreStatus; snapshot = $snapshotPath; report = $restoreReportPath; exitCode = $restoreExit }
                    if ($restoreExit -ne 0 -or $restoreStatus -eq 'failed') {
                        $result.status = 'failed'
                        $networkRestoreFailure = "Python network restoration exited with code $restoreExit"
                    }
                } catch {
                    $result.status = 'failed'
                    $result.networkRestoreFallback = [ordered]@{ status = 'failed'; snapshot = $snapshotPath; report = $restoreReportPath; error = $_.Exception.Message }
                    $networkRestoreFailure = $_.Exception.Message
                }
            } else {
                $result.networkRestoreFallback = [ordered]@{ status = 'not-needed'; snapshot = $snapshotPath }
            }
            & $adb -P $AdbPort -s "emulator-$Port" emu kill 2>&1 | Out-File -LiteralPath (Join-Path $run 'emulator-stop.log') -Encoding utf8
            if (-not $emulatorProcess.WaitForExit(20000)) {
                # This Process object is the child launched above, never a name
                # based search or a different emulator/real Android device.
                $emulatorProcess.Kill($true)
                $emulatorProcess.WaitForExit()
            }
        }
        $result.emulatorStopped = $emulatorProcess.HasExited
    }
    if ($adbOwned) { & $adb -P $AdbPort kill-server 2>&1 | Out-File -LiteralPath (Join-Path $run 'adb-stop.log') -Encoding utf8 }
    if ($view) { Remove-WorkspaceBuildView $view }
    $result.workspaceViewRemoved = ($null -eq $view -or -not $view.Drive -or $null -eq (Get-WorkspaceDosTarget $view.Drive))
    $result.finishedAt = Get-Date -Format o
    Save-RunStatus
}
if ($null -ne $networkRestoreFailure) { throw "Network restoration fallback failed: $networkRestoreFailure" }
