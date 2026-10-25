import { isIP } from 'node:net';

function publicAddress(value) {
  if (isIP(value) !== 4) return false;
  const [a, b] = value.split('.').map(Number);
  return a > 0 && a < 224 && ![10, 127].includes(a) && !(a === 169 && b === 254) &&
    !(a === 172 && b >= 16 && b <= 31) && !(a === 192 && b === 168) &&
    !(a === 100 && b >= 64 && b <= 127) && !(a === 198 && [18, 19].includes(b));
}
async function secureResolve(name) {
  const response = await fetch('https://cloudflare-dns.com/dns-query?name=' + encodeURIComponent(name) + '&type=A', {
    headers: { Accept: 'application/dns-json' }, signal: AbortSignal.timeout(6000), redirect: 'error',
  });
  if (!response.ok) throw new Error('DNS туннеля недоступен');
  return response.json();
}
export function createTunnelLookup({ resolve = secureResolve, now = Date.now } = {}) {
  const cache = new Map(), pending = new Map();
  async function addresses(host) {
    if (!/^[a-z0-9-]+\.trycloudflare\.com$/.test(host)) throw new Error('Недопустимый домен туннеля');
    if (cache.get(host)?.until > now()) return cache.get(host).addresses;
    if (pending.has(host)) return pending.get(host);
    const task = (async () => {
      const data = await resolve(host);
      const answers = data.Status === 0 ? data.Answer?.filter(value => value.type === 1 &&
        value.name?.replace(/\.$/, '').toLowerCase() === host && publicAddress(value.data)) : [];
      if (!answers?.length) throw new Error('DNS туннеля не вернул публичный адрес');
      const result = answers.map(value => ({ address: value.data, family: 4 }));
      cache.set(host, { addresses: result, until: now() + Math.max(1, Math.min(60, ...answers.map(value => value.TTL || 1))) * 1000 });
      return result;
    })();
    pending.set(host, task);
    try { return await task; } finally { pending.delete(host); }
  }
  return (host, options, callback) => {
    addresses(host).then(values => options?.all ? callback(null, values) : callback(null, values[0].address, 4), callback);
  };
}
