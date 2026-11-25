# Proves a Windows installer on a machine that has neither Swift nor Rust in its PATH: silent install, the installed app
# driven through its scenarios with invented games, a second install over it, then an uninstall that leaves the player's
# files. usage: prove.ps1 -Installer <setup.exe> -Out <folder> -Version <x.y.z>
param([Parameter(Mandatory)][string]$Installer, [Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][string]$Version)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$desktop = (Resolve-Path "$here/../..").Path
$script:failures = 0
function Check([bool]$ok, [string]$what) { if ($ok) { Write-Host "ok $what" } else { Write-Host "FAIL $what"; $script:failures++ } }
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$python = (Get-Command python).Source
$node = (Get-Command node).Source

# The proof's own tools, made with the C# compiler Windows comes with.
$csc = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$tools = "$env:RUNNER_TEMP\tools"; New-Item -ItemType Directory -Force $tools | Out-Null
$refs = '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll'
& $csc /nologo /target:winexe "/out:$tools\FakeGame.exe" $refs "$here\FakeGame.cs"; if ($LASTEXITCODE) { throw 'FakeGame' }
& $csc /nologo "/out:$tools\Desk.exe" $refs "$here\Desk.cs"; if ($LASTEXITCODE) { throw 'Desk' }
& "$tools\Desk.exe" screen 1920 1080
$run = "$env:RUNNER_TEMP\oort-run"
& $python "$desktop\scripts\fixtures.py" $run --windows "$tools\FakeGame.exe"; if ($LASTEXITCODE) { throw 'fixtures' }

Write-Host "Windows $([Environment]::OSVersion.Version), $((Get-CimInstance Win32_OperatingSystem).Caption)"
foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node', 'HKLM:\SOFTWARE', 'HKCU:\Software') {
  $webview = Get-ItemProperty "$key\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
  if ($webview) { Write-Host "WebView2 $($webview.pv) ($key)" }
}
$signature = Get-AuthenticodeSignature $Installer
Write-Host "installer: $((Get-Item $Installer).Length) bytes, sha256 $((Get-FileHash $Installer).Hash.ToLower()), signature $($signature.Status)"

# --- Install
function Install {
  $p = Start-Process -FilePath $Installer -ArgumentList '/S' -PassThru
  if (-not $p.WaitForExit(240000)) { throw 'the installer did not end' }
  Check ($p.ExitCode -eq 0) "silent install: exit $($p.ExitCode)"
}
Install
$entry = { Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object DisplayName -eq 'Oort NX' }
$installed = & $entry
Check ($null -ne $installed) 'it is in the list of installed apps'
Check ($installed.DisplayVersion -eq $Version) "version $($installed.DisplayVersion)"
$folder = $installed.InstallLocation.Trim('"')
Write-Host "installed in $($folder.Replace($env:USERPROFILE, '%USERPROFILE%'))"
Check ($folder.StartsWith($env:LOCALAPPDATA, 'OrdinalIgnoreCase')) 'for this user only, without administrator rights'
Get-ChildItem $folder -Recurse -File | ForEach-Object { '{0,10} {1}' -f $_.Length, $_.FullName.Substring($folder.Length + 1) }
& $python "$desktop\scripts\runtime_windows.py" check $folder --imports; Check ($LASTEXITCODE -eq 0) 'every library is in the folder or in Windows'
foreach ($file in 'NOTICE', 'LICENSE.txt', 'licenses\Swift-LICENSE.txt', 'licenses\ICU-LICENSE.txt', 'licenses\WebView2-SDK-LICENSE.txt', 'licenses\THIRD-PARTY-RUST.txt') { Check (Test-Path "$folder\$file") "$file is there" }
$app = Get-ChildItem $folder -Filter *.exe | Where-Object { $_.Name -notin 'oort-core.exe', 'uninstall.exe' }
Check (@($app).Count -eq 1) "the program: $($app.Name)"
$app = $app.FullName

# --- The core alone, from the installed folder, with nothing in PATH
$path = $env:PATH
$env:PATH = "$env:SystemRoot\System32"
Check ($null -eq (Get-Command swift, cargo, rustc -ErrorAction SilentlyContinue)) 'no Swift, no Rust in PATH'
$reply = '{"id":1,"method":"hello"}' | & "$folder\oort-core.exe" --data "$env:RUNNER_TEMP\core-data" --resources $folder --system windows
Check ("$reply" -match '"system":"windows"') 'the installed core answers'
$env:PATH = $path

