param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if(-not $OutputDirectory){$OutputDirectory=Join-Path $repo 'dist'}
$null=New-Item -ItemType Directory -Force -Path $OutputDirectory
$stage=Join-Path ([IO.Path]::GetTempPath()) ('handoff-build-'+[Guid]::NewGuid().ToString('N'))
try {
    $null=New-Item -ItemType Directory -Path $stage
    $null=New-Item -ItemType Directory -Path (Join-Path $stage 'payload\app\windows') -Force
    $null=New-Item -ItemType Directory -Path (Join-Path $stage 'payload\windows')
    foreach($file in @('Setup.ps1','Setup.Core.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stage 'payload\app\windows')}
    # Package only reviewed sources, never a developer's runtime config/logs.
    $allowed=@('DisplayHandoff.ps1','DisplayNative.cs','DisplayHandoffLauncher.cs','Start-Worker.ps1','Build-Launcher.ps1','MouseBridge.cs','ReadOptions.cs','OptionsPatch.cs','Configure-OptionsGestures.ps1','deskflow-server.template.conf')
    foreach($file in $allowed){Copy-Item -LiteralPath (Join-Path $repo ('windows\'+$file)) -Destination (Join-Path $stage 'payload\windows')}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=Join-Path $stage 'payload.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $stage 'payload'),$zip)
    $compiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    $output=Join-Path $OutputDirectory 'DisplayHandoffSetup.exe'
    & $compiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll ('/resource:'+$zip+',payload.zip') ('/out:'+$output) (Join-Path $PSScriptRoot 'SetupBootstrap.cs')
    if($LASTEXITCODE-ne 0){throw 'Setup compilation failed.'}
    Write-Output $output
} finally {if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}
