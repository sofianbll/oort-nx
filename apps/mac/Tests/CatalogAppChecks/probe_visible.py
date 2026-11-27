"""Give a screen probe what assertVisible needs (rule R13), written once for every probe that reads rendered text.

text_render() rewrites the shared render function so it saves, beside each PNG, the PDF of the render and keeps the
frame and the same content drawn at once, in the same state, with every text redacted; install() copies ProbeRenderedText.swift with the contrast the
charte requires of text (scripts/generate_oort_tokens.py). The PNGs written are the same as before.
"""
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[3] / "scripts"))
from generate_oort_tokens import TEXT_CONTRAST  # noqa: E402


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"render function changed: {old!r}")
    return text.replace(old, new)


def text_render(render, only=None):
    """`only` is a Swift condition on `name`; texts are kept for those renders alone."""
    render = replace_once(render, "let renderer = ImageRenderer(content: view.frame", "let content = view.frame")
    render = replace_once(render, ".environment(\\.seleneReduceMotion, true))",
                          ".environment(\\.seleneReduceMotion, true)\n        let renderer = ImageRenderer(content: content)")
    save = "try saveProbeText(renderer, hidden: ImageRenderer(content: content.redacted(reason: .placeholder)), beside: imageURL)"
    return replace_once(render, 'try png.write(to: output.appendingPathComponent(name + ".png"))',
                        'let imageURL = output.appendingPathComponent(name + ".png")\n'
                        "        try png.write(to: imageURL)\n"
                        f"        {f'if {only} {{ {save} }}' if only else save}")


def install(app):
    text = (HERE / "ProbeRenderedText.swift").read_text()
    (Path(app) / "ProbeRenderedText.swift").write_text(
        text + f"\nlet probeMinimumContrast = {TEXT_CONTRAST} // scripts/generate_oort_tokens.py TEXT_CONTRAST\n")
