import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const source = fs.readFileSync(process.argv[2], 'utf8')
  .replace(/^import .*\r?\n/gm, '')
  .replace(/^export /gm, '')
const context = {
  os: { EOL: '\n' },
  util: { runGitAsync: async () => '' },
  console,
}
vm.runInNewContext(source + '\nglobalThis.Patcher = GitPatcher', context)
const patcher = new context.Patcher('', '', false)
let active = 0
let peak = 0
patcher.getAppliesTo = async (path) => {
  active += 1
  peak = Math.max(peak, active)
  await new Promise((resolve) => setTimeout(resolve, 2))
  active -= 1
  return [{ path }]
}
patcher.resetRepoFiles = async () => {}
patcher.writePatchInfo = async () => {}
const patches = Array.from({ length: 257 }, (_, index) => ({
  patchPath: `patch-${index}`,
  patchInfoPath: `info-${index}`,
  reason: 0,
}))
const results = await patcher.performApplyForPatches(patches)
assert.equal(results.length, patches.length, 'Every patch must be processed')
assert.ok(peak > 1 && peak <= 8, `Expected bounded parallel metadata reads, observed ${peak}`)
console.log(JSON.stringify({ patches: results.length, maximumParallelGitReads: peak }))
