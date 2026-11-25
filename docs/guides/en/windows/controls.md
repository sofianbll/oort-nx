---
title: Controller and keyboard
system: windows
topic: controls
order: 7
version: 0.1.0-alpha.2
minutes: 4
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: home, prompts-playstation, search-pad, settings-controllers
---

## The useful buttons
<!-- step keys checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/pad.js -->
Reminders are at the bottom of the screen.

| Action | Xbox | Keyboard |
|---|---|---|
| Play, select | A | Enter |
| Back | B | Esc |
| Details | X | X |
| Search | Y | Y or Ctrl F |
| Grid or spotlight | View | V |
| Change tab | LB / RB | Q / E |
| Sort | Right stick | F3 |
| Settings | Menu | M |
| Full screen | | F11 |

![The home screen with invented games](../../media/windows/home.en.webp)

## Your controller
<!-- step prompts checked f18e2119:desktop/ui/nav.js f18e2119:desktop/tests/pad.js -->
Its name shows at the top left and the reminders take its buttons: Xbox, PlayStation or Nintendo. Checked with simulated controllers, not with a real one yet.

![The PlayStation reminders (picture in French)](../../media/windows/prompts-playstation.fr.webp)

## Type with a controller
<!-- step type checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/pad.js -->
Search opens an on-screen keyboard. **X** erases.

![The on-screen keyboard (picture in French)](../../media/windows/search-pad.fr.webp)

## Change the button names
<!-- step change checked f18e2119:Sources/OortCompanion/SettingRows.swift -->
**Settings › Controllers › Button names**. A game’s own keys are changed in the game.

![Settings › Controllers](../../media/windows/settings-controllers.en.webp)
