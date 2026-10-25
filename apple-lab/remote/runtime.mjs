import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export function runtime() {
  const root = resolve(process.env.APPLE_LAB_APP_DIR);
  const lab = fileURLToPath(new URL('..', import.meta.url));
  const { LAB_SESSION: session, LAB_REVISION: revision, LAB_DEVICE: device, GITHUB_RUN_ID: runId } = process.env;
  if (!/^[a-f0-9]{32}$/.test(session ?? '') || !/^[a-f0-9]{40}$/.test(revision ?? '') || !['iphone', 'ipad'].includes(device)) throw new Error('Invalid preview inputs');
  process.chdir(root);
  const cache = resolve(root, '.cache/apple-lab');
  const childEnv = { ...process.env, TMPDIR: cache + '/tmp', npm_config_cache: cache + '/npm',
    HOMEBREW_CACHE: cache + '/homebrew', HOMEBREW_LOGS: cache + '/brew-logs', HOMEBREW_TEMP: cache + '/tmp',
    PYTHONDONTWRITEBYTECODE: '1', HOMEBREW_NO_AUTO_UPDATE: '1' };
  // Helpers and application build scripts do not inherit workflow credentials or command files.
  for (const key of Object.keys(childEnv)) if (/TOKEN|SECRET|PASSWORD|PRIVATE|GITHUB_ENV|GITHUB_OUTPUT|GITHUB_PATH|ACTIONS_RUNTIME/.test(key)) delete childEnv[key];
  mkdirSync(childEnv.TMPDIR, { recursive: true }); mkdirSync(resolve(root, 'out'), { recursive: true });
  function command(binary, args, options = {}) {
    const result = spawnSync(binary, args, { cwd: root, env: childEnv, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
      stdio: options.capture ? 'pipe' : 'inherit', timeout: options.timeout ?? 600000, input: options.input });
    if (result.status !== 0) throw new Error(`${binary} failed (${result.status ?? result.error?.code})`);
    return result.stdout?.trim();
  }
  if (command('git', ['rev-parse', 'HEAD'], { capture: true }) !== revision) throw new Error('Source SHA mismatch');
  async function publish(state, description, url) {
    const response = await fetch(`https://api.github.com/repos/${process.env.GITHUB_REPOSITORY}/statuses/${process.env.GITHUB_SHA}`, {
      method: 'POST', headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: 'application/vnd.github+json', 'User-Agent': 'ATMA-Apple-Lab' },
      body: JSON.stringify({ state, context: `apple-lab/${session}`, description, ...(url ? { target_url: url } : {}) }), signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error(`Cannot publish session state (${response.status})`);
  }
  const progress = stage => publish('pending', `apple-lab:${stage}`);
  const planFile = resolve(root, 'out/apple-lab-build-plan.json');
  const readPlan = () => { const plan = JSON.parse(readFileSync(planFile, 'utf8')); if (plan.identity.manifest.revision !== revision || plan.device !== device) throw new Error('Build plan mismatch'); return plan; };
  const inspect = app => ({ info: JSON.parse(command('plutil', ['-convert', 'json', '-o', '-', app + '/Info.plist'], { capture: true })),
    arch: command('lipo', ['-archs', app + '/ATMA'], { capture: true }) });
  return { root, lab, cache, session, revision, device, runId, childEnv, command, publish, progress, planFile, readPlan, inspect };
}
