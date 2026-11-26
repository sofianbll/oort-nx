"""Every rule of check_ui_rules.py must refuse a bad change and accept its good twin.

The trees are synthetic, except where a real menu of the app is copied and one entry is added to it.
"""
import copy
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.dont_write_bytecode = True
import check_ui_rules as ui  # noqa: E402

REAL = json.loads((ROOT / "scripts/ui-rules.json").read_text(encoding="utf-8"))
EMPTY = {"surfaces": [], "openers": [], "values": {}, "english": [], "keyboard_paths": {}, "unmeasured": {}, "allowed": {}}
VIEW = "Sources/NXLibrary/Views/Screen/Sample.swift"


class Case(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="oort-ui-rules-"))
        self.addCleanup(shutil.rmtree, self.root)

    def write(self, text, relative=VIEW):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def catalog(self, *keys, **same):
        entry = {"localizations": {language: {"stringUnit": {"state": "translated", "value": "x"}} for language in ui.LANGUAGES}}
        strings = {key: copy.deepcopy(entry) for key in keys}
        for language, key in same.items():
            strings[key] = copy.deepcopy(entry)
            strings[key]["localizations"][language]["stringUnit"]["value"] = key
        self.write(json.dumps({"strings": strings}), ui.CATALOG)

    def found(self, rule, **rules):
        found, _ = ui.scan(self.root, {**EMPTY, **rules})
        return [item for item in found.items if item[0] == rule]


class Lexer(unittest.TestCase):
    def test_comments_and_strings_are_blank_and_interpolated_code_stays(self):
        source = ui.Source('let a = "x // \\(call("in")) )" // Button {\n/* Menu( /* nested */ */ let b = #"raw " quote"#\nlet c = """\nMenu {\n"""')
        self.assertIn("call(", source.code)
        self.assertNotIn("Button", source.code)
        self.assertNotIn("Menu", source.code)
        self.assertEqual([value for _, _, value, _ in source.strings][-2:], ['raw " quote', "\nMenu {\n"])

    def test_only_the_cases_of_the_enum_itself_count(self):
        self.assertEqual(ui.cases('case a, b = "x"\nvar t: Int { switch self { case .a: return 1\ncase .b: return 2 } }\ncase c(Int)'), ["a", "b", "c"])


class Menus(Case):
    def test_six_entries_are_refused_and_five_are_not(self):
        rules = {"surfaces": [{"id": "menu", "count": "enum:Kind"}]}
        self.write("enum Kind: CaseIterable { case a, b, c, d, e }", "Sources/NXLibraryCore/Kind.swift")
        self.assertEqual(self.found("menu-size", **rules), [])
        self.write("enum Kind: CaseIterable { case a, b, c, d, e, f, g }", "Sources/NXLibraryCore/Kind.swift")
        self.assertEqual(len(self.found("menu-size", **rules)), 2)

    def test_each_group_and_the_number_of_groups_are_counted(self):
        rules = {"surfaces": [{"id": "settings", "count": "groups:Category.groups"}]}
        groups = "(nil, [.a, .b, .c, .d, .e, .f]), " + ", ".join('("x", [.a])' for _ in range(5))
        self.write(f"enum Category {{ static let groups: [(String?, [Self])] = [{groups}] }}", "Sources/NXLibraryCore/Category.swift")
        self.assertEqual([item[2] for item in self.found("menu-size", **rules)], ["settings (groups)", "settings (group 1)"])

    def test_a_third_level_is_refused(self):
        self.write("enum Kind { case a }", "Sources/NXLibraryCore/Kind.swift")
        rules = {"surfaces": [{"id": "one", "count": "enum:Kind"}, {"id": "two", "count": "enum:Kind", "parent": "one"},
                              {"id": "three", "count": "enum:Kind", "parent": "two"}]}
        self.assertEqual([item[2] for item in self.found("menu-depth", **rules)], ["three"])

    def test_an_undeclared_list_is_refused(self):
        self.write("struct S: View { var body: some View { ForEach(Kind.allCases) { _ in EmptyView() } } }")
        self.assertEqual(len(self.found("menu-unregistered")), 1)
        self.assertEqual(self.found("menu-unregistered", values={"Kind": "values"}), [])

    def test_a_native_menu_and_a_context_menu_are_refused_until_declared(self):
        self.write('struct S: View { var body: some View { Menu { x } label: { y } ; z.contextMenu { x } } }')
        self.assertEqual(sorted(item[2] for item in self.found("menu-unregistered")), ["Menu", "contextMenu"])

    def test_a_tab_literal_with_six_items_is_refused(self):
        items = ", ".join(f".init(id: {index}, title: t)" for index in range(6))
        self.write(f"struct S: View {{ var body: some View {{ OortTabs(items: [{items}], selected: 0) {{ _ in }} }} }}")
        self.assertEqual(len(self.found("menu-size")), 1)

    def test_a_surface_that_left_the_sources_is_refused(self):
        self.write("enum Other { case a }", "Sources/NXLibraryCore/Other.swift")
        self.assertEqual(len(self.found("menu-unregistered", surfaces=[{"id": "gone", "count": "enum:Kind"}])), 1)
        self.assertEqual(self.found("menu-unregistered", surfaces=[{"id": "ios", "count": "enum:Kind", "system": "ios"}]), [])

    def test_a_row_that_opens_an_undeclared_list_is_refused(self):
        self.write("enum Row { case a, b\n var opens: Bool { [.a, .b].contains(self) } }", "Sources/NXLibraryCore/Row.swift")
        opener = {"type": "Row", "member": "opens", "opens": {"a": "declared"}}
        self.assertEqual([item[2] for item in self.found("menu-unregistered", openers=[opener])], ["Row.b"])

    def test_a_dialog_can_stack_four_or_five_keys_but_not_six(self):
        dialog = 'SeleneChoiceDialog(title: t, choices: [%s], focus: $f)'
        for choices in ["a, b, c, d", "a, b, c, d, e"]:
            self.write(dialog % choices)
            self.assertEqual(self.found("dialog-size"), [])
        self.write(dialog % "a, b, c, d, e, f")
        self.assertEqual(len(self.found("dialog-size")), 1)


