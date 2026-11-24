# Download light on tiles — 24 November 2026

`run_download_cloud.py OUTPUT --video` renders the real Spotlight and Collection rows against isolated synthetic covers. It compares the running, settled and reduced-motion pixels with the same rows without particles. At 60% fill, the minimum sRGB contrast for the lit cores against the same render with only its scrim is 4.99:1 on white, 6.42:1 on yellow and 14.82:1 on black. This excludes intentionally fading fringes. The Oort geometry is sampled from the rim, elliptical cut and fans in `scripts/brand_icons.py`.

The two silent video files each contain 360 rendered frames at 60 fps; the stills cover four synthetic artworks, two intensities, scales 1× and 3×, and reduced motion. The title pixels and the artwork after the completion cue match the particle-free reference. The Metal probe reports zero bitmap redraws and no animations after detaching 1, 6 or 12 active tiles.

`run_download_cloud.py OUTPUT --onscreen` uses a local window of twelve 170-point synthetic faces and the production Core Animation layers. It samples process CPU and energy per case after warm-up, once without layers and once after the completion cue removes its layers. The display link verifies a requested cadence separately without waking the process during sampling. This is not a measurement of the energy of the display, WindowServer or GPU.

On the M5 Pro, the window display link returned 60.0 Hz on a 120 Hz display without changing the display mode. For 1, 6 and 12 active tiles in both intensities, process CPU rounded to 0.000% of one core over each eight-second steady-state sample, excluding setup and changes in byte count. The process measured 0.040 mW with no active layers, then 0.051 mW (fine) and 0.042 mW (present) after completion. The window probe confirmed that the cue left no layers running.

The targeted tests and the full Swift suite pass (2,259 reported, three skipped: the engine checkout and disposable case-sensitive APFS are absent). No launcher startup, cloud account, real game or interactive input is exercised. See the [manual checks](../../working-on-it/validation.md).

## Fine front

`run_download_cloud.py OUTPUT --front --video` captures Fine at 0%, 20%, 60% and 95% in Selene and Vantablack at 1× and 3×, on black, white, yellow and busy synthetic covers. The feather measures about 19 points on the 160-point tile; lit cores sampled outside the badge and corners retain at least 3.25:1 against the local background. Reduced motion uses a fixed front; the probe compares it at two timestamps. This pass uses only the targeted porting/cloud tests and tile probes, not the full suite or an interactive session.

## Liquid surface

The two wave heights share a fill mask, the side-faded meniscus and the crest particles. Only the animated download gets a second artwork texture; the art is not drawn again as the wave moves. A confirmed byte update starts a short interpolation from the current surface. After 3.6 s without fresh bytes, there is no animation. An unknown total uses the same motion without a colour mask or a meniscus. The existing completion cue and build progress are separate.

`run_download_cloud.py OUTPUT --front --video` renders the real rows and makes an eight-second silent clip at 60 fps, at 2×, with a start, a steady level, a jump, a stall, verification and the Oort sign. `--lively` chooses the taller option for comparison. `--onscreen` measures 1, 6 and 12 synthetic tile faces in a window; its process CPU and energy figures do not include WindowServer or the GPU. The probe exercises Core Animation separately from the deterministic clip; neither is a manual scroll or input test.

In the two palettes and both heights, the lowest sampled bright-core contrast is 3.80:1 on white; this does not include the intentionally dissolving bubbles. The two porting rows match the baseline PNGs byte for byte in preparation and compilation. At 12 tiles the Metal probe reports a 26 ms setup for the calm wave, zero bitmap redraws during playback and no remaining animation after detaching. The calm window sample used 0.017%, 0.000% and 0.001% of one CPU core at 1, 6 and 12 tiles respectively. The full Swift suite reports 2,261 tests and no failures (three skipped: local engine checks and case-sensitive APFS).

## Continuous calm front

`run_download_cloud.py OUTPUT --front --video` emits 720 silent frames at 60 fps (12 s, 2×), two contact sheets and `niveaux-60hz.csv`. The sequence uses real tile views on two synthetic covers: bursts, pause, resume, verification, then success during the final rise. The level never exceeds the reported value; its largest frame step is 0.414 percentage points and its largest frame-to-frame speed change is 0.608 percentage points/s. Two seconds into the pause, the surface is flat and the level is 47.99% of 48% reported. The mark starts only after the colour reaches the top.

The focused Swift tests also cover an immediate 0→100%, five-second gaps, successive updates in one frame, the restart dissolve and stationary reduced-motion bands. The Metal probe checks no change on byte arrival, no bitmap redraws, and detachment with 1, 6 and 12 tiles. Its initial 12-tile setup takes about 54 ms; no interactive or on-screen measurement is run for this pass.
