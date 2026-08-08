#!/usr/bin/env python3
"""Render the analog component library into one self-contained local page.

    python3 build.py           # build .build/index.html
    python3 build.py --serve   # build, then serve on http://localhost:8099

Standard library only, on purpose: this is documentation tooling and must not
become a dependency anyone has to install to read the design system.
"""
import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / '.build' / 'index.html'
PORT = 8099


def split_frontmatter(text):
    if not text.startswith('---'):
        return {}, text
    end = text.index('\n---', 3)
    meta = {}
    for line in text[3:end].strip().splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            meta[k.strip()] = v.strip()
    return meta, text[end + 4:]


def inline(s):
    """Inline markdown -> HTML. Order matters; code spans are protected first."""
    spans = []

    def stash(m):
        spans.append(m.group(1))
        return f'\x00{len(spans) - 1}\x00'

    s = re.sub(r'`([^`]+)`', stash, s)
    s = html.escape(s, quote=False)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'(?<!\*)\*([^*\n]+)\*(?!\*)', r'<em>\1</em>', s)

    def link(m):
        label, href = m.group(1), m.group(2)
        if href.endswith('.mdx') or '.mdx#' in href:
            slug = pathlib.PurePosixPath(href.split('#')[0]).stem
            href = '#' + slug
        return f'<a href="{html.escape(href, quote=True)}">{label}</a>'

    s = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, s)
    s = s.replace('\\|', '|')
    return re.sub(r'\x00(\d+)\x00',
                  lambda m: '<code>' + html.escape(spans[int(m.group(1))], quote=False) + '</code>',
                  s)


def render(body, slug):
    out, i = [], 0
    lines = body.split('\n')
    while i < len(lines):
        line = lines[i]

        if line.startswith('```'):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].startswith('```'):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append('<div class="scroll"><pre><code>' +
                       html.escape('\n'.join(buf), quote=False) + '</code></pre></div>')
            continue

        if re.match(r'^#{1,4} ', line):
            level = len(line) - len(line.lstrip('#'))
            text = line[level:].strip()
            if level == 1:
                out.append(f'<h2 class="page-title">{inline(text)}</h2>')
            else:
                anchor = slug + '-' + re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
                out.append(f'<h{level} id="{anchor}">{inline(text)}</h{level}>')
            i += 1
            continue

        if line.strip().startswith('|'):
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                rows.append(lines[i].strip())
                i += 1
            if len(rows) >= 2:
                def cells(r):
                    return [c.strip() for c in re.split(r'(?<!\\)\|', r)[1:-1]]
                head = cells(rows[0])
                body_rows = [cells(r) for r in rows[2:]]
                t = ['<div class="scroll"><table><thead><tr>']
                t += [f'<th>{inline(c)}</th>' for c in head]
                t.append('</tr></thead><tbody>')
                for r in body_rows:
                    t.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>')
                t.append('</tbody></table></div>')
                out.append(''.join(t))
            continue

        if re.match(r'^[-*] ', line.strip()):
            items = []
            while i < len(lines) and re.match(r'^[-*] ', lines[i].strip()):
                item = lines[i].strip()[2:]
                i += 1
                while i < len(lines) and lines[i].startswith('  ') and lines[i].strip() \
                        and not re.match(r'^[-*] ', lines[i].strip()):
                    item += ' ' + lines[i].strip()
                    i += 1
                items.append(item)
            out.append('<ul>' + ''.join(f'<li>{inline(x)}</li>' for x in items) + '</ul>')
            continue

        if re.match(r'^\d+\. ', line.strip()):
            items = []
            while i < len(lines) and re.match(r'^\d+\. ', lines[i].strip()):
                items.append(re.sub(r'^\d+\. ', '', lines[i].strip()))
                i += 1
            out.append('<ol>' + ''.join(f'<li>{inline(x)}</li>' for x in items) + '</ol>')
            continue

        if line.strip().startswith('>'):
            buf = []
            while i < len(lines) and lines[i].strip().startswith('>'):
                buf.append(lines[i].strip().lstrip('>').strip())
                i += 1
            out.append(f'<blockquote>{inline(" ".join(buf))}</blockquote>')
            continue

        if line.strip() == '---':
            out.append('<hr>')
            i += 1
            continue

        if line.strip() == '':
            i += 1
            continue

        buf = []
        while i < len(lines) and lines[i].strip() and not re.match(
                r'^(#{1,4} |```|\||[-*] |\d+\. |>)', lines[i].strip()) and lines[i].strip() != '---':
            buf.append(lines[i].strip())
            i += 1
        if buf:
            out.append(f'<p>{inline(" ".join(buf))}</p>')

    return '\n'.join(out)


