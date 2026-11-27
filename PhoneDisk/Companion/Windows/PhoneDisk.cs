using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
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

internal static class DesktopPalette
{
    internal static readonly Color Surface = Color.FromArgb(22, 22, 22);
    internal static readonly Color Outline = Color.FromArgb(49, 49, 49);
    internal static readonly Color Muted = Color.FromArgb(180, 180, 180);
    internal static readonly Color Green = Color.FromArgb(164, 200, 174);
    internal static readonly Color Selection = Color.FromArgb(41, 58, 48);
    internal static readonly Color Red = Color.FromArgb(239, 168, 165);
    internal const TextFormatFlags Line = TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter |
        TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;

    internal static void Round(Graphics graphics, Rectangle bounds, int radius, Color fill, Color outline)
    {
        if (bounds.Width < 3 || bounds.Height < 3) return;
        int right = bounds.Right - 1;
        int bottom = bounds.Bottom - 1;
        int diameter = Math.Min(radius * 2, Math.Min(bounds.Width - 1, bounds.Height - 1));
        var saved = graphics.Save();
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var path = new GraphicsPath())
        using (var brush = new SolidBrush(fill))
        using (var pen = new Pen(outline)) {
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(right - diameter, bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            graphics.FillPath(brush, path);
            graphics.DrawPath(pen, path);
        }
        graphics.Restore(saved);
    }
}

internal class DesktopForm : Form
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    protected override void OnHandleCreated(EventArgs args)
    {
        base.OnHandleCreated(args);
        if (SystemInformation.HighContrast) return;
        const int useImmersiveDarkMode = 20;
        const int windowCornerPreference = 33;
        const int captionColor = 35;
        const int textColor = 36;
        int dark = 1;
        int round = 2;
        int caption = ColorTranslator.ToWin32(Color.Black);
        int text = ColorTranslator.ToWin32(Color.WhiteSmoke);
        DwmSetWindowAttribute(Handle, useImmersiveDarkMode, ref dark, sizeof(int));
        DwmSetWindowAttribute(Handle, windowCornerPreference, ref round, sizeof(int));
        DwmSetWindowAttribute(Handle, captionColor, ref caption, sizeof(int));
        DwmSetWindowAttribute(Handle, textColor, ref text, sizeof(int));
    }
}

internal sealed class DesktopCard : TableLayoutPanel
{
    internal DesktopCard()
    {
        DoubleBuffered = true;
        BackColor = DesktopPalette.Surface;
    }

    protected override void OnPaintBackground(PaintEventArgs args)
    {
        args.Graphics.FillRectangle(Brushes.Black, args.ClipRectangle);
        DesktopPalette.Round(args.Graphics, ClientRectangle, 22, BackColor, DesktopPalette.Outline);
    }
}

internal sealed class NetworkLabel : Label
{
    protected override void OnPaint(PaintEventArgs args)
    {
        DesktopPalette.Round(args.Graphics, ClientRectangle, 15, Color.FromArgb(27, 34, 30), Color.FromArgb(52, 60, 55));
        TextRenderer.DrawText(args.Graphics, Text, Font, ClientRectangle, ForeColor,
            DesktopPalette.Line | TextFormatFlags.HorizontalCenter);
    }
}

internal sealed class SoftButton : Button
{
    private readonly bool primary;
    private bool hover;

    internal SoftButton(string title, bool primary, bool destructive)
    {
        this.primary = primary;
        Text = title;
        AutoSize = true;
        MinimumSize = new Size(0, 32);
        Padding = new Padding(9, 1, 9, 1);
        Margin = new Padding(7, 0, 0, 0);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        UseVisualStyleBackColor = false;
        BackColor = DesktopPalette.Surface;
        ForeColor = primary ? DesktopPalette.Green : destructive ? DesktopPalette.Red : Color.WhiteSmoke;
        Cursor = Cursors.Hand;
        MouseEnter += delegate { hover = true; Invalidate(); };
        MouseLeave += delegate { hover = false; Invalidate(); };
        MouseDown += delegate { Invalidate(); };
        MouseUp += delegate { Invalidate(); };
    }

    protected override void OnPaint(PaintEventArgs args)
    {
        using (var brush = new SolidBrush(BackColor))
            args.Graphics.FillRectangle(brush, ClientRectangle);
        var fill = primary ? Color.FromArgb(38, 54, 44) : Color.FromArgb(37, 37, 37);
        if (hover) fill = Capture ? Color.FromArgb(48, 60, 52) : Color.FromArgb(52, 56, 52);
        var border = Focused && ShowFocusCues ? DesktopPalette.Green :
            primary ? Color.FromArgb(64, 87, 74) : Color.FromArgb(55, 55, 55);
        DesktopPalette.Round(args.Graphics, ClientRectangle, 11, fill, border);
        TextRenderer.DrawText(args.Graphics, Text, Font, ClientRectangle,
            Enabled ? ForeColor : DesktopPalette.Muted, DesktopPalette.Line | TextFormatFlags.HorizontalCenter);
    }
}

