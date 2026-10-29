// Dev-only behaviour check for `waymark view` (not part of tests/run.sh).
// Drives headless Chrome (or Edge) over the DevTools Protocol with Node's built-in
// WebSocket and fetch. No npm dependencies. Selects by ids and roles only.
//
//   node tests/browser/check-viewer.mjs [--html <built viewer>] [--keep]
//
// Without --html it builds the viewer from tests/fixtures/viewer-layer (plus a CRLF file).
import { spawn, execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, cpSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..', '..');
const args = process.argv.slice(2);
const argOf = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const fwd = (p) => p.replace(/\\/g, '/');

const browsers = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
];
const browser = browsers.find((b) => existsSync(b));
if (!browser) { console.error('no Chrome/Edge found'); process.exit(2); }

const tmp = mkdtempSync(join(tmpdir(), 'wm-view-'));
function build(layer, out) {
  execFileSync('bash', [fwd(join(repo, 'bin', 'waymark')), 'view', '--no-open', '--out', fwd(out)],
    { env: { ...process.env, WAYMARK_ROOT: fwd(layer) }, stdio: ['ignore', 'ignore', 'inherit'] });
}
let htmlPath = argOf('--html');
const fixtureFiles = ['decisions.md', 'docs/arabic.md', 'docs/crlf.md', 'docs/script-tag.md', 'docs/waymark/x.md', 'gotchas.md'];
if (!htmlPath) {
  const layer = join(tmp, 'layer');
  cpSync(join(repo, 'tests', 'fixtures', 'viewer-layer'), layer, { recursive: true });
  writeFileSync(join(layer, 'docs', 'crlf.md'), '---\r\ntitle: Crlf\r\n---\r\n\r\n# Crlf file\r\n\r\ntext\r\n');
  htmlPath = join(tmp, 'v.html');
  build(layer, htmlPath);
}
const emptyLayer = join(tmp, 'empty');
mkdirSync(emptyLayer);
writeFileSync(join(emptyLayer, 'layer.conf'), 'version=1\n');
const emptyHtml = join(tmp, 'empty.html');
build(emptyLayer, emptyHtml);

