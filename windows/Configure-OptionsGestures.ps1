param([ValidateSet('mx-master-2s','mx-master-3s')][string]$Model,[switch]$InspectOnly)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$mouseRoot=$PSScriptRoot
Add-Type -Path (Join-Path $mouseRoot 'ReadOptions.cs')
Add-Type -Path (Join-Path $mouseRoot 'OptionsPatch.cs')
$mouseDatabase=Join-Path $env:LOCALAPPDATA 'LogiOptionsPlus\settings.db'
$mouseData=[OptionsReadOnly]::Read($mouseDatabase)|ConvertFrom-Json
if(-not $Model) {
    $mouseModels=@(Get-PnpDevice -Class Mouse -PresentOnly|ForEach-Object {
        if($_.InstanceId-match 'PID[&_](B019|B034)') {
            if($Matches[1]-eq 'B019'){'mx-master-2s'}else{'mx-master-3s'}
        }
    }|Select-Object -Unique)
    if($mouseModels.Count-ne 1){throw 'Identify the active mouse in Options+ and pass -Model mx-master-2s or -Model mx-master-3s. Do not guess from old paired devices.'}
    $Model=$mouseModels[0]
}
$mouseBridge=Get-Content (Join-Path $mouseRoot 'mouse-bridge-state.json') -Raw|ConvertFrom-Json
if($mouseBridge.status-ne 'ready' -or $mouseBridge.registered-ne 5){throw 'Start DisplayHandoff with MouseBridge.cs before configuring Options+.'}
if($mouseData.schema_version-ne 26){throw 'This Options+ schema version needs review before editing.'}
$mouseProfiles=@($mouseData.PSObject.Properties|Where-Object {$_.Name-like 'profile-*'})
$mouseTargets=@()
foreach($mouseProfile in $mouseProfiles){for($mouseIndex=0;$mouseIndex-lt $mouseProfile.Value.assignments.Count;$mouseIndex++){$mouseAssignment=$mouseProfile.Value.assignments[$mouseIndex];if($mouseAssignment.slotId-like ($Model+'-*_c195')){$mouseTargets+=@{profile=$mouseProfile.Name;index=$mouseIndex;assignment=$mouseAssignment}}}}
if($mouseTargets.Count-ne 1){throw 'Expected one gesture assignment for the selected mouse model.'}
$mouseTarget=$mouseTargets[0]
if($InspectOnly){@{status='inspected';model=$Model;schema=$mouseData.schema_version;selected=$mouseTarget.assignment.card.selectedNestedCard;registered=$mouseBridge.registered}|ConvertTo-Json;exit}
if($mouseTarget.assignment.card.selectedNestedCard-ne 'virtual_desktops'){throw 'The current gesture selection changed; review before editing.'}
$mouseCustom=$mouseTarget.assignment.card.nestedCards.custom_gesture
foreach($mouseDirection in @('click','left','right','up','down')){if($mouseCustom.nestedCards.$mouseDirection.macro.type-ne 'DO_NOTHING'){throw 'Existing custom gestures must be reviewed before replacement.'}}
$mouseSignals=@{click=13;left=14;right=15;up=16;down=17}
foreach($mouseDirection in $mouseSignals.Keys){
    $mouseNumber=$mouseSignals[$mouseDirection]
    $mouseCard=$mouseCustom.nestedCards.$mouseDirection
    $mouseCard.id='deskflow_gesture_f'+$mouseNumber
    $mouseCard.name='Keyboard shortcut'
    $mouseCard.readOnly=$false
    $mouseCard.macro=[pscustomobject]@{type='KEYSTROKE';actionName=('Ctrl + Alt + Shift + F'+$mouseNumber);keystroke=[pscustomobject]@{code=(104+$mouseNumber-13);modifiers=@(224,225,226);virtualKeyId=('VK_F'+$mouseNumber);displayCharacter=('F'+$mouseNumber)}}
}
$mouseBackup=Join-Path $mouseRoot ('mouse-options-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $mouseBackup|Out-Null
$mouseAgentPath=Join-Path $env:ProgramFiles 'LogiOptionsPlus\logioptionsplus_agent.exe'
$mouseAgent=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath-eq $mouseAgentPath -and $_.SessionId-ne 0})
if($mouseAgent.Count-ne 1){throw 'Expected one current-user Logi Options+ agent.'}
$mouseTaskName='DisplayHandoff-RestartLogiAgent'
$mouseExistingTask=Get-ScheduledTask -TaskName $mouseTaskName -ErrorAction SilentlyContinue
if($mouseExistingTask -and $mouseExistingTask.Actions[0].Execute-ne $mouseAgentPath){throw 'An unrelated recovery task exists.'}
$mouseAgentCommand=$mouseAgent[0].CommandLine
$mouseQuoted='"'+$mouseAgentPath+'"'
if($mouseAgentCommand.StartsWith($mouseQuoted,[StringComparison]::OrdinalIgnoreCase)){$mouseArguments=$mouseAgentCommand.Substring($mouseQuoted.Length).Trim()}
elseif($mouseAgentCommand.StartsWith($mouseAgentPath,[StringComparison]::OrdinalIgnoreCase)){$mouseArguments=$mouseAgentCommand.Substring($mouseAgentPath.Length).Trim()}
else{throw 'Could not preserve the existing Logi agent launch arguments.'}
$mouseTask=@(Get-ScheduledTask -TaskName DisplayHandoff,DisplayHandoffApp -ErrorAction SilentlyContinue|Where-Object {
    $_.Actions.Count-eq 1 -and $_.Actions[0].Execute-eq (Join-Path $mouseRoot 'DisplayHandoffLauncher.exe')
})
if($mouseTask.Count-ne 1){throw 'Expected one helper task pointing to this installation.'}
$mouseTask=$mouseTask[0]
$mouseAction=if($mouseArguments){New-ScheduledTaskAction -Execute $mouseAgentPath -Argument $mouseArguments}else{New-ScheduledTaskAction -Execute $mouseAgentPath}
if(-not $mouseExistingTask){Register-ScheduledTask -TaskName $mouseTaskName -Action $mouseAction -Principal $mouseTask.Principal -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew)|Out-Null}
try {
    foreach($mouseUi in @(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath-eq (Join-Path $env:ProgramFiles 'LogiOptionsPlus\logioptionsplus.exe') -and $_.SessionId-eq $mouseAgent[0].SessionId})){Stop-Process -Id $mouseUi.ProcessId -Force}
    Stop-Process -Id $mouseAgent[0].ProcessId -Force
    Start-Sleep -Milliseconds 300
    [OptionsGesturePatch]::Backup($mouseDatabase,(Join-Path $mouseBackup 'settings.db'))
    $mousePath='$.'+'"'+$mouseTarget.profile+'"'+'.assignments['+$mouseTarget.index+'].card'
    [OptionsGesturePatch]::Apply($mouseDatabase,$mousePath,($mouseCustom|ConvertTo-Json -Depth 60 -Compress))
} finally {
    $mouseRunning=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath-eq $mouseAgentPath -and $_.SessionId-eq $mouseAgent[0].SessionId})
    if($mouseRunning.Count-eq 0){Start-ScheduledTask -TaskName $mouseTaskName}
    $mouseDeadline=[DateTimeOffset]::Now.AddSeconds(15)
    do{Start-Sleep -Milliseconds 300;$mouseRunning=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath-eq $mouseAgentPath -and $_.SessionId-eq $mouseAgent[0].SessionId});if($mouseRunning.Count-eq 1){break};if([DateTimeOffset]::Now-gt $mouseDeadline){throw 'Logi Options+ agent did not restart.'}}while($true)
    if(-not $mouseExistingTask){Unregister-ScheduledTask -TaskName $mouseTaskName -Confirm:$false}
}
$mouseRecord=@{status='configured';backup=$mouseBackup;signals=$mouseSignals;model=$Model;changed='Only selected mouse custom gestures and preset selection';agentPid=$mouseRunning[0].ProcessId;agentSession=$mouseRunning[0].SessionId}
[IO.File]::WriteAllText((Join-Path $mouseRoot 'mouse-options-installation.json'),($mouseRecord|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$mouseRecord|ConvertTo-Json -Depth 6
