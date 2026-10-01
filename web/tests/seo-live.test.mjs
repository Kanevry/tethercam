import test from 'node:test';
import assert from 'node:assert/strict';
import { analyseHtml, checkGraph, parseSitemap } from './seo-lib.mjs';

const base = process.env.SEO_BASE_URL;
if (!base) {
  test.skip('SEO_BASE_URL nicht gesetzt');
} else {
  test('live SEO: sequential requests with at least 7500 ms spacing', async t => {
    const baseUrl = new URL(base);
    const origin = 'https://tethercam.app';
    let lastStart;
    async function request(url) {
      // No automatic redirect hops: each fetch counts as exactly one request.
      while (lastStart !== undefined && performance.now() - lastStart < 7500) {
        await new Promise(resolve => setTimeout(resolve, Math.ceil(7500 - (performance.now() - lastStart))));
      }
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 25000);
      lastStart = performance.now();
      try {
        const response = await fetch(url, { redirect: 'manual', signal: controller.signal });
        const body = await response.text();
        return { status: response.status, location: response.headers.get('location'), body };
      } finally { clearTimeout(timer); }
    }
    const atBase = path => new URL(path, baseUrl.origin).href;
    const rewrite = loc => {
      const url = new URL(loc);
      assert.equal(url.origin, origin, `sitemap.xml: unexpected loc origin ${loc}`);
      return new URL(`${url.pathname}${url.search}${url.hash}`, baseUrl.origin).href;
    };
    let sitemap;
    await t.test('sitemap.xml: status 200 and nonempty URL list', async () => {
      const response = await request(atBase('/sitemap.xml'));
      assert.equal(response.status, 200, 'sitemap.xml: expected 200 without redirect');
      sitemap = parseSitemap(response.body);
      assert.ok(sitemap.urls.length > 0, 'sitemap.xml: no loc entries');
    });
    assert.ok(sitemap?.urls.length, 'sitemap.xml: cannot inspect pages without loc entries');
    for (const { loc } of sitemap.urls) {
      if (new URL(loc).pathname.replace(/\/$/, '') === '/privacy') {
        await t.test(`${loc}: geparkt: Rechtstext-Sperrzone, Refs #40`, { skip: true }, () => {});
        continue;
      }
      await t.test(`${loc}: 200, graph, canonical, images and snippets`, async () => {
        const response = await request(rewrite(loc));
        assert.equal(response.status, 200, `${loc}: expected 200 without redirect`);
        const meta = analyseHtml(response.body);
        const errors = checkGraph(meta.ldBlocks);
        assert.deepEqual(errors, [], `${loc}: ${errors.join('; ')}`);
        assert.deepEqual(meta.canonical, [loc], `${loc}: canonical must match original sitemap loc`);
        for (const field of ['ogImage', 'twitterImage']) {
          assert.ok(meta[field].startsWith('https://'), `${loc}: ${field} missing or not HTTPS`);
        }
        const titleLength = [...meta.title].length;
        const descriptionLength = [...meta.description].length;
        assert.ok(titleLength > 0 && titleLength <= 60, `${loc}: title length ${titleLength}, expected 1–60`);
        assert.ok(descriptionLength >= 110 && descriptionLength <= 160,
          `${loc}: description length ${descriptionLength}, expected 110–160`);
      });
    }
    for (const path of ['/tc-seo-live-404', '/tests/seo.test.mjs', '/scripts/indexnow.mjs']) {
      await t.test(`${path}: status 404`, async () => {
        const response = await request(atBase(path));
        assert.equal(response.status, 404, `${path}: expected 404, got ${response.status}`);
      });
    }
    await t.test('/de/: redirects to /de', async () => {
      const response = await request(atBase('/de/'));
      assert.ok(response.status >= 300 && response.status < 400, `/de/: expected 3xx, got ${response.status}`);
      assert.ok(response.location, '/de/: missing Location header');
      assert.ok(response.location.endsWith('/de'), `/de/: Location must end with /de: ${response.location}`);
      assert.equal(new URL(response.location, atBase('/de/')).pathname, '/de', '/de/: wrong redirect target');
    });
  });
}
