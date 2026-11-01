using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class SetupBootstrap {
    // No command shell and no user-provided code. Quote Windows argv correctly.
    private static string Quote(string value) {
        var result = new System.Text.StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c); slashes = 0;
        }
        result.Append('\\', slashes * 2); result.Append('"');
        return result.ToString();
    }
    [STAThread]
    private static int Main(string[] args) {
        string root = Path.Combine(Path.GetTempPath(), "DisplayHandoffSetup", Guid.NewGuid().ToString("N"));
        try {
            Directory.CreateDirectory(root);
            int count = 0;
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (var zip = new ZipArchive(stream, ZipArchiveMode.Read)) {
                foreach (var entry in zip.Entries) {
                    string path = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("Unsafe package entry.");
                    if (String.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(path); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    entry.ExtractToFile(path); count++;
                }
            }
            if (args.Length == 2 && args[0] == "--verify-payload") {
                if (!File.Exists(Path.Combine(root, @"app\windows\Setup.ps1")) ||
                    !File.Exists(Path.Combine(root, @"windows\DisplayNative.cs"))) throw new InvalidDataException("Incomplete payload.");
                File.WriteAllText(args[1], "{\"status\":\"passed\",\"files\":" + count + "}");
                return 0;
            }
            if (args.Length != 0) throw new ArgumentException("Unknown setup arguments.");
            string script = Path.Combine(root, @"app\windows\Setup.ps1");
            var start = new ProcessStartInfo {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File " + Quote(script) +
                    " -InstallerPath " + Quote(Assembly.GetExecutingAssembly().Location),
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true
            };
            string logRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DisplayHandoffSetup");
            Directory.CreateDirectory(logRoot);
            string error;
            using (var worker = Process.Start(start)) {
                worker.StandardInput.Close();
                var output = worker.StandardOutput.ReadToEndAsync();
                var errors = worker.StandardError.ReadToEndAsync();
                worker.WaitForExit();
                error = errors.Result;
                File.WriteAllText(Path.Combine(logRoot, "setup.log"), output.Result + Environment.NewLine + error);
                if (worker.ExitCode != 0) throw new InvalidOperationException("Setup could not run. Check PowerShell policy and the local setup.log in " + logRoot + ".\n" + error);
            }
            return 0;
        } catch (Exception error) {
            if (args.Length == 2 && args[0] == "--verify-payload") return 1;
            MessageBox.Show(error.Message, "Display Handoff setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        } finally {
            try { if (Directory.Exists(root)) Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
