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

    def test_a_dialog_with_four_keys_is_refused(self):
        self.write('struct S: View { var body: some View { SeleneChoiceDialog(title: t, choices: [a, b, c, d], focus: $f) } }')
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