internal sealed class DesktopList : ListView
{
    private readonly ImageList lineSpacing = new ImageList { ImageSize = new Size(1, 30) };

    internal DesktopList(params string[] headings)
    {
        Dock = DockStyle.Fill;
        View = View.Details;
        FullRowSelect = true;
        MultiSelect = false;
        HideSelection = false;
        HeaderStyle = ColumnHeaderStyle.Nonclickable;
        BackColor = DesktopPalette.Surface;
        ForeColor = Color.WhiteSmoke;
        BorderStyle = BorderStyle.None;
        Margin = new Padding(0);
        OwnerDraw = true;
        DoubleBuffered = true;
        SmallImageList = lineSpacing;
        for (int index = 0; index < headings.Length; ++index)
            Columns.Add(headings[index], index == 0 ? (headings.Length == 3 ? 175 : 210) : index == 1 ? 350 : 120);
    }

    protected override void OnClientSizeChanged(EventArgs args)
    {
        base.OnClientSizeChanged(args);
        if (Columns.Count < 2) return;
        int fixedWidth = Columns[0].Width + (Columns.Count == 3 ? Columns[2].Width : 0);
        Columns[1].Width = Math.Max(76, ClientSize.Width - fixedWidth);
    }

    protected override void OnDrawColumnHeader(DrawListViewColumnHeaderEventArgs args)
    {
        using (var brush = new SolidBrush(BackColor))
        using (var pen = new Pen(DesktopPalette.Outline)) {
            args.Graphics.FillRectangle(brush, args.Bounds);
            args.Graphics.DrawLine(pen, args.Bounds.Left, args.Bounds.Bottom - 1, args.Bounds.Right, args.Bounds.Bottom - 1);
        }
        var text = Rectangle.Inflate(args.Bounds, -4, 0);
        TextRenderer.DrawText(args.Graphics, args.Header.Text, Font, text, DesktopPalette.Muted,
            DesktopPalette.Line | TextFormatFlags.EndEllipsis);
    }

    protected override void OnDrawItem(DrawListViewItemEventArgs args)
    {
        var bounds = new Rectangle(args.Bounds.Left, args.Bounds.Top, ClientSize.Width, args.Bounds.Height);
        using (var brush = new SolidBrush(BackColor))
            args.Graphics.FillRectangle(brush, bounds);
        if (args.Item.Selected) {
            var selected = Rectangle.Inflate(bounds, 0, -1);
            var outline = Focused && args.Item.Focused && ShowFocusCues ? DesktopPalette.Green : DesktopPalette.Selection;
            DesktopPalette.Round(args.Graphics, selected, 7, DesktopPalette.Selection, outline);
        }

        int left = bounds.Left;
        for (int index = 0; index < args.Item.SubItems.Count && index < Columns.Count; ++index) {
            int width = Columns[index].Width;
            var text = new Rectangle(left + 4, bounds.Top, width - 8, bounds.Height);
            TextRenderer.DrawText(args.Graphics, args.Item.SubItems[index].Text, Font, text,
                index == 0 ? ForeColor : DesktopPalette.Muted, DesktopPalette.Line | TextFormatFlags.EndEllipsis);
            left += width;
        }
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) lineSpacing.Dispose();
    }
}

internal sealed class MainWindow : DesktopForm
{
    private readonly Backend backend;
    private readonly NotifyIcon tray;
    private readonly DesktopList folders = new DesktopList("Папка", "Путь", "Назначение");
    private readonly DesktopList phones = new DesktopList("Имя", "Доступные папки");
    private readonly Label status = new Label { AutoSize = true, ForeColor = DesktopPalette.Muted, Margin = new Padding(0) };
    private readonly NetworkLabel network = new NetworkLabel { AutoSize = true, Anchor = AnchorStyles.Right,
        Padding = new Padding(11, 6, 11, 6), Margin = new Padding(10, 0, 0, 0) };
    private Dictionary<string, object> state;
    private bool exit;

