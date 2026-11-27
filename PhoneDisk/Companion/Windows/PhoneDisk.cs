using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class Program
{
    internal static readonly string App = AppDomain.CurrentDomain.BaseDirectory;
    internal static readonly string Data = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhoneDisk Companion", "data");

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--verify") {
            try {
                using (var backend = new Backend(args[1], true)) {
                    return backend.Call("state").ContainsKey("folders") ? 0 : 1;
                }
            } catch (Exception) { return 1; }
        }
        if (args.Length == 1 && args[0] == "--allow-network") return AllowNetwork();
        bool first;
        using (var instance = new Mutex(true, @"Local\PhoneDiskCompanion", out first)) {
            if (!first) return 0;
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try {
                using (var backend = new Backend(Data, false))
                using (var screen = new MainWindow(backend)) {
                    if (args.Contains("--tray")) screen.Shown += delegate { screen.Hide(); };
                    Application.Run(screen);
                }
            } catch (Exception error) {
                MessageBox.Show(error.Message, "Мой диск", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
        return 0;
    }

    private static int AllowNetwork()
    {
        var python = Path.Combine(App, "runtime", "python.exe");
        try {
            Rule("Мой диск · Домашняя сеть", python, "TCP", "18119", "LocalSubnet", "private");
            Rule("Мой диск · Обнаружение ПК", python, "UDP", "5353", "LocalSubnet", "private");
            Rule("Мой диск · Tailscale", python, "TCP", "18119", "100.64.0.0/10", "any");
            return 0;
        } catch (Exception error) {
            MessageBox.Show(error.Message, "Мой диск", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return 1;
        }
    }

    private static void Rule(string name, string program, string protocol, string port, string remote, string profile)
    {
        string properties = " name=\"" + name + "\" program=\"" + program + "\"";
        RunFirewall("delete rule" + properties);
        if (RunFirewall("add rule" + properties + " dir=in action=allow protocol=" + protocol + " localport=" + port +
            " remoteip=" + remote + " profile=" + profile + " enable=yes") != 0)
            throw new IOException("Windows не разрешила подключение. Проверьте настройки брандмауэра.");
    }

    private static int RunFirewall(string arguments)
    {
        var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "netsh.exe"),
            "advfirewall firewall " + arguments) { UseShellExecute = false, CreateNoWindow = true };
        using (var command = Process.Start(info)) { command.WaitForExit(10000); return command.ExitCode; }
    }
}

internal sealed class Backend : IDisposable
{
    private readonly Process process;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };

    internal Backend(string state, bool loopback)
    {
        var info = new ProcessStartInfo(Path.Combine(Program.App, "runtime", "python.exe"));
        info.WorkingDirectory = Program.App;
        info.Arguments = "-I -B -X utf8 -c \"import runpy,sys;sys.path.insert(0,'.');runpy.run_path('run.py',run_name='__main__')\" --state \"" +
            state.TrimEnd('\\') + "\"" + (loopback ? " --loopback --port 0" : "");
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.RedirectStandardInput = true;
        info.RedirectStandardOutput = true;
        process = Process.Start(info);
        try { Read(); }
        catch { Dispose(); throw; }
    }

    private Dictionary<string, object> Read()
    {
        var reply = process.StandardOutput.ReadLineAsync();
        if (!reply.Wait(TimeSpan.FromSeconds(6)) || reply.Result == null)
            throw new IOException("Программа передачи недоступна. Закройте «Мой диск» и откройте его снова.");
        var data = json.Deserialize<Dictionary<string, object>>(reply.Result);
        if (data.ContainsKey("error")) {
            switch (data["error"] as string) {
            case "wifi-unavailable": throw new IOException("Подключите компьютер к домашней сети.");
            case "folder-needed": throw new IOException("Сначала добавьте папку.");
            case "startup": throw new IOException("Не удалось запустить передачу. Проверьте, открыта ли другая копия «Моего диска».");
            default: throw new IOException("Папка или устройство недоступны. Проверьте подключение и повторите.");
            }
        }
        return data;
    }

    internal Dictionary<string, object> Call(string action, params object[] arguments)
    {
        var command = new Dictionary<string, object> { { "action", action } };
        for (int index = 0; index < arguments.Length; index += 2)
            command.Add((string)arguments[index], arguments[index + 1]);
        // Escaped JSON stays in ASCII, independent of the Windows console code page.
        string wire = String.Concat(json.Serialize(command).Select(ch => ch <= 127 ? ch.ToString() : "\\u" + ((int)ch).ToString("x4")));
        process.StandardInput.WriteLine(wire);
        process.StandardInput.Flush();
        return Read();
    }

    public void Dispose()
    {
        try {
            process.StandardInput.Close();
            if (!process.WaitForExit(4000)) process.Kill();
        } catch (InvalidOperationException) { }
        finally { process.Dispose(); }
    }
}