# ── collect ────────────────────────────────────────────────────────────────
KITS = [('chrome', 'Chrome'), ('browse', 'Browse'), ('player', 'Player')]
index_meta, index_html = split_frontmatter((ROOT / 'index.mdx').read_text())
pages = [{
    'slug': 'index', 'title': 'Overview', 'kit': None,
    'meta': index_meta, 'html': render(index_html, 'index'),
}]

for kit, _label in KITS:
    for f in sorted((ROOT / kit).glob('*.mdx')):
        meta, body = split_frontmatter(f.read_text())
        pages.append({
            'slug': f.stem,
            'title': meta.get('title', f.stem),
            'kit': kit,
            'meta': meta,
            'html': render(body, f.stem),
        })

STATUS = {
    'parity': ('Both clients', 'ok'),
    'web-only': ('Web only', 'gap'),
    'native-only': ('Native only', 'gap'),
    'living': ('Living', 'ok'),
}

nav, articles = [], []
for kit, label in [(None, 'Library')] + KITS:
    group = [p for p in pages if p['kit'] == kit]
    if not group:
        continue
    nav.append(f'<div class="nav-group"><div class="nav-label">{label}</div>')
    for p in group:
        st = p['meta'].get('status', '')
        dot = ''
        if st in ('web-only', 'native-only'):
            dot = '<span class="gapdot" title="one client only"></span>'
        nav.append(
            f'<a class="nav-item" href="#{p["slug"]}" data-slug="{p["slug"]}">'
            f'<span class="detent"></span><span class="nav-name">{html.escape(p["title"])}</span>{dot}</a>')
    nav.append('</div>')

for p in pages:
    m = p['meta']
    chips = []
    if p['kit']:
        chips.append(f'<span class="chip kit">{p["kit"]}</span>')
    st = m.get('status')
    if st in STATUS:
        text, tone = STATUS[st]
        chips.append(f'<span class="chip {tone}">{text}</span>')
    for key, tag in (('web', 'web'), ('native', 'native')):
        val = m.get(key)
        if val and val not in ('—', '— (planned)'):
            chips.append(f'<span class="chip src"><i>{tag}</i>{html.escape(val)}</span>')
        elif val:
            chips.append(f'<span class="chip src absent"><i>{tag}</i>not built</span>')
    articles.append(
        f'<article class="page" id="{p["slug"]}" data-slug="{p["slug"]}">'
        f'<div class="chips">{"".join(chips)}</div>{p["html"]}</article>')

counts = {
    'total': len(pages) - 1,
    'gaps': sum(1 for p in pages if p['meta'].get('status') in ('web-only', 'native-only')),
}

