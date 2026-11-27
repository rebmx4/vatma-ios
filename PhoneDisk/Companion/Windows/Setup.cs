using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Setup
{
    private const string Title = "Установка «Моего диска»";
    private const string Boot = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string BootName = "PhoneDiskCompanion";

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--verify-package") {
            try { return Verify(args[1]); }
            catch (Exception) { return 1; }
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try {
            var path = Directory.GetParent(Environment.SystemDirectory).Root.FullName;
            var home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhoneDisk Companion");
            if (!String.Equals(Path.GetPathRoot(home), path, StringComparison.OrdinalIgnoreCase))
                throw new IOException("Выберите учётную запись Windows с профилем на системном диске.");
            using (var prompt = new SetupWindow()) {
                prompt.Install.Click += delegate {
                    try {
                        string executable = Install(home);
                        prompt.DialogResult = DialogResult.OK;
                        prompt.Close();
                        Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true });
                    } catch (Exception error) {
                        MessageBox.Show(prompt, error.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                };
                prompt.ShowDialog();
            }
            return 0;
        } catch (Exception error) {
            MessageBox.Show(error.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static Stream Payload()
    {
        return Assembly.GetExecutingAssembly().GetManifestResourceStream("PhoneDiskPayload");
    }

    private static string Unpack(string root)
    {
        string version;
        using (var hash = SHA256.Create())
        using (var payload = Payload())
            version = BitConverter.ToString(hash.ComputeHash(payload)).Replace("-", "").Substring(0, 16);
        Directory.CreateDirectory(root);
        string destination = Path.Combine(root, "app-" + version);
        if (!Directory.Exists(destination)) {
            string pending = Path.Combine(root, "install-" + Guid.NewGuid().ToString("N"));
            using (var payload = Payload())
            using (var archive = new ZipArchive(payload, ZipArchiveMode.Read))
                archive.ExtractToDirectory(pending);
            Directory.Move(pending, destination);
        }
        return Path.Combine(destination, "PhoneDisk.exe");
    }

    private static string Install(string root)
    {
        bool available;
        using (var guard = new Mutex(true, @"Local\PhoneDiskCompanion", out available)) {
            if (!available) throw new IOException("Закройте «Мой диск» через значок рядом с часами и повторите установку.");
            string executable = Unpack(root);
            using (var key = Registry.CurrentUser.CreateSubKey(Boot))
                key.SetValue(BootName, "\"" + executable + "\" --tray");
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
            dynamic shortcut = shell.CreateShortcut(Path.Combine(programs, "Мой диск.lnk"));
            shortcut.TargetPath = executable;
            shortcut.WorkingDirectory = Path.GetDirectoryName(executable);
            shortcut.Save();
            return executable;
        }
    }

    private static int Verify(string folder)
    {
        string executable = Unpack(folder);
        var check = new ProcessStartInfo(executable, "--verify \"" + Path.Combine(folder, "probe") + "\"") {
            UseShellExecute = false, CreateNoWindow = true
        };
        using (var process = Process.Start(check)) {
            if (process.WaitForExit(20000)) return process.ExitCode;
            process.Kill();
            return 1;
        }
    }

    private sealed class SetupWindow : Form
    {
        internal readonly Button Install = new Button { Text = "Установить", AutoSize = true, Width = 132, Height = 40 };

        internal SetupWindow()
        {
            Text = Title;
            ClientSize = new Size(452, 245);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.Black;
            ForeColor = Color.WhiteSmoke;
            Font = new Font("Segoe UI", 11);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MinimizeBox = MaximizeBox = false;
            var heading = new Label { Text = "Мой диск для Windows", Font = new Font("Segoe UI", 21, FontStyle.Bold),
                AutoSize = true, Location = new Point(23, 22) };
            var body = new Label { Text = "После установки выберите папку и подключите iPhone по QR-коду. Программа будет запускаться при входе в Windows.",
                ForeColor = Color.LightGray, Size = new Size(400, 94), Location = new Point(25, 80) };
            Install.Location = new Point(295, 172);
            Install.BackColor = Color.FromArgb(164, 200, 174);
            Install.ForeColor = Color.FromArgb(14, 28, 17);
            Install.FlatStyle = FlatStyle.Flat;
            Install.FlatAppearance.BorderSize = 0;
            var cancel = new Button { Text = "Отмена", Location = new Point(185, 172), Size = new Size(100, 40),
                FlatStyle = FlatStyle.Flat, DialogResult = DialogResult.Cancel };
            Controls.AddRange(new Control[] { heading, body, Install, cancel });
            AcceptButton = Install;
            CancelButton = cancel;
        }
    }
}
