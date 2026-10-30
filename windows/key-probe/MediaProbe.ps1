$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot 'MediaProbe.cs') -ReferencedAssemblies System.Windows.Forms
$script:mediaProbeEvents=[Collections.Generic.List[object]]::new()
$script:mediaProbePath=Join-Path $PSScriptRoot 'media-key-probe.json'
$script:mediaProbeNames=@{166='BrowserBack';167='BrowserForward';168='BrowserRefresh';169='BrowserStop';170='BrowserSearch';171='BrowserFavorites';172='BrowserHome';173='VolumeMute';174='VolumeDown';175='VolumeUp';176='NextTrack';177='PreviousTrack';178='StopMedia';179='PlayPause';180='LaunchMail';181='LaunchMedia';182='LaunchApp1';183='LaunchApp2'}
function Save-MediaProbe([string]$Status) {
    $mediaProbeRecord=@{status=$Status;session=[Diagnostics.Process]::GetCurrentProcess().SessionId;events=@($script:mediaProbeEvents.ToArray());at=[DateTime]::Now.ToString('o')}
    [IO.File]::WriteAllText(($script:mediaProbePath+'.tmp'),($mediaProbeRecord|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    Move-Item ($script:mediaProbePath+'.tmp') $script:mediaProbePath -Force
}
$mediaProbeWindow=$null
$mediaProbeTimer=[Windows.Forms.Timer]::new()
try {
    $mediaProbeWindow=[DisplayHandoffProbe.ProbeWindow]::new([Action[int]]{
        param($mediaProbeKey)
        $script:mediaProbeEvents.Add(@{key=$mediaProbeKey;hex=('0x{0:X2}'-f $mediaProbeKey);name=$script:mediaProbeNames[$mediaProbeKey];at=[DateTime]::Now.ToString('o')})
        Save-MediaProbe 'listening'
        if(@($script:mediaProbeEvents|Select-Object -ExpandProperty key -Unique).Count-ge 2){[Windows.Forms.Application]::ExitThread()}
    })
    $mediaProbeTimer.Interval=900000
    $mediaProbeTimer.add_Tick({[Windows.Forms.Application]::ExitThread()})
    $mediaProbeTimer.Start()
    Save-MediaProbe 'listening'
    [Windows.Forms.Application]::Run()
    Save-MediaProbe 'finished'
} catch {Save-MediaProbe ('error: '+$_.Exception.Message)}
finally {if($mediaProbeWindow){$mediaProbeWindow.Dispose()};$mediaProbeTimer.Dispose()}