function Drive([string]$script, [string[]]$pairs) {
  Write-Host "`n--- $script $pairs"
  & $node "$here\drive.mjs" $app $script "$Out\pictures" "run=$run" "desk=$tools\Desk.exe" @pairs
  Check ($LASTEXITCODE -eq 0) "$(Split-Path -Leaf $script) $pairs"
}

# --- A first start, with the app's own folder
$own = "$env:LOCALAPPDATA\io.github.sofianbll.oort-nx.desktop"
Check (-not (Test-Path "$own\library.json")) 'nothing of an earlier install'
Drive "$desktop\tests\first.js" @('tag=first-', 'language=fr')
Check (Test-Path "$own\library.json") 'the library is kept in the folder of this user'

# --- Which files the running app loads
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $null
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
$started = Start-Process $app -PassThru
Start-Sleep 6
$core = Get-Process oort-core -ErrorAction SilentlyContinue
Check ($null -ne $core) 'the core runs beside the window'
if ($core) {
  $modules = $core.Modules | Where-Object { $_.FileName -notlike "$env:SystemRoot\*" -and $_.ModuleName -ne 'oort-core.exe' }
  $modules | ForEach-Object { Write-Host "loaded $($_.ModuleName)" }
  Check (@($modules | Where-Object { -not $_.FileName.StartsWith($folder, 'OrdinalIgnoreCase') }).Count -eq 0) 'the core loads its libraries from its own folder'
  Check (@($modules | Where-Object ModuleName -eq 'swiftCore.dll').Count -eq 1) 'the Swift runtime is the one installed with the app'
}
& "$tools\Desk.exe" shot "$Out\pictures\start-menu-start.png"
& "$tools\Desk.exe" state $started.Id
$started.Refresh()
Write-Host "memory: window $([int]($started.WorkingSet64 / 1MB)) MB, core $([int]($core.WorkingSet64 / 1MB)) MB"
$null = $started.CloseMainWindow()
Check ($started.WaitForExit(15000)) 'the X button closes it'
Start-Sleep 2
Check ($null -eq (Get-Process oort-core -ErrorAction SilentlyContinue)) 'and the core with it'
$env:PATH = $path

# --- The scenarios, each with a data folder of its own
foreach ($one in @(
    @('walk', '1440x900', 'fr'), @('play', '1440x900', 'fr'), @('pad', '1440x900', 'fr'), @('look', '1280x720', 'fr'), @('look', '760x480', 'fr'), @('walk', '1280x720', 'en'))) {
  $tag = if ($one[0] -eq 'look' -and $one[1] -eq '760x480') { 'small-' } else { "$($one[0])-$($one[1])-$($one[2])-" }
  Drive "$desktop\tests\$($one[0]).js" @("data=$env:RUNNER_TEMP\data-$tag", "tag=$tag", "size=$($one[1])", "language=$($one[2])", 'limit=420')
}
Drive "$here\windows.js" @("data=$env:RUNNER_TEMP\data-play-1440x900-fr-", 'tag=windows-', 'size=1440x900', 'language=fr')

# --- A second install over the first keeps everything
Install
Drive "$desktop\tests\again.js" @('tag=again-', 'language=fr')

# --- Uninstall
$before = (Get-ChildItem $run -Recurse -File).Count
$p = Start-Process -FilePath "$folder\uninstall.exe" -ArgumentList '/S' -PassThru -Wait
Check ($p.ExitCode -eq 0) "silent uninstall: exit $($p.ExitCode)"
for ($i = 0; $i -lt 60 -and ((Test-Path $folder) -or (& $entry)); $i++) { Start-Sleep 1 }
Check (-not (Test-Path $folder)) 'the folder of the program is gone'
if (Test-Path $folder) { Get-ChildItem $folder -Recurse | ForEach-Object { Write-Host "left: $($_.FullName.Substring($folder.Length))" } }
Check ($null -eq (& $entry)) 'it is out of the list of installed apps'
$shortcuts = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:USERPROFILE\Desktop" -Recurse -Filter 'Oort NX*.lnk' -ErrorAction SilentlyContinue
Check (@($shortcuts).Count -eq 0) 'no shortcut is left'
Check (Test-Path "$own\library.json") 'the library of the player is left'
Check ((Get-ChildItem $run -Recurse -File).Count -eq $before) 'the games are untouched'
Write-Host "`n$script:failures failures"
if ($script:failures) { exit 1 }
