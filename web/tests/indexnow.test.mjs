import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { main } from '../scripts/indexnow.mjs';

const key = '610d0bee4021d7f563d233493b8010b9';
const site = 'https://tethercam.app';
const urls = [`${site}/`, `${site}/privacy`];
const expectedPayload = { host: 'tethercam.app', key, keyLocation: `${site}/${key}.txt`, urlList: urls };

function fixture(t, { keys = [key], keyContent = key, sitemapUrls = urls,
  liveStatus = 200, liveBody = key, postStatus = 200, throwAt } = {}) {
  const webRoot = mkdtempSync(join(tmpdir(), 'tethercam-indexnow-'));
  t.after(() => rmSync(webRoot, { recursive: true, force: true }));
  for (const name of keys) writeFileSync(join(webRoot, `${name}.txt`), keyContent);
  writeFileSync(join(webRoot, 'sitemap.xml'),
    `<urlset xmlns:xhtml="http://www.w3.org/1999/xhtml">${sitemapUrls.map(url =>
      `<url><loc>${url}</loc></url>`).join('')}<xhtml:link href="${site}/de"/></urlset>`);
  const calls = [];
  let out = '';
  let err = '';
  const options = {
    webRoot,
    env: {},
    stdout: { write: value => { out += value; } },
    stderr: { write: value => { err += value; } },
    fetch: async (url, init) => {
      calls.push({ url, init });
      if (init.method === throwAt) throw new Error('Fake network failure');
      return init.method === 'GET'
        ? { status: liveStatus, text: async () => liveBody }
        : { status: postStatus };
    },
  };
  return { options, calls, output: () => out, errors: () => err };
}

test('dry run outputs only loc URLs and never fetches', async t => {
  const f = fixture(t);
  assert.equal(await main(['--site', site], f.options), 0);
  assert.deepEqual(f.calls, []);
  assert.deepEqual(JSON.parse(f.output()), expectedPayload);
  assert.match(f.errors(), /Trockenlauf, nichts gesendet/);
});

for (const [name, settings] of [
  ['404', { liveStatus: 404 }],
  ['wrong body', { liveBody: 'wrong-key' }],
  ['redirect', { liveStatus: 301 }],
]) {
  test(`key preflight ${name} returns 2 without POST`, async t => {
    const f = fixture(t, settings);
    assert.equal(await main(['--site', site, '--send'], f.options), 2);
    assert.equal(f.calls.length, 1);
    assert.equal(f.calls[0].url, expectedPayload.keyLocation);
    assert.equal(f.calls[0].init.method, 'GET');
    assert.equal(f.calls[0].init.redirect, 'manual');
    assert.match(f.errors(), new RegExp(`status ${settings.liveStatus ?? 200}`));
  });
}

for (const value of ['preview', 'development', '']) {
  test(`VERCEL_ENV=${JSON.stringify(value)} prevents any fetch`, async t => {
    const f = fixture(t);
    f.options.env = { VERCEL_ENV: value };
    assert.equal(await main(['--site', site, '--send'], f.options), 2);
    assert.deepEqual(f.calls, []);
    assert.match(f.errors(), /VERCEL_ENV/);
  });
}

for (const postStatus of [200, 202, 403, 422, 500, 302]) {
  test(`POST ${postStatus} returns the required code and sends the exact payload`, async t => {
    const f = fixture(t, { postStatus, liveBody: ` ${key}\n` });
    f.options.env = { VERCEL_ENV: 'production' };
    assert.equal(await main(['--site', site, '--send'], f.options),
      [200, 202].includes(postStatus) ? 0 : 1);
    assert.equal(f.calls.length, 2);
    assert.deepEqual(f.calls[0], {
      url: expectedPayload.keyLocation, init: { method: 'GET', redirect: 'manual' },
    });
    assert.equal(f.calls[1].url, 'https://api.indexnow.org/indexnow');
    assert.equal(f.calls[1].init.method, 'POST');
    assert.equal(f.calls[1].init.redirect, 'manual');
    assert.deepEqual(f.calls[1].init.headers, { 'content-type': 'application/json; charset=utf-8' });
    assert.deepEqual(JSON.parse(f.calls[1].init.body), expectedPayload);
    assert.match(f.output(), /Key preflight status: 200/);
    assert.match(f.output(), new RegExp(`IndexNow status: ${postStatus}`));
  });
}

for (const throwAt of ['GET', 'POST']) {
  // Unreachable key file means nothing may be sent (2); a failed POST is a submission failure (1).
  test(`fetch throwing at ${throwAt} returns ${throwAt === 'GET' ? 2 : 1}`, async t => {
    const f = fixture(t, { throwAt });
    assert.equal(await main(['--site', site, '--send'], f.options), throwAt === 'GET' ? 2 : 1);
    assert.equal(f.calls.length, throwAt === 'GET' ? 1 : 2);
    assert.match(f.errors(), /network error \(status unavailable\): Fake network failure/);
  });
}

for (const [name, settings] of [
  ['no key', { keys: [] }],
  ['two keys', { keys: [key, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'] }],
  ['local key mismatch', { keyContent: 'wrong-key' }],
  ['empty loc list', { sitemapUrls: [] }],
  ['foreign sitemap host', { sitemapUrls: ['https://example.com/'] }],
]) {
  test(`${name} returns 2 without fetch`, async t => {
    const f = fixture(t, settings);
    assert.equal(await main(['--site', site, '--send'], f.options), 2);
    assert.deepEqual(f.calls, []);
    assert.match(f.errors(), /Validation failed/);
  });
}

for (const [name, argv] of [
  ['missing site', []],
  ['invalid site', ['--site', 'not-a-url']],
  ['http site', ['--site', 'http://tethercam.app']],
  ['missing URL value', ['--site', site, '--url']],
  ['foreign explicit host', ['--site', site, '--url', 'https://example.com/']],
  ['different port', ['--site', site, '--url', `${site}:8443/`]],
  ['invalid explicit URL', ['--site', site, '--url', 'invalid']],
  ['unknown flag', ['--site', site, '--unknown']],
]) {
  test(`${name} returns 2 without fetch`, async t => {
    const f = fixture(t);
    assert.equal(await main(argv, f.options), 2);
    assert.deepEqual(f.calls, []);
    assert.match(f.errors(), /Validation failed/);
  });
}

test('repeated explicit URLs replace the sitemap; keyLocation uses site origin', async t => {
  const f = fixture(t, { keyContent: `\n${key}\n` });
  const explicit = [`${site}/install`, `${site}/changelog`];
  assert.equal(await main(['--site', `${site}/path`, '--url', explicit[0], '--url', explicit[1]], f.options), 0);
  assert.deepEqual(f.calls, []);
  assert.deepEqual(JSON.parse(f.output()), { ...expectedPayload, urlList: explicit });
});

test('sitemap XML entities decode to URL characters', async t => {
  const f = fixture(t, { sitemapUrls: [`${site}/?a=1&amp;b=2`, `${site}/privacy`] });
  assert.equal(await main(['--site', site], f.options), 0);
  assert.deepEqual(f.calls, []);
  assert.deepEqual(JSON.parse(f.output()).urlList, [`${site}/?a=1&b=2`, `${site}/privacy`]);
});