    internal MainWindow(Backend service)
    {
        backend = service;
        Text = "Мой диск";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(790, 545);
        MinimumSize = new Size(655, 500);
        BackColor = Color.Black;
        ForeColor = Color.WhiteSmoke;
        Font = new Font("Segoe UI", 10f);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24, 18, 24, 14),
            ColumnCount = 1, RowCount = 4 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 55));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 45));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var header = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 2, RowCount = 1,
            Margin = new Padding(0, 0, 0, 16) };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        header.Controls.Add(Heading("Мой диск", 25), 0, 0);
        header.Controls.Add(network, 1, 0);
        layout.Controls.Add(header, 0, 0);
        layout.Controls.Add(Section("Общие папки", folders, Button("Добавить папку", delegate { AddFolder(false); }, true),
            Button("Папка для автокопий", delegate { AddFolder(true); }),
            Button("Убрать из списка", RemoveFolder, destructive: true)), 0, 1);
        layout.Controls.Add(Section("Подключённые устройства", phones, Button("Подключить телефон", PairPhone, true),
            Button("Обновить", RefreshState),
            Button("Права доступа", EditPermissions),
            Button("Отключить телефон", RevokePhone, destructive: true)), 0, 2);
        layout.Controls.Add(status, 0, 3);
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
                           AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0) };
    }

    private static Control Section(string title, DesktopList items, Button primary, params Control[] extra)
    {
        var card = new DesktopCard { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3,
            Margin = new Padding(0, 0, 0, 12), Padding = new Padding(16, 12, 16, 12) };
        card.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        card.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        card.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        var heading = Heading(title, 13);
        heading.Margin = new Padding(0, 0, 0, 7);
        primary.Anchor = AnchorStyles.Right;
        primary.Margin = new Padding(8, 0, 0, 7);
        card.Controls.Add(heading, 0, 0);
        card.Controls.Add(primary, 1, 0);
        card.Controls.Add(items, 0, 1);
        card.SetColumnSpan(items, 2);
        var actions = Actions(extra);
        card.Controls.Add(actions, 0, 2);
        card.SetColumnSpan(actions, 2);
        return card;
    }

    private Button Button(string title, Action run, bool primary = false, bool destructive = false)
    {
        var button = new SoftButton(title, primary, destructive);
        button.Click += delegate {
            try { run(); }
            catch (Exception error) { MessageBox.Show(this, error.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        };
        return button;
    }

    private static FlowLayoutPanel Actions(params Control[] controls)
    {
        var row = new FlowLayoutPanel { Anchor = AnchorStyles.Right, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false, Margin = new Padding(0, 7, 0, 0) };
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
        var routes = new List<string>();
        if ((bool)state["hasNetwork"]) routes.Add("Домашняя сеть");
        if ((bool)state["hasTailnet"]) routes.Add("Tailscale");
        network.Text = routes.Count > 0 ? "●  " + String.Join(" · ", routes) : "○  Нет сети";
        network.ForeColor = routes.Count > 0 ? DesktopPalette.Green : DesktopPalette.Muted;
        status.Text = shared.Count == 0 ? "Добавьте папку, чтобы подключить iPhone."
            : !(bool)state["hasNetwork"] ? "Подключите компьютер к домашней сети, чтобы создать QR-код."
            : phones.Items.Count == 0 ? "Папка готова. Нажмите «Подключить телефон»." : "Окно можно свернуть.";
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
        return new DesktopForm { Text = title, StartPosition = FormStartPosition.CenterParent, ClientSize = size,
            FormBorderStyle = FormBorderStyle.FixedDialog, MinimizeBox = false, MaximizeBox = false,
            ShowInTaskbar = false, BackColor = Color.Black, ForeColor = Color.WhiteSmoke, Font = Font };
    }

    private void PairPhone()
    {
        using (var prompt = Dialog("Подключить телефон", new Size(425, 490)))
        using (var timer = new System.Windows.Forms.Timer { Interval = 1000 }) {
            var layout = new DesktopCard { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4,
                Padding = new Padding(18) };
            prompt.Padding = new Padding(12);
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            var hint = new Label { Text = "Наведите камеру iPhone на QR-код и нажмите на ссылку. Код также можно считать в «Моём диске» через «Добавить компьютер». Оба устройства должны быть в одной сети Wi-Fi.",
                AutoSize = true, MaximumSize = new Size(380, 0) };
            var canvas = new CodePanel { Dock = DockStyle.Fill };
            var expires = new Label { AutoSize = true, ForeColor = DesktopPalette.Muted };
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
            var close = Button("Закрыть", prompt.Close);
            close.DialogResult = DialogResult.Cancel;
            prompt.CancelButton = close;
            layout.Controls.Add(Actions(Button("Новый код", renew, true), close), 0, 3);
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
            var list = new CheckedListBox { Dock = DockStyle.Fill, BackColor = DesktopPalette.Surface, ForeColor = Color.WhiteSmoke,
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
            var card = new DesktopCard { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 1, RowCount = 2 };
            card.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            card.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            prompt.Padding = new Padding(12);
            card.Controls.Add(list, 0, 0);
            card.Controls.Add(actions, 0, 1);
            prompt.Controls.Add(card);
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