class RealMenus(Case):
    """The app's own files, with one entry too many."""

    def mutate(self, relative, old, new):
        text = (ROOT / relative).read_text(encoding="utf-8")
        self.assertIn(old, text)
        self.write(text.replace(old, new, 1), relative)

    def sizes(self):
        found = ui.Findings()
        ui.check_menus(ui.Tree(self.root), REAL, found, [])
        return [item[2] for item in found.items if item[0] == "menu-size"]

    def test_a_sixth_icon_in_the_control_center(self):
        self.mutate("Sources/NXLibraryCore/Selene/MenuSelectionModel.swift", "power, activityCenter, settings", "power, activityCenter, settings, extra")
        self.assertIn("control-center", self.sizes())

    def test_a_sixth_default_tab(self):
        self.mutate("Sources/NXLibraryCore/Library/LibraryFilter.swift", "[.all, .installed, .cloud, .favorites]",
                    "[.all, .installed, .cloud, .favorites, .recentlyPlayed, .notPlayed]")
        self.assertIn("library-tabs", self.sizes())

    def test_a_sixth_settings_category_in_a_group(self):
        self.mutate("Sources/NXLibraryCore/Settings/SettingsCategory.swift", "[.home, .library, .switch, .saves, .cloudLibrary]",
                    "[.home, .library, .switch, .saves, .cloudLibrary, .logs]")
        self.assertIn("settings (group 3)", self.sizes())

    def test_the_library_card_of_the_control_center_grows(self):
        self.mutate("Sources/NXLibraryCore/Selene/MenuSelectionModel.swift", "[.addGame, .manageSources, .refreshLibrary, .gameInbox]",
                    "[.addGame, .manageSources, .refreshLibrary, .gameInbox, .theme, .myProfile]")
        self.assertIn("control-center cards (.library)", self.sizes())


class Texts(Case):
    def test_a_key_missing_from_the_catalog_is_refused(self):
        self.catalog("Known")
        self.write('let a = L10n.text("Known"); let b = L10n.text("Never translated")')
        self.assertEqual([item[2] for item in self.found("untranslated")], ["Never translated"])

    def test_a_literal_that_never_goes_through_l10n_is_refused(self):
        self.catalog()
        self.write('struct S: View { var body: some View { Text("Hello there"); Text("\\(count) / 3"); Text(verbatim: "x y") } }')
        self.assertEqual([item[2] for item in self.found("untranslated")], ["Hello there"])

    def test_a_key_given_to_a_component_is_looked_up(self):
        self.catalog("Back")
        self.write('let a = HintItem(.b, "Back"); let b = HintItem(.x, "Send now"); OortButton(title: "Try again")')
        self.assertEqual(sorted(item[2] for item in self.found("untranslated")), ["Send now", "Try again"])

    def test_identifiers_and_names_are_left_alone(self):
        self.catalog()
        self.write('let q = DispatchQueue(label: "NXLibrary.Sample.save"); let n = Row(title: "Selene")')
        self.assertEqual(self.found("untranslated", english=["Selene"]), [])

    def test_a_translation_that_repeats_english_is_refused(self):
        self.catalog(fr="Remove every copy from this folder")
        self.assertEqual(len(self.found("same-as-english")), 1)