CSS = """
*,*::before,*::after{box-sizing:border-box}
:root{
  --void:#070605; --ground:#0E0C0A; --surface:#16130F; --surface2:#201C18;
  --ink:#F4EFE6; --ink-dim:rgba(244,239,230,.64); --ink-faint:rgba(244,239,230,.38);
  --line:rgba(244,239,230,.10); --line-strong:rgba(244,239,230,.18);
  --danger:#E0655E; --success:#5AB98A;
  --sans:"Helvetica Neue",Helvetica,Arial,system-ui,sans-serif;
  --mono:ui-monospace,"JetBrains Mono",SFMono-Regular,Menlo,Consolas,monospace;
  --rail:16rem; --chrome-radius:4px;
}
@media (prefers-color-scheme:light){
  :root{
    --void:#EFEAE1; --ground:#F7F4EE; --surface:#FFFDF9; --surface2:#F2EDE4;
    --ink:#16130F; --ink-dim:rgba(22,19,15,.68); --ink-faint:rgba(22,19,15,.42);
    --line:rgba(22,19,15,.14); --line-strong:rgba(22,19,15,.26);
    --danger:#A63A34; --success:#2F7355;
  }
}
:root[data-theme="light"]{
  --void:#EFEAE1; --ground:#F7F4EE; --surface:#FFFDF9; --surface2:#F2EDE4;
  --ink:#16130F; --ink-dim:rgba(22,19,15,.68); --ink-faint:rgba(22,19,15,.42);
  --line:rgba(22,19,15,.14); --line-strong:rgba(22,19,15,.26);
  --danger:#A63A34; --success:#2F7355;
}
:root[data-theme="dark"]{
  --void:#070605; --ground:#0E0C0A; --surface:#16130F; --surface2:#201C18;
  --ink:#F4EFE6; --ink-dim:rgba(244,239,230,.64); --ink-faint:rgba(244,239,230,.38);
  --line:rgba(244,239,230,.10); --line-strong:rgba(244,239,230,.18);
  --danger:#E0655E; --success:#5AB98A;
}
html{scroll-behavior:smooth}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--sans);
  font-size:15px;line-height:1.62;-webkit-font-smoothing:antialiased}
.layout{display:grid;grid-template-columns:var(--rail) minmax(0,1fr);align-items:start}

/* ── index rail ─────────────────────────────────────────── */
.rail{position:sticky;top:0;height:100vh;overflow-y:auto;background:var(--void);
  border-right:1px solid var(--line);padding:1.75rem 0 3rem;display:flex;flex-direction:column;gap:1.25rem}
.brand{padding:0 1.25rem;display:flex;flex-direction:column;gap:.3rem}
.brand h1{margin:0;font-size:.92rem;font-weight:700;letter-spacing:-.01em}
.brand .sub{font-family:var(--mono);font-size:.66rem;letter-spacing:.09em;
  text-transform:uppercase;color:var(--ink-faint)}
.filter{margin:0 1.25rem;background:var(--surface);border:1px solid var(--line);
  border-radius:var(--chrome-radius);color:var(--ink);font-family:var(--mono);
  font-size:.72rem;padding:.5rem .6rem;width:calc(100% - 2.5rem)}
.filter::placeholder{color:var(--ink-faint)}
.filter:focus{outline:2px solid var(--ink);outline-offset:1px;border-color:var(--line-strong)}
.nav-group{display:flex;flex-direction:column}
.nav-label{font-family:var(--mono);font-size:.64rem;letter-spacing:.13em;text-transform:uppercase;
  color:var(--ink-faint);padding:.5rem 1.25rem .35rem}
.nav-item{display:flex;align-items:center;gap:.5rem;padding:.3rem 1.25rem;color:var(--ink-dim);
  text-decoration:none;font-size:.82rem;position:relative}
.nav-item:hover{color:var(--ink);background:var(--surface)}
.nav-item:focus-visible{outline:2px solid var(--ink);outline-offset:-2px}
/* the system's own selection idiom: a detent, not a tint */
.detent{width:2px;height:11px;background:transparent;flex:none}
.nav-item.active{color:var(--ink)}
.nav-item.active .detent{background:var(--ink);width:2px;height:15px}
.nav-item.active .nav-name{font-weight:700}
.gapdot{width:5px;height:5px;border:1px solid var(--danger);margin-left:auto;flex:none}

/* ── content ────────────────────────────────────────────── */
main{padding:3.5rem 3rem 8rem;min-width:0}
.masthead{max-width:68ch;margin:0 0 3rem;padding-bottom:2rem;border-bottom:2px solid var(--ink)}
.masthead h1{margin:0 0 .5rem;font-size:clamp(1.9rem,3.6vw,2.75rem);font-weight:700;
  letter-spacing:-.028em;line-height:1.06;text-wrap:balance}
.masthead p{margin:0;color:var(--ink-dim);max-width:60ch}
.stats{display:flex;gap:2rem;margin-top:1.5rem;font-family:var(--mono);font-size:.7rem;
  letter-spacing:.08em;text-transform:uppercase;color:var(--ink-faint);flex-wrap:wrap}
.stats b{display:block;font-size:1.5rem;color:var(--ink);letter-spacing:-.02em;
  font-family:var(--sans);font-variant-numeric:tabular-nums;text-transform:none}
.page{max-width:68ch;padding:3rem 0 1rem;border-top:1px solid var(--line);scroll-margin-top:1rem}
.page:first-of-type{border-top:0;padding-top:0}
.page-title{font-size:1.65rem;font-weight:700;letter-spacing:-.022em;margin:.2rem 0 1.25rem;
  text-wrap:balance;line-height:1.15}
h3{font-size:1rem;font-weight:700;letter-spacing:-.005em;margin:2.4rem 0 .7rem}
h4{font-family:var(--mono);font-size:.74rem;letter-spacing:.1em;text-transform:uppercase;
  color:var(--ink-faint);margin:1.8rem 0 .6rem;font-weight:500}
p{margin:0 0 1rem}
ul,ol{margin:0 0 1rem;padding-left:1.15rem}
li{margin-bottom:.35rem}
a{color:var(--ink);text-decoration-color:var(--line-strong);text-underline-offset:3px}
a:hover{text-decoration-color:var(--ink)}
strong{font-weight:700}
code{font-family:var(--mono);font-size:.855em;background:var(--surface2);
  padding:.1em .34em;border-radius:2px}
blockquote{margin:1.4rem 0;padding:.15rem 0 .15rem 1.15rem;border-left:2px solid var(--ink);
  color:var(--ink-dim);font-style:italic}
hr{border:0;border-top:1px solid var(--line);margin:2rem 0}
.scroll{overflow-x:auto;margin:0 0 1.25rem}
pre{margin:0;background:var(--surface);border:1px solid var(--line);padding:1rem 1.1rem;
  border-radius:var(--chrome-radius)}
pre code{background:none;padding:0;font-size:.78rem;line-height:1.55}
table{border-collapse:collapse;width:100%;font-size:.845rem;min-width:26rem}
th{text-align:left;font-family:var(--mono);font-size:.66rem;letter-spacing:.1em;
  text-transform:uppercase;color:var(--ink-faint);font-weight:500;
  padding:.5rem .75rem .5rem 0;border-bottom:2px solid var(--ink)}
td{padding:.6rem .75rem .6rem 0;border-bottom:1px solid var(--line);vertical-align:top}
tbody tr:hover{background:var(--surface)}

/* ── chips ──────────────────────────────────────────────── */
.chips{display:flex;flex-wrap:wrap;gap:.4rem;margin-bottom:.9rem}
.chip{font-family:var(--mono);font-size:.64rem;letter-spacing:.06em;padding:.22rem .5rem;
  border:1px solid var(--line-strong);border-radius:var(--chrome-radius);color:var(--ink-dim);
  display:inline-flex;gap:.4rem;align-items:center;white-space:nowrap}
.chip.kit{text-transform:uppercase;border-color:var(--ink);color:var(--ink);font-weight:700}
.chip i{font-style:normal;color:var(--ink-faint);text-transform:uppercase;font-size:.58rem}
/* parity is the one place semantic colour is spent, and it doubles the frame
   rather than relying on hue — the system's own rule */
.chip.ok{border-color:var(--success);color:var(--success)}
.chip.gap{border-color:var(--danger);color:var(--danger);border-width:2px;font-weight:700}
.chip.absent{border-style:dashed;color:var(--ink-faint)}
.hidden{display:none}

@media (max-width:900px){
  .layout{grid-template-columns:1fr}
  .rail{position:static;height:auto;border-right:0;border-bottom:1px solid var(--line)}
  main{padding:2rem 1.25rem 5rem}
}
"""

