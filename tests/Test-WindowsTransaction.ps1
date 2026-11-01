# Integration fixtures: fake native display API and in-memory task scheduler.
# No real display API, process control, task registration or app config is used.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'app\windows\Setup.Core.ps1')
Add-Type @'
namespace DisplayHandoff {
    public sealed class FixtureAdapter {
        public string Device,MonitorId,Mode; public int Flags,X,Width;
    }
    public static class Native {
        public static FixtureAdapter[] Adapters() {
            string mode=System.Convert.ToBase64String(new byte[220]);
            return new [] {
                new FixtureAdapter {Device="LEFT",MonitorId="fixture-left",Flags=5,X=0,Width=1920,Mode=mode},
                new FixtureAdapter {Device="RIGHT",MonitorId="fixture-right",Flags=1,X=1920,Width=1920,Mode=mode}
            };
        }
        public static int Input(string device,int value) { if(value!=-1)throw new System.Exception("Fixture prohibits DDC writes");return 15; }
        public static void TestRestore(string device,string mode) { }
    }
}
'@
function Assert-LocalDesktop { }
function Assert-DeskflowStopped { }
$script:fixtureTasks=@{}
$script:registrationFails=$false
function Get-ScheduledTask {param($TaskName,$ErrorAction) foreach($name in $TaskName){if($script:fixtureTasks.ContainsKey($name)){$script:fixtureTasks[$name]}}}
function New-ScheduledTaskAction {param($Execute,$WorkingDirectory) [pscustomobject]@{Execute=$Execute;WorkingDirectory=$WorkingDirectory}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{LogonType=$LogonType;RunLevel=$RunLevel}}
function New-ScheduledTaskTrigger {param([switch]$AtLogOn,$User) [pscustomobject]@{AtLogon=$true}}
function New-ScheduledTaskSettingsSet {param($ExecutionTimeLimit,$MultipleInstances,$RestartCount,$RestartInterval,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) [pscustomobject]@{RestartCount=$RestartCount}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$Trigger,$Settings) if($script:registrationFails){throw 'Fixture: registration fails'};$script:fixtureTasks[$TaskName]=[pscustomobject]@{Actions=@($Action);Principal=$Principal}}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm) $script:fixtureTasks.Remove($TaskName)}
function Stop-ScheduledTask {param($TaskName)}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('handoff-transaction-'+[Guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA;$oldRoaming=$env:APPDATA
$script:checks=0
function Check($Condition,$Message){$script:checks++;if(-not $Condition){throw ('FAIL: '+$Message)}}
function Reject([scriptblock]$Action,$Message){$script:checks++;$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};if(-not $rejected){throw ('FAIL: accepted '+$Message)}}
try {
    $env:LOCALAPPDATA=Join-Path $testRoot 'local'
    $env:APPDATA=Join-Path $testRoot 'roaming'
    $null=New-Item -ItemType Directory (Join-Path $env:APPDATA 'Deskflow') -Force
    $null=New-Item -ItemType Directory $env:LOCALAPPDATA -Force
    $ini=Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
    $original="[server]`r`nexternalConfig=false`r`nclipboardSharing=true`r`n[client]`r`nserverHostname=fixture`r`n"
    Write-HandoffText $ini $original
    $before=Get-HandoffHash $ini
    $settings=New-HandoffSettings 'win-fixture' 'mac-fixture' 15 17 181 180 $false
    $root=Install-Handoff $settings $repo (Join-Path $repo 'app\windows\SetupBootstrap.cs')
    Check ($script:fixtureTasks.Count-eq 1) 'register one fixture task'
    Check ($script:fixtureTasks.DisplayHandoffApp.Principal.LogonType-eq 'Interactive') 'interactive task'
    Check ($script:fixtureTasks.DisplayHandoffApp.Principal.RunLevel-eq 'Limited') 'unprivileged task'
    Check (Test-Path (Join-Path $root 'DisplayHandoffLauncher.exe')) 'build background launcher'
    Check ((Get-HandoffHash (Join-Path $root 'setup-backup\Deskflow.conf.bak'))-eq $before) 'byte-exact backup'
    $installed=[IO.File]::ReadAllText($ini)
    Write-HandoffText $ini ($installed+"`r`n# user edit")
    Reject {Restore-Handoff} 'overwrite later changes'
    Check ($script:fixtureTasks.Count-eq 1) 'rejected restore leaves task alone'
    Write-HandoffText $ini $installed
    $null=Restore-Handoff
    Check ($script:fixtureTasks.Count-eq 0) 'remove only fixture task'
    Check ((Get-HandoffHash $ini)-eq $before) 'restore original bytes'
    Check (Test-Path (Join-Path $root 'setup-backup\Deskflow.conf.bak')) 'retain backup after restore'
    Remove-Item $root -Recurse -Force
    $script:registrationFails=$true
    Reject {Install-Handoff $settings $repo (Join-Path $repo 'app\windows\SetupBootstrap.cs')} 'task registration failure'
    Check ((Get-HandoffHash $ini)-eq $before) 'rollback INI after failure'
    Check (-not(Test-Path $root)) 'rollback installed directory after failure'
    Check (@(Get-ChildItem $env:LOCALAPPDATA -Filter '*.stage-*').Count-eq 0) 'clean staging after failure'
    $script:registrationFails=$false
    $script:fixtureTasks.DisplayHandoff=[pscustomobject]@{Actions=@()}
    Reject {Install-Handoff $settings $repo (Join-Path $repo 'app\windows\SetupBootstrap.cs')} 'existing legacy task'
    Check ((Get-HandoffHash $ini)-eq $before) 'legacy task guard leaves INI unchanged'
    Write-Output ('Windows transaction: '+$script:checks+' fixture assertions passed; no real tasks or app settings changed.')
} finally {
    $env:LOCALAPPDATA=$oldLocal;$env:APPDATA=$oldRoaming
    if(Test-Path $testRoot){Remove-Item $testRoot -Recurse -Force}
}
