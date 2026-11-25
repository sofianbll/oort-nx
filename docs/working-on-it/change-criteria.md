# Criteria for a change

One list, for every change to Oort NX. G applies to all, V to anything a player sees or hears, C to logic. Each row says how to check it, where it comes from and why it exists. Skills: [oort-change](../../.agents/skills/oort-change/SKILL.md) picks the list, [oort-visual-change](../../.agents/skills/oort-visual-change/SKILL.md) and [oort-core-change](../../.agents/skills/oort-core-change/SKILL.md) apply it.

- `rule:…` is a rule of `python3 scripts/check_ui_rules.py`. It stops what is new. What was there before is in `allowed` in [ui-rules.json](../../scripts/ui-rules.json), which may only shrink.
- "Look" means a capture that someone opened. "Try" means a hand on the real device. A green script replaces neither.
- "Decision" is the maintainer's, with its date. Guides were read at their source on 25 November 2026.

## Every change

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| G1 | The need is one sentence, the scope is the smallest that meets it. | Pull request text | [AGENTS.md](../../AGENTS.md), Product value | An idea from elsewhere is an input, not a task. |
| G2 | Nothing is lost: no feature, language, field, shortcut or setting leaves without a decision. | List of actions, texts and shortcuts before and after | [PRODUCT.md](../../PRODUCT.md), Positioning; decision, 24 Nov 2026 | Oort improves what is there. |
| G3 | What the maintainer validated keeps working. | [validation.md](validation.md) read, regression check named | [AGENTS.md](../../AGENTS.md), Preserve validation | A passed test does not repeat a hand's approval. |
| G4 | Every service stays optional, off until chosen; no account, lock or data collection. | Diff read | [PRODUCT.md](../../PRODUCT.md), Constraints | Firm product rule. |
| G5 | Each of the five systems is marked same, adapted, or not concerned, with the reason. | Table in the pull request | Decision, 25 Nov 2026 | One product, several hands. |
| G6 | One thing keeps one word: the existing catalog key is reused before a new one. | Search of the catalog | [HIG Writing](https://developer.apple.com/design/human-interface-guidelines/writing), Build language patterns | Two words read as two things. |
| G7 | File map, area page, flows, validation and Unreleased notes change in the same commit. | Diff read | [AGENTS.md](../../AGENTS.md), Documentation | The next session trusts the docs. |
| G8 | Fixtures and captures are synthetic: no game, key, save, personal path or account. | `check_publication.py`, look | [AGENTS.md](../../AGENTS.md), Non-negotiables | The repository is public. |
| G9 | Reused work names its author and licence; a new dependency has a reason, a licence and a lock. | `NOTICE`, `runtime.lock` | [CONTRIBUTING.md](../../CONTRIBUTING.md) | Others' work stays theirs. |
| G10 | The pull request says what was run, what was seen, what was not tried. | Pull request text | [AGENTS.md](../../AGENTS.md), Verification | Implemented, verified and confirmed differ. |

## Visual: how much, and where

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| V1 | At most 5 entries in a menu, bar, tab set, segmented choice, card or group, counted with every condition true. | `rule:menu-size` | Decision, 25 Nov 2026; [HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus) (about five), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) (five or fewer), [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls) | A long list hides the entry one wants. |
| V2 | At most 2 levels to choose from, then the page. A dialog, or a file, colour or picture picker the system draws, is not a level. | `rule:menu-depth` | [HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [NN/g](https://www.nngroup.com/articles/progressive-disclosure/) | Past two levels people get lost. |
| V3 | A new list is declared as a surface, as values, or as not measured, with its reason. | `rule:menu-unregistered` | This list | A count no one declared is never checked. |
| V4 | More than five: up to 5 named groups of up to 5. A settings page holds 15 rows at most. Only the player's own content, or a list of values, is longer. | Look, count | [HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus), Menu length; [Android settings](https://source.android.com/docs/core/settings/settings-guidelines) | Grouping keeps a list readable without hiding it. |
| V5 | The most used entry is first; the order is fixed; only the player reorders. | Look | [HIG Menus](https://developer.apple.com/design/human-interface-guidelines/menus), Organization | A list that moves by itself is relearned each time. |
| V6 | One place for each setting and action. A task's option sits with the task. | Search of `SettingsCatalog` | [HIG Settings](https://developer.apple.com/design/human-interface-guidelines/settings); [conventions](conventions.md) §4 | A second copy disagrees one day. |
| V7 | A tab or a menu bar command stays and says why it cannot run; a context menu hides it. | Look at the blocked state | [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) | Stable places are learned. |
| V8 | On the Mac, a command is also in the menu bar; a standard shortcut keeps its meaning. | Look, `NXLibraryApp.swift` | [HIG Menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) | It is where people search, and Full Keyboard Access reads it. |
| V9 | A dialog asks one question: a precise title, at most 3 keys named by verbs, the safe one focused, B and Esc leave. Never to inform, never at launch. | `rule:dialog-size`, look | [DESIGN.md](../../DESIGN.md); [HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) | It stops the player. |

## Visual: how it is made

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| V10 | An existing piece first. A screen gives content and state; a missing preset is asked for, not drawn. | [components.md](components.md) read; `rule:shape` | [DESIGN.md](../../DESIGN.md), Nothing is drawn twice | One repair then reaches every screen. |
| V11 | No literal colour, opacity, size, space, radius, stroke, shadow, duration or curve in a screen. | `check_selene_tokens.py`, `rule:measure` | [DESIGN.md](../../DESIGN.md) | A value no token holds cannot follow a palette or a zoom. |
| V12 | Gold is the Sun only; a cover is never a page's ground; only a floating panel casts a shadow; no card in a card. | Look | [PRODUCT.md](../../PRODUCT.md), Brand; [DESIGN.md](../../DESIGN.md) | The charter is improved, not replaced. |
| V13 | Text over art or a moving cloud has a panel or a shade, measured at its worst place. | Look on a white picture | [DESIGN.md](../../DESIGN.md), Elevation | Any picture may come. |
| V14 | Motion takes a named role, can be interrupted, delays no action. Loops run in Core Animation or Metal. | Look; [conventions](conventions.md) §3 | [DESIGN.md](../../DESIGN.md); [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion) | The answer is physical, never a wait. |
| V15 | Reduce motion shows the final state; Reduce transparency and Increase contrast are followed. | `rule:motion`, capture with each on | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Movement makes some people ill. |
| V16 | A sound uses an existing cue, is quieter for a move, can be turned off, and repeats something seen. | Try, sound off | [PRODUCT.md](../../PRODUCT.md); [HIG Playing audio](https://developer.apple.com/design/human-interface-guidelines/playing-audio) | Many play muted. |

## Visual: how it is used

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| V17 | Pointer, keyboard and controller reach every action; touch too where the system has it. | `rule:pointer-only`, try each | [PRODUCT.md](../../PRODUCT.md), Accessibility; [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls) | No one owns every input. |
| V18 | Hints show only what works now, with the glyph of the pad in hand; a controller-only hint names its keyboard path. | `rule:pad-only`, look with each pad | [DESIGN.md](../../DESIGN.md), Hints; [HIG Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls) | A false hint is worse than none. |
| V19 | A selects, B goes back, X details, Y searches or options, L/R sections, ZL/ZR ends, a held direction repeats. | [keymap.md](../how-it-works/keymap.md), probe | [DESIGN.md](../../DESIGN.md), Controller | A button that changes role breaks the hand's memory. |
| V20 | One visible focus at all times, restored on return; a still pointer does not take it; moving it changes nothing. | Probe, look | [DESIGN.md](../../DESIGN.md), One thing is lit; [HIG Focus](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection) | On a sofa, focus is the pointer. |
| V21 | No trap: a slider or a list lets go; every item is reachable; about six presses cross the screen. | Try | [Microsoft gamepad](https://learn.microsoft.com/en-us/windows/apps/design/input/gamepad-and-remote-interactions) | A stuck focus ends the session. |
| V22 | A target is at least 28 pt on the Mac, 44 pt by touch (20 and 28 for minor ones). | Look | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Small targets are missed. |
| V23 | Nothing that must be read leaves on a timer. | Look | [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), Cognitive | People read at their own pace. |

## Visual: what it says

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| V24 | Empty, loading, error and offline are four different states; each says what is next and keeps Back working. | Capture of each | [HIG Writing](https://developer.apple.com/design/human-interface-guidelines/writing), [Loading](https://developer.apple.com/design/human-interface-guidelines/loading), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) | An empty list after a failed read is a lie. |
| V25 | An error says what failed, what is intact if that is known, and what to do, next to its cause. | Look | [HIG Writing](https://developer.apple.com/design/human-interface-guidelines/writing), [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) | A code is not help. |
| V26 | A warning only for a loss that is unexpected and cannot be undone. Otherwise act, and offer the way back. | Look | [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) | Warnings that always come are not read. |
| V27 | Settings are a draft: preview at once, Save, Leave without saving or Keep editing on the way out. An action with a real effect is confirmed on its own. | Probe | Decision, 24 Nov 2026 | One rule for every setting. |
| V28 | Every text goes through the catalog, in the seven languages, with its plurals. | `rule:untranslated`, `rule:same-as-english`, `check_localizations.py` | [PRODUCT.md](../../PRODUCT.md); [conventions](conventions.md) §7 | A raw key is English for everyone. |
| V29 | A button is a verb; a section is a thing in one or two words; help says the effect; sentences, not capitals. | Look, read aloud | [HIG Writing](https://developer.apple.com/design/human-interface-guidelines/writing); [DESIGN.md](../../DESIGN.md) | Words are the interface. |
| V30 | It holds in German and French, at 80 and 125 %, in a small window; nothing is cut without another way to read it. | Captures | [PRODUCT.md](../../PRODUCT.md); [Xbox guideline 101](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101) | Long words break layouts. |
| V31 | Only the six text roles. 4.5:1 for text, 3:1 for shapes and focus, in every palette. | Palette tests, look | [DESIGN.md](../../DESIGN.md); [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | Read from a sofa, in any palette. |
| V32 | A state is a word or a shape, never colour or sound alone. | Capture in grey | [PRODUCT.md](../../PRODUCT.md); [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Not everyone sees or hears it. |
| V33 | VoiceOver gets a name, a role and a value; decoration is hidden; the layer below a dialog is silent. | `rule:a11y-label`, `rule:a11y-tap`, try | [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover) | A picture has no words of its own. |
| V34 | Each changed screen, panel and dialog was captured before and after, with focus, in French and English, and every image opened. | Captures in the pull request | [AGENTS.md](../../AGENTS.md), UI gate | A build does not prove a look. |

## Core

| ID | Criterion | Check | Source | Why |
|---|---|---|---|---|
| C1 | The contract comes first: inputs, outputs, errors, owner, and each reader of a changed key, format, case or notification. | Search for every reader, listed | [AGENTS.md](../../AGENTS.md), milestones | A key changed on one side hid the games' art until a player saw it. |
| C2 | A test fails before the change, for the right reason, and passes after. | Both outputs | [conventions](conventions.md) §9 | A test that never failed proves nothing. |
| C3 | Tests use synthetic data, temporary folders and injected transports, and try the failures: cancel, full disk, offline, late answer. | Diff read | [conventions](conventions.md) §9 | The happy path is the one that worked already. |
| C4 | Code is in the lowest module that can hold it; imports go down only; OortCore imports Foundation and Swift only. | `check_oort_core.py`, `check_module_boundaries.py` where it exists | [conventions](conventions.md) §1 | Five systems share the bottom. |
| C5 | `AppViewModel` does not grow; a screen's state has its own model. | Diff read | [conventions](conventions.md) §1 | One coordinator cannot be understood. |
| C6 | An older file opens, unknown fields and cases survive, a downgrade is refused or safe. | Test with the previous version's file | [conventions](conventions.md) §5 | A library is never lost. |
| C7 | A write is temporary, checked, then swapped in; one writer per file; an unreadable file is kept and reported. | Test that interrupts it | [conventions](conventions.md) §5 | Power fails in the middle. |
| C8 | Removing goes to the Trash; a replacement is verified before the old one leaves. | Test | [conventions](conventions.md), Cestino | The original is the way back. |
| C9 | Paths and preferences come from `AppData`; no test or probe opens the real domain. | Test of profile boundaries | [conventions](conventions.md) §5, §9 | A rehearsal once read real preferences. |
| C10 | Errors are typed, reach the player, and name the next step. Nothing is swallowed. | Test per error | [AGENTS.md](../../AGENTS.md), diagnose | A silent error is found by a player. |
| C11 | The work can be cancelled, interrupted and resumed at each step; a queue survives a restart. | Test per step | [conventions](conventions.md), Confini dei dati | Long work meets a closed lid. |
| C12 | No network the player did not ask for. Hosts are listed, sizes bounded, redirects refused; offline uses what is kept. | Transport that counts calls: zero before consent | [conventions](conventions.md) §6; [PRODUCT.md](../../PRODUCT.md) | Local means local. |
| C13 | What is read, written and sent is named, and bounded to the account and folder chosen. A reference stays read-only. | Test that refuses the neighbour | [conventions](conventions.md), Cloud personale | Access given for one thing is not access. |
| C14 | Keys and tokens: mode 0600, never in a log, URL, setting, fixture or report. | `check_publication.py`, test | [AGENTS.md](../../AGENTS.md), Non-negotiables | A log travels. |
| C15 | No new concurrency warning; a new `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` has a line that proves it. | Build with complete checking, before and after | [Swift 6 migration](https://www.swift.org/migration/documentation/migrationguide/) | A data race is not seen in a test. |
| C16 | Files, network and processes run off the main thread; a late result checks its identity; a view body reads no file. | Test with a late answer | [conventions](conventions.md) §8 | A result for another game must not appear. |
| C17 | Operations that exclude each other pass through `SaveOperationGate`. | Test of both orders | [conventions](conventions.md) §8 | Play during a restore destroys a save. |
| C18 | What comes from outside is bounded and refused when odd: sizes, counts, paths, links, archives. | Negative tests | [conventions](conventions.md) §2, §6 | A file is an input from a stranger. |
| C19 | A performance claim has a measure before and after, on the same data. | Dated note in history/reviews | [AGENTS.md](../../AGENTS.md), Optimize | A feeling is not a number. |
| C20 | Saved raw values, row ids, `DM_*` names and bundle ids do not change and are not translated. | Test that reads the old value | [conventions](conventions.md) §7 | Others wrote them down. |
| C21 | An engine is an exact commit, never a branch; its checkout is not patched; Oort works without it. | Diff read | [AGENTS.md](../../AGENTS.md), Non-negotiables | Newer is not tested. |
| C22 | No delay, redraw or reset that hides a cause; no new warning in a release build. | Build output, diff read | [AGENTS.md](../../AGENTS.md); [conventions](conventions.md) §8, §9 | A patch on a symptom comes back. |
| C23 | The way back is written: what a player does, and what happens to data made since. | Pull request text | [PRODUCT.md](../../PRODUCT.md), Constraints | A release meets machines no one tried. |

## Conflicts already settled

| Between | Kept | Because |
|---|---|---|
| Quick panel of six, Android's 10 to 15 rows, HIG's "about five" | Five to choose from; 15 rows on a settings page (V1, V4) | The decision of 25 November is later. A page of settings is not a menu. |
| HIG Alerts puts the main key last; the fork puts it first | First, with the safe key focused (V9) | Validated choice, same in every dialog. |
| HIG reserves Home; Oort opens its control center with it | Home, unless macOS keeps it; + held otherwise | Decision, 24 Nov 2026. macOS 27 lets the player decide. |
| HIG: Menu opens settings; Oort: + opens the item's options | Options (V19) | Same as Xbox, documented by Microsoft. The Arcane layout stays a choice. |
| Simple settings apply at once; settings are a draft | The draft, with preview (V27) | Decision, 24 Nov 2026. |
| HIG: no own copy of a system setting; Oort has Reduce motion | Either one is enough to turn it on (V15) | The console player may not know the system's. |
| HIG: no motion on frequent acts; Oort's ring glides | The glide, short and interruptible (V14) | Decision, 25 Nov 2026. |
| A gold focus ring was proposed; gold is the Sun's | White ring with a dark edge (V12, V20) | Charter. |

## Conflicts that wait for the maintainer

Until then a change keeps what is there, and says so.

| Question | Facts |
|---|---|
| "Five" for the Settings sidebar | Four groups of at most five pass V4, but the sidebar shows sixteen names. |
| Address in French | The catalog speaks as *vous* in 522 texts (228 by the pronoun, 294 by a verb in -ez) and says *tu* in 4; the voice guide proposes *tu*. |
| Text at three metres | [Xbox guideline 101](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101) asks for 26 px at 1080p; the roles are 16, 19 and 22. Text to 200 % is not built. |
| Typeface | [DESIGN.md](../../DESIGN.md) says Inter; the app draws the system font. |
| Session card | It leaves after eight seconds, against V23. |
| Branch names | [AGENTS.md](../../AGENTS.md) asks for `bium/`, and for topic prefixes in the fork block. |
| Number of languages | [conventions](conventions.md) §3 says six, the catalog has seven. |
