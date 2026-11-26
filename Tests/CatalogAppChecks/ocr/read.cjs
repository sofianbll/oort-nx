const { execFileSync } = require("node:child_process");
const { mkdtempSync, rmSync } = require("node:fs");
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
    } finally {
        rmSync(scratch, { recursive: true, force: true });
        await worker.terminate();
    }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
