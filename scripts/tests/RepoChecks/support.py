"""A throwaway Git repository for the repository checks."""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

MODEL = '''
model {
  repo = repository "fixture" {
    metadata {
      files "README.md LICENSE"
      markdown "yes"
    }
    docs = folder "docs/" {
      metadata {
        path "docs"
        markdown "yes"
      }
      guides = folder "guides/" { metadata { path "docs/guides" } }
    }
    sources = folder "Sources/" {
      metadata { path "Sources" }
      core = folder "Core/" { metadata { path "Sources/Core" } }
    }
    architecture = folder "architecture/" { metadata { path "architecture" } }
    scripts = folder "scripts/" { metadata { path "scripts" } }
  }
}
'''


class Fixture:
    def __init__(self, test):
        temp = tempfile.TemporaryDirectory(prefix="oort-repo-check-")
        test.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.track("architecture/structure.c4", MODEL)
        self.track("README.md", "# Fixture\n")
        self.track("LICENSE", "MIT\n")
        self.track("docs/guides/start.md", "Start.\n")
        self.track("Sources/Core/Core.swift", "struct Core {}\n")
        self.track("scripts/private-markers.json", '{"markers": ["/Users/"], "allowed": {}}\n')

    def track(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        subprocess.run(["git", "add", "--", name], cwd=self.root, check=True)

    def commit(self):
        subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@users.noreply.github.com",
                        "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], cwd=self.root, check=True)
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()