class Styles(Case):
    def test_literal_measures_are_refused_and_tokens_are_not(self):
        self.write("let a: CGFloat = 96\nx.frame(width: canvas.u(70)).offset(y: 6)\ny.frame(width: canvas.u(SeleneTokens.Space.small), height: 0)")
        self.assertEqual(sorted(item[2] for item in self.found("measure")), [".offset(y:6", "canvas.u(70)", "leta:CGFloat=96"])

    def test_a_shape_drawn_in_a_screen_is_refused_and_not_in_the_library(self):
        shape = "RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(c)"
        self.write(shape)
        self.write(shape, "Sources/NXLibrary/Views/OortUI/OortPiece.swift")
        self.assertEqual([item[1] for item in self.found("shape")], [VIEW])


class Access(Case):
    def test_a_picture_only_button_needs_a_label(self):
        bad = 'struct S: View { @FocusState var focus: Int?\n var body: some View { Button { go() } label: { Image(systemName: "xmark") } } }'
        self.write(bad)
        self.assertEqual(len(self.found("a11y-label")), 1)
        self.write(bad.replace('"xmark") }', '"xmark") }\n.accessibilityLabel(close)'))
        self.assertEqual(self.found("a11y-label"), [])

    def test_a_tap_needs_a_role_and_a_veil_does_not(self):
        tap = "struct S: View { var body: some View { Tile(a)\n.onTapGesture { open() }%s } }"
        self.write(tap % "")
        self.assertEqual(len(self.found("a11y-tap")), 1)
        self.write(tap % "\n.accessibilityAddTraits(.isButton)")
        self.assertEqual(self.found("a11y-tap"), [])
        self.write("struct S: View { var body: some View { SeleneTheme.scrim45.onTapGesture { close() } } }")
        self.assertEqual(self.found("a11y-tap"), [])

    def test_the_role_may_be_on_the_tile_itself(self):
        self.write("struct Tile: View { var body: some View { x.accessibilityAddTraits(.isButton) } }\n"
                   "struct S: View { var body: some View { Tile(a)\n.onTapGesture { open() } } }")
        self.assertEqual(self.found("a11y-tap"), [])

    def test_a_view_that_takes_clicks_needs_a_focus(self):
        self.write("struct S: View { var body: some View { Button(title) { go() } } }")
        self.assertEqual([item[2] for item in self.found("pointer-only")], ["S"])
        self.write("struct S: View { let focused: Bool; var body: some View { Button(title) { go() } } }")
        self.assertEqual(self.found("pointer-only"), [])

    def test_a_controller_only_hint_names_its_keyboard_path(self):
        self.write("hint.controllerOnly = true")
        self.assertEqual(len(self.found("pad-only")), 1)
        self.assertEqual(self.found("pad-only", keyboard_paths={VIEW: {"hints": 1, "keys": "⌘F"}}), [])

    def test_a_loop_reads_reduce_motion(self):
        self.write("x.animation(Motion.loop.repeatForever(), value: y)")
        self.assertEqual(len(self.found("motion")), 1)
        self.write("if !reduceMotion { x.animation(Motion.loop.repeatForever(), value: y) }")
        self.assertEqual(self.found("motion"), [])


class Debt(unittest.TestCase):
    def test_debt_may_shrink_but_not_grow(self):
        before = {"measure": {"a.swift": {"canvas.u(3)": 2}}}
        self.assertFalse(ui.grown({"measure": {"a.swift": {"canvas.u(3)": 1}}}, before))
        self.assertTrue(ui.grown({"measure": {"a.swift": {"canvas.u(3)": 3}}}, before))
        self.assertTrue(ui.grown({"shape": {"a.swift": {"Circle().fill": 1}}}, before))

    def test_the_tree_matches_its_debt_list_exactly(self):
        found, _ = ui.scan(ROOT, REAL)
        self.assertEqual(found.counts(), REAL["allowed"])


