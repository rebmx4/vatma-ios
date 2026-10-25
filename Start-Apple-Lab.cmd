@echo off
setlocal
set "TEMP=D:\tmp"
set "TMP=D:\tmp"
set "npm_config_cache=D:\npm-cache"
set "PSModuleAnalysisCachePath=D:\caches\powershell\ModuleAnalysisCache"
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apple-lab\Start-Apple-Lab.ps1"
if errorlevel 1 pause
