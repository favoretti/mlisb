import mermaid from 'mermaid';

const FONT = '-apple-system, system-ui, sans-serif';
const stage = document.getElementById('stage');

// d2's own Worker wrapper overflows the wasm stack in WKWebView, so run its Go/WASM here
// (wasm_exec.js is a classic script, see index.html).
globalThis.global = globalThis;
const d2Ready = (async () => {
  const go = new Go();
  const { instance } = await WebAssembly.instantiateStreaming(fetch('d2.wasm'), go.importObject);
  go.run(instance);
  while (!globalThis.d2) await new Promise((r) => setTimeout(r, 5));
})();
async function d2call(method, arg) {
  await d2Ready;
  const r = JSON.parse(await globalThis.d2[method](JSON.stringify(arg)));
  if (r.error) {
    // d2 reports syntax errors as a JSON array of {errmsg}.
    let msg = r.error.message;
    try { msg = JSON.parse(msg).map((e) => e.errmsg).join('\n'); } catch {}
    throw new Error(msg);
  }
  return r.data;
}
let seq = 0;

async function renderMermaid(source, theme) {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    suppressErrorRendering: true,
    theme: theme === 'dark' ? 'dark' : 'default',
    fontFamily: FONT,
    flowchart: { htmlLabels: false, useMaxWidth: false },
    sequence: { useMaxWidth: false },
  });
  const host = document.createElement('div');
  document.body.append(host);
  try {
    const { svg } = await mermaid.render(`m${++seq}`, source, host);
    return svg;
  } finally {
    host.remove();
    document.getElementById(`dm${seq}`)?.remove();
  }
}

async function renderD2(source, theme) {
  const options = { layout: 'dagre', themeID: theme === 'dark' ? 200 : 0, pad: 16, noXMLTag: true };
  const compiled = await d2call('compile', { fs: { index: source }, options });
  const b64 = await d2call('render', { diagram: compiled.diagram, options: { ...compiled.renderOptions, scale: 1 } });
  return new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
}

// Natural size from the viewBox; both renderers otherwise emit fit-to-width SVG.
function normalize(svgText) {
  const doc = new DOMParser().parseFromString(svgText, 'image/svg+xml');
  const svg = doc.documentElement;
  if (svg.localName !== 'svg') throw new Error('renderer did not produce an SVG');
  const [, , w, h] = svg.getAttribute('viewBox').split(/[\s,]+/).map(Number);
  svg.setAttribute('width', w);
  svg.setAttribute('height', h);
  svg.style.removeProperty('max-width');
  svg.style.background = 'transparent';
  // d2 paints a full-canvas background rect first.
  const bg = svg.querySelector('rect.fill-N7');
  if (bg && parseFloat(bg.getAttribute('width')) === w && parseFloat(bg.getAttribute('height')) === h) bg.remove();
  return { svg: new XMLSerializer().serializeToString(svg), width: w, height: h };
}

let queue = Promise.resolve();

window.mlisb = {
  render(lang, source, theme) {
    const run = async () => {
      stage.replaceChildren();
      const raw = lang === 'd2' ? await renderD2(source, theme) : await renderMermaid(source, theme);
      const out = normalize(raw);
      stage.innerHTML = out.svg;
      // d2 embeds its font as a data: URL; a snapshot taken before it loads has no text.
      stage.getBoundingClientRect();
      await document.fonts.ready;
      return out;
    };
    const p = queue.then(run);
    queue = p.catch(() => {});
    return p;
  },
};