class ButtonOrder(Case):
    def row(self, first, second):
        self.write(f"struct S: View {{ var body: some View {{ HStack {{ {first}\n {second} }} }} }}")
        return [item[2] for item in self.found("button-order")]

    def test_a_way_back_after_the_main_button_is_refused(self):
        main = 'SelenePillButton(title: "Done", focused: true) { save() }'
        back = 'SelenePillButton(title: "Cancel", focused: false) { close() }'
        self.assertEqual(self.row(main, back), ["row Cancel"])
        self.assertEqual(self.row(back, main), [])

    def test_a_way_back_named_by_its_focus_is_seen(self):
        self.assertEqual(len(self.row("pill(.primary, title, action: save)", "pill(.cancel, other, action: close)")), 1)
        self.assertEqual(self.row("pill(.cancel, other, action: close)", "pill(.primary, title, action: save)"), [])

    def test_a_dialog_with_cancel_last_is_refused(self):
        dialog = 'struct S: View { var body: some View { SeleneChoiceDialog(title: t, choices: [a, b], focus: $f, cancelIndex: %s) } }'
        for index in ("1", "list.count"):
            self.write(dialog % index)
            self.assertEqual(len(self.found("button-order")), 1, index)
        self.write(dialog % "0")
        self.assertEqual(self.found("button-order"), [])

    def test_what_erases_may_stand_before_the_way_back(self):
        dialog = 'struct S: View { var body: some View { SeleneChoiceDialog(title: t, choices: [a, b, c], focus: $f, cancelIndex: %s, destructive: [0]) } }'
        self.write(dialog % "1")
        self.assertEqual(self.found("button-order"), [])
        self.write(dialog % "2")
        self.assertEqual(len(self.found("button-order")), 1)

    def test_a_destructive_pair_cannot_put_cancel_on_the_right(self):
        dialog = 'SeleneChoiceDialog(choices: [a, b], focus: $f, cancelIndex: %s, destructive: [%s])'
        for back, danger, count in [(0, 1, 0), (1, 0, 1)]:
            self.write(dialog % (back, danger))
            self.assertEqual(len(self.found("button-order")), count)

    def test_four_choices_stack_with_cancel_at_the_bottom(self):
        dialog = 'SeleneChoiceDialog(choices: [a, b, c, d], focus: $f, cancelIndex: %s)'
        for back, count in [(3, 0), (0, 1)]:
            self.write(dialog % back)
            self.assertEqual(len(self.found("button-order")), count)

    def test_left_cannot_focus_confirm_in_a_binary_dialog(self):
        self.write('let next: SeleneConfirmButton = action == .navigateLeft ? .confirm : .cancel')
        self.assertEqual(len(self.found("button-order")), 1)
        self.write('let next: SeleneConfirmButton = action == .navigateLeft ? .left : .right')
        self.assertEqual(self.found("button-order"), [])

    def test_the_back_hint_on_the_right_is_refused(self):
        bar = "struct S: View {{ var body: some View {{ SeleneHintsBar({0}, bottom: 0) }} }}"
        self.write(bar.format('right: [HintItem(.a, "Select"), HintItem(.b, "Back")]'))
        self.assertEqual([item[2] for item in self.found("button-order")], ["hint B on the right"])
        self.write(bar.format('left: [HintItem(.b, "Back")], right: [HintItem(.a, "Select")]'))
        self.assertEqual(self.found("button-order"), [])

    def test_a_known_row_out_of_order_or_gone_is_refused(self):
        rules = {"button_rows": [{"id": "piece", "file": VIEW, "scope": "enum Side", "order": [r"= Self\.cancel", r"= Self\.confirm"], "why": "x"}]}
        self.write("enum Side { case cancel, confirm\n static let left = Self.confirm\n static let right = Self.cancel }")
        self.assertEqual([item[2] for item in self.found("button-order", **rules)], ["piece"])
        self.write("enum Side { case cancel, confirm\n static let left = Self.cancel\n static let right = Self.confirm }")
        self.assertEqual(self.found("button-order", **rules), [])
        self.write("enum Side { case cancel }")
        self.assertEqual([item[2] for item in self.found("button-order", **rules)], ["gone:piece"])


