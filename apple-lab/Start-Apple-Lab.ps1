$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $taskRoot.StartsWith('D:\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Apple Lab must be stored on D:.' }
$env:TEMP = 'D:\tmp'
$env:TMP = 'D:\tmp'
$env:npm_config_cache = 'D:\npm-cache'
$env:PSModuleAnalysisCachePath = 'D:\caches\powershell\ModuleAnalysisCache'
$taskOutput = Join-Path $taskRoot 'out\apple-lab'
New-Item -ItemType Directory -Force -Path $taskOutput, 'D:\tmp', 'D:\caches\apple-lab\browser' | Out-Null
$taskNode = (Get-Command node.exe -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules\ws\package.json'))) {
    Push-Location $taskRoot
    try { & npm.cmd ci --prefix apple-lab --ignore-scripts --no-audit --no-fund; if ($LASTEXITCODE -ne 0) { throw 'Cannot install Apple Lab dependency.' } }
    finally { Pop-Location }
}
$taskHealthy = $false
try { $taskState = Invoke-RestMethod 'http://127.0.0.1:4186/api/state' -TimeoutSec 2; $taskHealthy = $taskState.app -eq 'ATMA Apple Lab' } catch { }
if (-not $taskHealthy) {
    Start-Process -FilePath $taskNode -ArgumentList @(('"' + (Join-Path $PSScriptRoot 'local\server.mjs') + '"')) -WorkingDirectory $taskRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskOutput 'controller.log') -RedirectStandardError (Join-Path $taskOutput 'controller-error.log') | Out-Null
    for ($taskAttempt = 0; $taskAttempt -lt 30; $taskAttempt++) {
        try { $taskState = Invoke-RestMethod 'http://127.0.0.1:4186/api/state' -TimeoutSec 1; if ($taskState.app -eq 'ATMA Apple Lab') { $taskHealthy = $true; break } } catch { }
        Start-Sleep -Milliseconds 200
    }
    if (-not $taskHealthy) { throw "Panel did not start. See $taskOutput\controller-error.log" }
}
$taskBrowser = @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe', 'C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $taskBrowser) { throw 'Microsoft Edge was not found. No browser was installed or launched with a default profile.' }
$taskProfile = Join-Path $taskOutput 'browser-profile'
New-Item -ItemType Directory -Force -Path $taskProfile | Out-Null
$taskDownloads = Join-Path $taskOutput 'downloads'
$taskDefaults = Join-Path $taskProfile 'Default'
New-Item -ItemType Directory -Force -Path $taskDownloads, $taskDefaults | Out-Null
$taskPreferences = Join-Path $taskDefaults 'Preferences'
if (-not (Test-Path -LiteralPath $taskPreferences)) {
    $taskSettings = @{ download = @{ default_directory = $taskDownloads; prompt_for_download = $false; directory_upgrade = $true }; savefile = @{ default_directory = $taskDownloads } }
    [System.IO.File]::WriteAllText($taskPreferences, ($taskSettings | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
}
$taskSavedSettings = Get-Content -LiteralPath $taskPreferences -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ([string]$taskSavedSettings.download.default_directory).StartsWith('D:\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Apple Lab download folder must stay on D:.' }
$taskArguments = @('--app=http://127.0.0.1:4186/', ('--user-data-dir="' + $taskProfile + '"'), '--disk-cache-dir=D:\caches\apple-lab\browser', '--no-first-run', '--no-default-browser-check', '--disable-breakpad', '--disable-crash-reporter', '--disable-features=Crashpad', '--window-size=1280,920')
Start-Process -FilePath $taskBrowser -ArgumentList $taskArguments -WorkingDirectory $taskRoot -WindowStyle Normal | Out-Null
