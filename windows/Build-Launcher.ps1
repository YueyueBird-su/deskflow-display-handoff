$ErrorActionPreference='Stop'
$displayHandoffSource=Join-Path $PSScriptRoot 'DisplayHandoffLauncher.cs'
$displayHandoffOutput=Join-Path $PSScriptRoot 'DisplayHandoffLauncher.exe'
$displayHandoffTemporary=Join-Path $PSScriptRoot 'DisplayHandoffLauncher.build.exe'
$displayHandoffCompiler=Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if(-not(Test-Path $displayHandoffCompiler)){throw 'Use Windows PowerShell 5.1 with the .NET Framework C# compiler.'}
if(-not(Test-Path $displayHandoffSource)){throw 'DisplayHandoffLauncher.cs is missing.'}
if(-not(Test-Path (Join-Path $PSScriptRoot 'DisplayHandoff.ps1'))){throw 'DisplayHandoff.ps1 must be in the same directory.'}
if(-not(Test-Path (Join-Path $PSScriptRoot 'Start-Worker.ps1'))){throw 'Start-Worker.ps1 must be in the same directory.'}
try {
    & $displayHandoffCompiler '/nologo' '/target:winexe' '/optimize+' ('/out:'+$displayHandoffTemporary) $displayHandoffSource
    if($LASTEXITCODE-ne 0){throw 'Launcher compilation failed.'}
    [IO.File]::Copy($displayHandoffTemporary,$displayHandoffOutput,$true)
    Write-Output 'Built DisplayHandoffLauncher.exe as a Windows application.'
} finally {
    if(Test-Path $displayHandoffTemporary){Remove-Item $displayHandoffTemporary}
}
