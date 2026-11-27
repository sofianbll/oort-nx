---
name: Oort NX
description: A dark, controller-first game library lit by one Sun.
colors:
  night: "#05070B"
  orbit: "#0C0F15"
  orbit-high: "#11151D"
  frost: "#AFC3E6"
  silver: "#D6DEEA"
  mist: "#98A6BD"
  white: "#FFFFFF"
  sun: "#F4CE8E"
  danger: "#FF6B6B"
  ok: "#3DDC84"
  cloud: "#9CCBFF"
  untested: "#E8B65C"
typography:
  hero: {fontFamily: "Inter", fontSize: "62px", fontWeight: 600}
  screen: {fontFamily: "Inter", fontSize: "40px", fontWeight: 600}
  heading: {fontFamily: "Inter", fontSize: "28px", fontWeight: 600}
  row: {fontFamily: "Inter", fontSize: "22px", fontWeight: 500}
  text: {fontFamily: "Inter", fontSize: "19px", fontWeight: 400}
  badge: {fontFamily: "Inter", fontSize: "16px", fontWeight: 600}
rounded:
  row: "10px"
  content: "12px"
  badge: "14px"
  card: "16px"
  modal: "20px"
  field: "22px"
  dialog: "28px"
spacing:
  hairline: "4px"
  compact: "8px"
  small: "12px"
  medium: "16px"
  large: "24px"
  section: "32px"
  group: "48px"
components:
  key: {backgroundColor: "{colors.orbit-high}", textColor: "{colors.white}", rounded: "{rounded.card}", height: "60px"}
  key-focused: {backgroundColor: "{colors.white}", textColor: "{colors.night}", rounded: "{rounded.card}", height: "60px"}
  row: {backgroundColor: "{colors.orbit}", textColor: "{colors.white}", rounded: "{rounded.card}"}
---

# Oort NX design system

`design/oort.tokens.json` is the only source of values. `scripts/generate_oort_tokens.py` writes the Swift and the CSS; `scripts/check_selene_tokens.py` refuses a literal colour, opacity, size, space, radius, stroke, shadow or animation in a screen. The allowance list is empty and stays empty.

## Overview

**The scene.** Someone on a sofa, lights low, a controller in hand. The night is the room; the cloud is the place; the Sun is the only warm thing in it. The interface is quiet until a hand moves, and the answer is physical: a key sinks, dots rise, one ring travels.

**Three rules decide everything.**

1. *One thing is lit.* Exactly one element holds the focus, and it is the brightest thing on screen.
2. *Nothing is drawn twice.* One key, one row, one panel, one ring, one field. A screen gives content and state; it never styles.
3. *The Sun is alone.* Gold is never a button, a badge, a warning or a price.

Values are in canvas units on a 1920 × 1080 reference. `canvas.u()` scales them to the window and to the player's interface size.

## Colors

| Role | Token | Use |
|---|---|---|
| Night | `scrim` | The ground, and the shade under text |
| Orbit | `glass`, `panelLow/High/Raised` | Panels, computed from the palette so all 27 work |
| White | `focus`, `ink` | Focus and text |
| Frost | `glyph` | The halftone, icons, quiet values |
| Sun | `Art.sun` | The Sun, and nothing else |
| Danger, OK, Cloud, Untested | `Color.*` | States, always with a word or a symbol |

Translucency uses one ramp, `Alpha`: trace, faint, soft, line, mist, shade, half, veil, muted, strong, heavy, near. On artwork, use `artShade` and `artInk` whatever the palette.

Every palette keeps ink on its panels and ground at 4.5:1 or more, and focus and glyph at 3:1 or more. A test checks all of them.

## Typography

Inter, six roles, no other size. `row` is the reading size of a list; `text` explains; `badge` labels. Numbers that change use monospaced digits. A line of prose stays under 75 characters. Headings are sentences, never small capitals above another heading.

## Layout

One scale: 2, 4, 6, 8, 12, 16, 24, 32, 48, then the named measures of a page. Space is tight inside a group and generous between groups, larger above a heading than under it. Lists put the label on the left and the control on the right; the whole line is the target. A settings level is two deep at most.

A page has one title, one list or one stage, and one line of hints. Help is one line at the foot, for the focused row only.

## Elevation & Depth

Four layers: the cloud or the game's art, the stage, panels, floating panels. A panel is lit from above: a vertical gradient and a hairline brighter at the top. Only a floating panel casts a shadow, with an offset. Blur belongs to what covers the stage, never to decoration. Text never sits on a moving cloud without a panel or a shade.

## Shapes

Three families. *Capsules* for tabs, badges and segments. *Fixed* radii for keys, rows and tiles. *Concentric* for anything inside a panel: the inner radius is the panel's radius minus its inset.

## Components

Each lives in `apps/mac/OortMac/Views/OortUI` and shows every state in the Debug gallery.

- **Key** (`SelenePillButton`, `OortButton`): rest, hover, focus, pressed, blocked, busy, queued, destructive, download. Focus turns it solid and raises the halftone. A press sinks it 2 units, by mouse, keyboard or controller.
- **Row** (`SeleneRow` family): value, choice, switch, slider, action, link. One action per row. A pending change shows a mark and the old value.
- **Switch**: off is empty, on is filled with halftone and the thumb on the right, so the state reads without colour.
- **Field** (`OortSearchField`, `OortField`): same grid as the rows around it.
- **Panel** (`oortPanel`): the one surface. `floats` only when it covers something.
- **Dialog** (`SeleneConfirmDialog`, `SeleneChoiceDialog`): a precise title and a safe initial focus. In a pair, Cancel is left and the action is right, including a destructive action. In a row of three, the destructive key is separated on the left. From four choices, stack main first and Cancel last. Destructive text is red and never gets the filled default style. B still leaves the question without performing the action.
- **Ring** (`SeleneTileRing`): one per row of tiles; it glides. White over a dark edge, so it reads on any cover.
- **Tabs**: one pill glides. LB and RB move it.
- **Hints** (`SeleneHintsBar`): the glyphs of the pad in hand, and only actions that work now.
- **Cloud**: the default background. Still under Reduce motion.

Motion has four roles: *press* 60 ms, *quick* 140 ms, *move* 280 ms, *slow* 520 ms. It is interruptible and never delays an action. Reduce motion replaces movement with a 120 ms fade. Sounds follow the same roles; a move climbs a note per step, quieter than everything else.

Controller: A selects, B goes back, X opens details, Y searches or opens options, LB/RB change section, ZL/ZR reach the ends, L3 searches, R3 sorts, a held direction repeats, the right stick scrolls.

## Do's and Don'ts

- Do compose OortUI pieces. Ask for a named preset when one is missing.
- Do keep a visible focus at every moment, and restore it on return.
- Do write what a control does, in the player's language.
- Don't add a second ring, a second gold, a kicker above a heading, a card inside a card, or a bar down one side of a box.
- Don't use a modal for what a row can do, or a toast for what needs an answer.
- Don't stretch a cover, or bake text into an image.
