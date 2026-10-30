$ErrorActionPreference='Stop'
# Windows PowerShell can allocate a console even with CreateNoWindow.
# Standard streams are redirected by the launcher; detach before loading the UI.
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace DisplayHandoffStartup {
    public static class ConsoleSession {
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool FreeConsole();
    }
}
'@
$null=[DisplayHandoffStartup.ConsoleSession]::FreeConsole()
& (Join-Path $PSScriptRoot 'DisplayHandoff.ps1') -Mode Run
