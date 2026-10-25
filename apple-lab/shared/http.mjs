export async function readBody(req, limit = 8192) {
  const chunks = []; let length = 0;
  for await (const chunk of req) {
    length += chunk.length;
    if (length > limit) throw Object.assign(new Error('Request too large'), { status: 413 });
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function json(res, status, value) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  res.end(JSON.stringify(value));
}

export function safeError(error) {
  return String(error?.message ?? error).replace(/Bearer\s+\S+/gi, 'Bearer [redacted]').slice(0, 300);
}