class FocusDanger(Case):
    def notice(self, title, first, **rules):
        self.write(f'func ask() {{ app.showSettingsNotice(title: t, message: m, actionTitle: {title}, primaryFirst: {first}) {{ go() }} }}')
        return self.found("focus-danger", **rules)

    def test_a_notice_that_starts_on_the_trash_is_refused(self):
        self.assertEqual(len(self.notice('L10n.text("Move to Trash")', "true")), 1)
        self.assertEqual(self.notice('L10n.text("Move to Trash")', "false"), [])
        self.assertEqual(self.notice('"Download"', "true"), [])

    def test_a_computed_answer_in_focus_needs_a_reason(self):
        self.assertEqual(len(self.notice("title", "true")), 1)
        self.assertEqual(self.notice("title", "true", safe_focus={f"{VIEW}::title": "removes nothing"}), [])

    def test_a_confirmation_that_starts_on_delete_is_refused(self):
        view = ('struct S: View {{ @State var focus: SeleneConfirmButton = .{0}\n var body: some View {{ '
                'SeleneConfirmDialog(title: t, message: m, confirmTitle: "Delete", focus: $focus, onCancel: a, onConfirm: b) }} }}')
        self.write(view.format("confirm"))
        self.assertEqual(len(self.found("focus-danger")), 1)
        self.write(view.format("cancel"))
        self.assertEqual(self.found("focus-danger"), [])

    def test_a_loss_said_in_the_message_counts(self):
        self.write('struct S: View { @State var focus: SeleneConfirmButton = .confirm\n var body: some View { '
                   'SeleneConfirmDialog(title: t, message: L10n.text("Unsaved progress will be lost."), confirmTitle: "Close", focus: $focus) } }')
        self.assertEqual(len(self.found("focus-danger")), 1)

    def test_an_explicitly_destructive_move_cannot_default_to_confirm(self):
        self.write('struct S: View { @State var focus: SeleneConfirmButton = .confirm\n var body: some View { '
                   'SeleneConfirmDialog(title: t, message: m, confirmTitle: "Move", destructive: true, focus: $focus) } }')
        self.assertEqual(len(self.found("focus-danger")), 1)

    def test_a_choice_that_starts_on_discard_is_refused(self):
        view = ('struct S: View {{ @State var focus = {0}\n var body: some View {{ '
                'SeleneChoiceDialog(title: t, choices: ["Keep editing", "Discard"], focus: $focus, cancelIndex: 0) }} }}')
        self.write(view.format(1))
        self.assertEqual(len(self.found("focus-danger")), 1)
        self.write(view.format(0))
        self.assertEqual(self.found("focus-danger"), [])


class KeyboardPath(Case):
    SECTION = "Sources/NXLibrary/Views/Settings/SettingsSampleSection.swift"

    def section(self, rows):
        self.write('struct S: View { var body: some View { Button("Change", action: change)\n '
                   'Button("Reveal") { model.reveal(url: path) } }\n '
                   f'private func publishActions() {{ onActions([{rows}]) }} }}', self.SECTION)
        return [item[2] for item in self.found("keyboard-path")]

    def test_a_settings_button_no_row_presses_is_refused(self):
        self.assertEqual(self.section('.init(id: "a", activate: change)'), ["button Reveal"])
        self.assertEqual(self.section('.init(id: "a", secondary: ("Reveal", { model.reveal(url: path) }), activate: change)'), [])

    def test_a_row_help_opened_by_click_only_is_refused(self):
        component = ui.LIBRARY + "SeleneSettingsRow.swift"
        self.write('struct S: View { var body: some View { SeleneRow("Engine", info: "Why") { x } } }', self.SECTION)
        self.write("struct SeleneRow: View { var body: some View { SeleneInfoTip(info) } }", component)
        self.assertEqual([item[2] for item in self.found("keyboard-path")], ["help Engine"])
        self.write("struct SeleneRow: View { var body: some View { SeleneInfoTip(info, isShowing: shown) } }", component)
        self.assertEqual(self.found("keyboard-path"), [])

    def test_return_without_the_keypad_enter_is_refused(self):
        self.write("func key(_ code: Int) { switch code { case 36, 49: confirm()\n default: break } }")
        self.assertEqual(len(self.found("keyboard-path")), 1)
        self.write("func key(_ code: Int) { switch code { case 36, 76, 49: confirm()\n case 36, 125: break\n default: break } }")
        self.assertEqual(self.found("keyboard-path"), [])

    def test_a_link_inside_a_dialog_is_refused(self):
        dialog = "struct S: View {{ var body: some View {{ SeleneConfirmDialog(title: t, onCancel: a, onConfirm: b) {{ {0} }} }} }}"
        self.write(dialog.format('Button("Get a key") { open() }'))
        self.assertEqual([item[2] for item in self.found("keyboard-path")], ["dialog Get a key"])
        self.write(dialog.format("Text(note)"))
        self.assertEqual(self.found("keyboard-path"), [])

    def test_a_button_without_a_shortcut_among_shortcuts_is_refused(self):
        view = 'struct S: View {{ var body: some View {{ Button("Close") {{ a() }}.keyboardShortcut(.cancelAction)\n Button("Start") {{ b() }}{0} }} }}'
        self.write(view.format(""))
        self.assertEqual([item[2] for item in self.found("keyboard-path")], ["shortcut Start"])
        self.write(view.format('.keyboardShortcut("s")'))
        self.assertEqual(self.found("keyboard-path"), [])

    def test_a_declared_action_whose_key_is_gone_is_refused(self):
        keys = "Sources/NXLibrary/Views/Screen/Sample+Input.swift"
        rules = {"action_paths": [{"id": "more", "click": [VIEW, "Read more"], "key": [keys, r"expanded\.toggle"], "why": "x"}]}
        self.write('struct S { let a = "Read more" }')
        self.write("extension S { func handle() { move() } }", keys)
        self.assertEqual([item[2] for item in self.found("keyboard-path", **rules)], ["more"])
        self.write("extension S { func handle() { expanded.toggle() } }", keys)
        self.assertEqual(self.found("keyboard-path", **rules), [])


