param(
    [Parameter(Mandatory)][string]$PythonRuntime,
    [string]$Ffmpeg,
    [string]$FfmpegLicense,
    [string]$OutputDirectory,
    [string]$WheelCache,
    [string]$SigningThumbprint
)

$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot '..\out\windows' }
$runtime = (Resolve-Path -LiteralPath $PythonRuntime).Path
$python = Join-Path $runtime 'python.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $python -c 'import sys; assert sys.version_info[:2] == (3, 11) and sys.maxsize > 2**32'
if ($LASTEXITCODE) { throw 'Provide a Windows x64 Python 3.11 runtime.' }

$output = [IO.Path]::GetFullPath($OutputDirectory)
$build = Join-Path $output ('build-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $build 'payload'
[void](New-Item -Path $payload -ItemType Directory -Force)
$runtimeTarget = Join-Path $payload 'runtime'
[void](New-Item -Path $runtimeTarget -ItemType Directory)
$runtimeParts = 'python.exe','python3.dll','python311.dll','vcruntime140.dll','vcruntime140_1.dll','LICENSE.txt','DLLs','Lib'
foreach ($name in $runtimeParts) {
    Copy-Item -LiteralPath (Join-Path $runtime $name) -Destination $runtimeTarget -Recurse
}
foreach ($name in 'phonedisk','web','run.py') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $payload -Recurse
}
if ($WheelCache) {
    Copy-Item -LiteralPath (Resolve-Path -LiteralPath $WheelCache).Path -Destination (Join-Path $payload 'vendor') -Recurse
} else {
    & $python -B (Join-Path $PSScriptRoot 'prepare_deps.py') (Join-Path $payload 'vendor')
    if ($LASTEXITCODE) { throw 'Could not prepare verified dependencies.' }
}
if ($Ffmpeg) {
    if ($SigningThumbprint -and -not $FfmpegLicense) { throw 'Provide the FFmpeg distribution license for the signed package.' }
    $media = Join-Path $payload 'media'
    [void](New-Item -Path $media -ItemType Directory)
    Copy-Item -LiteralPath $Ffmpeg -Destination (Join-Path $media 'ffmpeg.exe')
    if ($FfmpegLicense) { Copy-Item -LiteralPath $FfmpegLicense -Destination $media }
}

$icon = Join-Path $build 'PhoneDisk.ico'
Add-Type -AssemblyName System.Drawing
$original = [Drawing.Image]::FromFile((Join-Path $PSScriptRoot '..\Assets.xcassets\AppIcon.appiconset\icon.png'))
try {
    $bitmap = [Drawing.Bitmap]::new($original, 128, 128)
    $bytes = [IO.MemoryStream]::new()
    $bitmap.Save($bytes, [Drawing.Imaging.ImageFormat]::Png)
    $ico = [IO.BinaryWriter]::new([IO.File]::Create($icon))
    try {
        $ico.Write([UInt16]0)
        $ico.Write([UInt16]1)
        $ico.Write([UInt16]1)
        $ico.Write([byte[]]@(128,128,0,0))
        $ico.Write([UInt16]1)
        $ico.Write([UInt16]32)
        $ico.Write([UInt32]$bytes.Length)
        $ico.Write([UInt32]22)
        $ico.Write($bytes.ToArray())
    } finally { $ico.Dispose(); $bytes.Dispose(); $bitmap.Dispose() }
} finally { $original.Dispose() }

function Sign-PackageFile([string]$Path) {
    if (-not $SigningThumbprint) { return }
    $certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $SigningThumbprint)
    $result = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
    if ($result.Status -ne 'Valid') { throw ('Windows code signing returned ' + $result.Status) }
}

$app = Join-Path $payload 'PhoneDisk.exe'
$common = '/nologo','/target:winexe','/platform:x64','/codepage:65001',('/win32icon:' + $icon),'/optimize+',
    '/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll'
& $compiler @common ('/out:' + $app) '/reference:System.Web.Extensions.dll' (Join-Path $PSScriptRoot 'Windows\PhoneDisk.cs')
if ($LASTEXITCODE) { throw 'Could not compile PhoneDisk.exe.' }
Sign-PackageFile $app

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = Join-Path $build 'payload.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $archive)
$setup = Join-Path $output 'PhoneDisk-Setup.exe'
& $compiler @common ('/out:' + $setup) ('/resource:' + $archive + ',PhoneDiskPayload') '/reference:System.IO.Compression.dll' '/reference:System.IO.Compression.FileSystem.dll' '/reference:Microsoft.CSharp.dll' (Join-Path $PSScriptRoot 'Windows\Setup.cs')
if ($LASTEXITCODE) { throw 'Could not compile the Windows installer.' }
Sign-PackageFile $setup
Get-Item -LiteralPath $setup | Select-Object FullName,Length
