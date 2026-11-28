# 2026-11-28 — nxnative fork candidate for Oort NX 0.6.0

The previous distributed Mac beta used [`46612553`](https://github.com/sofianbll/nxnative/commit/46612553ee409a7f42549d0533cb76655e72cd77). The candidate is [`29f84a30`](https://github.com/sofianbll/nxnative/commit/29f84a30876f1516bd1dc3c92fcf93ae900785e7), available on the public fork. Existing game apps keep their own engine.

The engine's Metal lock still names `32023.922` with Xcode 27.2. The launcher remains deployable at macOS 26.0; the macOS 26.6 deployment target of the built games is unchanged from the previous fork pin. The runtime keeps `fonttools` 4.67.0: the engine CLI checks the import, and the engine's coverage and lint environments still use 4.67.0 even though its tools lock names 4.68.0. A certified build is the check for a real incompatibility, not the version difference alone.

The merger into the engine fork carries upstream host, shader, input and packaging changes. Synthetic engine checks cover host code, shader translation and save-archive interoperability with the old pin. They do not verify a live cloud, Nextendo peers or a real game. Oort NX adopts no new engine flags or override defaults.

**Still required:** on the actual Mac, confirm the exact pin and certified gate without the untested override. Compile the agreed isolated copy through pipeline archiving, verify the signed game app and log, then ask the maintainer to confirm a visible launch. This does not replace or rebuild an installed game. Do not describe the pin as manually validated until that evidence exists.
