$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'app\windows\Setup.Core.ps1')
$script:count=0
function Check([bool]$Value,[string]$Message){$script:count++;if(-not $Value){throw ('FAIL: '+$Message)}}
function Reject([scriptblock]$Action,[string]$Message){$script:count++;$rejected=$false;try{& $Action}catch{$rejected=$true};if(-not $rejected){throw ('FAIL: accepted '+$Message)}}
$settings=New-HandoffSettings 'win-fixture' 'mac-fixture' 15 17 181 180 $true
Check ($settings.windowsInput-eq 15) 'settings values'
Reject {New-HandoffSettings 'bad) = rule' 'mac' 15 17 181 180 $true} 'config injection'
Reject {New-HandoffSettings 'win' 'WIN' 15 17 181 180 $true} 'same computer name'
Reject {New-HandoffSettings 'win' 'mac' 15 15 181 180 $true} 'same input'
Reject {New-HandoffSettings 'win' 'mac' 15 17 181 181 $true} 'same media key'
Reject {New-HandoffSettings 'win' 'mac' 15 17 65 180 $true} 'ordinary text key'
$mode=[Convert]::ToBase64String([byte[]]::new(220))
$left=[pscustomobject]@{Device='LEFT';MonitorId='monitor-left';Mode=$mode;Flags=5;X=0;Width=1920}
$right=[pscustomobject]@{Device='RIGHT';MonitorId='monitor-right';Mode=$mode;Flags=1;X=1920;Width=1920}
$layout=Get-HandoffLayout @($left,$right)
Check ($layout.right.Device-eq 'RIGHT') 'select shared display'
Reject {Get-HandoffLayout @($left)} 'one screen capture'
$extra=[pscustomobject]@{Device='THIRD';MonitorId='monitor-third';Mode=$mode;Flags=1;X=3840;Width=1920}
Reject {Get-HandoffLayout @($left,$right,$extra)} 'three screen capture'
$right.X=-1920;Reject {Get-HandoffLayout @($left,$right)} 'shared display on left';$right.X=1920
$text="[core]`r`nname=win-fixture`r`n[server]`r`nexternalConfig=false`r`nclipboardSharing=true`r`n[client]`r`nserverHostname=fixture`r`n"
$patched=Set-DeskflowIni $text 'C:\Fixture Path\deskflow-server.conf'
Check ($patched.Contains('clipboardSharing=true')) 'preserve server fields'
Check ($patched.Contains('serverHostname=fixture')) 'preserve client section'
Check ($patched.Contains('externalConfigFile=C:/Fixture Path/deskflow-server.conf')) 'space in path'
Check (([regex]::Matches($patched,'(?m)^externalConfig=')).Count-eq 1) 'one setting only'
Reject {Set-DeskflowIni ($text+"[server]`r`n") 'C:\fixture'} 'duplicate section'
Reject {Set-DeskflowIni $text.Replace('externalConfig=false','externalConfig=true') 'C:\fixture'} 'overwrite external rules'
Reject {Set-DeskflowIni $text.Replace('clipboardSharing=true',"externalConfig=false`r`nclipboardSharing=true") 'C:\fixture'} 'duplicate field'
$template=[IO.File]::ReadAllText((Join-Path $repo 'windows\deskflow-server.template.conf'))
$supplement=New-DeskflowSupplement $template $settings
Check (-not $supplement.Contains('__WINDOWS_SCREEN__')) 'replace template placeholders'
Check ($supplement.Contains('switchToScreen(mac-fixture)')) 'target Mac correctly'
# Parse without executing controller hooks, topology changes or installer mutations.
foreach($script in @(Get-ChildItem (Join-Path $repo 'app\windows') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $repo 'windows') -Filter '*.ps1')) {
    $null=[scriptblock]::Create([IO.File]::ReadAllText($script.FullName));$script:count++
}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $repo 'windows\DisplayNative.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $repo 'windows\MouseBridge.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $repo 'windows\ReadOptions.cs')
Add-Type -Path (Join-Path $repo 'windows\OptionsPatch.cs')
Reject {[DisplayHandoff.HotkeyWindow]::new([Action[int]]{},181,181)} 'duplicate native media keys before hooks'
Write-Output ('Windows setup: '+$script:count+' assertions/parse checks passed; native sources compiled; no hooks or live settings changed.')
