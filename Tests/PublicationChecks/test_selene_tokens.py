import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_selene_tokens.py"
SPEC = importlib.util.spec_from_file_location("check_selene_tokens", SCRIPT)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)


class SeleneTokenChecks(unittest.TestCase):
    def test_numeric_arguments_including_multiline_and_scaled(self):
        text = """view.font(
            .system(size: canvas.u(20), weight: .bold))
            .padding(.top,
                -8).padding(12)
            .cornerRadius(6)
        RoundedRectangle(cornerRadius: 8)"""
        self.assertEqual(
            list(check.literals(text)),
            [(".font(.system(size:canvas.u(20", 1), (".padding(.top,-8", 3),
             (".padding(12", 4), ("cornerRadius(6", 5), ("cornerRadius:8", 6)],
        )

    def test_comments_strings_and_token_references_are_not_counted(self):
        text = '''// .seleneFont(12)
        /* .padding(8) */ let source = ".cornerRadius(2)"
        view.seleneFont(.caption).padding(canvas.u(SeleneTokens.Space.small))'''
        self.assertEqual(list(check.literals(text)), [])

    def test_baseline_may_lose_but_not_gain_allowances(self):
        old = {"A.swift": {".padding(4": 3, ".padding(8": 2}}
        self.assertEqual(check.baseline_additions({"A.swift": {".padding(4": 2}}, old), {})
        self.assertEqual(
            check.baseline_additions({"A.swift": {".padding(4": 2, ".padding(12": 1}}, old),
            {"A.swift": {".padding(12": 1}},
        )

    def test_view_styles_and_components_are_detected(self):
        code = """
        struct EmailRow<T: View>: View {}
        let style = Color(red: 0.1, green: 0, blue: 1)
        let view = content.foregroundStyle(.white).opacity(0.3)
            .shadow(color: Palette.ink, radius: canvas.u(4)).font(.caption)
            .animation(.easeIn(duration: 0.2), value: focused)
        let tokens = content.foregroundStyle(SeleneTheme.ink).animation(Motion.focus(reduced), value: focused)
        """
        self.assertEqual([sig.split(":")[0] for sig, _ in check.literals(code, styles=True)],
                         ["component", "color", "color", "opacity", "shadow", "font", "animation"])
        self.assertIn("shadow:.shadow(color:Palette.ink,radius:canvas.u(4))",
                      [sig for sig, _ in check.literals(code, styles=True)])
