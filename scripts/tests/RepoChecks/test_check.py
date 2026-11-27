import contextlib
import importlib.machinery
import io
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from support import ROOT


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "scripts" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class CheckRunnerTests(unittest.TestCase):
    def test_the_list_names_every_rule_and_its_red_examples(self):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/check"), "--list"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        for rule in ("R1  structure", "R2  boundaries", "R4  generated", "R5  strings", "R8  docs",
                     "R10  publication", "R13  probes"):
            self.assertIn(rule, result.stdout)
        self.assertEqual(result.stdout.count("red examples:"), len(load("check").RULES))

    def test_an_unknown_rule_is_refused(self):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/check"), "nothing"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_one_failing_command_fails_the_run_and_the_others_still_run(self):
        check = load("check")
        ran = []
        check.RULES = [
            ("red", "R0", "fails", lambda base: [[sys.executable, "-c", "raise SystemExit(1)"]], "this test"),
            ("green", "R0", "passes", lambda base: [[sys.executable, "-c", "print('ran')"]], "this test"),
        ]
        original = check.subprocess.run
        check.subprocess.run = lambda command, **kwargs: (
            ran.append(command), original(command, stdout=subprocess.DEVNULL, **kwargs))[1]
        try:
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                self.assertEqual(check.main([]), 1)
                self.assertEqual(check.main(["green"]), 0)
        finally:
            check.subprocess.run = original
        self.assertIn("1/2 rules passed", printed.getvalue())
        self.assertEqual(len(ran), 3)

    def test_the_base_reaches_the_debt_lists(self):
        commands = {name: commands("main") for name, _, _, commands, _ in load("check").RULES}
        self.assertIn(["--base", "main"], [command[-2:] for command in commands["interface"]])
        self.assertIn(["--base", "main"], [command[-2:] for command in commands["docs"]])


class GenerateTests(unittest.TestCase):
    def test_a_stale_output_fails_the_check(self):
        generate = load("generate")
        with tempfile.TemporaryDirectory(prefix="oort-generate-") as temp:
            stale = Path(temp) / "stale.py"
            stale.write_text("import sys\nraise SystemExit(1 if '--check' in sys.argv else 0)\n")
            generate.GENERATORS = [(str(stale), "a source", "an output")]
            with contextlib.redirect_stdout(io.StringIO()) as printed:
                self.assertEqual(generate.main(["--check"]), 1)
                self.assertEqual(generate.main([]), 0)
            self.assertIn("FAILED", printed.getvalue())

    def test_the_repository_outputs_are_current(self):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/generate"), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
