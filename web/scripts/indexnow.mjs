// node web/scripts/indexnow.mjs --site https://tethercam.app [--send] [--url <url> ...]
// Exit codes: 0 success/dry run; 1 POST answered other than 200/202 or POST network error;
// 2 invalid input, or key file not reachable live (non-200, wrong body, network error): nothing sent.
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';

const defaultWebRoot = fileURLToPath(new URL('../', import.meta.url));

function decodeXml(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => {
    if (entity.startsWith('#')) {
      return String.fromCodePoint(entity[1].toLowerCase() === 'x'
        ? parseInt(entity.slice(2), 16) : parseInt(entity.slice(1), 10));
    }
    return { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }[entity.toLowerCase()];
  });
}

export async function main(argv, {
  fetch = globalThis.fetch,
  webRoot = defaultWebRoot,
  env = process.env,
  stdout = process.stdout,
  stderr = process.stderr,
} = {}) {
  let payload;
  let send = false;
  try {
    let site;
    const explicitUrls = [];
    for (let i = 0; i < argv.length; i++) {
      const arg = argv[i];
      if (arg === '--send') {
        send = true;
      } else if (arg === '--site' || arg === '--url') {
        const value = argv[++i];
        if (!value || value.startsWith('--')) throw new Error(`${arg} requires a value.`);
        if (arg === '--site') site = value;
        else explicitUrls.push(value);
      } else {
        throw new Error(`Unknown argument: ${arg}`);
      }
    }
    if (!site) throw new Error('--site is required (https URL).');
    const siteUrl = new URL(site);
    if (siteUrl.protocol !== 'https:') throw new Error('--site must be an https URL.');
    const host = siteUrl.host;
    const files = (await readdir(webRoot, { withFileTypes: true }))
      .filter(entry => entry.isFile() && /^[0-9a-f]{32}\.txt$/.test(entry.name));
    if (files.length !== 1) throw new Error(`Expected exactly one key file; found ${files.length}.`);
    const key = files[0].name.slice(0, -4);
    if ((await readFile(join(webRoot, files[0].name), 'utf8')).trim() !== key) {
      throw new Error('Key file content does not match its filename.');
    }
    const urlList = explicitUrls.length ? explicitUrls : Array.from(
      (await readFile(join(webRoot, 'sitemap.xml'), 'utf8'))
        .matchAll(/<loc\b[^>]*>([\s\S]*?)<\/loc\s*>/g),
      match => decodeXml(match[1].trim()),
    );
    if (!urlList.length) throw new Error('URL list is empty.');
    for (const url of urlList) {
      if (new URL(url).host !== host) throw new Error(`URL host must be ${host}: ${url}`);
    }
    payload = { host, key, keyLocation: `${siteUrl.origin}/${key}.txt`, urlList };
    if (send && env.VERCEL_ENV !== undefined && env.VERCEL_ENV !== 'production') {
      throw new Error(`Sending blocked for VERCEL_ENV=${env.VERCEL_ENV}.`);
    }
  } catch (error) {
    stderr.write(`Validation failed: ${error.message}\n`);
    return 2;
  }

  if (!send) {
    stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    stderr.write('Trockenlauf, nichts gesendet\n');
    return 0;
  }

  try {
    const response = await fetch(payload.keyLocation, { method: 'GET', redirect: 'manual' });
    stdout.write(`Key preflight status: ${response.status}\n`);
    if (response.status !== 200 || (await response.text()).trim() !== payload.key) {
      stderr.write(`Key preflight failed (status ${response.status}).\n`);
      return 2;
    }
  } catch (error) {
    stderr.write(`Key preflight network error (status unavailable): ${error.message}\n`);
    return 2;
  }

  try {
    const response = await fetch('https://api.indexnow.org/indexnow', {
      method: 'POST',
      redirect: 'manual',
      headers: { 'content-type': 'application/json; charset=utf-8' },
      body: JSON.stringify(payload),
    });
    stdout.write(`IndexNow status: ${response.status}\n`);
    return response.status === 200 || response.status === 202 ? 0 : 1;
  } catch (error) {
    stderr.write(`IndexNow network error (status unavailable): ${error.message}\n`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2));
}
