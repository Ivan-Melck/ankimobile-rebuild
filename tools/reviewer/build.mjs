import { build } from "esbuild";
import { copyFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, "../..");
const output = path.join(root, "ios/Flashcards/Resources");
const fork = path.join(root, "Vendor/anki/ts/routes/image-occlusion");
const css = (await readFile(path.join(fork, "review.scss"), "utf8"))
    .split("\n").filter(line => !/^\s*\/\//.test(line)).join("\n");

await build({
    stdin: { contents: `
      import { imageOcclusionAPI } from ${JSON.stringify(path.join(fork, "review.ts"))};
      window.anki = window.anki || {};
      window.anki.imageOcclusion = imageOcclusionAPI;
      window.anki.setupImageCloze = imageOcclusionAPI.setup;
      const style = document.createElement('style');
      style.textContent = ${JSON.stringify(css)};
      document.head.append(style);
    `, resolveDir: root, sourcefile: "anki-ios-image-occlusion.ts", loader: "ts" },
    bundle: true, platform: "browser", target: ["safari15"], format: "iife",
    conditions: ["browser", "production"], define: {"process.env.NODE_ENV": '"production"'},
    tsconfigRaw: {compilerOptions: {target: "ES2020"}},
    nodePaths: [path.join(directory, "node_modules")],
    outfile: path.join(output, "anki-image-occlusion.js"),
    banner: { js: "// Anki image-occlusion reviewer: Ankitects Pty Ltd and contributors. AGPL-3.0-or-later.\n// Source: Vendor/anki at 96af4ca9d214e71743b1186fd2ceab1a7e7e3f32; adapter: tools/reviewer/build.mjs." },
    plugins: [{ name: "native-reviewer-platform", setup(plugin) {
        // Only the missing-image error uses desktop translation transport.
        // Normal occlusion parsing/drawing is the unmodified upstream source.
        plugin.onResolve({filter: /^(@generated\/ftl|@tslib\/i18n)$/}, args => ({path: args.path, namespace: "mobile-i18n"}));
        plugin.onLoad({filter: /.*/, namespace: "mobile-i18n"}, args => ({
            contents: args.path === "@generated/ftl"
                ? "export const notetypeErrorNoImageToShow = () => 'No image to show.';"
                : "export const ModuleName = {NOTETYPES: 0}; export const setupI18n = async () => {};",
            loader: "js",
        }));
        // Upstream shape classes share editor conversion helpers, but the
        // reviewer draws with CanvasRenderingContext2D. Keep desktop Fabric
        // serialization out of the app; its editing API is not ported yet.
        plugin.onResolve({filter: /^fabric$/}, () => ({path: "editor-only", namespace: "mobile-editor"}));
        plugin.onLoad({filter: /.*/, namespace: "mobile-editor"}, () => ({
            contents: "export const fabric = new Proxy({}, {get(){throw new Error('Desktop canvas conversion is unavailable in the iOS reviewer.')}});",
            loader: "js",
        }));
    }}],
});
await copyFile(path.join(directory, "node_modules/mathjax/es5/tex-svg-full.js"), path.join(output, "anki-mathjax-svg.js"));
await writeFile(path.join(output, "reviewer-asset-licenses.txt"),
    "Anki and this derivative (AGPL-3.0-or-later)\n" + await readFile(path.join(root, "LICENSE"), "utf8") +
    "\nMathJax 3.2.2 (Apache-2.0)\n" + await readFile(path.join(directory, "node_modules/mathjax/LICENSE"), "utf8") +
    "\nSvelte (MIT)\n" + await readFile(path.join(directory, "node_modules/svelte/LICENSE.md"), "utf8") +
    "\nesm-env (MIT)\n" + await readFile(path.join(directory, "node_modules/esm-env/LICENSE"), "utf8"));
