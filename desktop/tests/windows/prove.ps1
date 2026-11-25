# Proves a Windows installer on a machine that has neither Swift nor Rust in its PATH: silent install, the installed app
# driven through its scenarios with invented games, a second install over it, then an uninstall that leaves the player's
# files. usage: prove.ps1 -Installer <setup.exe> -Out <folder> -Version <x.y.z> [-Before <the published alpha.1's setup.exe>]
param([string]$Before, [Parameter(Mandatory)][string]$Installer, [Parameter(Mandatory)][string]$Out, [Parameter(Mandatory)][string]$Version)
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
& $csc /nologo "/out:$tools\FakeSteam.exe" "$here\FakeSteam.cs"; if ($LASTEXITCODE) { throw 'FakeSteam' }
$run = "$env:RUNNER_TEMP\oort-run"
# A second drive, for Steam's second library.
New-Item -ItemType Directory -Force "$run\second" | Out-Null
subst S: "$run\second"; if ($LASTEXITCODE) { throw 'subst' }
& $python "$desktop\scripts\fixtures.py" $run --windows "$tools\FakeGame.exe" --steam-second 'S:\'; if ($LASTEXITCODE) { throw 'fixtures' }
# A program with its own name and icon, added by its file's name.
& $csc /nologo /target:winexe "/out:$run\programs\lb_x64.exe" "/win32icon:$run\programs\lamp.ico" $refs "$here\FakeGame.cs" "$here\Named.cs"; if ($LASTEXITCODE) { throw 'Named' }
'seconds=2' | Set-Content "$run\programs\lb_x64.play"
# One of Steam's games has an icon too.
Copy-Item "$run\programs\lb_x64.exe" "$run\Steam\steamapps\common\Twice Awake\game.exe" -Force
Copy-Item "$tools\FakeSteam.exe" "$run\Steam\steam.exe"
function Steam([bool]$on) {
  if ($on) {
    New-Item 'HKCU:\Software\Valve\Steam' -Force | Out-Null
    New-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -Value "$run/Steam".Replace('\', '/').ToLower() -Force | Out-Null
    New-Item 'HKCU:\Software\Classes\steam\shell\open\command' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Classes\steam' -Name '(default)' -Value 'URL:steam protocol'
    New-ItemProperty 'HKCU:\Software\Classes\steam' -Name 'URL Protocol' -Value '' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Classes\steam\shell\open\command' -Name '(default)' -Value "`"$run\Steam\steam.exe`" `"%1`""
  } else { Remove-Item 'HKCU:\Software\Valve\Steam', 'HKCU:\Software\Classes\steam' -Recurse -ErrorAction SilentlyContinue }
}

# The runner's own welcome window, where there is one, is not part of a player's screen.
foreach ($p in Get-Process | Where-Object MainWindowTitle) { Write-Host "open window: $($p.ProcessName), $($p.MainWindowTitle.Split('\')[0])" }
Get-Process | Where-Object MainWindowTitle -eq 'Microsoft account' | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Windows $([Environment]::OSVersion.Version), $((Get-CimInstance Win32_OperatingSystem).Caption)"
foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node', 'HKLM:\SOFTWARE', 'HKCU:\Software') {
  $webview = Get-ItemProperty "$key\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
  if ($webview) { Write-Host "WebView2 $($webview.pv) ($key)" }
}
$signature = Get-AuthenticodeSignature $Installer
Write-Host "installer: $((Get-Item $Installer).Length) bytes, sha256 $((Get-FileHash $Installer).Hash.ToLower()), signature $($signature.Status)"

# --- Install
function Install([string]$Setup = $Installer) {
  $p = Start-Process -FilePath $Setup -ArgumentList '/S' -PassThru
  if (-not $p.WaitForExit(240000)) { throw 'the installer did not end' }
  Check ($p.ExitCode -eq 0) "silent install: exit $($p.ExitCode)"
}
$entry = { Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | Get-ItemProperty | Where-Object DisplayName -eq 'Oort NX' }
function Uninstall([string]$from) {
  $p = Start-Process -FilePath "$from\uninstall.exe" -ArgumentList '/S' -PassThru -Wait
  Check ($p.ExitCode -eq 0) "silent uninstall: exit $($p.ExitCode)"
  for ($i = 0; $i -lt 60 -and ((Test-Path $from) -or (& $entry)); $i++) { Start-Sleep 1 }
  Check (-not (Test-Path $from)) 'the folder of the program is gone'
}
$own = "$env:LOCALAPPDATA\io.github.sofianbll.oort-nx.desktop"
# WebView2 takes the debugging port from its own policy, for this program only; nothing of the app is changed. The
# variable of the same name is not read for a program run as administrator, as the runner's are.
$policies = 'HKLM:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments', 'HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
function Debugging([bool]$on) {
  foreach ($policy in $policies) {
    if ($on) {
      New-Item $policy -Force | Out-Null
      New-ItemProperty $policy -Name (Split-Path -Leaf $app) -Value '--remote-debugging-port=9333 --remote-allow-origins=*' -Force | Out-Null
    } elseif (Test-Path $policy) { Remove-Item $policy -Recurse }
  }
}
function Quiet {
  # One WebView2 at a time uses the folder of the app.
  for ($i = 0; $i -lt 40 -and (Get-Process msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Path }); $i++) {
    $ours = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" | Where-Object { $_.CommandLine -match 'oort-nx' }
    if (-not $ours) { return }
    Start-Sleep -Milliseconds 500
  }
}

