import { spawn } from 'node:child_process';

export async function gitCredential(cwd, repo) {
  return new Promise((resolve, reject) => {
    const child = spawn('git', ['-C', cwd, 'credential', 'fill'], {
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'Never' }, windowsHide: true, stdio: 'pipe' });
    let output = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('GitHub: не удалось прочитать сохранённый вход Git')); }, 20000);
    child.stdout.on('data', data => { output += data; }); child.stderr.resume();
    child.once('error', () => { clearTimeout(timer); reject(new Error('Git не найден')); });
    child.once('close', code => {
      clearTimeout(timer);
      const password = output.split(/\r?\n/).find(line => line.startsWith('password='))?.slice(9);
      output = '';
      if (code || !password) reject(new Error('Нет сохранённого входа GitHub для этого репозитория'));
      else resolve(password);
    });
    child.stdin.end(`protocol=https\nhost=github.com\npath=${repo}.git\nusername=${repo.split('/')[0]}\n\n`);
  });
}

export class GitHub {
  constructor({ repo, cwd, workflow = 'atma-apple-preview.yml', workflowRef = 'apple-simulator-lab', sourceRef = 'atma-browser-testflight', credential = gitCredential, api = 'https://api.github.com' }) {
    Object.assign(this, { repo, cwd, workflow, workflowRef, sourceRef, credential, api });
  }
  async request(path, method = 'GET', body) {
    this.token ??= this.credential(this.cwd, this.repo).catch(error => { this.token = null; throw error; });
    const response = await fetch(`${this.api}/repos/${this.repo}${path}`, {
      method, headers: { Authorization: `Bearer ${await this.token}`, Accept: 'application/vnd.github+json',
        'User-Agent': 'ATMA-Apple-Lab', 'X-GitHub-Api-Version': '2022-11-28' },
      ...(body == null ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(20000), redirect: 'error',
    });
    if (!response.ok) {
      if (response.status === 401) this.token = null;
      throw Object.assign(new Error(`GitHub ${response.status}: ${method === 'POST' ? 'операция не выполнена' : 'данные недоступны'}`), { status: response.status });
    }
    return response.status === 204 ? null : response.json();
  }
  async source() {
    const [repo, commit] = await Promise.all([this.request(''), this.request('/commits/' + encodeURIComponent(this.sourceRef))]);
    if (!repo.permissions?.push) throw new Error('Нужен доступ к запуску Actions этого репозитория');
    if (repo.private) throw new Error('Профиль настроен для публичного репозитория; платный запуск не включён');
    if (!/^[a-f0-9]{40}$/.test(commit.sha)) throw new Error('Некорректная ревизия исходников');
    return commit.sha;
  }
  dispatch(session) {
    return this.request(`/actions/workflows/${this.workflow}/dispatches`, 'POST', { ref: this.workflowRef,
      inputs: { session: session.id, public_key: session.key.publicKey, device: session.device, revision: session.revision } });
  }
  async findRun(session) {
    const data = await this.request(`/actions/workflows/${this.workflow}/runs?event=workflow_dispatch&per_page=50`);
    return data.workflow_runs.find(run => run.display_title === `Apple Lab · ${session.id} · ${session.device}` &&
      run.head_branch === this.workflowRef && run.path === `.github/workflows/${this.workflow}`);
  }
  run(id) { return this.request(`/actions/runs/${id}`); }
  async previewUrl(session) {
    const states = await this.request(`/commits/${session.run.head_sha}/statuses?per_page=100`);
    const state = states.find(value => value.context === `apple-lab/${session.id}`);
    if (!state?.target_url || state.state !== 'success') return null;
    const url = new URL(state.target_url);
    if (url.protocol !== 'https:' || !/^[a-z0-9-]+\.trycloudflare\.com$/.test(url.hostname) ||
        url.port || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new Error('Некорректный адрес удалённого Simulator');
    return url.origin;
  }
  async cancel(session) {
    if (!session.run || session.run.display_title !== `Apple Lab · ${session.id} · ${session.device}`) throw new Error('Отмена чужого сеанса запрещена');
    const current = await this.run(session.run.id);
    if (current.status !== 'completed') await this.request(`/actions/runs/${session.run.id}/cancel`, 'POST');
  }
}
