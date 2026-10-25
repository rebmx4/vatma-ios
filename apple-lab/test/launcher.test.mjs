import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

test('Windows launcher passes one explicit D: browser profile argument', { skip: process.platform !== 'win32' }, () => {
  const script = fileURLToPath(new URL('../Start-Apple-Lab.ps1', import.meta.url)).replaceAll("'", "''");
  // Exercise the launcher with only the external process and HTTP boundaries replaced.
  const command = `function Invoke-RestMethod { @{ app='ATMA Apple Lab' } }
function Start-Process { param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle)
  $global:labCaptured = @{ file=$FilePath; arguments=@($ArgumentList); cwd=$WorkingDirectory }
}
& '${script}'
$global:labCaptured | ConvertTo-Json -Compress`;
  const result = JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-Command', command], {
    encoding: 'utf8', windowsHide: true, env: { ...process.env, TEMP: 'D:/tmp', TMP: 'D:/tmp', PSModuleAnalysisCachePath: 'D:/caches/powershell/ModuleAnalysisCache' },
  }));
  const profiles = result.arguments.filter(value => value.startsWith('--user-data-dir='));
  assert.equal(profiles.length, 1);
  assert.match(profiles[0], /^--user-data-dir="D:\\.*\\out\\apple-lab\\browser-profile"$/i);
  assert.equal(result.arguments.length, 9);
  const preferences = JSON.parse(readFileSync(new URL('../../out/apple-lab/browser-profile/Default/Preferences', import.meta.url), 'utf8'));
  assert.match(preferences.download.default_directory, /^D:\\.*\\out\\apple-lab\\downloads$/i);
});
