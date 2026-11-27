# ADR 0002 · Only an app's entry point imports an engine adapter

**Status: accepted (27/11/2026).** Validated by the maintainer with the target structure.

## Context

[ADR 0001](0001-oort-independant-du-moteur.md) puts every engine behind one interface, in the core module (`OortCore`), with two adapters: nxnative and Ryujinx. It does not say who may import an adapter.

Today the nxnative module (`NxnativeAdapter`, in `engines/nxnative/`) holds the adapter **and** domains that are not about the engine yet: library, store, catalog, launch, cheats, game settings, saves, mods. 141 files of the Mac app import it. While any file of an app can import an adapter, nothing stops a screen from depending on one engine, and adding a second engine means touching those screens.

## Decision

In an app, only its entry point imports an engine adapter. The entry point creates the adapter and hands it to the rest of the app as the core's engine interface. Every other file of the app, the core and the screen renderers use that interface and never import an adapter.

- An app's entry point is declared in [`architecture/names.json`](../../architecture/names.json) (`entry`); for the Mac it is the file that holds `@main` ([`NXLibraryApp.swift`](../../apps/mac/OortMac/NXLibraryApp.swift)).
- [`scripts/check_module_boundaries.py`](../../scripts/check_module_boundaries.py) (rule R2, run by `scripts/check`) refuses an import of a module of kind `engine` from a module of kind `app`, outside its entry point.
- The files that import the adapter today are listed in [`scripts/engine-import-debt.json`](../../scripts/engine-import-debt.json). The list only shrinks: a listed file that no longer imports the adapter must leave the list, and with `--base` a file the base did not list is refused.

## Consequences

- Moving a domain out of `NxnativeAdapter` into `core/` removes its importers from the debt list; the engine lots do this until only the adapter is left.
- The Ryujinx adapter is written in Swift and follows the same rule in the PC companion.
- Changing this decision later would mean letting screens depend on one engine again; the debt list shows how far the code is from it.
