---
name: oort-visual-change
description: Apply the visual criteria of Oort NX to anything a player sees, hears or presses: menus, tabs, screens, texts, icons, motion, sounds, hints, accessibility. Use with oort-change.
---

# Visual change

## When to use

- A screen, panel, dialog, menu, tab, hint, text, picture, motion or sound is added, moved or changed, on any system.

## Steps

1. **Count first (V1–V9).** Write the entries of each menu, bar, tab set and group you touch, with every condition true, and their levels. At most 5 and 2. Over: take away, group, or move to the task. Never a "More" entry.
2. **Is it there already? (V6, V10)** Search [components](../../../docs/working-on-it/components.md), `SettingsCatalog` and the menus. A shortcut to an existing place is a second place.
3. **Capture before (V34).** Each screen, panel and dialog, with the headless probes and synthetic data.
4. **Compose (V10–V16).** OortUI pieces, named presets, tokens, named motions, existing cues. A missing piece: stop and ask for the preset.
5. **Give every action its four paths (V17–V23).** Pointer, keyboard, controller, touch where the system has it; a hint with the right glyph; focus on opening, inside and after closing.
6. **Write every state (V24–V27).** Empty, loading, error, offline, blocked, done. Each one says what is next.
7. **Write the words (V28–V33).** Reuse the key; seven languages and plurals; name, role and value for VoiceOver.
8. **Look.** Open every image, one by one: French, English and the longest language; 80 and 125 %; small window; a light and a dark palette; a white picture behind text; Reduce motion; grey.
9. **Other systems.** Same entries, same order, same words, or the reason why not.

## Proof

- `python3 scripts/check_ui_rules.py --report` and `check_selene_tokens.py --base <base>`, before and after.
- `python3 scripts/check_localizations.py`.
- The table of entries and levels from step 1.
- Captures before and after with their paths, and one line on what each shows.
- What needs a hand: a real pad, VoiceOver, touch, sound.

## Stop

- A sixth entry, a third level, a second gold, a new component, or a piece removed: it is a decision, not a detail.
- A capture shows a cut text, a lost focus or unreadable text: not done.
- Passing scripts say nothing about beauty, order of focus, or speech. Do not claim them.
