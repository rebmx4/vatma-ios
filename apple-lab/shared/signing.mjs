import { createHash, createPublicKey, generateKeyPairSync, randomBytes, sign, verify } from 'node:crypto';

const digest = body => createHash('sha256').update(body ?? Buffer.alloc(0)).digest('hex');
const message = (session, time, nonce, method, path, body) => Buffer.from(
  [session, time, nonce, method, path, digest(body)].join('\n'));

export function createSessionKey() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  return { privateKey, publicKey: publicKey.export({ type: 'spki', format: 'der' }).toString('base64url') };
}

export function signRequest(privateKey, session, method, path, body, now = Date.now()) {
  const time = String(now);
  const nonce = randomBytes(16).toString('hex');
  return {
    'x-lab-session': session, 'x-lab-time': time, 'x-lab-nonce': nonce,
    'x-lab-signature': sign(null, message(session, time, nonce, method, path, body), privateKey).toString('base64url'),
  };
}

export function createVerifier({ publicKey, session, now = Date.now }) {
  if (!/^[a-f0-9]{32}$/.test(session)) throw new Error('Invalid session ID');
  const key = createPublicKey({ key: Buffer.from(publicKey, 'base64url'), type: 'spki', format: 'der' });
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('Ed25519 key required');
  const used = new Map();
  return (headers, method, path, body) => {
    const time = headers['x-lab-time'];
    const nonce = headers['x-lab-nonce'];
    const signature = headers['x-lab-signature'];
    const current = now();
    if (headers['x-lab-session'] !== session || !/^\d{1,16}$/.test(time ?? '') ||
        Math.abs(current - Number(time)) > 30000 || !/^[a-f0-9]{32}$/.test(nonce ?? '') ||
        !/^[A-Za-z0-9_-]{86}$/.test(signature ?? '')) return false;
    for (const [value, expiry] of used) if (expiry < current) used.delete(value);
    if (used.has(nonce) || used.size >= 4096) return false;
    try {
      if (!verify(null, message(session, time, nonce, method, path, body), key, Buffer.from(signature, 'base64url'))) return false;
    } catch { return false; }
    used.set(nonce, current + 60000);
    return true;
  };
}
