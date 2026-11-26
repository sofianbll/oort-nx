const { execFileSync } = require("node:child_process");
const { mkdtempSync, readFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { createWorker, PSM } = require("tesseract.js");

async function main() {
    const [language, image] = process.argv.slice(2);
    const { langPath } = require(`@tesseract.js-data/${language}`);
    const worker = await createWorker(language, 1, { langPath, cacheMethod: "none" });
    const scratch = mkdtempSync(join(tmpdir(), "oort-ocr-"));
    try {
        const large = join(scratch, "large.png");
        execFileSync("/usr/bin/sips", ["--resampleWidth", "2880", image, "--out", large]);
        await worker.setParameters({ tessedit_pageseg_mode: PSM.SPARSE_TEXT });
        for (const input of [image, large]) {
            const { data: { text } } = await worker.recognize(input);
            console.log(text);
        }
        if (image.split("/").pop().startsWith("jeu-panneau-")) {
            // Read the focus row separately: its patterned background confuses whole-image layout.
            const png = readFileSync(large);
            const width = png.readUInt32BE(16), height = png.readUInt32BE(20);
            const left = Math.round(width * 0.70);
            const lineHeight = Math.round(height * 0.04);
            const top = Math.round(width * 0.195) - Math.floor(lineHeight / 2);
            await worker.setParameters({ tessedit_pageseg_mode: PSM.SINGLE_LINE });
            const { data: { text } } = await worker.recognize(large, {
                rectangle: { left, top, width: width - left, height: lineHeight },
            });
            console.log(text);
        }
    } finally {
        rmSync(scratch, { recursive: true, force: true });
        await worker.terminate();
    }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
