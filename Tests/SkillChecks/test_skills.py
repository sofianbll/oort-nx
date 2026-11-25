"""Structure tests for the public skills in .agents/skills.

These check the file format and the evaluation cases. They do not run a model:
the behaviour in evals/cases.md is judged by hand or by a separate evaluation run.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".agents" / "skills"
REQUIRED_SECTIONS = ("## When to use", "## Steps", "## Proof", "## Stop")
CASE = re.compile(r"^### Case \d+:", re.MULTILINE)
LINK = re.compile(r"\]\((\.[^)#]+)(?:#[^)]*)?\)")
PRIVATE_MARKERS = ("/Users/", "~/Games", "Switch/", "sofian")


def frontmatter(text):
    match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        return None
    fields = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip().strip('"')
    return fields


class SkillFormatTests(unittest.TestCase):
    def skill_dirs(self):
        return sorted(path for path in SKILLS.iterdir() if path.is_dir())

    def test_there_are_seven_public_skills(self):
        self.assertEqual(
            [path.name for path in self.skill_dirs()],
            ["oort-change", "oort-contribute", "oort-core-change", "oort-guides",
             "oort-release", "oort-triage", "oort-visual-change"],
        )

    def test_each_skill_has_matching_frontmatter_and_sections(self):
        for folder in self.skill_dirs():
            with self.subTest(skill=folder.name):
                text = (folder / "SKILL.md").read_text(encoding="utf-8")
                fields = frontmatter(text)
                self.assertIsNotNone(fields, "missing frontmatter")
                self.assertEqual(fields.get("name"), folder.name)
                self.assertTrue(0 < len(fields.get("description", "")) <= 400)
                for section in REQUIRED_SECTIONS:
                    self.assertIn(section, text)
                self.assertLessEqual(len(text.splitlines()), 80, "a skill stays short")

    def test_each_skill_has_three_evaluation_cases_with_expected_behaviour(self):
        for folder in self.skill_dirs():
            with self.subTest(skill=folder.name):
                cases = (folder / "evals" / "cases.md").read_text(encoding="utf-8")
                self.assertEqual(len(CASE.findall(cases)), 3)
                self.assertEqual(cases.count("Input:"), 3)
                self.assertEqual(cases.count("Expected:"), 3)

    def test_relative_links_resolve(self):
        for folder in self.skill_dirs():
            text = (folder / "SKILL.md").read_text(encoding="utf-8")
            for target in LINK.findall(text):
                with self.subTest(skill=folder.name, link=target):
                    self.assertTrue((folder / target).resolve().exists())

    def test_no_private_path_or_name_in_public_skills(self):
        for path in SKILLS.rglob("*.md"):
            text = path.read_text(encoding="utf-8")
            for marker in PRIVATE_MARKERS:
                with self.subTest(file=path.name, marker=marker):
                    self.assertNotIn(marker, text)


if __name__ == "__main__":
    unittest.main()