class MousePath(Case):
    def hints(self, hint, extra="", **rules):
        self.write(f"struct S: View {{ var body: some View {{ SeleneHintsBar(left: [{hint}]{extra}) }} }}")
        return [item[2] for item in self.found("mouse-path", **rules)]

    def test_an_action_only_a_hint_offers_is_refused_until_its_other_place_is_named(self):
        hint = 'HintItem(.x, "Delete", action: remove)'
        self.assertEqual(self.hints(hint), ["x Delete"])
        self.assertEqual(self.hints(hint, mouse_paths={VIEW: {"x Delete": "the row's button"}}), [])

    def test_a_hint_nobody_can_click_is_refused_and_a_pressing_bar_is_not(self):
        self.assertEqual(self.hints('HintItem(.rs, "Sort")'), ["rs Sort"])
        self.assertEqual(self.hints('HintItem(.rs, "Sort")', extra=", press: handle"), [])
        self.assertEqual(self.hints('HintItem(.a, "Select")'), [])

    def test_a_declared_place_whose_hint_is_gone_is_refused(self):
        self.assertEqual(len(self.hints('HintItem(.a, "Select")', mouse_paths={VIEW: {"x Delete": "a button"}})), 1)


class Debt(unittest.TestCase):
    def test_a_new_rule_declares_its_debt_once_and_a_known_one_cannot_grow(self):
        before = {"measure": {"a": {"x": 1}}}
        now = {"measure": {"a": {"x": 2}}, "mouse-path": {"a": {"y": 1}}}
        known = ui.judged('''"""Rules\n\n  measure            a literal size\n"""\n''')
        self.assertEqual(known, {"measure"})
        self.assertEqual(dict(ui.grown(now, before, known)), {("measure", "a", "x"): 1})
        self.assertEqual(len(ui.grown(now, before)), 2)


class RealButtons(Case):
    """The app's own files: today's gaps are all declared, and each rule sees one more."""

    def copy(self, relative, old=None, new=None):
        text = (ROOT / relative).read_text(encoding="utf-8")
        if old:
            self.assertIn(old, text)
            text = text.replace(old, new, 1)
        self.write(text, relative)

    def signatures(self, check):
        found = ui.Findings()
        check(ui.Tree(self.root), {**REAL, "button_rows": [], "action_paths": [], "mouse_paths": {}}, found)
        return [item[2] for item in found.items]

    def test_swapping_cancel_after_search_in_the_mod_search(self):
        panel = "Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift"
        self.copy(panel)
        self.assertEqual(self.signatures(ui.check_order), [])
        self.copy(panel, 'SelenePillButton(title: "Cancel", focused: false, action: close)\n',
                  'SelenePillButton(title: "Go", focused: false, action: close)\n SelenePillButton(title: "Cancel", focused: false, action: close)\n')
        self.assertEqual(self.signatures(ui.check_order), ["row Cancel"])

    def test_a_trash_confirmation_that_starts_on_the_answer(self):
        panel = "Sources/NXLibrary/Views/GameOptions/ModsPanel.swift"
        self.copy(panel, "var confirmFocus: SeleneConfirmButton = .cancel", "var confirmFocus: SeleneConfirmButton = .confirm")
        self.assertEqual(self.signatures(ui.check_focus), ["confirm confirmFocus"])

    def test_a_key_row_removed_from_the_engine_settings(self):
        section = "Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift"
        self.copy(section)
        before = self.signatures(ui.check_keyboard)
        self.copy(section, 'isEnabled: !configurationLocked, activate: recheck)', 'isEnabled: !configurationLocked, activate: {})')
        self.assertEqual(len(self.signatures(ui.check_keyboard)), len(before) + 1)


