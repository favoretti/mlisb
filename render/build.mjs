import { build } from 'esbuild';
import { copyFileSync, cpSync, rmSync } from 'node:fs';

const out = '../Kit/Sources/MlisbKit/Resources/render';
rmSync(out, { recursive: true, force: true });
await build({
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'esm',
  splitting: true,
  minify: true,
  outdir: out,
  logLevel: 'warning',
});
cpSync('src/index.html', `${out}/index.html`);
const d2 = 'node_modules/@terrastruct/d2/dist/node-esm';
for (const f of ['wasm_exec.js', 'd2.wasm']) copyFileSync(`${d2}/${f}`, `${out}/${f}`);
