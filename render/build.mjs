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

// The third-party notices, opened from Help as a read-only document: our notices, then the license of
// every package that was bundled. The About panel only points there; its credits view cannot be resized.
const fenced = text => {
  const fence = '`'.repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map(m => m[0].length + 1)));
  return `${fence}text\n${text.trimEnd()}\n${fence}`;
};
const packages = new Map();
for (const input of Object.keys(result.metafile.inputs)) {
  const dir = input.match(/^.*node_modules\/(?:@[^/]+\/)?[^/]+/)?.[0];
  if (!dir || packages.has(dir)) continue;
  const { name, version, license } = JSON.parse(readFileSync(`${dir}/package.json`, 'utf8'));
  const file = readdirSync(dir).find(f => /^(licen[sc]e|copying|notice)/i.test(f));
  const text = file ? `\n\n${fenced(readFileSync(`${dir}/${file}`, 'utf8'))}` : '';
  packages.set(dir, { name, md: `### ${name} ${version}${license ? ` (${license.type ?? license})` : ''}${text}` });
}
const list = [...packages.values()].sort((a, b) => a.name.localeCompare(b.name)).map(p => p.md);
writeFileSync('../app/Third-Party Notices.md', `${readFileSync('../THIRD-PARTY-NOTICES.md', 'utf8').trimEnd()}

## JavaScript packages in the diagram page

Generated from the packages bundled into the diagram page when this copy of mlisb was built.

${list.join('\n\n')}
`);
writeFileSync('../app/Credits.html', `<html><body style="font: 11px -apple-system; text-align: center">
Third-party notices and licenses: <b>Help → Third-Party Notices</b>.
</body></html>
`);
console.log(`notices: ${list.length} bundled packages`);
