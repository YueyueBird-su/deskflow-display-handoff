using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace DisplayHandoff {
    // Compile as a Windows application: the launcher and worker have no console.
    internal static class Launcher {
        [DllImport("kernel32.dll")]
        private static extern uint WTSGetActiveConsoleSessionId();

        private static readonly string Root = AppDomain.CurrentDomain.BaseDirectory;

        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimits {
            public long ProcessTime, JobTime;
            public uint Flags;
            public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters {
            public ulong ReadOperations, WriteOperations, OtherOperations;
            public ulong ReadBytes, WriteBytes, OtherBytes;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimits {
            public BasicLimits Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }

        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool SetInformationJobObject(IntPtr job, int type, ref ExtendedLimits limits, uint length);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        private sealed class WorkerJob : IDisposable {
            private IntPtr handle;

            public WorkerJob() {
                handle = CreateJobObject(IntPtr.Zero, null);
                if (handle == IntPtr.Zero) throw new Win32Exception();
                var limits = new ExtendedLimits();
                limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits)))) {
                    int error = Marshal.GetLastWin32Error();
                    Dispose();
                    throw new Win32Exception(error);
                }
            }

            public void Add(Process worker) {
                if (!AssignProcessToJobObject(handle, worker.Handle)) {
                    int error = Marshal.GetLastWin32Error();
                    if (!worker.HasExited) worker.Kill();
                    throw new Win32Exception(error);
                }
            }

            public void Dispose() {
                if (handle != IntPtr.Zero) {
                    CloseHandle(handle);
                    handle = IntPtr.Zero;
                }
            }
        }

        private static void Log(string message) {
            try {
                File.AppendAllText(Path.Combine(Root, "launcher.log"),
                    DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine,
                    new UTF8Encoding(false));
            } catch (IOException) {
            } catch (UnauthorizedAccessException) {
            }
        }

        [STAThread]
        private static int Main() {
            try {
                if ((uint)Process.GetCurrentProcess().SessionId != WTSGetActiveConsoleSessionId()) {
                    Log("Refusing to start outside the active physical desktop session.");
                    return 2;
                }
                string script = Path.Combine(Root, "DisplayHandoff.ps1");
                if (!File.Exists(script)) {
                    Log("DisplayHandoff.ps1 is missing.");
                    return 2;
                }
                string entry = Path.Combine(Root, "Start-Worker.ps1");
                if (!File.Exists(entry)) {
                    Log("Start-Worker.ps1 is missing.");
                    return 2;
                }
                var start = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File \"" + entry + "\"",
                    WorkingDirectory = Root,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                using (var job = new WorkerJob())
                using (var worker = new Process { StartInfo = start }) {
                    // Drain both pipes so worker output cannot block the event loop.
                    worker.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { };
                    worker.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                        if (e.Data != null) Log("Worker error: " + e.Data);
                    };
                    if (!worker.Start()) {
                        Log("Worker could not be started.");
                        return 1;
                    }
                    job.Add(worker);
                    worker.StandardInput.Close();
                    worker.BeginOutputReadLine();
                    worker.BeginErrorReadLine();
                    Log("Started worker pid=" + worker.Id + "; CreateNoWindow=True.");
                    worker.WaitForExit();
                    Log("Worker exited with code 0x" + worker.ExitCode.ToString("X8") + ".");
                    return worker.ExitCode;
                }
            } catch (Exception error) {
                Log("Launcher failed: " + error.GetType().Name + ": " + error.Message);
                return 1;
            }
        }
    }
}
