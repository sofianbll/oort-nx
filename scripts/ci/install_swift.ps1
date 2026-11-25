# Install one exact Swift release on a Windows runner: the official installer, its digest pinned here, its signature
# checked. Third-party setup actions call unpinned actions, which this repository refuses.
param([Parameter(Mandatory)][ValidateSet('x64', 'arm64')][string]$Arch)
$ErrorActionPreference = 'Stop'
$version = '6.4.3'
$release = @{
  x64   = @{ Folder = 'windows10'; Name = "swift-$version-RELEASE-windows10.exe"; Sha256 = 'a4f1369833f77de28dbac998c8debe1c1d6044410dc6380238ae61a0d7ce5f77' }
  arm64 = @{ Folder = 'windows10-arm64'; Name = "swift-$version-RELEASE-windows10-arm64.exe"; Sha256 = 'ef45204347252878d867549171ad54cb95f26996dbcd3b881a95809b55b914e3' }
}[$Arch]
$url = "https://download.swift.org/swift-$version-release/$($release.Folder)/swift-$version-RELEASE/$($release.Name)"
$installer = Join-Path $env:RUNNER_TEMP 'swift-installer.exe'
& curl.exe --fail --silent --show-error --location --retry 3 --output $installer $url
if ($LASTEXITCODE) { throw "download: $LASTEXITCODE" }

$digest = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
$signature = Get-AuthenticodeSignature $installer
Write-Host "sha256 $digest, $((Get-Item $installer).Length) bytes, signature $($signature.Status): $($signature.SignerCertificate.Subject)"
if ($digest -ne $release.Sha256) { throw "unexpected digest for $url" }
if ($signature.Status -ne 'Valid') { throw "signature: $($signature.Status)" }

$log = Join-Path $env:RUNNER_TEMP 'swift-install.log'
$process = Start-Process -FilePath $installer -ArgumentList '/quiet', '/norestart', '/log', $log -Wait -PassThru
if ($process.ExitCode -notin 0, 3010) { Get-Content $log -Tail 60; throw "installer: $($process.ExitCode)" }
Remove-Item $installer

# The installer writes the user's and the machine's environment; the next steps get it from here.
$known = $env:Path -split ';'
$added = foreach ($level in 'Machine', 'User') { [Environment]::GetEnvironmentVariable('Path', $level) -split ';' }
$added = @($added | Where-Object { $_ -and $_ -notin $known } | Select-Object -Unique)
[array]::Reverse($added)
$added | Out-File $env:GITHUB_PATH -Append -Encoding utf8
$sdk = foreach ($level in 'User', 'Machine') { [Environment]::GetEnvironmentVariable('SDKROOT', $level) }
$sdk = @($sdk | Where-Object { $_ })[0]
if (-not $sdk) { throw 'the installer set no SDKROOT' }
"SDKROOT=$sdk" | Out-File $env:GITHUB_ENV -Append -Encoding utf8
Write-Host "SDKROOT $sdk"; $added | ForEach-Object { Write-Host "PATH $_" }
