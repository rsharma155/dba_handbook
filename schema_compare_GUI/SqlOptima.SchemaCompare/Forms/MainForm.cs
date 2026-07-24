using System.Diagnostics;
using System.Text;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Main window inspired by OpenDBDiff: dual connection panels, Compare,
/// difference tree, and synchronization script tabs — with clearer UX extras.
/// Implements full shutdown/dispose so child PowerShell processes do not linger.
/// </summary>
public sealed class MainForm : Form
{
    private readonly CompareEngine _engine;
    private CompareOptions _options = new();
    private CompareResult? _lastResult;
    private CancellationTokenSource? _cts;
    private readonly CappedStringBuffer _logBuffer = new(CompareEngine.MaxLogChars);
    private readonly List<Bitmap> _ownedBitmaps = new();
    private bool _isShuttingDown;
    private bool _busy;

    private readonly ConnectionPanel _sourcePanel;
    private readonly ConnectionPanel _targetPanel;
    private readonly RadioButton _rbOneToOne = new() { Text = "One-to-One", AutoSize = true, Checked = true };
    private readonly RadioButton _rbOneToMany = new() { Text = "One-to-Many (1 source -> many targets)", AutoSize = true };
    private readonly TextBox _txtListFile = new();
    private readonly ModernButton _btnBrowseList = new() { Text = "List file...", Width = 104, Height = 32 };
    private readonly ModernButton _btnCompare = new() { Text = "Compare", Width = 128, Height = 36 };
    private readonly ModernButton _btnSaveDeploy = new() { Text = "Save deploy script", Width = 158, Height = 36 };
    private readonly ModernButton _btnOptions = new() { Text = "Options", Width = 104, Height = 36 };
    private readonly ModernButton _btnOpenOutput = new() { Text = "Open output", Width = 116, Height = 36 };
    private readonly ModernButton _btnOpenReport = new() { Text = "HTML report", Width = 116, Height = 36 };
    private readonly ModernButton _btnCopyScript = new() { Text = "Copy script", Width = 118, Height = 32 };
    private readonly TextBox _txtFilter = new() { PlaceholderText = "Filter objects..." };
    private readonly TreeView _tree = new() { HideSelection = false, FullRowSelect = true };
    private readonly TabControl _tabs = new();
    private readonly TextBox _txtScript = new() { Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 9.5f), ReadOnly = true, WordWrap = false };
    private readonly TextBox _txtManual = new() { Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 9.5f), ReadOnly = true, WordWrap = false, ForeColor = Color.FromArgb(140, 40, 20) };
    private readonly TextBox _txtDetails = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true, Font = new Font("Segoe UI", 9.5f) };
    private readonly TextBox _txtLog = new() { Multiline = true, ScrollBars = ScrollBars.Both, ReadOnly = true, Font = new Font("Consolas", 8.5f) };
    private TabPage? _tabManual;
    private DeployScriptResult? _deployResult;
    private readonly Label _lblSummary = new() { AutoSize = true, Font = new Font("Segoe UI Semibold", 9.5f) };
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 0, Height = 18 };
    private readonly StatusStrip _status = new();
    private readonly ToolStripStatusLabel _statusText = new() { Text = "Ready", Spring = true, TextAlign = ContentAlignment.MiddleLeft };
    private readonly ImageList _treeImages = new() { ImageSize = new Size(16, 16), ColorDepth = ColorDepth.Depth32Bit };

    public MainForm()
        : this(null)
    {
    }

    /// <summary>Allows tests to inject a pre-built engine (or null = discover paths).</summary>
    public MainForm(CompareEngine? engine)
    {
        _engine = engine ?? new CompareEngine();
        _options.OutputPath = Path.Combine(_engine.SchemaCompareRoot, "output");

        Text = "SQL Optima Schema Compare";
        Width = 1180;
        Height = 820;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1000, 700);
        Font = UiTheme.UiFont();
        BackColor = UiTheme.AppBackground;
        ForeColor = UiTheme.TextPrimary;

        BuildImageList();
        _tree.ImageList = _treeImages;

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 72,
            BackColor = UiTheme.HeaderBackground
        };
        var accent = new Panel { Dock = DockStyle.Bottom, Height = 4, BackColor = UiTheme.HeaderAccent };
        var title = new Label
        {
            Text = "SQL Optima Schema Compare",
            ForeColor = UiTheme.TextOnDark,
            Font = new Font("Segoe UI", 16f, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(20, 12)
        };
        var subtitle = new Label
        {
            Text = "Source of truth  \u2192  Target     \u00B7     One-to-one and one-to-many schema sync",
            ForeColor = UiTheme.TextOnDarkMuted,
            Font = UiTheme.UiFont(9f),
            AutoSize = true,
            Location = new Point(22, 44)
        };
        header.Controls.Add(subtitle);
        header.Controls.Add(title);
        header.Controls.Add(accent);
        Controls.Add(header);

        var strip = new Panel { Dock = DockStyle.Top, Height = 60, Padding = new Padding(14, 12, 14, 12), BackColor = Color.White };
        var stripBorder = new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = UiTheme.CardBorder };
        strip.Controls.Add(stripBorder);
        _rbOneToOne.Location = new Point(16, 20);
        _rbOneToOne.ForeColor = UiTheme.TextPrimary;
        _rbOneToOne.Font = UiTheme.SemiBold(9.5f);
        _rbOneToMany.Location = new Point(130, 20);
        _rbOneToMany.ForeColor = UiTheme.TextPrimary;
        _rbOneToMany.Font = UiTheme.SemiBold(9.5f);
        strip.Controls.Add(_rbOneToOne);
        strip.Controls.Add(_rbOneToMany);

        UiTheme.StyleSuccess(_btnCompare);
        UiTheme.StylePrimary(_btnSaveDeploy);
        UiTheme.StyleSecondary(_btnOptions);
        UiTheme.StyleSecondary(_btnOpenOutput);
        UiTheme.StyleSecondary(_btnOpenReport);
        _btnSaveDeploy.Enabled = false;
        strip.Controls.Add(_btnCompare);
        strip.Controls.Add(_btnSaveDeploy);
        strip.Controls.Add(_btnOptions);
        strip.Controls.Add(_btnOpenOutput);
        strip.Controls.Add(_btnOpenReport);
        Controls.Add(strip);

        var connHost = new Panel { Dock = DockStyle.Top, Height = 310, Padding = new Padding(14, 8, 14, 8), BackColor = UiTheme.AppBackground };
        _sourcePanel = new ConnectionPanel("Source database (source of truth)");
        _targetPanel = new ConnectionPanel("Destination database (will be updated)", multiSelectTargets: true);
        _sourcePanel.Location = new Point(14, 6);
        _sourcePanel.Width = 560;
        _targetPanel.Location = new Point(590, 6);
        _targetPanel.Width = 560;
        connHost.Controls.Add(_sourcePanel);
        connHost.Controls.Add(_targetPanel);

        var listLabel = new Label { Text = "Destination list file (optional):", AutoSize = true, Location = new Point(14, 280), ForeColor = UiTheme.TextMuted, Font = UiTheme.UiFont(9f) };
        UiTheme.StyleTextBox(_txtListFile);
        _txtListFile.SetBounds(200, 276, 420, 26);
        _btnBrowseList.Location = new Point(630, 274);
        UiTheme.StyleSecondary(_btnBrowseList);
        connHost.Controls.Add(listLabel);
        connHost.Controls.Add(_txtListFile);
        connHost.Controls.Add(_btnBrowseList);
        Controls.Add(connHost);

        var mid = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(12, 4, 12, 4) };
        _lblSummary.Text = "Add: 0   Update: 0   Extra: 0   Total: 0";
        _lblSummary.Location = new Point(12, 10);
        _progress.SetBounds(400, 12, 740, 16);
        mid.Controls.Add(_lblSummary);
        mid.Controls.Add(_progress);
        Controls.Add(mid);

        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            SplitterDistance = 360,
            BorderStyle = BorderStyle.FixedSingle
        };

        var left = new Panel { Dock = DockStyle.Fill, Padding = new Padding(8) };
        var treeLabel = new Label
        {
            Text = "Schema differences",
            Font = UiTheme.SemiBold(9.5f),
            ForeColor = UiTheme.TextPrimary,
            Dock = DockStyle.Top,
            Height = 22
        };
        _txtFilter.Dock = DockStyle.Top;
        _txtFilter.Height = 26;
        _tree.Dock = DockStyle.Fill;
        left.Controls.Add(_tree);
        left.Controls.Add(_txtFilter);
        left.Controls.Add(treeLabel);
        split.Panel1.Controls.Add(left);

        var tabSchema = new TabPage("Object detail");
        tabSchema.Controls.Add(_txtDetails);
        _txtDetails.Dock = DockStyle.Fill;

        var tabScript = new TabPage("Deployable script");
        var scriptHost = new Panel { Dock = DockStyle.Fill };
        var scriptBar = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(6) };
        _btnCopyScript.Location = new Point(8, 5);
        UiTheme.StyleSecondary(_btnCopyScript);
        var scriptHint = new Label
        {
            Text = "Self-contained auto/safe changes. Run on the TARGET server (SSMS or sqlcmd).",
            AutoSize = true,
            ForeColor = UiTheme.TextMuted,
            Location = new Point(128, 12)
        };
        scriptBar.Controls.Add(scriptHint);
        scriptBar.Controls.Add(_btnCopyScript);
        _txtScript.Dock = DockStyle.Fill;
        scriptHost.Controls.Add(_txtScript);
        scriptHost.Controls.Add(scriptBar);
        tabScript.Controls.Add(scriptHost);

        _tabManual = new TabPage("Manual actions");
        var manualHost = new Panel { Dock = DockStyle.Fill };
        var manualBar = new Panel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(6), BackColor = Color.FromArgb(253, 245, 230) };
        var manualHint = new Label
        {
            Text = "\u26A0  These changes are NOT applied automatically. Review and run them manually on the TARGET.",
            AutoSize = true,
            ForeColor = UiTheme.Warning,
            Font = UiTheme.SemiBold(9f),
            Location = new Point(10, 12)
        };
        manualBar.Controls.Add(manualHint);
        _txtManual.Dock = DockStyle.Fill;
        manualHost.Controls.Add(_txtManual);
        manualHost.Controls.Add(manualBar);
        _tabManual.Controls.Add(manualHost);

        var tabLog = new TabPage("Progress log");
        tabLog.Controls.Add(_txtLog);
        _txtLog.Dock = DockStyle.Fill;

        _tabs.Dock = DockStyle.Fill;
        _tabs.TabPages.Add(tabSchema);
        _tabs.TabPages.Add(tabScript);
        _tabs.TabPages.Add(_tabManual);
        _tabs.TabPages.Add(tabLog);
        split.Panel2.Controls.Add(_tabs);
        Controls.Add(split);

        _status.Dock = DockStyle.Bottom;
        _status.Items.Add(_statusText);
        Controls.Add(_status);

        Controls.SetChildIndex(split, 0);
        Controls.SetChildIndex(_status, 0);

        WireEvents();
        LoadSettings();
        UpdateModeUi();
        SetStatus($"Engine: {_engine.SchemaCompareRoot}");
    }

    private void BuildImageList()
    {
        AddGlyph("root", Color.FromArgb(27, 79, 114));
        AddGlyph("type", Color.SteelBlue);
        AddGlyph("add", Color.FromArgb(39, 174, 96));
        AddGlyph("upd", Color.FromArgb(243, 156, 18));
        AddGlyph("extra", Color.FromArgb(192, 57, 43));
        AddGlyph("other", Color.Gray);
    }

    private void AddGlyph(string key, Color color)
    {
        var bmp = MakeGlyph(color);
        _ownedBitmaps.Add(bmp);
        _treeImages.Images.Add(key, bmp);
    }

    private static Bitmap MakeGlyph(Color color)
    {
        var bmp = new Bitmap(16, 16);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.Transparent);
        using var b = new SolidBrush(color);
        g.FillEllipse(b, 2, 2, 12, 12);
        return bmp;
    }

    private void WireEvents()
    {
        _rbOneToOne.CheckedChanged += (_, _) => SafeUi(() => { if (_rbOneToOne.Checked) UpdateModeUi(); });
        _rbOneToMany.CheckedChanged += (_, _) => SafeUi(() => { if (_rbOneToMany.Checked) UpdateModeUi(); });

        _sourcePanel.TestClicked += async (_, _) => await TestSideAsync(true);
        _targetPanel.TestClicked += async (_, _) => await TestSideAsync(false);
        _sourcePanel.RefreshClicked += async (_, _) => await RefreshSideAsync(true);
        _targetPanel.RefreshClicked += async (_, _) => await RefreshSideAsync(false);

        _btnOptions.Click += (_, _) => SafeUi(() =>
        {
            using var dlg = new OptionsForm(_options);
            if (dlg.ShowDialog(this) == DialogResult.OK)
                _options = dlg.Options;
        });

        _btnBrowseList.Click += (_, _) => SafeUi(() =>
        {
            using var dlg = new OpenFileDialog
            {
                Filter = "List files|*.json;*.yml;*.yaml;*.txt|All files|*.*",
                Title = "Destination database list"
            };
            var sample = Path.Combine(_engine.SchemaCompareRoot, "config");
            if (Directory.Exists(sample)) dlg.InitialDirectory = sample;
            if (dlg.ShowDialog(this) == DialogResult.OK)
            {
                _txtListFile.Text = dlg.FileName;
                _rbOneToMany.Checked = true;
            }
        });

        _btnCompare.Click += async (_, _) => await RunCompareAsync();
        _btnSaveDeploy.Click += (_, _) => SafeUi(SaveDeployScript);
        _btnCopyScript.Click += (_, _) => SafeUi(() =>
        {
            if (string.IsNullOrWhiteSpace(_txtScript.Text)) return;
            Clipboard.SetText(_txtScript.Text);
            SetStatus("Deployable script copied to clipboard.");
        });
        _btnOpenOutput.Click += (_, _) => SafeUi(OpenOutputFolder);
        _btnOpenReport.Click += (_, _) => SafeUi(OpenHtmlReport);

        _txtFilter.TextChanged += (_, _) => SafeUi(() => RebuildTree(_txtFilter.Text.Trim()));
        _tree.AfterSelect += (_, e) => SafeUi(() =>
        {
            if (e.Node?.Tag is not DifferenceItem d) return;
            _txtDetails.Text =
                $"Object: {d.ObjectName}\r\n" +
                $"Type: {d.ObjectType}\r\n" +
                $"Database: {d.Database}\r\n" +
                $"Status: {d.Status}\r\n" +
                $"Action: {d.ActionLabel}\r\n\r\n" +
                $"Details:\r\n{d.Details}";
            _tabs.SelectedIndex = 0;
        });

        FormClosing += OnFormClosing;
        Resize += (_, _) => SafeUi(LayoutActionButtons);
        LayoutActionButtons();
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (_isShuttingDown) return;

        if (_busy || _cts != null)
        {
            var r = MessageBox.Show(this,
                "A compare is still running.\r\n\r\nCancel the job and close the application?",
                "Exit", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (r != DialogResult.Yes)
            {
                e.Cancel = true;
                return;
            }
        }

        _isShuttingDown = true;
        try { SaveSettings(); } catch { /* ignore */ }
        ShutdownResources();
    }

    /// <summary>
    /// Cancels work, kills child PowerShell processes, clears large buffers, disposes GDI objects.
    /// </summary>
    public void ShutdownResources()
    {
        try
        {
            try { _cts?.Cancel(); } catch { /* ignore */ }
            try { _engine.CancelActiveProcess(); } catch { /* ignore */ }
            try { _engine.Shutdown(); } catch { /* ignore */ }

            _lastResult = null;
            _deployResult = null;
            _logBuffer.Clear();
            try
            {
                if (!IsDisposed && IsHandleCreated)
                {
                    _txtLog.Clear();
                    _txtScript.Clear();
                    _txtManual.Clear();
                    _txtDetails.Clear();
                    _tree.Nodes.Clear();
                    _btnSaveDeploy.Enabled = false;
                }
            }
            catch { /* ignore */ }

            RuntimeCleanup.ClearPasswordEnvironment();
            RuntimeCleanup.CleanupTempFolders(TimeSpan.FromMinutes(1));
            RuntimeCleanup.RequestMemoryReclaim();
        }
        catch
        {
            // Never throw during shutdown.
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            try { ShutdownResources(); } catch { /* ignore */ }
            try { _cts?.Dispose(); } catch { /* ignore */ }
            _cts = null;
            try { _engine.Dispose(); } catch { /* ignore */ }
            try
            {
                _tree.ImageList = null;
                _treeImages.Images.Clear();
                _treeImages.Dispose();
            }
            catch { /* ignore */ }
            foreach (var bmp in _ownedBitmaps)
            {
                try { bmp.Dispose(); } catch { /* ignore */ }
            }
            _ownedBitmaps.Clear();
        }
        base.Dispose(disposing);
    }

    private void SafeUi(Action action)
    {
        try
        {
            if (IsDisposed || _isShuttingDown) return;
            action();
        }
        catch (Exception ex)
        {
            try
            {
                if (!IsDisposed && IsHandleCreated)
                    MessageBox.Show(this, ex.Message, "Unexpected error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch { /* ignore */ }
        }
    }

    private void LayoutActionButtons()
    {
        if (IsDisposed) return;
        var right = ClientSize.Width - 16;
        _btnOpenReport.Left = Math.Max(12, right - _btnOpenReport.Width);
        _btnOpenOutput.Left = Math.Max(12, _btnOpenReport.Left - 8 - _btnOpenOutput.Width);
        _btnOptions.Left = Math.Max(12, _btnOpenOutput.Left - 8 - _btnOptions.Width);
        _btnSaveDeploy.Left = Math.Max(12, _btnOptions.Left - 8 - _btnSaveDeploy.Width);
        _btnCompare.Left = Math.Max(12, _btnSaveDeploy.Left - 8 - _btnCompare.Width);
        _btnCompare.Top = _btnSaveDeploy.Top = _btnOptions.Top = _btnOpenOutput.Top = _btnOpenReport.Top = 11;
    }

    private void UpdateModeUi()
    {
        var many = _rbOneToMany.Checked;
        _txtListFile.Enabled = many;
        _btnBrowseList.Enabled = many;
        _targetPanel.SetMultiSelectVisible(many);
        SetStatus(many
            ? "One-to-Many: pick one source DB, then check multiple destination DBs (or use a list file)."
            : "One-to-One: source DB is compared to one destination DB (check a single target).");
    }

    private void SetStatus(string text)
    {
        if (IsDisposed) return;
        _statusText.Text = text;
    }

    private void SetBusy(bool busy)
    {
        _busy = busy;
        if (IsDisposed) return;
        UseWaitCursor = busy;
        _btnCompare.Enabled = !busy;
        _btnOptions.Enabled = !busy;
        _btnSaveDeploy.Enabled = !busy && (_deployResult?.HasAuto == true || _deployResult?.HasManual == true);
        _progress.MarqueeAnimationSpeed = busy ? 35 : 0;
        _progress.Style = busy ? ProgressBarStyle.Marquee : ProgressBarStyle.Blocks;
        if (!busy) _progress.Value = 0;
    }

    private void AppendLogUi(string line)
    {
        if (IsDisposed || !IsHandleCreated) return;
        void Write()
        {
            _logBuffer.AppendLine(line);
            // Keep TextBox in sync without unbounded growth: refresh from capped buffer periodically.
            if (_txtLog.TextLength > CompareEngine.MaxLogChars)
                _txtLog.Text = _logBuffer.Snapshot();
            else
                _txtLog.AppendText(line + Environment.NewLine);
        }

        if (InvokeRequired)
        {
            try { BeginInvoke(Write); } catch { /* closing */ }
        }
        else
        {
            Write();
        }
    }

    private void OpenOutputFolder()
    {
        var dir = _lastResult?.RunFolder;
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
            dir = _options.OutputPath;
        if (!string.IsNullOrWhiteSpace(dir) && Directory.Exists(dir))
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
        }
        else
        {
            MessageBox.Show(this, "No output folder yet.", "Open output",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }

    private void OpenHtmlReport()
    {
        var path = _lastResult?.ReportPath;
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        else
            MessageBox.Show(this, "No HTML report from this session.", "HTML report",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private void UpdateManualTabCaption()
    {
        if (_tabManual == null) return;
        var count = _deployResult?.ManualFileCount ?? 0;
        _tabManual.Text = count > 0 ? $"\u26A0 Manual actions ({count})" : "Manual actions";
    }

    /// <summary>
    /// Exports a single self-contained, deployable .sql for the auto/safe changes,
    /// and (when present) a separate manual .sql the operator must run by hand.
    /// </summary>
    private void SaveDeployScript()
    {
        if (_deployResult == null || (!_deployResult.HasAuto && !_deployResult.HasManual))
        {
            MessageBox.Show(this, "Run a compare first - there is nothing to save yet.",
                "Save deploy script", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        using var dlg = new SaveFileDialog
        {
            Title = "Save deployable SQL script",
            Filter = "SQL script (*.sql)|*.sql|All files|*.*",
            FileName = $"Deploy_AutoChanges_{stamp}.sql",
            OverwritePrompt = true
        };
        if (!string.IsNullOrWhiteSpace(_lastResult?.RunFolder) && Directory.Exists(_lastResult.RunFolder))
            dlg.InitialDirectory = _lastResult.RunFolder;
        else if (!string.IsNullOrWhiteSpace(_options.OutputPath) && Directory.Exists(_options.OutputPath))
            dlg.InitialDirectory = _options.OutputPath;

        if (dlg.ShowDialog(this) != DialogResult.OK) return;

        var autoPath = dlg.FileName;
        File.WriteAllText(autoPath, _deployResult.BuildCombinedDeployScript(), new UTF8Encoding(true));

        string? manualPath = null;
        if (_deployResult.HasManual)
        {
            var dir = Path.GetDirectoryName(autoPath) ?? ".";
            var baseName = Path.GetFileNameWithoutExtension(autoPath);
            manualPath = Path.Combine(dir, baseName + "_MANUAL.sql");
            File.WriteAllText(manualPath, _deployResult.BuildManualScript(), new UTF8Encoding(true));
        }

        var msg = new StringBuilder();
        msg.AppendLine("Deployable script saved.");
        msg.AppendLine();
        msg.AppendLine($"Auto (safe) changes:\r\n  {autoPath}");
        msg.AppendLine();
        msg.AppendLine("Run it on the TARGET server (SSMS or sqlcmd). It is self-contained -");
        msg.AppendLine("no :r includes, so no need to keep the run folder alongside it.");
        if (manualPath != null)
        {
            msg.AppendLine();
            msg.AppendLine($"\u26A0  {_deployResult.ManualFileCount} MANUAL change(s) were also saved to:\r\n  {manualPath}");
            msg.AppendLine();
            msg.AppendLine("The manual file is NOT safe to run blindly. Review each statement,");
            msg.AppendLine("take a backup, and execute it manually on the target.");
        }

        MessageBox.Show(this, msg.ToString(), "Save deploy script",
            MessageBoxButtons.OK,
            _deployResult.HasManual ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
        SetStatus("Deploy script saved.");

        var r = MessageBox.Show(this, "Open the folder containing the saved script?",
            "Save deploy script", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (r == DialogResult.Yes)
        {
            var dir = Path.GetDirectoryName(autoPath);
            if (!string.IsNullOrWhiteSpace(dir) && Directory.Exists(dir))
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
        }
    }

    private async Task TestSideAsync(bool source)
    {
        if (_busy || _isShuttingDown) return;
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            _cts?.Token ?? CancellationToken.None);
        linked.CancelAfter(TimeSpan.FromSeconds(45));
        try
        {
            SetBusy(true);
            var info = source ? _sourcePanel.GetConnectionInfo(false) : _targetPanel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Testing {(source ? "source" : "target")} connection...");
            await SqlConnectionService.TestAsync(info, linked.Token).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed) return;
            MessageBox.Show(this, "Connection successful.", "Test connection",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            SetStatus("Connection OK.");
        }
        catch (OperationCanceledException)
        {
            SetStatus("Connection test cancelled.");
        }
        catch (Exception ex)
        {
            if (!_isShuttingDown && !IsDisposed)
                MessageBox.Show(this, ex.Message, "Connection failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatus("Connection failed.");
        }
        finally { if (!_isShuttingDown) SetBusy(false); }
    }

    private async Task RefreshSideAsync(bool source)
    {
        if (_busy || _isShuttingDown) return;
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            _cts?.Token ?? CancellationToken.None);
        linked.CancelAfter(TimeSpan.FromSeconds(60));
        try
        {
            SetBusy(true);
            var info = source ? _sourcePanel.GetConnectionInfo(false) : _targetPanel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Refreshing {(source ? "source" : "target")} databases...");
            var dbs = await SqlConnectionService.ListUserDatabasesAsync(info, linked.Token).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed) return;
            if (source) _sourcePanel.SetDatabases(dbs);
            else _targetPanel.SetDatabases(dbs);
            SetStatus($"Loaded {dbs.Count} database(s).");
        }
        catch (OperationCanceledException)
        {
            SetStatus("Refresh cancelled.");
        }
        catch (Exception ex)
        {
            if (!_isShuttingDown && !IsDisposed)
            {
                MessageBox.Show(this,
                    ex.Message + "\r\n\r\nYou can still type database names manually.",
                    "Refresh failed", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            SetStatus("Refresh failed.");
        }
        finally { if (!_isShuttingDown) SetBusy(false); }
    }

    private async Task RunCompareAsync()
    {
        if (_busy || _isShuttingDown) return;
        try
        {
            var mode = _rbOneToMany.Checked ? CompareMode.OneToMany : CompareMode.OneToOne;
            var listFile = _txtListFile.Text.Trim();

            // Panel-level validation (ErrorProvider icons + messages)
            if (!_sourcePanel.ValidateForCompare(oneToMany: false, out var srcErr))
            {
                MessageBox.Show(this, srcErr, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Destination: allow list-file-only for one-to-many
            if (mode == CompareMode.OneToMany && !string.IsNullOrWhiteSpace(listFile))
            {
                if (!_targetPanel.ValidateForConnection(out var tgtConnErr))
                {
                    MessageBox.Show(this, tgtConnErr, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                if (!File.Exists(listFile))
                {
                    MessageBox.Show(this, $"Destination list file not found:\r\n{listFile}",
                        "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
            }
            else if (!_targetPanel.ValidateForCompare(oneToMany: mode == CompareMode.OneToMany, out var tgtErr))
            {
                MessageBox.Show(this, tgtErr, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            var source = _sourcePanel.GetConnectionInfo();
            source.TrustServerCertificate = _options.TrustServerCertificate;
            var target = _targetPanel.GetConnectionInfo(false);
            target.TrustServerCertificate = _options.TrustServerCertificate;
            var checkedTargets = _targetPanel.GetCheckedDatabases().ToList();

            var validation = FormValidator.ValidateCompare(
                source, target, mode, checkedTargets, listFile,
                _sourcePanel.PortText, _targetPanel.PortText);
            if (!validation.Ok)
            {
                MessageBox.Show(this, validation.AsMessage(), "Validation",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            if (mode == CompareMode.OneToOne && checkedTargets.Count > 1)
            {
                var r = MessageBox.Show(this,
                    "Multiple destination databases are checked.\r\nSwitch to One-to-Many mode?",
                    "Multiple targets", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r != DialogResult.Yes) return;
                _rbOneToMany.Checked = true;
                mode = CompareMode.OneToMany;
            }

            var (targets, listForEngine) = CompareTargetResolver.Resolve(
                mode, source.Database, checkedTargets, listFile);

            if (_options.Apply)
            {
                var confirm = MessageBox.Show(this,
                    "APPLY is enabled.\r\n\r\nThis will execute auto_ scripts on the TARGET.\r\n" +
                    "manual_ scripts (including any DROP TABLE) are never auto-applied.\r\n\r\nContinue?",
                    "Confirm Apply", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (confirm != DialogResult.Yes) return;
            }

            _cts?.Dispose();
            _cts = new CancellationTokenSource();
            SetBusy(true);
            _logBuffer.Clear();
            _txtLog.Clear();
            _tabs.SelectedTab = _tabs.TabPages[_tabs.TabPages.Count - 1];
            SetStatus("Comparing schemas...");

            var progress = new Progress<string>(AppendLogUi);

            var result = await _engine.RunAsync(
                source, target, mode, targets,
                listForEngine,
                _options, progress, _cts.Token).ConfigureAwait(true);

            if (_isShuttingDown || IsDisposed) return;

            // Drop previous large result before assigning new one.
            _lastResult = null;
            _deployResult = null;
            RuntimeCleanup.RequestMemoryReclaim();
            _lastResult = result;

            // Build self-contained, deployable SQL (inlines the :r includes).
            _deployResult = DeployScriptBuilder.Build(result.RunFolder);
            _txtScript.Text = _deployResult.HasAuto
                ? _deployResult.BuildCombinedDeployScript()
                : (result.CombinedScriptPreview ?? "");
            _txtManual.Text = _deployResult.HasManual
                ? _deployResult.BuildManualScript()
                : "-- No manual scripts were produced for this run.";
            _btnSaveDeploy.Enabled = _deployResult.HasAuto || _deployResult.HasManual;
            UpdateManualTabCaption();

            RebuildTree(_txtFilter.Text.Trim());
            UpdateSummaryCounts(result.AllDifferences);

            if (!result.Success)
            {
                MessageBox.Show(this, result.Error ?? "Compare failed. See Progress log.",
                    "Compare failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                SetStatus("Compare failed.");
            }
            else
            {
                _tabs.SelectedIndex = result.AllDifferences.Count > 0 ? 0 : 1;
                var manualNote = _deployResult.HasManual
                    ? $"\r\n\r\n\u26A0  {_deployResult.ManualFileCount} MANUAL script(s) were produced.\r\n" +
                      "These are NOT applied automatically - open the 'Manual actions' tab\r\nand run them by hand on the target after review.\r\n" +
                      "(DROP TABLE is always manual.)"
                    : "";
                MessageBox.Show(this,
                    $"Compare finished.\r\n\r\nDifferences: {result.AllDifferences.Count}\r\n" +
                    $"Databases: {result.Summaries.Count}\r\n" +
                    $"Auto (deployable) scripts: {_deployResult.AutoFileCount}" +
                    manualNote +
                    "\r\n\r\nUse 'Save deploy script' to export a ready-to-run .sql file.",
                    "Done", MessageBoxButtons.OK,
                    _deployResult.HasManual ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
                SetStatus($"Done - {result.AllDifferences.Count} difference(s), " +
                          $"{_deployResult.AutoFileCount} auto / {_deployResult.ManualFileCount} manual.");
            }
            SaveSettings();
        }
        catch (OperationCanceledException)
        {
            SetStatus("Cancelled.");
        }
        catch (Exception ex)
        {
            if (!_isShuttingDown && !IsDisposed)
                MessageBox.Show(this, ex.Message, "Cannot start compare", MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatus("Error.");
        }
        finally
        {
            try { _cts?.Dispose(); } catch { /* ignore */ }
            _cts = null;
            if (!_isShuttingDown) SetBusy(false);
        }
    }

    private void UpdateSummaryCounts(IReadOnlyList<DifferenceItem> diffs)
    {
        var (add, upd, extra, total) = DiffQuery.CountByKind(diffs);
        _lblSummary.Text = $"Add: {add}    Update: {upd}    Extra: {extra}    Total: {total}";
        _lblSummary.ForeColor = total == 0
            ? Color.FromArgb(39, 174, 96)
            : Color.FromArgb(27, 79, 114);
    }

    private void RebuildTree(string filter)
    {
        if (IsDisposed) return;
        _tree.BeginUpdate();
        try
        {
            _tree.Nodes.Clear();
            var source = _lastResult?.AllDifferences ?? (IReadOnlyList<DifferenceItem>)Array.Empty<DifferenceItem>();
            var diffs = DiffQuery.Filter(source, filter);

            var root = new TreeNode("Differences") { ImageKey = "root", SelectedImageKey = "root" };
            foreach (var byDb in DiffQuery.GroupByDatabaseThenType(diffs))
            {
                var dbNode = new TreeNode(byDb.Key) { ImageKey = "root", SelectedImageKey = "root" };
                foreach (var byType in byDb.GroupBy(d => d.ObjectType).OrderBy(g => g.Key))
                {
                    var typeNode = new TreeNode($"{byType.Key} ({byType.Count()})")
                    {
                        ImageKey = "type",
                        SelectedImageKey = "type"
                    };
                    foreach (var d in byType.OrderBy(x => x.ObjectName))
                    {
                        var key = d.Kind switch
                        {
                            DiffKind.Add => "add",
                            DiffKind.Update => "upd",
                            DiffKind.Extra => "extra",
                            _ => "other"
                        };
                        typeNode.Nodes.Add(new TreeNode($"{d.ObjectName}  [{d.ActionLabel}]")
                        {
                            Tag = d,
                            ImageKey = key,
                            SelectedImageKey = key
                        });
                    }
                    dbNode.Nodes.Add(typeNode);
                }
                root.Nodes.Add(dbNode);
            }

            _tree.Nodes.Add(root);
            root.Expand();
            foreach (TreeNode n in root.Nodes) n.Expand();
        }
        finally
        {
            _tree.EndUpdate();
        }
    }

    private void LoadSettings()
    {
        var s = SettingsStore.Load();
        if (s == null) return;
        try
        {
            if (s.Mode == CompareMode.OneToMany) _rbOneToMany.Checked = true;
            else _rbOneToOne.Checked = true;
            _sourcePanel.Apply(s.Source);
            _targetPanel.Apply(s.Target);
            _txtListFile.Text = s.DestinationListFile;
            _options = s.Options ?? new CompareOptions();
            if (string.IsNullOrWhiteSpace(_options.OutputPath))
                _options.OutputPath = Path.Combine(_engine.SchemaCompareRoot, "output");
        }
        catch { /* ignore corrupt settings */ }
    }

    private void SaveSettings()
    {
        try
        {
            var source = _sourcePanel.GetConnectionInfo();
            var target = _targetPanel.GetConnectionInfo(false);
            SettingsStore.Save(new AppSessionSettings
            {
                Mode = _rbOneToMany.Checked ? CompareMode.OneToMany : CompareMode.OneToOne,
                Source = source,
                Target = target,
                TargetDatabases = _targetPanel.GetCheckedDatabases().ToList(),
                DestinationListFile = _txtListFile.Text.Trim(),
                Options = _options
            });
        }
        catch { /* ignore */ }
    }
}