function Drive([string]$script, [string[]]$pairs) {
  Write-Host "`n--- $script $pairs"
  Quiet; Debugging $true
  & $node "$here\drive.mjs" $app $script "$Out\pictures" "run=$run" "desk=$tools\Desk.exe" @pairs
  $code = $LASTEXITCODE
  Check ($code -eq 0) "$(Split-Path -Leaf $script) $pairs"
  Debugging $false
}

# --- From the published alpha.1, as a player updates
if ($Before) {
  Write-Host "`n--- alpha.1: sha256 $((Get-FileHash $Before).Hash.ToLower())"
  Install $Before
  $old = & $entry
  Check ($old.DisplayVersion -eq '0.1.0-alpha.1') "the published version: $($old.DisplayVersion)"
  $app = (Get-ChildItem $old.InstallLocation.Trim('"') -Filter *.exe | Where-Object { $_.Name -notin 'oort-core.exe', 'uninstall.exe' }).FullName
  Drive "$desktop\tests\alpha1.js" @('tag=update-', 'language=fr', 'size=1440x900')
  Quiet
  $kept = @('library.json', 'sessions.json', 'profiles.json', 'settings.json') | ForEach-Object { "$own\$_" }
  $digests = $kept | ForEach-Object { (Get-FileHash $_).Hash }
  Steam $true
  Install
  Check (@(& $entry).Count -eq 1) 'one Oort NX in the list'
  Check ((& $entry).DisplayVersion -eq $Version) "updated to $((& $entry).DisplayVersion)"
  Check (($kept | ForEach-Object { (Get-FileHash $_).Hash }) -join ',' -eq ($digests -join ',')) 'the installer does not touch the library'
  $app = (Get-ChildItem (& $entry).InstallLocation.Trim('"') -Filter *.exe | Where-Object { $_.Name -notin 'oort-core.exe', 'uninstall.exe' }).FullName
  Drive "$desktop\tests\update.js" @('tag=update-', 'language=fr', 'size=1440x900', 'expect=.dialog')
  Steam $false
  Quiet
  Uninstall (& $entry).InstallLocation.Trim('"')
  Check (Test-Path "$own\library.json") 'the library stays after it'
  Remove-Item $own -Recurse -Force
}

Install
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

# --- A first start, with the app's own folder
Check (-not (Test-Path "$own\library.json")) 'nothing of an earlier install'
Drive "$desktop\tests\first.js" @('tag=first-', 'language=fr')
Check (Test-Path "$own\library.json") 'the library is kept in the folder of this user'

# --- Which files the running app loads
Quiet
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

# --- The first steps, Steam and information online: an invented Steam, invented services on this computer
$service = Start-Process $node -ArgumentList "`"$desktop\tests\online.mjs`"", '9555', "`"$run\online-log.txt`"" -PassThru -WindowStyle Hidden
Steam $true
foreach ($one in @(@('guide', '1440x900', 'fr'), @('guide', '760x480', 'fr'), @('guide', '1280x720', 'en'))) {
  $tag = "$($one[0])-$($one[1])-$($one[2])-"
  Drive "$desktop\tests\guide.js" @("data=$env:RUNNER_TEMP\data-$tag", "tag=$tag", "size=$($one[1])", "language=$($one[2])", 'online=http://127.0.0.1:9555', 'limit=300')
}
Drive "$desktop\tests\steam.js" @("data=$env:RUNNER_TEMP\data-steam-", 'tag=steam-', 'size=1440x900', 'language=fr', 'limit=400')
Check ((Get-Content "$run\Steam\asked.txt" | Where-Object { $_ -notmatch '^steam://rungameid/[0-9]+/?$' }).Count -eq 0) 'Steam was given numbers, nothing else'
Set-Content "$run\online-log.txt" ''
Drive "$desktop\tests\online.js" @("data=$env:RUNNER_TEMP\data-online-", 'tag=online-', 'size=1440x900', 'language=fr', 'online=http://127.0.0.1:9555', 'limit=420')
# Without anyone answering: the same app, the same library, no error.
Stop-Process $service
Steam $false
Drive "$desktop\tests\offline.js" @("data=$env:RUNNER_TEMP\data-guide-1440x900-fr-", 'tag=offline-', 'size=1440x900', 'language=fr', 'online=http://127.0.0.1:9555')

# --- A second install over the first keeps everything
Install
Drive "$desktop\tests\again.js" @('tag=again-', 'language=fr')

# --- Uninstall
$before = (Get-ChildItem $run -Recurse -File).Count
Uninstall $folder
if (Test-Path $folder) { Get-ChildItem $folder -Recurse | ForEach-Object { Write-Host "left: $($_.FullName.Substring($folder.Length))" } }
Check ($null -eq (& $entry)) 'it is out of the list of installed apps'
$shortcuts = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu", "$env:USERPROFILE\Desktop" -Recurse -Filter 'Oort NX*.lnk' -ErrorAction SilentlyContinue
Check (@($shortcuts).Count -eq 0) 'no shortcut is left'
Check (Test-Path "$own\library.json") 'the library of the player is left'
Check ((Get-ChildItem $run -Recurse -File).Count -eq $before) 'the games are untouched'
subst S: /D
Write-Host "`n$script:failures failures"
if ($script:failures) { exit 1 }
