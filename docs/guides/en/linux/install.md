---
title: Install
system: linux
topic: install
order: 1
version: 0.1.0-alpha.2
minutes: 5
tried: Tried on a fresh GitHub machine (Ubuntu 24.04), with invented games and an invented Steam. Never on a player’s computer.
captures: missing:release-page, missing:checksum, missing:apt-install, setup-welcome
---

## Download
<!-- step download code f18e2119:desktop/src-tauri/tauri.conf.json https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2 -->
Take `Oort-NX-Linux-0.1.0-alpha.2-x64.deb` and `SHA256SUMS` from the [release page](https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2). You need a 64-bit Linux that reads .deb packages; only Ubuntu 24.04 was tried.

<!-- missing release-page: The release page on GitHub, files unfolded. -->

## Compare the checksum
<!-- step checksum code f18e2119:desktop/tests/linux/prove.sh https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.2 -->
In the download folder, `sha256sum -c SHA256SUMS --ignore-missing` must answer OK. Otherwise, delete the file.

<!-- missing checksum: The terminal with the checksum and its answer. -->

## Install the package
<!-- step run checked f18e2119:desktop/tests/linux/prove.sh -->
In the download folder: `sudo apt install ./Oort-NX-Linux-0.1.0-alpha.2-x64.deb`. The libraries it needs come with it.

<!-- missing apt-install: The terminal while the .deb installs. -->

## Open Oort NX
<!-- step open checked f18e2119:desktop/tests/linux/prove.sh -->
It is in the applications menu. The guided setup opens; you can skip it.

![The guided setup, page 1 (captured on Windows)](../../media/windows/setup-welcome.en.webp)