class Skills(unittest.TestCase):
    """The three skills, the criteria and the checks name each other, so none can drift alone."""
    FOLDER = ROOT / ".agents/skills"
    CRITERIA = (ROOT / "docs/working-on-it/change-criteria.md").read_text(encoding="utf-8")
    NAMES = ("oort-change", "oort-visual-change", "oort-core-change")

    def text(self, name):
        return (self.FOLDER / name / "SKILL.md").read_text(encoding="utf-8")

    def rows(self):
        return dict(re.findall(r"^\| ([GVC]\d+) \| (.+) \|$", self.CRITERIA, re.MULTILINE))

    def test_criteria_have_one_row_each_with_check_source_and_reason(self):
        identifiers = re.findall(r"^\| ([GVC]\d+) \|", self.CRITERIA, re.MULTILINE)
        self.assertEqual(len(identifiers), len(set(identifiers)))
        for identifier, row in self.rows().items():
            with self.subTest(criterion=identifier):
                cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", row)]
                self.assertEqual(len(cells), 4, "criterion, check, source, reason")
                self.assertTrue(all(cells))

    def test_each_criterion_is_in_a_skill_and_each_skill_names_only_real_ones(self):
        used = set()
        for name in self.NAMES:
            for first, last in re.findall(r"\b([GVC]\d+)(?:–([GVC]?\d+))?", self.text(name)):
                low, high = int(first[1:]), int(re.sub(r"\D", "", last or first))
                used |= {f"{first[0]}{number}" for number in range(low, high + 1)}
        self.assertEqual(used, set(self.rows()))

    def test_every_rule_of_the_check_is_explained_and_every_rule_named_exists(self):
        rules = set(re.findall(r"^  ([a-z0-9-]+)  +\S", ui.__doc__, re.MULTILINE))
        named = set(re.findall(r"`rule:([a-z0-9-]+)`", self.CRITERIA))
        self.assertEqual(named, rules)
        source = (ROOT / "scripts/check_ui_rules.py").read_text(encoding="utf-8")
        self.assertEqual(set(re.findall(r'found\.add\("([a-z0-9-]+)"', source)), rules)

    def test_skills_are_short_complete_and_public(self):
        for name in self.NAMES:
            with self.subTest(skill=name):
                text = self.text(name)
                self.assertRegex(text, rf"\A---\nname: {name}\ndescription: .{{40,400}}\n---\n")
                for section in ("## When to use", "## Steps", "## Proof", "## Stop"):
                    self.assertIn(section, text)
                self.assertLessEqual(len(text.splitlines()), 80)
                cases = (self.FOLDER / name / "evals/cases.md").read_text(encoding="utf-8")
                self.assertEqual((len(re.findall(r"^### Case \d+:", cases, re.MULTILINE)), cases.count("Input:"), cases.count("Expected:")), (3, 3, 3))
                for private in ("/Users/", "~/Games", "Switch/", "sofian", ".scratch"):
                    self.assertNotIn(private, text + cases)

    def test_relative_links_resolve(self):
        for path in [self.FOLDER / name / "SKILL.md" for name in self.NAMES] + [ROOT / "docs/working-on-it/change-criteria.md"]:
            for target in re.findall(r"\]\((\.{0,2}[^)#:]+)(?:#[^)]*)?\)", path.read_text(encoding="utf-8")):
                with self.subTest(file=path.name, link=target):
                    self.assertTrue((path.parent / target).resolve().exists())


if __name__ == "__main__":
    unittest.main()
