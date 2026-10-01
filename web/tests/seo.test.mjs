import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { analyseHtml, visibleText, checkGraph, checkDateModified, parseSitemap } from './seo-lib.mjs';

const root = process.env.SEO_WEB_ROOT || resolve(dirname(fileURLToPath(import.meta.url)), '..');
const origin = 'https://tethercam.app';
const languages = { en: `${origin}/`, de: `${origin}/de`, 'x-default': `${origin}/` };
const pages = [
  { file: 'index.html', url: `${origin}/`, lang: 'en', faq: true },
  { file: 'de/index.html', url: `${origin}/de`, lang: 'de', faq: true },
  { file: 'install.html', url: `${origin}/install`, lang: 'en', dated: true, faq: true },
  { file: 'changelog.html', url: `${origin}/changelog`, lang: 'en', dated: true },
];
const read = file => readFileSync(resolve(root, file), 'utf8');
const typed = (node, type) => [node?.['@type']].flat().includes(type);
function graphOf(meta) {
  return meta.ldBlocks.flatMap(raw => {
    // Blocks without @graph still count as nodes, so content checks never pass vacuously.
    try { const doc = JSON.parse(raw); const graph = doc?.['@graph']; return Array.isArray(graph) ? graph : [doc]; }
    catch { return []; }
  });
}
function dateOf(file, html) {
  if (file === 'changelog.html') {
    const heading = html.match(/<h2\b[^>]*\bid\s*=\s*["']v[^"']*["'][^>]*>([\s\S]*?)<\/h2\s*>/i)?.[1] ?? '';
    return visibleText(heading).match(/—\s*(\d{4}-\d{2}-\d{2})/)?.[1];
  }
  return visibleText(html).match(/Last updated: (\d{4}-\d{2}-\d{2})/)?.[1];
}

