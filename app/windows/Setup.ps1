param([Parameter(Mandatory=$true)][string]$InstallerPath)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. (Join-Path $PSScriptRoot 'Setup.Core.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$payload=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Add-Type -Path (Join-Path $payload 'windows\DisplayNative.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$window=[Windows.Forms.Form]::new()
$window.Text='Display Handoff · 配置向导（实验版）'
$window.Size=[Drawing.Size]::new(830,800)
$window.MinimumSize=[Drawing.Size]::new(830,800)
$window.StartPosition='CenterScreen'
$window.Font=[Drawing.Font]::new('Microsoft YaHei UI',10)
$window.BackColor=[Drawing.Color]::FromArgb(246,247,244)
$flow=[Windows.Forms.FlowLayoutPanel]::new()
$flow.Dock='Fill';$flow.FlowDirection='TopDown';$flow.WrapContents=$false;$flow.AutoScroll=$true;$flow.Padding=[Windows.Forms.Padding]::new(24)
$window.Controls.Add($flow)
function Add-Label([string]$Text,[int]$Height=28) {
    $c=[Windows.Forms.Label]::new();$c.Text=$Text;$c.Size=[Drawing.Size]::new(740,$Height);$flow.Controls.Add($c);return $c
}
function Add-Row([string]$Label,$Control) {
    $row=[Windows.Forms.FlowLayoutPanel]::new();$row.Size=[Drawing.Size]::new(740,35)
    $name=[Windows.Forms.Label]::new();$name.Text=$Label;$name.Size=[Drawing.Size]::new(290,28)
    $Control.Size=[Drawing.Size]::new(400,28);$row.Controls.Add($name);$row.Controls.Add($Control);$flow.Controls.Add($row)
}
function Add-Buttons([string[]]$Labels) {
    $row=[Windows.Forms.FlowLayoutPanel]::new();$row.Size=[Drawing.Size]::new(740,44)
    $buttons=@();foreach($label in $Labels){$button=[Windows.Forms.Button]::new();$button.Text=$label;$button.AutoSize=$true;$button.MinimumSize=[Drawing.Size]::new(150,34);$row.Controls.Add($button);$buttons+=,$button}
    $flow.Controls.Add($row);return $buttons
}
$title=Add-Label '两台电脑，一套键鼠。' 42;$title.Font=[Drawing.Font]::new('Microsoft YaHei UI',20,[Drawing.FontStyle]::Bold)
$null=Add-Label 'Windows 双屏 ↔ 左 Windows / 右 Mac。先检测、预览，再安装。' 32
$null=Add-Label '1   准备：两屏已扩展、左屏为主屏；Deskflow 已配对；共享屏已开启 DDC/CI。' 30
$windowsName=[Windows.Forms.TextBox]::new();$windowsName.Text=[Environment]::MachineName
$macName=[Windows.Forms.TextBox]::new()
Add-Row 'Windows 的 Deskflow 名称' $windowsName
Add-Row 'Mac 的 Deskflow 名称' $macName
$windowsInput=[Windows.Forms.NumericUpDown]::new();$windowsInput.Minimum=1;$windowsInput.Maximum=255;$windowsInput.Value=15
$macInput=[Windows.Forms.NumericUpDown]::new();$macInput.Minimum=1;$macInput.Maximum=255;$macInput.Value=17
Add-Row 'Windows 输入值（DP1 常见为 15）' $windowsInput
Add-Row 'Mac 输入值（HDMI1 常见为 17）' $macInput
$keyNames=@('下一曲 · 176','上一曲 · 177','停止 · 178','播放/暂停 · 179','邮件 LaunchMail · 180','音乐 LaunchMedia · 181','应用 1 · 182','应用 2 · 183')
$windowsKey=[Windows.Forms.ComboBox]::new();$windowsKey.DropDownStyle='DropDownList';$windowsKey.Items.AddRange($keyNames);$windowsKey.SelectedIndex=5
$macKey=[Windows.Forms.ComboBox]::new();$macKey.DropDownStyle='DropDownList';$macKey.Items.AddRange($keyNames);$macKey.SelectedIndex=4
Add-Row '进入 Windows 双屏的实体键' $windowsKey
Add-Row '返回 Mac 的实体键' $macKey
$mouse=[Windows.Forms.CheckBox]::new();$mouse.Text='启用可选罗技手势桥接（Options+ 需另行设置）';$mouse.Size=[Drawing.Size]::new(740,30);$flow.Controls.Add($mouse)
$confirmed=[Windows.Forms.CheckBox]::new();$confirmed.Text='我已手动确认：右屏两种输入都正常，输入值与实体键已核对。';$confirmed.Size=[Drawing.Size]::new(740,30);$flow.Controls.Add($confirmed)
$actions=Add-Buttons @('2  检测并预览','3  安装到此 Windows')
$preview=[Windows.Forms.TextBox]::new();$preview.Multiline=$true;$preview.ReadOnly=$true;$preview.ScrollBars='Vertical';$preview.Size=[Drawing.Size]::new(740,150);$preview.Text='检测不会切换画面、监听按键或修改配置。';$flow.Controls.Add($preview)
$maintenance=Add-Buttons @('启动已安装助手','撤销本向导的安装','打开使用说明')
$status=Add-Label '实验版 · 当前日常配置不会自动迁移。' 50
$script:previewSettings=$null
function Read-Settings {
    New-HandoffSettings $windowsName.Text.Trim() $macName.Text.Trim() ([int]$windowsInput.Value) ([int]$macInput.Value) ($windowsKey.SelectedIndex+176) ($macKey.SelectedIndex+176) $mouse.Checked
}
function Show-SetupError($Failure) {$status.Text=$Failure.Exception.Message;[Windows.Forms.MessageBox]::Show($Failure.Exception.Message,'未完成','OK','Warning')|Out-Null}
$actions[0].add_Click({
    try {
        Assert-LocalDesktop
        $settings=Read-Settings
        $layout=Get-HandoffLayout ([DisplayHandoff.Native]::Adapters())
        $current=[DisplayHandoff.Native]::Input($layout.right.Device,-1)-band 255
        $ini=Join-Path $env:APPDATA 'Deskflow\Deskflow.conf'
        $root=Join-Path $env:LOCALAPPDATA 'DisplayHandoffApp'
        $null=Set-DeskflowIni ([IO.File]::ReadAllText($ini)) (Join-Path $root 'deskflow-server.conf')
        $preview.Text="左侧保留：$($layout.left.MonitorName) · $($layout.left.Width)×$($layout.left.Height)`r`n右侧共享：$($layout.right.MonitorName) · $($layout.right.Width)×$($layout.right.Height)`r`n当前 DDC 输入：$current；Windows=$($settings.windowsInput)，Mac=$($settings.macInput)`r`n安装目录：$root`r`n将备份 Deskflow.conf，仅修改 server 段的 3 项，生成布局并创建普通权限登录任务 DisplayHandoffApp。`r`n旧助手或外部规则存在时会停止安装。撤销会核对配置哈希，保留后续改动。"
        $script:previewSettings=$settings|ConvertTo-Json -Compress
        $status.Text='预览已生成。请核对后退出 Windows Deskflow，再点击安装。'
    }catch{Show-SetupError $_}
})
$actions[1].add_Click({
    try {
        $settings=Read-Settings
        if(-not $confirmed.Checked){throw '请先手动核对接线、输入源和实体键，再勾选确认。'}
        if(-not $script:previewSettings -or ($settings|ConvertTo-Json -Compress)-ne $script:previewSettings){throw '请先检测并预览当前设置。'}
        if([Windows.Forms.MessageBox]::Show('按预览安装并创建本用户登录任务？安装过程不切换画面。','安装确认','OKCancel','Information')-ne 'OK'){return}
        $root=Install-Handoff $settings $payload $InstallerPath
        $status.Text='安装完成。重新打开 Deskflow，再点击“启动已安装助手”，测试两方向。'
        $script:previewSettings=$null
    }catch{Show-SetupError $_}
})
$maintenance[0].add_Click({
    try {
        $root=Join-Path $env:LOCALAPPDATA 'DisplayHandoffApp'
        if(-not(Test-Path (Join-Path $root 'setup-installation.json'))){throw '尚未安装本实验版。'}
        if(Get-ScheduledTask -TaskName DisplayHandoff -ErrorAction SilentlyContinue){throw '检测到旧助手，请先解决重复安装。'}
        $task=Get-ScheduledTask -TaskName DisplayHandoffApp
        if($task.Actions.Count-ne 1 -or $task.Actions[0].Execute-ne (Join-Path $root 'DisplayHandoffLauncher.exe')){throw '登录任务已改变，请先检查其启动路径。'}
        Start-ScheduledTask -TaskName DisplayHandoffApp
        $status.Text='已请求启动。请在任务栏托盘检查状态，再测试两个实体键。'
    }catch{Show-SetupError $_}
})
$maintenance[1].add_Click({
    try {
        if([Windows.Forms.MessageBox]::Show('退出 Deskflow 后恢复安装前配置，并删除本实验版登录任务？本机备份会保留。','撤销确认','OKCancel','Question')-ne 'OK'){return}
        $archive=Restore-Handoff
        $status.Text='已恢复。重新打开 Deskflow；如有需要，用显示器菜单和 Windows 显示设置恢复画面。'
    }catch{Show-SetupError $_}
})
$maintenance[2].add_Click({Start-Process 'https://github.com/YueyueBird-su/deskflow-display-handoff/blob/codex/setup-app/docs/APP.md'})
[Windows.Forms.Application]::Run($window)
$window.Dispose()