JS = """
const items=[...document.querySelectorAll('.nav-item')];
const filter=document.getElementById('filter');
filter.addEventListener('input',()=>{
  const q=filter.value.trim().toLowerCase();
  items.forEach(a=>a.classList.toggle('hidden',
    q && !a.querySelector('.nav-name').textContent.toLowerCase().includes(q)));
  document.querySelectorAll('.nav-group').forEach(g=>{
    const any=[...g.querySelectorAll('.nav-item')].some(a=>!a.classList.contains('hidden'));
    g.classList.toggle('hidden',!any);
  });
});
const byslug=new Map(items.map(a=>[a.dataset.slug,a]));
const seen=new Set();
const io=new IntersectionObserver(es=>{
  es.forEach(e=>e.isIntersecting?seen.add(e.target.dataset.slug):seen.delete(e.target.dataset.slug));
  const first=[...document.querySelectorAll('.page')].find(p=>seen.has(p.dataset.slug));
  items.forEach(a=>a.classList.remove('active'));
  if(first) byslug.get(first.dataset.slug)?.classList.add('active');
},{rootMargin:'-8% 0px -80% 0px'});
document.querySelectorAll('.page').forEach(p=>io.observe(p));
"""

doc = f"""<title>Analog component library — Watchparty</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>{CSS}</style>
<div class="layout">
  <nav class="rail">
    <div class="brand">
      <h1>Analog</h1>
      <div class="sub">Component library</div>
    </div>
    <input id="filter" class="filter" type="search" placeholder="Filter components" aria-label="Filter components">
    {''.join(nav)}
  </nav>
  <main>
    <header class="masthead">
      <h1>The analog component library</h1>
      <p>One page per component, in both clients. If the React and Flutter
         implementations disagree, the page is right and the code is wrong.</p>
      <div class="stats">
        <div><b>{counts['total']}</b> components</div>
        <div><b>3</b> kits</div>
        <div><b>{counts['gaps']}</b> single-client gaps</div>
      </div>
    </header>
    {''.join(articles)}
  </main>
</div>
<script>{JS}</script>
"""

OUT.parent.mkdir(exist_ok=True)
OUT.write_text(doc)
print(f'built {OUT.relative_to(ROOT)} — {len(pages)} pages, '
      f'{counts["gaps"]} single-client gaps, {len(doc) / 1024:.0f} KB')

if '--serve' in sys.argv:
    import functools
    import http.server
    import socketserver

    handler = functools.partial(http.server.SimpleHTTPRequestHandler,
                                directory=str(OUT.parent))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(('127.0.0.1', PORT), handler) as httpd:
        print(f'\n  http://localhost:{PORT}\n\nCtrl-C to stop. '
              f'Re-run to rebuild after editing any .mdx.')
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print('\nstopped')