for (const page of pages) {
  // Read within each test so filtered rotprobes never depend on source files.
  const inspect = () => { const html = read(page.file); return { html, meta: analyseHtml(html) }; };
  test(`${page.file}: JSON-LD graph is closed and allowed`, () => {
    const { meta } = inspect();
    assert.deepEqual(checkGraph(meta.ldBlocks), [], `${page.file}: ${checkGraph(meta.ldBlocks).join('; ')}`);
  });
  test(`${page.file}: WebPage identity, URL and language match`, () => {
    const nodes = graphOf(inspect().meta).filter(n => typed(n, 'WebPage'));
    assert.equal(nodes.length, 1, `${page.file}: expected one WebPage, found ${nodes.length}`);
    assert.equal(nodes[0]['@id'], `${page.url}#webpage`, `${page.file}: wrong WebPage @id`);
    assert.equal(nodes[0].url, page.url, `${page.file}: wrong WebPage url`);
    assert.equal(nodes[0].inLanguage, page.lang, `${page.file}: wrong WebPage inLanguage`);
  });
  test(`${page.file}: exactly one canonical with expected URL`, () => {
    assert.deepEqual(inspect().meta.canonical, [page.url], `${page.file}: canonical must be exactly ${page.url}`);
  });
  test(`${page.file}: dateModified matches visible date policy`, () => {
    const { html, meta } = inspect();
    const date = page.dated ? dateOf(page.file, html) : undefined;
    if (page.dated) assert.ok(date, `${page.file}: missing visible update date`);
    const errors = checkDateModified(graphOf(meta), date);
    assert.deepEqual(errors, [], `${page.file}: ${errors.join('; ')}`);
  });
  if (page.faq) test(`${page.file}: FAQ question names occur literally in visible text`, () => {
    const { html, meta } = inspect();
    const text = visibleText(html);
    const faqs = graphOf(meta).filter(n => typed(n, 'FAQPage'));
    assert.equal(faqs.length, 1, `${page.file}: expected one FAQPage, found ${faqs.length}`);
    for (const faq of faqs) {
      assert.ok(Array.isArray(faq.mainEntity) && faq.mainEntity.length > 0, `${page.file}: FAQPage mainEntity must be a nonempty array`);
      for (const question of faq.mainEntity) {
        assert.ok(typeof question.name === 'string' && question.name.length > 0 && text.includes(question.name),
          `${page.file}: FAQ question missing verbatim: ${JSON.stringify(question.name)}`);
      }
    }
  });
  test(`${page.file}: decoded title has 1–60 characters`, () => {
    const length = [...inspect().meta.title].length;
    assert.ok(length > 0 && length <= 60, `${page.file}: title length ${length}, expected 1–60`);
  });
  test(`${page.file}: decoded description has 110–160 characters`, () => {
    const length = [...inspect().meta.description].length;
    assert.ok(length >= 110 && length <= 160, `${page.file}: description length ${length}, expected 110–160`);
  });
  for (const field of ['ogImage', 'twitterImage']) {
    test(`${page.file}: ${field} is an absolute HTTPS image`, () => {
      const value = inspect().meta[field];
      assert.ok(value.startsWith('https://'), `${page.file}: ${field} missing or not HTTPS: ${value}`);
    });
  }
  test(`${page.file}: exactly one h1`, () => {
    assert.equal(inspect().meta.h1Count, 1, `${page.file}: expected exactly one h1`);
  });
  if (!page.dated) {
    test(`${page.file}: homepage hreflang is reciprocal`, () => {
      assert.deepEqual(inspect().meta.hreflang, languages, `${page.file}: wrong homepage hreflang`);
      const other = page.lang === 'en' ? 'de/index.html' : 'index.html';
      assert.deepEqual(analyseHtml(read(other)).hreflang, languages, `${page.file}: ${other} hreflang is not reciprocal`);
    });
  }
  test(`${page.file}: no reference to redirecting /de/ URL`, () => {
    assert.doesNotMatch(inspect().html, /tethercam\.app\/de\/|href="\/de\//, `${page.file}: redirecting /de/ reference`);
  });
}

test.skip('privacy.html: geparkt: Rechtstext-Sperrzone, Refs #40');

test('shared Organization, Person and WebSite nodes are identical on every page', () => {
  // Same @id with different content on two pages gives search engines conflicting facts.
  const shared = ['Organization', 'Person', 'WebSite'];
  const pick = file => JSON.stringify(shared.map(type => graphOf(analyseHtml(read(file))).filter(n => typed(n, type))));
  const first = pick(pages[0].file);
  assert.notEqual(first, JSON.stringify([[], [], []]), `${pages[0].file}: shared nodes missing`);
  for (const { file } of pages.slice(1)) assert.equal(pick(file), first, `${file}: shared nodes differ from ${pages[0].file}`);
});

test('sitemap.xml: xhtml namespace is declared', () => {
  assert.ok(parseSitemap(read('sitemap.xml')).hasXhtmlNs, 'sitemap.xml: missing xhtml namespace');
});
test('sitemap.xml: exact canonical loc set without trailing slashes', () => {
  const urls = parseSitemap(read('sitemap.xml')).urls;
  const expected = [`${origin}/`, `${origin}/privacy`, `${origin}/install`, `${origin}/changelog`, `${origin}/de`];
  assert.deepEqual(urls.map(u => u.loc).sort(), expected.sort(), 'sitemap.xml: unexpected, missing or duplicate loc');
  for (const { loc } of urls) assert.ok(loc === `${origin}/` || !loc.endsWith('/'), `sitemap.xml: trailing slash in ${loc}`);
});
for (const loc of [languages.en, languages.de]) {
  test(`sitemap.xml: reciprocal alternates for ${loc}`, () => {
    const entry = parseSitemap(read('sitemap.xml')).urls.find(u => u.loc === loc);
    assert.ok(entry, `sitemap.xml: missing ${loc}`);
    assert.deepEqual(entry.alternates, languages, `sitemap.xml: wrong alternates for ${loc}`);
  });
}
for (const file of ['install.html', 'changelog.html', 'privacy.html']) {
  test(`sitemap.xml: /${file.slice(0, -5)} lastmod equals visible date in ${file}`, () => {
    const date = dateOf(file, read(file));
    assert.ok(date, `${file}: missing visible date for sitemap lastmod`);
    const loc = `${origin}/${file.slice(0, -5)}`;
    const entry = parseSitemap(read('sitemap.xml')).urls.find(u => u.loc === loc);
    assert.ok(entry, `sitemap.xml: missing ${loc}`);
    assert.equal(entry.lastmod, date, `sitemap.xml: ${loc} lastmod differs from ${file} visible date ${date}`);
  });
}
for (const loc of [languages.en, languages.de]) {
  test(`sitemap.xml: ${loc} lastmod is a valid date no later than today UTC`, () => {
    const date = parseSitemap(read('sitemap.xml')).urls.find(u => u.loc === loc)?.lastmod;
    assert.match(date ?? '', /^\d{4}-\d{2}-\d{2}$/, `sitemap.xml: ${loc} invalid lastmod ${date}`);
    const timestamp = Date.parse(`${date}T00:00:00Z`);
    assert.ok(Number.isFinite(timestamp) && new Date(timestamp).toISOString().slice(0, 10) === date,
      `sitemap.xml: ${loc} impossible date ${date}`);
    assert.ok(date <= new Date().toISOString().slice(0, 10), `sitemap.xml: ${loc} lastmod ${date} is in the future`);
  });
}
test('llms.txt: no redirecting /de/ URL', () => {
  assert.doesNotMatch(read('llms.txt'), /tethercam\.app\/de\//, 'llms.txt: redirecting /de/ reference');
});

const fixture = nodes => JSON.stringify({ '@graph': nodes });
const site = { '@type': 'WebSite', '@id': 'https://tethercam.app/#website', alternateName: 'tethercam.app' };
test('rotprobe: unresolved organization @id is reported exactly', () => {
  const id = 'https://tethercam.app/#organization';
  assert.deepEqual(checkGraph([fixture([{ ...site, publisher: { '@id': id } }])]), [`Unresolved @id reference: ${id}`]);
});
test('rotprobe: two JSON-LD blocks report block count', () => {
  assert.deepEqual(checkGraph([fixture([site]), fixture([site])]), ['Expected exactly 1 JSON-LD block; found 2']);
});
test('rotprobe: dateModified mismatch reports both dates', () => {
  const errors = checkDateModified([{ '@type': 'WebPage', dateModified: '2026-09-09' }], '2026-09-10');
  assert.equal(errors.length, 1);
  assert.match(errors[0], /2026-09-09.*2026-09-10/);
});
test('rotprobe: WebSite without alternateName is rejected', () => {
  assert.deepEqual(checkGraph([fixture([{ '@type': 'WebSite' }])]), ['WebSite alternateName must be a nonempty string']);
});
