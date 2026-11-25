---
title: Install
system: windows
topic: install
order: 1
version: 0.1.0-alpha.2
minutes: 5
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: missing:release-page, missing:checksum, missing:smartscreen, missing:installer, setup-welcome
---

## Download
<!-- step download code f18e2119:desktop/src-tauri/tauri.conf.json https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2 -->
Take `Oort-NX-Windows-0.1.0-alpha.2-x64-setup.exe` and `SHA256SUMS` from the [release page](https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2). You need 64-bit Windows 10 or 11; Windows 10 was not tried.

<!-- missing release-page: The release page on GitHub, files unfolded. -->

## Compare the checksum
<!-- step checksum code f18e2119:desktop/tests/windows/prove.ps1 https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2 -->
In PowerShell, `Get-FileHash Oort-NX-Windows-0.1.0-alpha.2-x64-setup.exe` must give the line of `SHA256SUMS`. If it differs, delete the file.

<!-- missing checksum: The terminal with the checksum and its answer. -->

## Go past the warning
<!-- step warning code f18e2119:desktop/tests/windows/prove.ps1 https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2 -->
The installer is not signed: Windows shows “Windows protected your PC”. Choose **More info**, then **Run anyway**, only for this checked file.

<!-- missing smartscreen: The SmartScreen window, before and after “More info”. -->

## Follow the installation
<!-- step run checked f18e2119:desktop/tests/windows/prove.ps1 -->
It installs for your account, without administrator rights. If WebView2 is missing, the installer takes Microsoft’s; that case was not tried.

<!-- missing installer: The installer windows, one by one. -->

## Open Oort NX
<!-- step open checked f18e2119:desktop/tests/windows/prove.ps1 -->
It is in the Start menu. The guided setup opens; you can skip it.

![The guided setup, page 1](../../media/windows/setup-welcome.en.webp)
