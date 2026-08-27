Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'local-env.ps1')
Enter-LocalToolEnvironment $root
$sha = '31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26'
$cache = Join-Path $env:GRADLE_USER_HOME 'wrapper\dists\gradle-8.10.2-bin\a04bxjujx95o3nb99gddekhwo'
$binary = Join-Path $cache 'gradle-8.10.2\bin\gradle.bat'
$marker = Join-Path $cache 'gradle-8.10.2-bin.zip.ok'
$receipt = Join-Path $root '.toolchains\gradle-ready.json'
if ((Test-Path -LiteralPath $binary) -and (Test-Path -LiteralPath $marker) -and (Test-Path -LiteralPath $receipt)) {
    $previous = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($previous.distributionSha256 -eq $sha -and $previous.version -eq '8.10.2') {
        if ($previous.javaHome -ne $env:JAVA_HOME) {
            $version = & $binary --version 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $version -notmatch 'Gradle 8\.10\.2') { throw "Existing Gradle failed with the newly bound JDK: $version" }
            $previous.javaHome = $env:JAVA_HOME
            $previous | ConvertTo-Json | Set-Content -LiteralPath $receipt -Encoding utf8
            $version | Set-Content -LiteralPath (Join-Path $root '.tmp\toolchain-prep\gradle-version.log') -Encoding utf8
        }
        Write-Host "Reusing prepared Gradle: $binary"
        exit 0
    }
}
$zip = Join-Path $root '.toolchains\downloads\gradle-8.10.2-bin.zip'
& $env:JASMINE_PYTHON (Join-Path $PSScriptRoot 'download_verified.py') `
    'https://services.gradle.org/distributions/gradle-8.10.2-bin.zip' $zip --size 136715430 --sha256 $sha
if ($LASTEXITCODE -ne 0) { throw 'Gradle archive preparation failed; existing chunks preserved.' }
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$cachedZip = Join-Path $cache 'gradle-8.10.2-bin.zip'
if (-not (Test-Path -LiteralPath $cachedZip) -or (Get-FileHash -LiteralPath $cachedZip -Algorithm SHA256).Hash -ne $sha) {
    Copy-Item -LiteralPath $zip -Destination $cachedZip
}
$version = & (Join-Path $root 'android\gradlew.bat') --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $version -notmatch 'Gradle 8\.10\.2' -or -not (Test-Path -LiteralPath $marker)) { throw "Gradle wrapper verification failed: $version" }
New-Item -ItemType Directory -Path (Join-Path $root '.tmp\toolchain-prep') -Force | Out-Null
$version | Set-Content -LiteralPath (Join-Path $root '.tmp\toolchain-prep\gradle-version.log') -Encoding utf8
[ordered]@{ version = '8.10.2'; distributionSha256 = $sha; executable = $binary; javaHome = $env:JAVA_HOME } |
    ConvertTo-Json | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host $version