const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn(browser, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${join(tmp, 'profile')}`,
  '--no-first-run', '--no-default-browser-check', '--disable-gpu', 'about:blank'], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws; let nextId = 1; const pending = new Map(); const problems = [];
async function connect() {
  for (let i = 0; i < 100; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = list.find((t) => t.type === 'page');
      if (page) {
        ws = new WebSocket(page.webSocketDebuggerUrl);
        await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = bad; });
        ws.onmessage = (m) => {
          const d = JSON.parse(m.data);
          if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
          else if (d.method === 'Runtime.exceptionThrown') problems.push(d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text);
          else if (d.method === 'Runtime.consoleAPICalled' && d.params.type === 'error') problems.push(d.params.args.map((a) => a.value ?? a.description).join(' '));
        };
        return;
      }
    } catch { /* browser not ready */ }
    await sleep(100);
  }
  throw new Error('could not connect to browser');
}
const send = (method, params = {}) => new Promise((ok) => { const id = nextId++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });
async function ev(expr) {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'eval failed');
  return r.result.result.value;
}
async function until(expr, ms = 15000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { try { if (await ev(`!!(${expr})`)) return true; } catch { /* page navigating */ } await sleep(100); }
  return false;
}
async function load(path) {
  await send('Page.navigate', { url: pathToFileURL(path).href });
  await until(`document.readyState === 'complete' && document.getElementById('wm-article') && document.getElementById('wm-article').dataset.state !== 'loading'`);
}
async function key(k) {
  for (const type of ['keyDown', 'keyUp']) await send('Input.dispatchKeyEvent', { type, key: k, text: type === 'keyDown' ? k : undefined });
}
async function typeQuery(q) {
  await ev(`(() => { const i = document.getElementById('wm-q'); i.value = ${JSON.stringify(q)}; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  await sleep(350); // search input is debounced
}

let failed = 0;
const report = (ok, name, extra = '') => { if (!ok) failed++; console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${!ok && extra ? ' -- ' + extra : ''}`); };

try {
  await connect();
  await send('Runtime.enable'); await send('Page.enable');

  // 1. tree
  await load(htmlPath);
  const treePaths = await ev(`Array.from(document.querySelectorAll('#wm-tree a[data-path]')).map(a => a.dataset.path).sort()`);
  report(JSON.stringify(treePaths) === JSON.stringify(fixtureFiles), 'tree shows all fixture files', JSON.stringify(treePaths));
  await ev(`(() => { const f = document.getElementById('wm-filter'); f.value = 'arab'; f.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  report((await ev(`document.querySelectorAll('#wm-tree a[data-path]').length`)) === 1, 'tree filter narrows by name');
  await ev(`(() => { const f = document.getElementById('wm-filter'); f.value = ''; f.dispatchEvent(new Event('input', { bubbles: true })); })()`);

  // 2. search "mermaid" via the "/" key
  await ev(`document.body.focus()`);
  await key('/');
  report(await ev(`!document.getElementById('wm-search').hidden`), 'slash key opens search panel');
  await typeQuery('mermaid');
  const hit = await ev(`(() => { const li = document.querySelector('#wm-results li[data-path="docs/waymark/x.md"]');
    return li ? { n: document.querySelectorAll('#wm-results li').length, title: li.querySelector('[data-role=title]').textContent, snippet: li.querySelector('[data-role=snippet]').textContent, marks: li.querySelectorAll('mark').length } : null; })()`);
  report(!!hit && /mermaid/i.test(hit.snippet) && hit.snippet.length <= 125 && hit.marks > 0 && hit.title === 'Waymark design notes',
    'search "mermaid" finds nested doc with snippet', JSON.stringify(hit));
  await typeQuery('capture flow');
  report((await ev(`document.querySelectorAll('#wm-results li').length`)) === 1, 'multi-word AND search');

  // 3. ID jump
  await typeQuery('G-0001');
  await until(`location.hash.endsWith(':G-0001')`);
  const jump = await ev(`({ hash: decodeURIComponent(location.hash), target: document.querySelector('[data-target]')?.textContent || '', hidden: document.getElementById('wm-search').hidden })`);
  await until(`document.querySelector('[data-target]')`);
  const target = await ev(`document.querySelector('[data-target]')?.id`);
  report(jump.hash === '#gotchas.md:G-0001' && target === 'entry-G-0001' && jump.hidden, 'search G-0001 jumps to the entry', JSON.stringify({ jump, target }));

  // 4. mermaid renders
  await ev(`location.hash = '#docs/waymark/x.md'`);
  const mm = await until(`document.querySelector('#wm-body figure[data-mermaid] svg')`, 30000);
  report(mm, 'mermaid diagram renders to svg', JSON.stringify(await ev(`document.getElementById('wm-article').innerText.slice(0, 300)`)));
  const hdr = await ev(`({ expired: !!document.querySelector('#wm-entry-header [data-state=expired]'), title: document.querySelector('#wm-entry-header h1')?.textContent })`);
  report(hdr.expired && hdr.title === 'Waymark design notes', 'frontmatter header shows expired valid_until', JSON.stringify(hdr));
  report(await ev(`!!document.querySelector('#wm-body a[data-entry-link="G-0001"]')`), 'ID token becomes a link');

  // 5. </script> file renders as text, nothing executes
  await ev(`location.hash = '#docs/script-tag.md'`);
  await until(`document.getElementById('wm-article').dataset.path === 'docs/script-tag.md'`);
  const st = await ev(`({ text: document.getElementById('wm-body').innerText, pwned: window.__pwned === true,
    scripts: document.querySelectorAll('#wm-body script').length, onerror: !!document.querySelector('#wm-body [onerror]') })`);
  report(st.text.includes('</script>') && st.text.includes('<!-- not a comment -->') && !st.pwned && !st.scripts && !st.onerror,
    '</script> file renders as text and is sanitised', JSON.stringify(st));

  // 6. Arabic
  await ev(`location.hash = '#docs/arabic.md'`);
  await until(`document.getElementById('wm-article').dataset.path === 'docs/arabic.md'`);
  const ar = await ev(`document.getElementById('wm-article').innerText`);
  report(ar.includes('هذا نص عربي للاختبار') && ar.includes('ملاحظات عربية'), 'Arabic text renders');
  await ev(`location.hash = '#docs/crlf.md'`);
  await until(`document.getElementById('wm-article').dataset.path === 'docs/crlf.md'`);
  report(await ev(`document.getElementById('wm-body').innerText.includes('Crlf file') && document.querySelector('#wm-entry-header h1').textContent === 'Crlf'`), 'CRLF file renders with frontmatter');

  // same-page anchor, missing and escaping links
  await ev(`location.hash = '#docs/waymark/x.md'`);
  await until(`document.querySelector('#wm-body a[data-anchor]')`);
  const anc = await ev(`(() => { const a = document.querySelector('#wm-body a[data-anchor]'); a.click();
    return { path: document.getElementById('wm-article').dataset.path, hash: decodeURIComponent(location.hash), err: !!document.getElementById('wm-error') }; })()`);
  report(anc.path === 'docs/waymark/x.md' && anc.hash === '#docs/waymark/x.md' && !anc.err, 'same-page #section link keeps the article', JSON.stringify(anc));
  const miss = await ev(`({ missing: !!document.querySelector('#wm-body a[data-missing="docs/waymark/nowhere.md"]:not([href])'),
    escape: document.querySelector('#wm-body a[href="../../../../x.md"]') !== null && !document.querySelector('#wm-body a[href="../../../../x.md"][data-internal]') })`);
  report(miss.missing && miss.escape, 'missing .md link marked, underflowing link left alone', JSON.stringify(miss));

  // 7. link between files, 8. back button
  await ev(`location.hash = '#docs/waymark/x.md'`);
  await until(`document.querySelector('#wm-body a[data-internal]')`);
  await ev(`document.querySelector('#wm-body a[data-internal="decisions.md"]').click()`);
  await until(`document.getElementById('wm-article').dataset.path === 'decisions.md'`);
  report((await ev(`decodeURIComponent(location.hash)`)) === '#decisions.md' && (await ev(`document.getElementById('wm-body').innerText.includes('Keep the viewer offline')`)),
    'link between files opens the target file');
  await ev(`history.back()`);
  await until(`document.getElementById('wm-article').dataset.path === 'docs/waymark/x.md'`);
  report((await ev(`decodeURIComponent(location.hash)`)) === '#docs/waymark/x.md', 'back button returns to the previous file');

  // refresh keeps the view
  await send('Page.reload');
  await until(`document.getElementById('wm-article').dataset.path === 'docs/waymark/x.md'`);
  report(await ev(`document.getElementById('wm-article').dataset.path === 'docs/waymark/x.md'`), 'reload restores the view from the hash');

  // search result opening highlights matches
  await ev(`document.body.focus()`);
  await key('/');
  await typeQuery('offline');
  await ev(`document.querySelector('#wm-results li[data-path="decisions.md"] a').click()`);
  await until(`document.getElementById('wm-article').dataset.path === 'decisions.md'`);
  await until(`document.querySelector('#wm-body mark')`);
  report(await ev(`document.querySelector('#wm-body mark').textContent.toLowerCase() === 'offline'`), 'opening a result highlights matches');

  // empty state
  await load(emptyHtml);
  report(await ev(`document.getElementById('wm-empty') && document.getElementById('wm-article').dataset.state === 'empty'`), 'empty state for a layer with no files');

  report(problems.length === 0, 'no page errors or console errors', problems.slice(0, 3).join(' | '));
} catch (e) {
  failed++;
  console.log(`FAIL harness error -- ${e.stack || e}`);
} finally {
  try { ws?.close(); } catch { /* ignore */ }
  chrome.kill();
  await sleep(300);
  if (!args.includes('--keep')) { try { rmSync(tmp, { recursive: true, force: true }); } catch { /* profile still locked */ } }
}
console.log(failed ? `${failed} check(s) FAILED` : 'all checks passed');
process.exit(failed ? 1 : 0);
