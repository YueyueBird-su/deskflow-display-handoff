# Pure configuration functions are shared by the GUI and fixture tests.
function Assert-ScreenName([string]$Name) {
    if($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$'){throw 'Deskflow names may contain letters, digits, dots, underscores and hyphens (max 128).'}
}
function New-HandoffSettings([string]$WindowsName,[string]$MacName,[int]$WindowsInput,[int]$MacInput,[int]$WindowsKey,[int]$MacKey,[bool]$Mouse) {
    Assert-ScreenName $WindowsName;Assert-ScreenName $MacName
    if($WindowsName-eq $MacName){throw 'The two Deskflow computer names must differ.'}
    if($WindowsInput-lt 1 -or $WindowsInput-gt 255 -or $MacInput-lt 1 -or $MacInput-gt 255 -or $WindowsInput-eq $MacInput){throw 'Select distinct DDC input values from 1 to 255.'}
    if($WindowsKey-lt 176 -or $WindowsKey-gt 183 -or $MacKey-lt 176 -or $MacKey-gt 183 -or $WindowsKey-eq $MacKey){throw 'Choose two different media/application keys.'}
    [ordered]@{schema=1;windowsName=$WindowsName;macName=$MacName;windowsInput=$WindowsInput;macInput=$MacInput;windowsKey=$WindowsKey;macKey=$MacKey;enableMouse=$Mouse}
}
function Get-HandoffLayout($Adapters) {
    $active=@($Adapters|Where-Object {($_.Flags-band 1)-ne 0})
    $left=@($active|Where-Object {($_.Flags-band 5)-eq 5})
    $right=@($active|Where-Object {($_.Flags-band 5)-ne 5})
    if($active.Count-ne 2 -or $left.Count-ne 1 -or $right.Count-ne 1){throw 'First extend Windows to exactly two displays, with the left display primary.'}
    if($right[0].X-lt ($left[0].X+$left[0].Width)){throw 'Place the shared display to the right of the Windows primary in Display Settings.'}
    if(-not $left[0].MonitorId -or -not $right[0].MonitorId -or -not $right[0].Mode -or $left[0].Device-eq $right[0].Device){throw 'Display identity or current mode is missing.'}
    $mode=[Convert]::FromBase64String($right[0].Mode)
    if($mode.Length-ne 220){throw 'Unsupported display mode structure.'}
    [ordered]@{left=$left[0];right=$right[0]}
}
function New-DeskflowSupplement([string]$Template,$Settings) {
    Assert-ScreenName $Settings.windowsName;Assert-ScreenName $Settings.macName
    $Template.Replace('__WINDOWS_SCREEN__',$Settings.windowsName).Replace('__MAC_SCREEN__',$Settings.macName)
}
function Set-DeskflowIni([string]$Text,[string]$SupplementPath) {
    # Preserve all other sections, comments and settings. Reject ambiguous INI.
    if($SupplementPath.Contains("`n") -or $SupplementPath.Contains("`r")){throw 'Invalid config path.'}
    $lines=[Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($Text -split '\r?\n'))
    $servers=@(for($i=0;$i-lt $lines.Count;$i++){if($lines[$i]-match '^\s*\[server\]\s*$'){$i}})
    if($servers.Count-ne 1){throw 'Expected exactly one [server] section in Deskflow.conf. Configure Deskflow as server first.'}
    $start=$servers[0]+1;$end=$lines.Count
    for($i=$start;$i-lt $lines.Count;$i++){if($lines[$i]-match '^\s*\['){$end=$i;break}}
    $values=[ordered]@{externalConfig='true';externalConfigFile=$SupplementPath.Replace('\','/');disableLockToComputer='false'}
    $indices=@{}
    foreach($name in $values.Keys){
        $found=@(for($i=$start;$i-lt $end;$i++){if($lines[$i]-match ('^\s*'+[regex]::Escape($name)+'\s*=')){$i}})
        if($found.Count-gt 1){throw ('Duplicate Deskflow setting: '+$name)}
        if($found.Count-eq 1){$indices[$name]=$found[0]}
    }
    if($indices.ContainsKey('externalConfig') -and $lines[$indices.externalConfig]-match '=\s*true\s*$') {
        throw 'Deskflow already uses an external config. Preserve or merge those rules before using this experimental installer.'
    }
    foreach($name in $values.Keys){
        $line=$name+'='+$values[$name]
        if($indices.ContainsKey($name)){$lines[$indices[$name]]=$line}
        else{$lines.Insert($end,$line);$end++}
    }
    $lines -join "`r`n"
}
function Write-HandoffText([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}
function Get-HandoffHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Assert-DeskflowStopped {
    if(@(Get-Process -Name deskflow,deskflow-core -ErrorAction SilentlyContinue).Count){throw 'Exit Deskflow from its tray menu first. The installer will not stop it forcibly.'}
}
function Assert-LocalDesktop {
    if([Diagnostics.Process]::GetCurrentProcess().SessionId-ne [DisplayHandoff.Native]::WTSGetActiveConsoleSessionId()){throw 'Run setup on the physical Windows desktop, not SSH or Remote Desktop.'}
}
function Install-Handoff($Settings,[string]$Payload,[string]$InstallerPath) {
    Assert-LocalDesktop;Assert-DeskflowStopped
    $root=Join-Path $env:LOCALAPPDATA 'DisplayHandoffApp'
    $ini=Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
    if(Test-Path $root){throw 'An installation/directory already exists. Restore it first; it will not be overwritten.'}
    if(Get-ScheduledTask -TaskName DisplayHandoff,DisplayHandoffApp -ErrorAction SilentlyContinue){throw 'An existing display helper task was found. Keep the current setup, or remove it deliberately before migrating.'}
    if(-not(Test-Path $ini)){throw 'Deskflow.conf was not found. Install Deskflow and configure the server first.'}
    $layout=Get-HandoffLayout ([DisplayHandoff.Native]::Adapters())
    $input=[DisplayHandoff.Native]::Input($layout.right.Device,-1)-band 255
    if($input-ne $Settings.windowsInput){throw 'The shared display is not on the selected Windows input. Switch it to Windows and check the DDC value.'}
    [DisplayHandoff.Native]::TestRestore($layout.right.Device,$layout.right.Mode)
    $before=Get-HandoffHash $ini
    $text=[IO.File]::ReadAllText($ini)
    $patched=Set-DeskflowIni $text (Join-Path $root 'deskflow-server.conf')
    $stage=$root+'.stage-'+[Guid]::NewGuid().ToString('N')
    $taskCreated=$false;$iniChanged=$false;$rootMoved=$false
    try {
        $null=New-Item -ItemType Directory -Path $stage
        foreach($file in @('DisplayHandoff.ps1','DisplayNative.cs','DisplayHandoffLauncher.cs','Start-Worker.ps1','Build-Launcher.ps1','MouseBridge.cs','ReadOptions.cs','OptionsPatch.cs','Configure-OptionsGestures.ps1')) {
            Copy-Item -LiteralPath (Join-Path $Payload ('windows\'+$file)) -Destination $stage
        }
        Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $stage 'DisplayHandoffSetup.exe')
        Write-HandoffText (Join-Path $stage 'display-layout.json') ($layout|ConvertTo-Json -Depth 8)
        Write-HandoffText (Join-Path $stage 'handoff-settings.json') ($Settings|ConvertTo-Json)
        $supplement=New-DeskflowSupplement ([IO.File]::ReadAllText((Join-Path $Payload 'windows\deskflow-server.template.conf'))) $Settings
        Write-HandoffText (Join-Path $stage 'deskflow-server.conf') $supplement
        $null=New-Item -ItemType Directory -Path (Join-Path $stage 'setup-backup')
        Copy-Item -LiteralPath $ini -Destination (Join-Path $stage 'setup-backup\Deskflow.conf.bak')
        & (Join-Path $stage 'Build-Launcher.ps1')|Out-Null
        if((Get-HandoffHash $ini)-ne $before){throw 'Deskflow.conf changed during setup. Nothing will be overwritten.'}
        [IO.Directory]::Move($stage,$root);$rootMoved=$true
        $iniChanged=$true;Write-HandoffText $ini $patched
        $installed=Get-HandoffHash $ini
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action=New-ScheduledTaskAction -Execute (Join-Path $root 'DisplayHandoffLauncher.exe') -WorkingDirectory $root
        $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
        $taskSettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName DisplayHandoffApp -Action $action -Principal $principal -Trigger $trigger -Settings $taskSettings|Out-Null
        $taskCreated=$true
        $record=@{schema=1;installedAt=[DateTimeOffset]::Now.ToString('o');iniBeforeHash=$before;iniInstalledHash=$installed;task='DisplayHandoffApp'}
        Write-HandoffText (Join-Path $root 'setup-installation.json') ($record|ConvertTo-Json)
        return $root
    } catch {
        $failure=$_
        if($taskCreated){Unregister-ScheduledTask -TaskName DisplayHandoffApp -Confirm:$false}
        if($iniChanged){Copy-Item -LiteralPath (Join-Path $root 'setup-backup\Deskflow.conf.bak') -Destination $ini -Force}
        if($rootMoved){Remove-Item -LiteralPath $root -Recurse -Force}
        if(Test-Path $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
        throw $failure
    }
}
function Restore-Handoff {
    Assert-LocalDesktop;Assert-DeskflowStopped
    $root=Join-Path $env:LOCALAPPDATA 'DisplayHandoffApp'
    $record=Get-Content -LiteralPath (Join-Path $root 'setup-installation.json') -Raw|ConvertFrom-Json
    $ini=Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
    $backup=Join-Path $root 'setup-backup\Deskflow.conf.bak'
    if($record.schema-ne 1 -or $record.task-ne 'DisplayHandoffApp'){throw 'Unknown installation record.'}
    if((Get-HandoffHash $ini)-ne $record.iniInstalledHash){throw 'Deskflow.conf was edited after installation. Restore is paused to preserve your changes. Use the local setup-backup to merge it manually.'}
    if((Get-HandoffHash $backup)-ne $record.iniBeforeHash){throw 'Backup verification failed.'}
    $task=Get-ScheduledTask -TaskName DisplayHandoffApp -ErrorAction SilentlyContinue
    if($task -and ($task.Actions.Count-ne 1 -or $task.Actions[0].Execute-ne (Join-Path $root 'DisplayHandoffLauncher.exe'))){throw 'The login task changed after installation; review it before restoring.'}
    if($task){Stop-ScheduledTask -TaskName DisplayHandoffApp;Unregister-ScheduledTask -TaskName DisplayHandoffApp -Confirm:$false}
    Copy-Item -LiteralPath $backup -Destination $ini -Force
    # Keep files and backup; the setup EXE may currently be running here.
    Move-Item -LiteralPath (Join-Path $root 'setup-installation.json') -Destination (Join-Path $root 'setup-installation.restored.json')
    return $root
}
