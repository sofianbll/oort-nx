#!/usr/bin/env python3
"""Draw the frozen Integrations screens with the Mac's ScreenView and compare them with the reviewed reference tree.

Links IntegrationScreenProbe.swift against the debug app (run the debug Swift suite first). No window is shown, no
sound plays (OORT_HEADLESS_INPUT), no real data is read. Exit 1 on any difference or text not seen.
"""
import os
from pathlib import Path
import shutil
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from audit_probe_host import run_host  # noqa: E402
from probe_visible import TEXT_CONTRAST  # noqa: E402
import names  # noqa: E402  architecture/names.json (on sys.path from audit_probe_host)


def main():
    os.environ["OORT_HEADLESS_INPUT"] = "1"
    helper = (HERE / "ProbeRenderedText.swift").read_text()
    helper += f"\nlet probeMinimumContrast = {TEXT_CONTRAST} // scripts/generate_oort_tokens.py TEXT_CONTRAST\n"
    with tempfile.TemporaryDirectory(prefix="oort-integration-screens-") as output:
        # The sandbox denies the home, where CI checks the repository out: the frozen screens go beside the output.
        screens = Path(output) / "screens"
        shutil.copytree(names.ROOT / names.test_path("library") / "Screens", screens)
        # OORT_SCREENS_OUTPUT keeps the PNG and PDF of each screen, for a reader.
        keep = os.environ.get("OORT_SCREENS_OUTPUT")
        run_host((HERE / "IntegrationScreenProbe.swift").read_text(), helper, save_model=True, capture=Path(keep or output),
                 environment={"OORT_SCREENS_DIR": str(screens)})


if __name__ == "__main__":
    main()
