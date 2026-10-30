param(
    [ValidateSet('Run','Mac','Windows','Inspect')][string]$Mode='Run',
    [switch]$NoSignal
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'DisplayNative.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
if([Diagnostics.Process]::GetCurrentProcess().SessionId -ne [DisplayHandoff.Native]::WTSGetActiveConsoleSessionId()) {
    throw 'This controller must run in the signed-in physical console session.'
}
$script:layoutPath=Join-Path $PSScriptRoot 'display-layout.json'
$script:layout=Get-Content $script:layoutPath -Raw|ConvertFrom-Json
$script:statePath=Join-Path $PSScriptRoot 'controller-state.json'
$script:logPath=Join-Path $PSScriptRoot 'controller-log.jsonl'
$script:tray=$null
$script:busy=$false
function Write-State([string]$Status,[string]$ModeName,[string]$ErrorText='') {
    $displayHandoffRecord=[ordered]@{
        at=[DateTime]::Now.ToString('o');status=$Status;mode=$ModeName;error=$ErrorText
        session=[Diagnostics.Process]::GetCurrentProcess().SessionId
        screens=@([DisplayHandoff.Native]::Adapters()|Where-Object {($_.Flags-band 1)-ne 0}|Select-Object Device,MonitorId,Flags,X,Y,Width,Height)
    }
    $displayHandoffText=$displayHandoffRecord|ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText(($script:statePath+'.tmp'),$displayHandoffText,[Text.UTF8Encoding]::new($false))
    Move-Item ($script:statePath+'.tmp') $script:statePath -Force
    [IO.File]::AppendAllText($script:logPath,(($displayHandoffRecord|ConvertTo-Json -Compress -Depth 8)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    if($script:tray) {$script:tray.Text=if($ErrorText){'双屏切换：失败，请从托盘重试'}elseif($ModeName-eq 'Mac'){'双屏切换：左 Windows / 右 Mac'}elseif($ModeName-eq 'Windows'){'双屏切换：Windows 扩展双屏'}else{'双屏切换：已就绪'}}
}
function Find-Displays {
    $displayHandoffAll=@([DisplayHandoff.Native]::Adapters())
    $displayHandoffLeft=@($displayHandoffAll|Where-Object {$_.MonitorId-eq $script:layout.left.MonitorId -and ($_.Flags-band 5)-eq 5})
    if($displayHandoffLeft.Count-ne 1 -or ($displayHandoffLeft[0].Flags-band 5)-ne 5) {throw 'The saved left primary display is unavailable; no display will be disabled.'}
    $displayHandoffMatches=@($displayHandoffAll|Where-Object {$_.MonitorId-eq $script:layout.right.MonitorId})
    $displayHandoffRight=@($displayHandoffMatches|Where-Object {($_.Flags-band 1)-ne 0})
    if($displayHandoffRight.Count-ne 1) {
        $displayHandoffRight=@($displayHandoffAll|Where-Object {$_.Device-eq $script:layout.right.Device -and $_.AdapterId-eq $script:layout.right.AdapterId -and ($_.Flags-band 1)-eq 0})
    }
    if($displayHandoffRight.Count-ne 1 -or $displayHandoffRight[0].Device-eq $displayHandoffLeft[0].Device) {throw 'The saved right Dell connector could not be identified safely.'}
    $displayHandoffActive=@($displayHandoffAll|Where-Object {($_.Flags-band 1)-ne 0})
    if(@($displayHandoffActive|Where-Object {$_.Device-ne $displayHandoffLeft[0].Device -and $_.Device-ne $displayHandoffRight[0].Device}).Count-ne 0) {throw 'An additional active display was detected; review the saved layout.'}
    @{left=$displayHandoffLeft[0];right=$displayHandoffRight[0];active=$displayHandoffActive}
}
function Wait-Topology([bool]$RightEnabled) {
    $displayHandoffDeadline=[DateTime]::UtcNow.AddSeconds(5)
    do {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 150
        $displayHandoffPair=Find-Displays
        $displayHandoffEnabled=($displayHandoffPair.right.Flags-band 1)-ne 0
        if($displayHandoffEnabled-eq $RightEnabled -and $displayHandoffPair.active.Count-eq $(if($RightEnabled){2}else{1})) {return $displayHandoffPair}
    } while([DateTime]::UtcNow-lt $displayHandoffDeadline)
    throw 'Windows did not confirm the requested display topology.'
}
function Invoke-DisplayMode([string]$Target) {
    if($script:busy){return}
    $script:busy=$true
    try {
        Write-State 'switching' $Target
        $displayHandoffPair=Find-Displays
        if(($displayHandoffPair.right.Flags-band 1)-ne 0) {
            if($displayHandoffPair.right.X-lt ($displayHandoffPair.left.X+$displayHandoffPair.left.Width)) {throw 'The Dell is not positioned to the right of the primary display.'}
            $script:layout.right.Mode=$displayHandoffPair.right.Mode
            $script:layout.right.Device=$displayHandoffPair.right.Device
            [IO.File]::WriteAllText($script:layoutPath,($script:layout|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        } else {
            [DisplayHandoff.Native]::ApplyRight($displayHandoffPair.right.Device,$script:layout.right.Mode,$false)
            $displayHandoffPair=Wait-Topology $true
        }
        $displayHandoffValue=if($Target-eq 'Windows'){15}else{17}
        $displayHandoffRead=[DisplayHandoff.Native]::Input($displayHandoffPair.right.Device,$displayHandoffValue)
        if(($displayHandoffRead-band 255)-ne $displayHandoffValue){throw 'The monitor did not confirm the selected input.'}
        if($Target-eq 'Mac') {
            [DisplayHandoff.Native]::ApplyRight($displayHandoffPair.right.Device,$script:layout.right.Mode,$true)
            $null=Wait-Topology $false
        } else {$null=Wait-Topology $true}
        if(-not $NoSignal){[DisplayHandoff.Native]::Signal($(if($Target-eq 'Windows'){22}else{23}))}
        Write-State 'ready' $Target
    } catch {
        $displayHandoffError=$_.Exception.Message
        if(-not $NoSignal){try{[DisplayHandoff.Native]::Signal(22)}catch{}}
        Write-State 'failed' $Target $displayHandoffError
        if($script:tray){$script:tray.ShowBalloonTip(5000,'双屏切换失败',$displayHandoffError,[Windows.Forms.ToolTipIcon]::Warning)}
        if($Mode-ne 'Run'){throw}
    } finally {$script:busy=$false;if($script:displayHandoffWindow){$script:displayHandoffWindow.RefreshMediaHook()}}
}
if($Mode-eq 'Inspect') {Find-Displays|ConvertTo-Json -Depth 6;exit}
if($Mode-ne 'Run') {Invoke-DisplayMode $Mode;exit}
$displayHandoffMutex=[Threading.Mutex]::new($false,'Local\DisplayHandoff')
if(-not $displayHandoffMutex.WaitOne(0)) {exit}
$displayHandoffWindow=$null
$displayHandoffHookTimer=[Windows.Forms.Timer]::new()
try {
    $displayHandoffWindow=[DisplayHandoff.HotkeyWindow]::new([Action[int]]{
        param($displayHandoffId)
        if($displayHandoffId-eq 1){Invoke-DisplayMode 'Windows'}
        elseif($displayHandoffId-eq 2){Invoke-DisplayMode 'Mac'}
    })
    $script:tray=[Windows.Forms.NotifyIcon]::new()
    $script:tray.Icon=[Drawing.SystemIcons]::Application
    $script:tray.Text='双屏切换：已就绪'
    $displayHandoffMenu=[Windows.Forms.ContextMenuStrip]::new()
    $displayHandoffWindowsItem=$displayHandoffMenu.Items.Add('音乐键：Windows 扩展双屏')
    $displayHandoffWindowsItem.add_Click({Invoke-DisplayMode 'Windows'})
    $displayHandoffMacItem=$displayHandoffMenu.Items.Add('邮件键：左 Windows / 右 Mac')
    $displayHandoffMacItem.add_Click({Invoke-DisplayMode 'Mac'})
    $null=$displayHandoffMenu.Items.Add('-')
    $displayHandoffExitItem=$displayHandoffMenu.Items.Add('退出切换助手')
    $displayHandoffExitItem.add_Click({[Windows.Forms.Application]::ExitThread()})
    $script:tray.ContextMenuStrip=$displayHandoffMenu
    $script:tray.Visible=$true
    Write-State 'listening' 'Unchanged'
    $displayHandoffHookTimer.Interval=5000
    $displayHandoffHookTimer.add_Tick({if(-not $script:busy){$script:displayHandoffWindow.RefreshMediaHook()}})
    $displayHandoffHookTimer.Start()
    [Windows.Forms.Application]::Run()
} finally {
    $displayHandoffHookTimer.Stop();$displayHandoffHookTimer.Dispose()
    if($script:tray){$script:tray.Visible=$false;$script:tray.Dispose()}
    if($displayHandoffWindow){$displayHandoffWindow.Dispose()}
    $displayHandoffMutex.ReleaseMutex();$displayHandoffMutex.Dispose()
}