internal sealed class MainWindow : Form
{
    private static readonly Color Green = Color.FromArgb(164, 200, 174);
    private static readonly Color Surface = Color.FromArgb(29, 29, 29);
    private static readonly Color Muted = Color.FromArgb(174, 174, 174);
    private readonly Backend backend;
    private readonly NotifyIcon tray;
    private readonly ListView folders = List("Папка", "Путь", "Назначение");
    private readonly ListView phones = List("Имя", "Папки");
    private readonly Label status = new Label { AutoSize = true, ForeColor = Muted };
    private Dictionary<string, object> state;
    private bool exit;

    internal MainWindow(Backend service)
    {
        backend = service;
        Text = "Мой диск";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(740, 565);
        MinimumSize = new Size(630, 500);
        BackColor = Color.Black;
        ForeColor = Color.WhiteSmoke;
        Font = new Font("Segoe UI", 10f);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24, 18, 24, 14),
            ColumnCount = 1, RowCount = 8 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 56));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 44));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(Heading("Мой диск", 23), 0, 0);
        layout.Controls.Add(Heading("Общие папки", 12), 0, 1);
        layout.Controls.Add(folders, 0, 2);
        layout.Controls.Add(Actions(
            Button("Добавить папку", delegate { AddFolder(false); }, true),
            Button("Папка для автокопий", delegate { AddFolder(true); }),
            Button("Убрать из списка", RemoveFolder)), 0, 3);
        layout.Controls.Add(Heading("Подключённые устройства", 12), 0, 4);
        layout.Controls.Add(phones, 0, 5);
        layout.Controls.Add(Actions(
            Button("Подключить телефон", PairPhone, true),
            Button("Права доступа", EditPermissions),
            Button("Отключить телефон", RevokePhone),
            Button("Обновить", RefreshState)), 0, 6);
        layout.Controls.Add(status, 0, 7);
        Controls.Add(layout);
        var menu = new ContextMenuStrip();
        menu.Items.Add("Открыть «Мой диск»", null, delegate { ShowWindow(); });
        menu.Items.Add("Разрешить подключения", null, delegate { AllowNetwork(); });
        menu.Items.Add("Выйти", null, delegate { exit = true; Close(); });
        tray = new NotifyIcon { Icon = Icon, Text = "Мой диск", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += delegate { ShowWindow(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (exit || e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
        };
        FormClosed += delegate { tray.Dispose(); };
        RefreshState();
    }

    private void ShowWindow() { Show(); WindowState = FormWindowState.Normal; Activate(); }

    private async void AllowNetwork()
    {
        try {
            using (var command = Process.Start(new ProcessStartInfo(Application.ExecutablePath, "--allow-network") {
                UseShellExecute = true, Verb = "runas"
            })) {
                await System.Threading.Tasks.Task.Run(() => command.WaitForExit());
                if (command.ExitCode == 0) status.Text = "Windows разрешила подключение в домашней сети.";
            }
        } catch (Win32Exception) {
            status.Text = "Разрешение можно выдать через значок «Моего диска» рядом с часами.";
        }
    }

    private static Control Heading(string name, float size)
    {
        return new Label { Text = name, Font = new Font("Segoe UI", size, FontStyle.Bold),
                           AutoSize = true, Margin = new Padding(0, 5, 0, 8) };
    }

    private static ListView List(params string[] columns)
    {
        var list = new ListView { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true,
                                 MultiSelect = false, HeaderStyle = ColumnHeaderStyle.Nonclickable,
                                 BackColor = Surface, ForeColor = Color.WhiteSmoke, BorderStyle = BorderStyle.None };
        for (int index = 0; index < columns.Length; ++index)
            list.Columns.Add(columns[index], index == 1 ? 338 : 147);
        return list;
    }

    private Button Button(string title, Action run, bool primary = false)
    {
        var button = new Button { Text = title, AutoSize = true, MinimumSize = new Size(0, 36),
            Padding = new Padding(8, 1, 8, 1), FlatStyle = FlatStyle.Flat, UseVisualStyleBackColor = false,
            BackColor = primary ? Green : Surface, ForeColor = primary ? Color.FromArgb(14, 28, 17) : Color.WhiteSmoke };
        button.FlatAppearance.BorderSize = 0;
        button.Click += delegate {
            try { run(); }
            catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        };
        return button;
    }

    private static Control Actions(params Control[] controls)
    {
        var row = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = true,
            Margin = new Padding(0, 5, 0, 8) };
        row.Controls.AddRange(controls);
        return row;
    }

    private static Dictionary<string, object> Dict(object value) { return (Dictionary<string, object>)value; }
    private static string Selected(ListView list) { return list.SelectedItems.Count == 0 ? null : (string)list.SelectedItems[0].Tag; }
    private Dictionary<string, object>[] PhoneList(Dictionary<string, object> value)
    {
        return ((System.Collections.IEnumerable)value["phones"]).Cast<object>().Select(Dict).ToArray();
    }

    private void RefreshState()
    {
        var activePhone = Selected(phones);
        var activeFolder = Selected(folders);
        state = backend.Call("state");
        var shared = Dict(state["folders"]);
        folders.Items.Clear();
        foreach (var entry in shared) {
            var folder = Dict(entry.Value);
            var row = new ListViewItem(new[] { (string)folder["name"], (string)folder["path"],
                (bool)folder["backup"] ? "Автокопии" : "Файлы" }) { Tag = entry.Key };
            folders.Items.Add(row);
            row.Selected = entry.Key == activeFolder;
        }
        phones.Items.Clear();
        foreach (var phone in PhoneList(state)) {
            var scopes = Dict(phone["scopes"]);
            var labels = scopes.Keys.Where(shared.ContainsKey).Select(key => (string)Dict(shared[key])["name"]);
            var row = new ListViewItem(new[] { (string)phone["name"], String.Join(", ", labels) }) { Tag = phone["id"] };
            phones.Items.Add(row);
            row.Selected = (string)phone["id"] == activePhone;
        }
        status.Text = !(bool)state["hasNetwork"] ? "Подключите ПК к домашней сети."
            : shared.Count == 0 ? "Выберите первую папку для iPhone."
            : phones.Items.Count == 0 ? "Папка готова. Нажмите «Подключить телефон»."
            : (bool)state["hasTailnet"] ? "Домашняя сеть · Tailscale доступен" : "Домашняя сеть";
    }

    private void AddFolder(bool backup)
    {
        using (var picker = new FolderBrowserDialog {
            Description = backup ? "Выберите папку для фото и видео с iPhone" : "Выберите папку, которую хотите открыть на iPhone",
            ShowNewFolderButton = true
        }) {
            if (picker.ShowDialog(this) != DialogResult.OK) return;
            backend.Call("add", "path", picker.SelectedPath, "backup", backup);
            RefreshState();
            if (phones.Items.Count > 0)
                status.Text = "Чтобы открыть новую папку на подключённом iPhone, настройте его права доступа.";
        }
    }

    private void RemoveFolder()
    {
        string source = Selected(folders);
        if (source == null) { status.Text = "Выберите папку в списке."; return; }
        if (MessageBox.Show(this, "Закрыть доступ с телефона к выбранной папке?", Text, MessageBoxButtons.YesNo) != DialogResult.Yes) return;
        backend.Call("remove", "source", source);
        RefreshState();
    }

    private void RevokePhone()
    {
        string device = Selected(phones);
        if (device == null) { status.Text = "Выберите телефон в списке."; return; }
        if (MessageBox.Show(this, "Отключить выбранный телефон от этого ПК?", Text, MessageBoxButtons.YesNo) != DialogResult.Yes) return;
        backend.Call("revoke", "device", device);
        RefreshState();
    }

    private Form Dialog(string title, Size size)
    {
        return new Form { Text = title, StartPosition = FormStartPosition.CenterParent, ClientSize = size,
            FormBorderStyle = FormBorderStyle.FixedDialog, MinimizeBox = false, MaximizeBox = false,
            ShowInTaskbar = false, BackColor = Color.Black, ForeColor = Color.WhiteSmoke, Font = Font };
    }

    private void PairPhone()
    {
        using (var prompt = Dialog("Подключить телефон", new Size(425, 490)))
        using (var timer = new System.Windows.Forms.Timer { Interval = 1000 }) {
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4,
                Padding = new Padding(18) };
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var hint = new Label { Text = "Откройте «Мой диск» на iPhone в домашней сети и нажмите «Добавить компьютер».",
                AutoSize = true, MaximumSize = new Size(380, 0) };
            var canvas = new CodePanel { Dock = DockStyle.Fill };
            var expires = new Label { AutoSize = true, ForeColor = Muted };
            var paired = PhoneList(backend.Call("state")).Select(phone => (string)phone["id"]).ToArray();
            var until = DateTime.UtcNow;
            Action renew = delegate {
                var invitation = backend.Call("invite");
                canvas.Rows = ((System.Collections.IEnumerable)invitation["matrix"]).Cast<object>().Select(item => (string)item).ToArray();
                until = DateTime.UtcNow.AddSeconds(Convert.ToInt32(invitation["expiresIn"]));
                expires.Text = "Код действует 3 минуты";
                canvas.Invalidate();
                timer.Start();
            };
            timer.Tick += delegate {
                try {
                    var latest = backend.Call("state");
                    if (!(bool)latest["inviting"] && DateTime.UtcNow < until ||
                        PhoneList(latest).Any(phone => !paired.Contains((string)phone["id"]))) {
                        prompt.DialogResult = DialogResult.OK;
                        prompt.Close();
                        return;
                    }
                    int remaining = Math.Max(0, (int)Math.Ceiling((until - DateTime.UtcNow).TotalSeconds));
                    expires.Text = remaining > 0 ? "Код действует " + TimeSpan.FromSeconds(remaining).ToString(@"m\:ss") : "Срок кода истёк";
                    if (remaining == 0) { canvas.Rows = null; canvas.Invalidate(); timer.Stop(); }
                } catch (IOException) {
                    expires.Text = "Связь с программой передачи потеряна.";
                    timer.Stop();
                }
            };
            layout.Controls.Add(hint, 0, 0);
            layout.Controls.Add(canvas, 0, 1);
            layout.Controls.Add(expires, 0, 2);
            layout.Controls.Add(Actions(Button("Новый код", renew), Button("Закрыть", prompt.Close)), 0, 3);
            prompt.Controls.Add(layout);
            renew();
            try { prompt.ShowDialog(this); }
            finally { timer.Stop(); backend.Call("cancel"); }
            RefreshState();
            if (prompt.DialogResult == DialogResult.OK) status.Text = "Телефон подключён. Папки доступны в «Файлах».";
        }
    }

    private void EditPermissions()
    {
        string device = Selected(phones);
        if (device == null) { status.Text = "Выберите телефон в списке."; return; }
        var phone = PhoneList(state).First(record => (string)record["id"] == device);
        var granted = Dict(phone["scopes"]);
        using (var prompt = Dialog("Права доступа · " + phone["name"], new Size(485, 470))) {
            var list = new CheckedListBox { Dock = DockStyle.Fill, BackColor = Surface, ForeColor = Color.WhiteSmoke,
                CheckOnClick = true, BorderStyle = BorderStyle.None };
            var choices = new List<Tuple<string, string>>();
            var labels = new Dictionary<string, string> { { "view", "Просмотр" }, { "download", "Скачивание" },
                { "create", "Запись" }, { "delete", "Удаление" } };
            foreach (var entry in Dict(state["folders"])) {
                var folder = Dict(entry.Value);
                string[] permitted = (bool)folder["backup"] ? new[] { "create" } : new[] { "view", "download", "create", "delete" };
                foreach (var permission in permitted) {
                    choices.Add(Tuple.Create(entry.Key, permission));
                    bool enabled = granted.ContainsKey(entry.Key) &&
                        ((System.Collections.IEnumerable)granted[entry.Key]).Cast<object>().Contains(permission);
                    list.Items.Add(folder["name"] + " · " + labels[permission], enabled);
                }
            }
            var actions = Actions(Button("Сохранить", delegate {
                var rules = list.CheckedIndices.Cast<int>().Select(i => choices[i]).GroupBy(p => p.Item1)
                    .ToDictionary(group => group.Key, group => group.Select(p => p.Item2).ToList());
                foreach (var group in rules.Values)
                    if (group.Contains("download") && !group.Contains("view")) group.Add("view");
                backend.Call("grant", "device", device, "scopes", rules);
                prompt.DialogResult = DialogResult.OK;
                prompt.Close();
            }, true), Button("Закрыть", prompt.Close));
            actions.Dock = DockStyle.Bottom;
            prompt.Padding = new Padding(16);
            prompt.Controls.Add(list);
            prompt.Controls.Add(actions);
            prompt.ShowDialog(this);
            RefreshState();
        }
    }
}

internal sealed class CodePanel : Panel
{
    internal string[] Rows;

    protected override void OnPaint(PaintEventArgs args)
    {
        base.OnPaint(args);
        if (Rows == null || Rows.Length == 0) return;
        int module = Math.Min(Width, Height) / Rows.Length;
        int length = module * Rows.Length;
        int left = (Width - length) / 2;
        int top = (Height - length) / 2;
        args.Graphics.FillRectangle(Brushes.White, left, top, length, length);
        for (int y = 0; y < Rows.Length; ++y)
            for (int x = 0; x < Rows[y].Length; ++x)
                if (Rows[y][x] == '1')
                    args.Graphics.FillRectangle(Brushes.Black, left + x * module, top + y * module, module, module);
    }
}
