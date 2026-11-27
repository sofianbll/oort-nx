"""Read the repository's declared layout from architecture/structure.c4.

The model is the one place that lists the folders, the root files and the folders that may hold documentation.
check_structure.py and check_docs.py read it through these functions only.
"""
import re
import subprocess
from pathlib import Path

MODEL = "architecture/structure.c4"
COMMENT = re.compile(r"(?m)(?:^|(?<=[ \t]))//[^\n]*|/\*.*?\*/", re.DOTALL)
METADATA = re.compile(r"\bmetadata\s*\{([^{}]*)\}")
FIELD = re.compile(r"\b(path|files|markdown)\s+(?:\"([^\"]*)\"|'([^']*)')")


class Layout:
    def __init__(self, folders, files, markdown):
        self.folders = folders      # every declared folder path, first and second level
        self.files = files          # declared root files
        self.markdown = markdown    # folders whose files may include documentation


def read_layout(root):
    text = COMMENT.sub("", (Path(root) / MODEL).read_text(encoding="utf-8"))
    folders, files, markdown = set(), set(), set()
    for block in METADATA.findall(text):
        fields = {key: double or single for key, double, single in FIELD.findall(block)}
        if "path" in fields:
            folders.add(fields["path"])
            if fields.get("markdown") == "yes":
                markdown.add(fields["path"])
        elif "files" in fields:
            files.update(fields["files"].split())
            if fields.get("markdown") == "yes":
                markdown.add("")
    return Layout(folders, files, markdown)


def tracked(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    return [name for name in names if name]


def renamed(root, ref):
    """Tracked paths renamed since REF, old -> new, as Git detects them. Debt lists keyed by path are read through
    it when compared with a base, so that a moved file keeps its entry."""
    out = subprocess.check_output(["git", "diff", "-M", "--name-status", "--diff-filter=R", "-z", ref, "--"],
                                  cwd=root).decode().split("\0")
    moved, fields = {}, [field for field in out if field]
    for i in range(0, len(fields) - 2, 3):
        moved[fields[i + 1]] = fields[i + 2]
    return moved
