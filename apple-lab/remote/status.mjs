const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export function createPublisher({ repo, sha, session, token, fetchImpl = fetch, delay = sleep, warn = console.warn }) {
  async function publish(state, description, url, { attempts = 3, timeout = 15000 } = {}) {
    for (let attempt = 1; attempt <= attempts; attempt++) {
      try {
        const response = await fetchImpl(`https://api.github.com/repos/${repo}/statuses/${sha}`, {
          method: 'POST', headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'User-Agent': 'ATMA-Apple-Lab' },
          body: JSON.stringify({ state, context: `apple-lab/${session}`, description, ...(url ? { target_url: url } : {}) }), signal: AbortSignal.timeout(timeout) });
        await response.arrayBuffer();
        if (!response.ok) throw Object.assign(new Error('HTTP ' + response.status), { status: response.status });
        return;
      } catch (error) {
        const code = error.status ?? error.cause?.code ?? error.name;
        if (attempt === attempts || error.status && error.status < 500 && error.status !== 429) throw new Error(`Cannot publish session state (${code})`);
        warn(`Retrying session status (${code}, attempt ${attempt})`); await delay(attempt * 1000);
      }
    }
  }
  async function progress(stage) {
    try { await publish('pending', `apple-lab:${stage}`, undefined, { attempts: 1, timeout: 6000 }); }
    catch (error) { warn(`Progress update skipped: ${error.message}`); }
  }
  return { publish, progress };
}
