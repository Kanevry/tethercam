/** Pure SEO helpers: analyseHtml extracts metadata and raw JSON-LD; visibleText
 * strips non-visible markup; checkGraph/checkDateModified return diagnostics;
 * parseSitemap extracts locations, dates and language alternatives. */

const entities = {
  quot: '"', amp: '&', apos: "'", lt: '<', gt: '>', nbsp: ' ',
  ldquo: '“', rdquo: '”', lsquo: '‘', rsquo: '’', mdash: '—',
  ndash: '–', middot: '·', hellip: '…', copy: '©', reg: '®',
  trade: '™', bull: '•', laquo: '«', raquo: '»',
  auml: 'ä', ouml: 'ö', uuml: 'ü', Auml: 'Ä', Ouml: 'Ö', Uuml: 'Ü', szlig: 'ß',
};

function decode(text) {
  return text.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (entity, name) => {
    if (!name.startsWith('#')) return entities[name] ?? entity;
    const point = name[1].toLowerCase() === 'x'
      ? Number.parseInt(name.slice(2), 16) : Number(name.slice(1));
    return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff)
      ? String.fromCodePoint(point) : '\uFFFD';
  });
}

function attributes(tag) {
  const result = {};
  for (const match of tag.matchAll(/([^\s=<>/]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) {
    result[match[1].toLowerCase()] = decode(match[2] ?? match[3] ?? match[4]);
  }
  return result;
}

export function analyseHtml(html) {
  const head = html.split(/<\/head\s*>/i)[0];
  const result = {
    title: decode(head.match(/<title\b[^>]*>([\s\S]*?)<\/title\s*>/i)?.[1] ?? '').trim(),
    description: '', canonical: [], hreflang: {}, ogImage: '', twitterImage: '',
    h1Count: [...html.matchAll(/<h1\b[^>]*>/gi)].length, ldBlocks: [], hrefs: [],
  };
  for (const match of head.matchAll(/<(?:meta|link)\b[^>]*>/gi)) {
    const a = attributes(match[0]);
    if (a.name?.toLowerCase() === 'description') result.description = a.content ?? '';
    if (a.property?.toLowerCase() === 'og:image') result.ogImage = a.content ?? '';
    if (a.name?.toLowerCase() === 'twitter:image') result.twitterImage = a.content ?? '';
    const rel = a.rel?.toLowerCase().split(/\s+/) ?? [];
    if (rel.includes('canonical')) result.canonical.push(a.href ?? '');
    if (rel.includes('alternate') && a.hreflang) result.hreflang[a.hreflang] = a.href ?? '';
  }
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    if (attributes(match[1]).type?.toLowerCase() === 'application/ld+json') {
      result.ldBlocks.push(match[2]);
    }
  }
  for (const match of html.matchAll(/<[a-z][^>]*>/gi)) {
    const a = attributes(match[0]);
    if (Object.hasOwn(a, 'href')) result.hrefs.push(a.href);
  }
  return result;
}

export function visibleText(html) {
  const body = html.match(/<body\b[^>]*>([\s\S]*?)(?:<\/body\s*>|$)/i)?.[1] ?? html;
  return decode(body.replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ').replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ').trim();
}

function hasType(node, type) {
  return node !== null && typeof node === 'object'
    && [node['@type']].flat().includes(type);
}

export function checkGraph(ldBlocks) {
  const errors = [];
  if (ldBlocks.length !== 1) errors.push(`Expected exactly 1 JSON-LD block; found ${ldBlocks.length}`);
  for (const [index, raw] of ldBlocks.entries()) {
    let document;
    try { document = JSON.parse(raw); }
    catch (error) { errors.push(`JSON-LD block ${index + 1}: JSON parse error: ${error.message}`); continue; }
    if (!Array.isArray(document?.['@graph'])) {
      errors.push(`JSON-LD block ${index + 1}: missing @graph array`);
      continue;
    }
    const graph = document['@graph'];
    const ids = new Set(graph.filter(n => n && typeof n === 'object' && n['@id']).map(n => n['@id']));
    const forbiddenTypes = new Set(['SearchAction', 'Speakable', 'MedicalWebPage', 'AggregateRating', 'Review', 'HowTo']);
    const forbiddenProperties = new Set(['speakable', 'aggregateRating', 'review', 'potentialAction']);
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      if (Array.isArray(value)) { value.forEach(visit); return; }
      if (Object.keys(value).length === 1 && Object.hasOwn(value, '@id') && !ids.has(value['@id'])) {
        errors.push(`Unresolved @id reference: ${value['@id']}`);
      }
      for (const type of [value['@type']].flat()) {
        if (forbiddenTypes.has(type)) errors.push(`Forbidden @type: ${type}`);
      }
      for (const [key, child] of Object.entries(value)) {
        if (forbiddenProperties.has(key)) errors.push(`Forbidden property: ${key}`);
        visit(child);
      }
    }
    visit(graph);
    const sites = graph.filter(n => hasType(n, 'WebSite'));
    if (sites.length !== 1) errors.push(`Expected exactly 1 WebSite node; found ${sites.length}`);
    for (const site of sites) {
      if (typeof site.alternateName !== 'string' || !site.alternateName.trim()) {
        errors.push('WebSite alternateName must be a nonempty string');
      } else if (graph.some(n => hasType(n, 'SoftwareApplication') && n.alternateName === site.alternateName)) {
        errors.push('WebSite alternateName must differ from SoftwareApplication alternateName');
      }
    }
  }
  return errors;
}

export function checkDateModified(graph, visibleDate) {
  const errors = [];
  const pages = graph.filter(n => hasType(n, 'WebPage'));
  if (!pages.length) errors.push('Missing WebPage for dateModified check');
  for (const page of pages) {
    const present = Object.hasOwn(page, 'dateModified');
    if (visibleDate == null || visibleDate === '') {
      if (present) errors.push(`WebPage ${page['@id']}: dateModified ${JSON.stringify(page.dateModified)} without visible date`);
    } else if (!present || page.dateModified !== visibleDate) {
      errors.push(`WebPage ${page['@id']}: dateModified ${JSON.stringify(page.dateModified)} differs from visible date ${visibleDate}`);
    }
  }
  return errors;
}

export function parseSitemap(xml) {
  const root = xml.match(/<urlset\b[^>]*>/i)?.[0] ?? '';
  return {
    hasXhtmlNs: attributes(root)['xmlns:xhtml'] === 'http://www.w3.org/1999/xhtml',
    urls: [...xml.matchAll(/<url\b[^>]*>([\s\S]*?)<\/url\s*>/gi)].map(([, block]) => {
      const alternates = {};
      for (const match of block.matchAll(/<xhtml:link\b[^>]*>/gi)) {
        const a = attributes(match[0]);
        if (a.rel === 'alternate' && a.hreflang) alternates[a.hreflang] = a.href ?? '';
      }
      return {
        loc: decode(block.match(/<loc\b[^>]*>([\s\S]*?)<\/loc\s*>/i)?.[1] ?? '').trim(),
        lastmod: decode(block.match(/<lastmod\b[^>]*>([\s\S]*?)<\/lastmod\s*>/i)?.[1] ?? '').trim(),
        alternates,
      };
    }),
  };
}
