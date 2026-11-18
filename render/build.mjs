import { build } from 'esbuild';
import { copyFileSync, cpSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';

const out = '../Kit/Sources/MlisbKit/Resources/render';
rmSync(out, { recursive: true, force: true });
const result = await build({
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'esm',
  splitting: true,
  minify: true,
  outdir: out,
  logLevel: 'warning',
  metafile: true,
});
cpSync('src/index.html', `${out}/index.html`);
const d2 = 'node_modules/@terrastruct/d2/dist/node-esm';
for (const f of ['wasm_exec.js', 'd2.wasm']) copyFileSync(`${d2}/${f}`, `${out}/${f}`);

// Credits for the About window: our notices, then the license of every package that was bundled.
const escape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const packages = new Map();
for (const input of Object.keys(result.metafile.inputs)) {
  const dir = input.match(/^.*node_modules\/(?:@[^/]+\/)?[^/]+/)?.[0];
  if (!dir || packages.has(dir)) continue;
  const { name, version, license } = JSON.parse(readFileSync(`${dir}/package.json`, 'utf8'));
  const file = readdirSync(dir).find(f => /^(licen[sc]e|copying|notice)/i.test(f));
  const text = file ? `<pre>${escape(readFileSync(`${dir}/${file}`, 'utf8'))}</pre>` : '';
  packages.set(dir, { name, html: `<h3>${name} ${version}${license ? ` (${license.type ?? license})` : ''}</h3>${text}` });
}
const list = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name)).map(p => p.html);
writeFileSync('../app/Credits.html', `<html><body style="font: 11px -apple-system">
<pre>${escape(readFileSync('../THIRD-PARTY-NOTICES.md', 'utf8'))}</pre>
<h2>JavaScript packages in the diagram page</h2>
${list.join('\n')}
</body></html>
`);
console.log(`credits: ${list.length} bundled packages`);
