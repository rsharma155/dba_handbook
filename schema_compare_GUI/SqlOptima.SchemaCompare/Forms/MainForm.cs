// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.MainForm
// Purpose:  Main application window - dark chrome shell (nav rail, header with
//           workflow stepper), collapsible connection card, comparison action
//           bar, Object Explorer + results dashboard, and graceful shutdown of
//           child PowerShell processes on close.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Diagnostics;
using System.Text;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Main window matching the SQL Optima mockup: Connect -> Compare -> Review ->
/// Deploy workflow with a collapsible connection card and results dashboard.
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
    private readonly NavRail _navRail = new();
    private readonly WorkflowStepBar _steps = new();
    private CollapsibleCard _connCard = null!;
    private readonly RadioButton _rbOneToOne = new() { Text = "One-to-One", AutoSize = true, Checked = true };
    private readonly RadioButton _rbOneToMany = new() { Text = "One-to-Many", AutoSize = true };
    private readonly TextBox _txtListFile = new();
    private readonly ModernButton _btnBrowseList = new() { Text = "Browse list...", Width = 110, Height = 30 };
    private Control? _listFileHost;
    private readonly ModernButton _btnCompare = new() { Text = "Compare Schemas  \u2192", Width = 190, Height = 36 };
    private readonly ModernButton _btnCompareNow = new() { Text = "\u25B6  Compare Now", Width = 180, Height = 38 };
    private readonly ModernButton _btnSaveDeploy = new() { Text = "Save Script", Width = 120, Height = 34 };
    private readonly ModernButton _btnPresets = new() { Text = "Presets  \u02C5", Width = 104, Height = 34 };
    private readonly ModernButton _btnOptions = new() { Text = "\uE713", Width = 38, Height = 34 };
    private readonly ModernButton _btnHelp = new() { Text = "?", Width = 38, Height = 34 };
    private readonly ModernButton _btnCopyScript = new() { Text = "Copy script", Width = 110, Height = 30 };
    private readonly ModernButton _btnSwap = new() { Text = "\u21C4", Width = 40, Height = 40 };
    private readonly ModernButton _btnAdvanced = new() { Text = "Advanced Options  \u02C5", Height = 30 };
    private readonly ModernButton _btnExplorerRefresh = new() { Text = "\uE72C", Width = 26, Height = 24 };
    private readonly ComboBox _cmbProfile = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 150 };
    private readonly ModernButton _btnEditProfile = new() { Text = "\uE70F", Width = 32, Height = 27 };
    private readonly ModernButton _btnIgnoreRules = new() { Text = "\u2699  Configure ignore rules", Height = 28 };
    private readonly ModernButton _btnObjectTypes = new() { Height = 28 };
    private readonly ContextMenuStrip _typeMenu = new();
    private readonly ContextMenuStrip _presetsMenu = new();
    private static readonly string[] TypeCategories =
    {
        "Tables", "Views", "Stored Procedures", "User Defined Functions",
        "Indexes", "Triggers", "Schemas", "Others"
    };
    private readonly HashSet<string> _enabledTypes = new(TypeCategories, StringComparer.OrdinalIgnoreCase);
    private readonly TextBox _txtFilter = new() { PlaceholderText = "Search objects..." };
    private readonly TreeView _tree = new() { HideSelection = false, FullRowSelect = true, BorderStyle = BorderStyle.None, BackColor = Color.White };
    private readonly TabControl _tabs = new();
    private readonly TextBox _txtScript = new() { Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 9.5f), ReadOnly = true, WordWrap = false, BorderStyle = BorderStyle.None, BackColor = Color.FromArgb(0x1E, 0x1E, 0x1E), ForeColor = Color.FromArgb(0xD4, 0xD4, 0xD4) };
    private readonly TextBox _txtManual = new() { Multiline = true, ScrollBars = ScrollBars.Both, Font = new Font("Consolas", 9.5f), ReadOnly = true, WordWrap = false, BorderStyle = BorderStyle.None, ForeColor = Color.FromArgb(140, 40, 20) };
    private readonly TextBox _txtDetails = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true, Font = new Font("Segoe UI", 10f), BorderStyle = BorderStyle.None };
    private readonly TextBox _txtSourceDef = new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Both,
        ReadOnly = true,
        WordWrap = false,
        Font = new Font("Consolas", 9.5f),
        BorderStyle = BorderStyle.None,
        BackColor = Color.FromArgb(0x1E, 0x1E, 0x1E),
        ForeColor = Color.FromArgb(0xD4, 0xD4, 0xD4),
        Dock = DockStyle.Fill
    };
    private readonly TextBox _txtTargetDef = new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Both,
        ReadOnly = true,
        WordWrap = false,
        Font = new Font("Consolas", 9.5f),
        BorderStyle = BorderStyle.None,
        BackColor = Color.FromArgb(0x1E, 0x1E, 0x1E),
        ForeColor = Color.FromArgb(0xD4, 0xD4, 0xD4),
        Dock = DockStyle.Fill
    };
    private readonly Label _lblSourceCaption = new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = UiTheme.SemiBold(9f),
        ForeColor = UiTheme.TextPrimary,
        BackColor = Color.Transparent,
        Text = "SOURCE"
    };
    private readonly Label _lblTargetCaption = new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = UiTheme.SemiBold(9f),
        ForeColor = UiTheme.TextPrimary,
        BackColor = Color.Transparent,
        Text = "TARGET"
    };
    private readonly Label _lblDetailHeader = new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = UiTheme.SemiBold(9.5f),
        ForeColor = UiTheme.TextPrimary,
        BackColor = Color.Transparent,
        Text = ""
    };
    private readonly Panel _detailSingleHost = new() { Dock = DockStyle.Fill, BackColor = Color.White };
    private readonly Panel _detailDualHost = new() { Dock = DockStyle.Fill, BackColor = Color.White, Visible = false };
    private SplitContainer? _detailSplit;
    private readonly TextBox _txtLog = new() { Multiline = true, ScrollBars = ScrollBars.Both, ReadOnly = true, Font = new Font("Consolas", 8.5f), BorderStyle = BorderStyle.None };
    private readonly TextBox _txtOverview = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, ReadOnly = true, Font = new Font("Segoe UI", 10f), BorderStyle = BorderStyle.None, BackColor = Color.White };
    private TabPage? _tabOverview;
    private TabPage? _tabDetails;
    private TabPage? _tabScript;
    private TabPage? _tabManual;
    private TabPage? _tabDeploy;
    private TabPage? _tabLog;
    private readonly DataGridView _gridDeploy = new()
    {
        Dock = DockStyle.Fill,
        ReadOnly = true,
        AllowUserToAddRows = false,
        AllowUserToDeleteRows = false,
        AllowUserToResizeRows = false,
        RowHeadersVisible = false,
        SelectionMode = DataGridViewSelectionMode.FullRowSelect,
        MultiSelect = false,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
        BackgroundColor = Color.White,
        BorderStyle = BorderStyle.None
    };
    private readonly TextBox _txtDeployDetail = new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Vertical,
        ReadOnly = true,
        Font = new Font("Consolas", 9f),
        BorderStyle = BorderStyle.None,
        BackColor = Color.FromArgb(248, 250, 252)
    };
    private readonly Label _lblDeployBanner = new()
    {
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft,
        Font = UiTheme.SemiBold(9f),
        BackColor = Color.Transparent,
        Text = "Run a compare with Apply enabled to see deployment status."
    };
    // Per-DB deploy progress state driven by ##GUI: engine lines.
    private int _deployDbIndex;
    private int _deployDbTotal;
    private readonly Panel _overviewEmpty = new() { Dock = DockStyle.Fill, BackColor = Color.White };
    private readonly Panel _overviewDash = new() { Dock = DockStyle.Fill, BackColor = Color.White, Visible = false, Padding = new Padding(12) };
    private DeployScriptResult? _deployResult;
    private readonly SummaryCard _cardAdded = new("Added", UiTheme.AddAccent, "Objects");
    private readonly SummaryCard _cardChanged = new("Changed", UiTheme.ChangeAccent, "Objects");
    private readonly SummaryCard _cardExtra = new("Removed", UiTheme.ExtraAccent, "Objects");
    private readonly SummaryCard _cardManual = new("Warnings", UiTheme.WarnAccent, "Warnings");
    private readonly StatusBadge _badgeAdded = new("Added", UiTheme.BadgeAdded);
    private readonly StatusBadge _badgeRemoved = new("Removed", UiTheme.BadgeRemoved);
    private readonly StatusBadge _badgeChanged = new("Changed", UiTheme.BadgeChanged);
    private readonly StatusBadge _badgeIdentical = new("Identical", UiTheme.BadgeIdentical);
    private readonly StatusBadge _badgeIgnored = new("Ignored", UiTheme.BadgeIgnored);
    private readonly Label _lblProgressStage = new() { AutoSize = true, Text = "Ready to connect", ForeColor = UiTheme.TextMuted, Font = UiTheme.UiFont(9.5f) };
    private readonly Label _lblElapsed = new() { AutoSize = true, Text = "Elapsed  00:00", ForeColor = UiTheme.TextMuted, Font = UiTheme.UiFont(9.5f) };
    private readonly Label _lblTreePlaceholder = new()
    {
        Text = "No objects yet.\r\n\r\nConnect and select a database to browse objects,\r\nor click Compare Now.",
        TextAlign = ContentAlignment.MiddleCenter,
        Dock = DockStyle.Fill,
        ForeColor = UiTheme.TextMuted,
        Font = UiTheme.UiFont(10.5f),
        BackColor = Color.White
    };
    private readonly Label _lblDetailPlaceholder = new()
    {
        Text = "Select an object in the explorer\r\nto review impact, details, and scripts.",
        TextAlign = ContentAlignment.MiddleCenter,
        Dock = DockStyle.Fill,
        ForeColor = UiTheme.TextMuted,
        Font = UiTheme.UiFont(10.5f),
        BackColor = Color.White
    };
    private readonly ProgressBar _progress = new() { Style = ProgressBarStyle.Continuous, Height = 8, Maximum = 100 };
    private readonly StatusStrip _status = new() { BackColor = Color.White, SizingGrip = false };
    private readonly ToolStripStatusLabel _statusText = new() { Text = "Ready", Spring = true, TextAlign = ContentAlignment.MiddleLeft };
    private readonly ToolStripStatusLabel _statusSource = new() { Text = "Source: Not selected", BorderSides = ToolStripStatusLabelBorderSides.Left, BorderStyle = Border3DStyle.Etched };
    private readonly ToolStripStatusLabel _statusTarget = new() { Text = "Target: Not selected", BorderSides = ToolStripStatusLabelBorderSides.Left, BorderStyle = Border3DStyle.Etched };
    private readonly ToolStripStatusLabel _statusObjects = new() { Text = "Objects: 0", BorderSides = ToolStripStatusLabelBorderSides.Left, BorderStyle = Border3DStyle.Etched };
    private readonly ToolStripStatusLabel _statusTime = new() { Text = "Elapsed: \u2014", BorderSides = ToolStripStatusLabelBorderSides.Left, BorderStyle = Border3DStyle.Etched };
    private readonly ImageList _treeImages = new() { ImageSize = new Size(16, 16), ColorDepth = ColorDepth.Depth32Bit };
    private DateTime? _compareStarted;
    private Panel? _headerBar;
    private Panel? _summaryStrip;
    private Panel? _connHost;
    private Panel? _actionBar;
    private SplitContainer? _mainSplit;
    private IReadOnlyList<SchemaObjectInfo> _sourceObjects = Array.Empty<SchemaObjectInfo>();
    private IReadOnlyList<SchemaObjectInfo> _targetObjects = Array.Empty<SchemaObjectInfo>();
    private string _sourceBrowseDb = "";
    private string _targetBrowseDb = "";
    private CancellationTokenSource? _browseCts;
    private CancellationTokenSource? _scriptCts;
    private string? _browseScriptSnapshot;

    public MainForm()
        : this(null)
    {
    }

    /// <summary>Allows tests to inject a pre-built engine (or null = discover paths).</summary>
    public MainForm(CompareEngine? engine)
    {
        _engine = engine ?? new CompareEngine();
        _options.OutputPath = Path.Combine(_engine.SchemaCompareRoot, "output");

        Text = "SQL Optima  \u00B7  Schema Compare";
        Width = 1400;
        Height = 880;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1200, 720);
        Font = UiTheme.UiFont();
        BackColor = UiTheme.AppBackground;
        ForeColor = UiTheme.TextPrimary;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96F, 96F);

        BuildImageList();
        _tree.ImageList = _treeImages;
        _tree.ShowLines = false;
        _tree.Indent = 22;

        _sourcePanel = new ConnectionPanel("Source");
        _targetPanel = new ConnectionPanel("Target", multiSelectTargets: true);

        BuildHeaderBar();
        BuildConnectionCard();
        BuildActionBar();
        BuildProgressStrip();
        BuildMainSplit();
        BuildStatusBar();

        // Dock order: last Add is docked first (outermost edge). Build inner -> outer.
        SuspendLayout();
        Controls.Add(_mainSplit);
        Controls.Add(_summaryStrip);
        Controls.Add(_actionBar);
        Controls.Add(_connHost);
        Controls.Add(_status);
        Controls.Add(_headerBar);
        Controls.Add(_navRail);
        ResumeLayout(true);

        WireEvents();
        if (Environment.GetEnvironmentVariable("SQLOPTIMA_NO_SETTINGS") != "1")
            LoadSettings();
        ApplyMainSplitterDistance(300);
        UpdateModeUi();
        _steps.Active = WorkflowStep.Connect;
        UpdateSummaryCounts(Array.Empty<DifferenceItem>());
        UpdateHeaderProject();
        SetStatus("Ready");
    }

    // ------------------------------------------------------------------
    //  Shell builders (mockup layout)
    // ------------------------------------------------------------------

    private void BuildHeaderBar()
    {
        _headerBar = new Panel { Dock = DockStyle.Top, Height = 64, BackColor = UiTheme.HeaderBackground };
        _headerBar.Controls.Add(new Panel { Dock = DockStyle.Bottom, Height = 1, BackColor = Color.FromArgb(0x1E, 0x2A, 0x3F) });

        var brand = new Panel { Dock = DockStyle.Left, Width = 180, BackColor = Color.Transparent };
        brand.Controls.Add(new Label
        {
            Text = "SQL Optima",
            ForeColor = UiTheme.TextOnDark,
            Font = UiTheme.TitleFont(),
            AutoSize = true,
            Location = new Point(16, 10),
            BackColor = Color.Transparent
        });
        brand.Controls.Add(new Label
        {
            Text = "Schema Compare",
            ForeColor = UiTheme.TextOnDarkMuted,
            Font = UiTheme.UiFont(8.5f),
            AutoSize = true,
            Location = new Point(17, 36),
            BackColor = Color.Transparent
        });

        UiTheme.StyleHeaderSecondary(_btnPresets);
        UiTheme.StyleHeaderSecondary(_btnSaveDeploy);
        _btnSaveDeploy.Enabled = false;
        UiTheme.StyleHeaderSecondary(_btnOptions);
        _btnOptions.Font = UiTheme.IconFont(11f);
        _btnOptions.AccessibleName = "Settings";
        UiTheme.StyleHeaderSecondary(_btnHelp);
        _btnHelp.AccessibleName = "Help";
        UiTheme.StyleCta(_btnCompare);
        _btnCompare.Height = 36;

        UiTheme.FitButton(_btnPresets, 96);
        UiTheme.FitButton(_btnSaveDeploy, 100);
        _btnOptions.Width = 38;
        _btnHelp.Width = 38;
        UiTheme.FitButton(_btnCompare, 170);

        _presetsMenu.Items.Add(new ToolStripMenuItem("Default Profile") { Checked = true });

        var actions = new FlowLayoutPanel
        {
            Dock = DockStyle.Right,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 14, 12, 0),
            Margin = new Padding(0)
        };
        foreach (var b in new[] { _btnPresets, _btnSaveDeploy, _btnOptions, _btnHelp, _btnCompare })
        {
            b.Margin = new Padding(0, 0, 8, 0);
            actions.Controls.Add(b);
        }
        _btnCompare.Margin = new Padding(4, 0, 0, 0);

        _steps.OnDark = true;
        _steps.Dock = DockStyle.Fill;
        var stepHost = new Panel { Dock = DockStyle.Fill, BackColor = Color.Transparent, Padding = new Padding(8, 4, 8, 4) };
        stepHost.Controls.Add(_steps);

        _headerBar.Controls.Add(stepHost);
        _headerBar.Controls.Add(actions);
        _headerBar.Controls.Add(brand);
    }

    private void BuildConnectionCard()
    {
        _connCard = new CollapsibleCard("1. Connect to Source and Target", "Select databases to compare.")
        {
            Dock = DockStyle.Fill,
            // One stable height for One-to-One and One-to-Many — avoids flicker/jump
            // when the mode radios toggle the target list row.
            ExpandedHeight = 360
        };

        var connGrid = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 1,
            BackColor = Color.Transparent
        };
        connGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        connGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 56));
        connGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        connGrid.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        _sourcePanel.Dock = DockStyle.Fill;
        _targetPanel.Dock = DockStyle.Fill;
        _sourcePanel.Margin = new Padding(0, 2, 0, 2);
        _targetPanel.Margin = new Padding(0, 2, 0, 2);

        // Swap source/target (mockup: circular swap glyph between the panels)
        _btnSwap.CornerRadius = 20;
        _btnSwap.Font = new Font("Segoe UI", 13f, FontStyle.Bold);
        _btnSwap.ApplyColors(Color.White, UiTheme.Primary, UiTheme.NeutralHover, UiTheme.Neutral);
        _btnSwap.AccessibleName = "Swap source and target";
        _btnSwap.Anchor = AnchorStyles.None;
        _btnSwap.Size = new Size(40, 40);
        var swapHost = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 1, BackColor = Color.Transparent, Margin = new Padding(0) };
        swapHost.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        swapHost.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        swapHost.Controls.Add(_btnSwap, 0, 0);

        connGrid.Controls.Add(_sourcePanel, 0, 0);
        connGrid.Controls.Add(swapHost, 1, 0);
        connGrid.Controls.Add(_targetPanel, 2, 0);

        // Bottom row inside the card: compare mode | list file (1:N) | Advanced Options
        var modeRow = new TableLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 40,
            BackColor = Color.Transparent,
            ColumnCount = 3,
            RowCount = 1,
            Padding = new Padding(0),
            Margin = new Padding(0)
        };
        modeRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        modeRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        modeRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        modeRow.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));

        StyleModeRadio(_rbOneToOne);
        StyleModeRadio(_rbOneToMany);
        _rbOneToOne.Margin = new Padding(0, 6, 12, 0);
        _rbOneToMany.Margin = new Padding(0, 6, 8, 0);

        var radioFlow = new FlowLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0),
            Margin = new Padding(0),
            Dock = DockStyle.Fill
        };
        radioFlow.Controls.Add(_rbOneToOne);
        radioFlow.Controls.Add(_rbOneToMany);

        var listLabel = new Label
        {
            Text = "Optional destination list file",
            AutoSize = true,
            ForeColor = UiTheme.TextMuted,
            Font = UiTheme.UiFont(9f),
            BackColor = Color.Transparent,
            Margin = new Padding(8, 10, 8, 0)
        };
        UiTheme.StyleTextBox(_txtListFile);
        _txtListFile.Width = 260;
        _txtListFile.Margin = new Padding(0, 5, 8, 0);
        UiTheme.StyleSecondary(_btnBrowseList);
        _btnBrowseList.Height = 30;
        UiTheme.FitButton(_btnBrowseList, 110, 24);
        _btnBrowseList.Margin = new Padding(0, 4, 0, 0);

        var listFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0),
            Margin = new Padding(0),
            Visible = false
        };
        listFlow.Controls.Add(listLabel);
        listFlow.Controls.Add(_txtListFile);
        listFlow.Controls.Add(_btnBrowseList);
        _listFileHost = listFlow;

        UiTheme.StyleSecondary(_btnAdvanced);
        _btnAdvanced.Height = 30;
        UiTheme.FitButton(_btnAdvanced, 150);
        _btnAdvanced.Margin = new Padding(8, 4, 0, 0);

        modeRow.Controls.Add(radioFlow, 0, 0);
        modeRow.Controls.Add(listFlow, 1, 0);
        modeRow.Controls.Add(_btnAdvanced, 2, 0);

        _connCard.ContentHost.Controls.Add(connGrid);
        _connCard.ContentHost.Controls.Add(modeRow);

        _connHost = new Panel { Dock = DockStyle.Top, Padding = new Padding(16, 12, 16, 4), BackColor = UiTheme.AppBackground };
        _connHost.Controls.Add(_connCard);
        _connCard.CollapsedChanged += (_, _) => SyncConnCardHeight();
        SyncConnCardHeight();
    }

    private void SyncConnCardHeight()
    {
        if (_connHost == null) return;
        var cardH = _connCard.Collapsed ? 52 : _connCard.ExpandedHeight;
        _connHost.Height = cardH + _connHost.Padding.Vertical;
    }

    private void BuildActionBar()
    {
        _actionBar = new Panel { Dock = DockStyle.Top, Height = 70, BackColor = UiTheme.AppBackground, Padding = new Padding(16, 4, 16, 8) };
        var bar = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };
        bar.Paint += (_, e) =>
        {
            using var pen = new Pen(UiTheme.CardBorder);
            e.Graphics.DrawRectangle(pen, 0, 0, bar.Width - 1, bar.Height - 1);
        };

        UiTheme.StyleCta(_btnCompareNow);
        _btnCompareNow.Height = 38;
        UiTheme.FitButton(_btnCompareNow, 170);
        var right = new FlowLayoutPanel
        {
            Dock = DockStyle.Right,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 10, 12, 0),
            Margin = new Padding(0)
        };
        right.Controls.Add(_btnCompareNow);

        var flow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(12, 6, 0, 0),
            Margin = new Padding(0)
        };
        flow.Controls.Add(MakeCaptionedCluster("Comparison Profile", BuildProfileCluster()));
        flow.Controls.Add(MakeCaptionedCluster("Ignore Rules", BuildIgnoreCluster()));
        flow.Controls.Add(MakeCaptionedCluster("Object Types", BuildTypesCluster()));

        bar.Controls.Add(flow);
        bar.Controls.Add(right);
        _actionBar.Controls.Add(bar);
    }

    private static Panel MakeCaptionedCluster(string caption, Control control)
    {
        var host = new Panel { BackColor = Color.Transparent, Margin = new Padding(0, 0, 28, 0), Height = 52 };
        var lbl = new Label
        {
            Text = caption,
            AutoSize = true,
            Font = UiTheme.SemiBold(8f),
            ForeColor = UiTheme.TextMuted,
            Location = new Point(0, 0),
            BackColor = Color.Transparent
        };
        control.Location = new Point(0, 18);
        host.Controls.Add(lbl);
        host.Controls.Add(control);
        host.Width = Math.Max(lbl.PreferredWidth, control.Width) + 4;
        return host;
    }

    private Control BuildProfileCluster()
    {
        UiTheme.StyleCombo(_cmbProfile);
        _cmbProfile.Items.Add("Default Profile");
        _cmbProfile.SelectedIndex = 0;
        _cmbProfile.Width = 150;
        UiTheme.StyleSecondary(_btnEditProfile);
        _btnEditProfile.Font = UiTheme.IconFont(10f);
        _btnEditProfile.Size = new Size(32, 27);
        _btnEditProfile.AccessibleName = "Edit comparison profile";
        _btnEditProfile.Click += (_, _) => SafeUi(() => ShowOptionsDialog(OptionsFocus.Profile));
        var host = new Panel { BackColor = Color.Transparent, Height = 30 };
        _cmbProfile.Location = new Point(0, 2);
        _btnEditProfile.Location = new Point(_cmbProfile.Width + 6, 1);
        host.Controls.Add(_cmbProfile);
        host.Controls.Add(_btnEditProfile);
        host.Width = _btnEditProfile.Right + 2;
        return host;
    }

    private Control BuildIgnoreCluster()
    {
        UiTheme.StyleGhost(_btnIgnoreRules);
        _btnIgnoreRules.Height = 28;
        UiTheme.FitButton(_btnIgnoreRules, 160);
        _btnIgnoreRules.Click += (_, _) => SafeUi(() => ShowOptionsDialog(OptionsFocus.IgnoreRules));
        return _btnIgnoreRules;
    }

    private Control BuildTypesCluster()
    {
        foreach (var cat in TypeCategories)
        {
            var item = new ToolStripMenuItem(cat) { Checked = true, CheckOnClick = true };
            item.CheckedChanged += (_, _) => SafeUi(() => OnTypeMenuChanged(item));
            _typeMenu.Items.Add(item);
        }
        UiTheme.StyleSecondary(_btnObjectTypes);
        _btnObjectTypes.Height = 28;
        UpdateObjectTypesCaption();
        _btnObjectTypes.Click += (_, _) => _typeMenu.Show(_btnObjectTypes, new Point(0, _btnObjectTypes.Height));
        return _btnObjectTypes;
    }

    private void OnTypeMenuChanged(ToolStripMenuItem item)
    {
        var name = item.Text ?? "";
        if (item.Checked) _enabledTypes.Add(name);
        else _enabledTypes.Remove(name);
        UpdateObjectTypesCaption();
        RebuildTree(_txtFilter.Text.Trim());
    }

    private void UpdateObjectTypesCaption()
    {
        _btnObjectTypes.Text = $"{_enabledTypes.Count} selected  \u02C5";
        UiTheme.FitButton(_btnObjectTypes, 110);
    }

    private void BuildProgressStrip()
    {
        _summaryStrip = new Panel { Dock = DockStyle.Bottom, Height = 32, Padding = new Padding(16, 2, 16, 2), BackColor = UiTheme.AppBackground, Visible = false };
        var t = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3, RowCount = 1, BackColor = Color.Transparent };
        t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        t.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        _lblProgressStage.Anchor = AnchorStyles.Left;
        _lblProgressStage.Margin = new Padding(0, 0, 16, 0);
        _lblElapsed.Anchor = AnchorStyles.Left;
        _lblElapsed.Margin = new Padding(0, 0, 16, 0);
        _progress.Dock = DockStyle.Fill;
        _progress.Margin = new Padding(0, 10, 0, 10);
        t.Controls.Add(_lblProgressStage, 0, 0);
        t.Controls.Add(_lblElapsed, 1, 0);
        t.Controls.Add(_progress, 2, 0);
        _summaryStrip.Controls.Add(t);
    }

    private void BuildMainSplit()
    {
        // Do not set Panel1MinSize / Panel2MinSize / SplitterDistance here:
        // SplitContainer defaults to a narrow Width and throws
        // "SplitterDistance must be between Panel1MinSize and Width - Panel2MinSize".
        _mainSplit = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            FixedPanel = FixedPanel.None,
            IsSplitterFixed = false,
            SplitterWidth = 6,
            BackColor = UiTheme.AppBackground,
            BorderStyle = BorderStyle.None
        };
        var split = _mainSplit;

        var left = new Panel { Dock = DockStyle.Fill, Padding = new Padding(16, 2, 6, 8), BackColor = UiTheme.AppBackground };
        var leftCard = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(8) };
        leftCard.Paint += (_, e) =>
        {
            using var pen = new Pen(UiTheme.CardBorder);
            e.Graphics.DrawRectangle(pen, 0, 0, leftCard.Width - 1, leftCard.Height - 1);
        };

        var explorerHeader = new Panel { Dock = DockStyle.Top, Height = 26, BackColor = Color.White };
        var treeLabel = new Label
        {
            Text = "Object Explorer",
            Font = UiTheme.SemiBold(10f),
            ForeColor = UiTheme.TextPrimary,
            AutoSize = true,
            Location = new Point(0, 4),
            BackColor = Color.White
        };
        _btnExplorerRefresh.Font = UiTheme.IconFont(9f);
        _btnExplorerRefresh.CornerRadius = 6;
        _btnExplorerRefresh.ApplyColors(Color.White, UiTheme.TextMuted, UiTheme.NeutralHover, UiTheme.Neutral);
        _btnExplorerRefresh.AccessibleName = "Refresh object explorer";
        explorerHeader.Controls.Add(treeLabel);
        explorerHeader.Controls.Add(_btnExplorerRefresh);
        explorerHeader.Resize += (_, _) => _btnExplorerRefresh.Location = new Point(explorerHeader.Width - _btnExplorerRefresh.Width - 2, 1);

        UiTheme.StyleTextBox(_txtFilter);
        _txtFilter.Dock = DockStyle.Top;
        _txtFilter.Height = 28;
        _tree.Dock = DockStyle.Fill;
        leftCard.Controls.Add(_lblTreePlaceholder);
        leftCard.Controls.Add(_tree);
        leftCard.Controls.Add(_txtFilter);
        leftCard.Controls.Add(explorerHeader);
        left.Controls.Add(leftCard);
        split.Panel1.Controls.Add(left);

        var right = new Panel { Dock = DockStyle.Fill, Padding = new Padding(6, 2, 16, 8), BackColor = UiTheme.AppBackground };
        var rightCard = new Panel { Dock = DockStyle.Fill, BackColor = Color.White, Padding = new Padding(2) };
        rightCard.Paint += (_, e) =>
        {
            using var pen = new Pen(UiTheme.CardBorder);
            e.Graphics.DrawRectangle(pen, 0, 0, rightCard.Width - 1, rightCard.Height - 1);
        };

        // Badge row per mockup: Added / Removed / Changed / Identical / Ignored
        var badgeStrip = new Panel { Dock = DockStyle.Top, Height = 34, BackColor = Color.White };
        var badgeFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Right,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.Transparent,
            Padding = new Padding(0, 4, 8, 0),
            Margin = new Padding(0)
        };
        foreach (var b in new[] { _badgeAdded, _badgeRemoved, _badgeChanged, _badgeIdentical, _badgeIgnored })
        {
            b.Margin = new Padding(0, 0, 6, 0);
            badgeFlow.Controls.Add(b);
        }
        badgeStrip.Controls.Add(badgeFlow);

        _tabOverview = new TabPage("Overview") { BackColor = Color.White };
        BuildOverviewTab(_tabOverview);

        _tabDetails = new TabPage("Object Details") { BackColor = Color.White };
        BuildObjectDetailsTab(_tabDetails);

        _tabScript = new TabPage("Script Preview") { BackColor = Color.White };
        var scriptHost = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };
        var scriptBar = new Panel { Dock = DockStyle.Top, Height = 40, BackColor = Color.FromArgb(248, 250, 252) };
        _btnCopyScript.Location = new Point(10, 5);
        UiTheme.StyleSecondary(_btnCopyScript);
        scriptBar.Controls.Add(new Label
        {
            Text = "Self-contained auto/safe changes - run on the TARGET",
            AutoSize = true,
            ForeColor = UiTheme.TextMuted,
            Location = new Point(130, 12),
            BackColor = Color.Transparent
        });
        scriptBar.Controls.Add(_btnCopyScript);
        _txtScript.Dock = DockStyle.Fill;
        scriptHost.Controls.Add(_txtScript);
        scriptHost.Controls.Add(scriptBar);
        _tabScript.Controls.Add(scriptHost);

        _tabManual = new TabPage("Manual Actions") { BackColor = Color.White };
        var manualHost = new Panel { Dock = DockStyle.Fill };
        var manualBar = new Panel { Dock = DockStyle.Top, Height = 40, BackColor = Color.FromArgb(255, 247, 237) };
        manualBar.Controls.Add(new Label
        {
            Text = "Manual review required - including any DROP TABLE. Not auto-applied.",
            AutoSize = true,
            ForeColor = UiTheme.Warning,
            Font = UiTheme.SemiBold(9f),
            Location = new Point(12, 12),
            BackColor = Color.Transparent
        });
        _txtManual.Dock = DockStyle.Fill;
        manualHost.Controls.Add(_txtManual);
        manualHost.Controls.Add(manualBar);
        _tabManual.Controls.Add(manualHost);

        _tabDeploy = new TabPage("Deployment") { BackColor = Color.White };
        BuildDeployTab(_tabDeploy);

        _tabLog = new TabPage("Progress Log") { BackColor = Color.White };
        _tabLog.Controls.Add(_txtLog);
        _txtLog.Dock = DockStyle.Fill;

        _tabs.Dock = DockStyle.Fill;
        _tabs.Font = UiTheme.UiFont(9.5f);
        _tabs.TabPages.Add(_tabOverview);
        _tabs.TabPages.Add(_tabDetails);
        _tabs.TabPages.Add(_tabScript);
        _tabs.TabPages.Add(_tabManual);
        _tabs.TabPages.Add(_tabDeploy);
        _tabs.TabPages.Add(_tabLog);
        rightCard.Controls.Add(_tabs);
        rightCard.Controls.Add(badgeStrip);
        right.Controls.Add(rightCard);
        split.Panel2.Controls.Add(right);
    }

    private void BuildOverviewTab(TabPage tab)
    {
        // Empty state (mockup): illustration + call to action
        var emptyTable = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 5, BackColor = Color.White };
        emptyTable.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        emptyTable.RowStyles.Add(new RowStyle(SizeType.Percent, 40f));
        emptyTable.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        emptyTable.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        emptyTable.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        emptyTable.RowStyles.Add(new RowStyle(SizeType.Percent, 60f));
        var icon = new Label
        {
            Text = "\uE7C3",
            Font = UiTheme.IconFont(38f),
            ForeColor = Color.FromArgb(0xC9, 0xD4, 0xE3),
            AutoSize = true,
            Anchor = AnchorStyles.None,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 0, 0, 10)
        };
        var title = new Label
        {
            Text = "Run a comparison to see summary and results",
            Font = UiTheme.SemiBold(11f),
            ForeColor = UiTheme.TextPrimary,
            AutoSize = true,
            Anchor = AnchorStyles.None,
            BackColor = Color.Transparent
        };
        var sub = new Label
        {
            Text = "Click \"Compare Now\" to analyse differences between selected databases",
            Font = UiTheme.UiFont(9.5f),
            ForeColor = UiTheme.TextMuted,
            AutoSize = true,
            Anchor = AnchorStyles.None,
            BackColor = Color.Transparent,
            Margin = new Padding(0, 6, 0, 0)
        };
        emptyTable.Controls.Add(icon, 0, 1);
        emptyTable.Controls.Add(title, 0, 2);
        emptyTable.Controls.Add(sub, 0, 3);
        _overviewEmpty.Controls.Add(emptyTable);

        // Post-compare dashboard: summary cards + run summary
        var cardsFlow = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 76,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            BackColor = Color.White,
            Padding = new Padding(0, 8, 0, 8),
            Margin = new Padding(0)
        };
        foreach (var c in new[] { _cardAdded, _cardChanged, _cardExtra, _cardManual })
        {
            c.Width = 170;
            c.Height = 54;
            c.Margin = new Padding(0, 0, 12, 0);
            cardsFlow.Controls.Add(c);
        }
        _txtOverview.Dock = DockStyle.Fill;
        _overviewDash.Controls.Add(_txtOverview);
        _overviewDash.Controls.Add(cardsFlow);

        tab.Controls.Add(_overviewDash);
        tab.Controls.Add(_overviewEmpty);
    }

    private void BuildObjectDetailsTab(TabPage tab)
    {
        var root = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };

        _detailSingleHost.Controls.Add(_lblDetailPlaceholder);
        _detailSingleHost.Controls.Add(_txtDetails);
        _txtDetails.Dock = DockStyle.Fill;

        var header = new Panel
        {
            Dock = DockStyle.Top,
            Height = 36,
            BackColor = Color.FromArgb(248, 250, 252),
            Padding = new Padding(12, 0, 12, 0)
        };
        header.Controls.Add(_lblDetailHeader);

        _detailSplit = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Vertical,
            SplitterWidth = 6,
            BackColor = Color.FromArgb(0xE5, 0xE7, 0xEB)
        };

        Panel BuildSide(Label caption, TextBox body, Color barColor)
        {
            var host = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };
            var bar = new Panel { Dock = DockStyle.Top, Height = 32, BackColor = barColor, Padding = new Padding(10, 0, 10, 0) };
            bar.Controls.Add(caption);
            host.Controls.Add(body);
            host.Controls.Add(bar);
            return host;
        }

        _detailSplit.Panel1.Controls.Add(BuildSide(_lblSourceCaption, _txtSourceDef, Color.FromArgb(0xEC, 0xF5, 0xFF)));
        _detailSplit.Panel2.Controls.Add(BuildSide(_lblTargetCaption, _txtTargetDef, Color.FromArgb(0xFE, 0xF3, 0xC7)));

        _detailDualHost.Controls.Add(_detailSplit);
        _detailDualHost.Controls.Add(header);

        root.Controls.Add(_detailDualHost);
        root.Controls.Add(_detailSingleHost);
        tab.Controls.Add(root);

        tab.Enter += (_, _) =>
        {
            try
            {
                if (_detailSplit != null && _detailSplit.Width > 200)
                    _detailSplit.SplitterDistance = Math.Max(120, _detailSplit.Width / 2);
            }
            catch { /* layout not ready */ }
        };

        ShowDetailSingleMode();
    }

    private void ShowDetailSingleMode()
    {
        _detailDualHost.Visible = false;
        _detailSingleHost.Visible = true;
        _detailSingleHost.BringToFront();
    }

    private void ShowDetailDualMode()
    {
        _detailSingleHost.Visible = false;
        _detailDualHost.Visible = true;
        _detailDualHost.BringToFront();
        try
        {
            if (_detailSplit != null && _detailSplit.Width > 200 && _detailSplit.SplitterDistance < 80)
                _detailSplit.SplitterDistance = Math.Max(120, _detailSplit.Width / 2);
        }
        catch { /* ignore */ }
    }

    private void ShowSingleDetailText(string text, bool showPlaceholder = false)
    {
        ShowDetailSingleMode();
        _txtDetails.Text = text;
        _lblDetailPlaceholder.Visible = showPlaceholder;
        if (!showPlaceholder)
            _txtDetails.BringToFront();
        else
            _lblDetailPlaceholder.BringToFront();
    }

    private void BuildDeployTab(TabPage tab)
    {
        var host = new Panel { Dock = DockStyle.Fill, BackColor = Color.White };

        var banner = new Panel { Dock = DockStyle.Top, Height = 40, BackColor = Color.FromArgb(248, 250, 252), Padding = new Padding(12, 0, 12, 0) };
        _lblDeployBanner.ForeColor = UiTheme.TextMuted;
        banner.Controls.Add(_lblDeployBanner);

        var split = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Horizontal,
            FixedPanel = FixedPanel.Panel2,
            SplitterWidth = 6
        };

        _gridDeploy.Columns.Clear();
        _gridDeploy.Columns.Add(new DataGridViewTextBoxColumn { Name = "colDb", HeaderText = "Target database", FillWeight = 24 });
        _gridDeploy.Columns.Add(new DataGridViewTextBoxColumn { Name = "colApplied", HeaderText = "Applied / Auto", FillWeight = 14 });
        _gridDeploy.Columns.Add(new DataGridViewTextBoxColumn { Name = "colStatus", HeaderText = "Status", FillWeight = 16 });
        _gridDeploy.Columns.Add(new DataGridViewTextBoxColumn { Name = "colFailed", HeaderText = "Failed", FillWeight = 10 });
        _gridDeploy.Columns.Add(new DataGridViewTextBoxColumn { Name = "colVerify", HeaderText = "Verification", FillWeight = 36 });
        _gridDeploy.EnableHeadersVisualStyles = false;
        _gridDeploy.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(0x24, 0x29, 0x2F);
        _gridDeploy.ColumnHeadersDefaultCellStyle.ForeColor = Color.White;
        _gridDeploy.ColumnHeadersDefaultCellStyle.Font = UiTheme.SemiBold(9f);
        _gridDeploy.DefaultCellStyle.Font = UiTheme.UiFont(9f);
        _gridDeploy.SelectionChanged += (_, _) => ShowDeployRowDetail();

        split.Panel1.Controls.Add(_gridDeploy);
        _txtDeployDetail.Dock = DockStyle.Fill;
        _txtDeployDetail.Text = "Select a database row to see failed scripts and verification details.";
        split.Panel2.Controls.Add(_txtDeployDetail);

        host.Controls.Add(split);
        host.Controls.Add(banner);
        tab.Controls.Add(host);

        tab.Enter += (_, _) =>
        {
            try { if (split.Height > 120) split.SplitterDistance = Math.Max(80, split.Height - 110); }
            catch { /* layout not ready */ }
        };
    }

    private void ShowDeployRowDetail()
    {
        if (_gridDeploy.SelectedRows.Count == 0 || _lastResult == null) return;
        var db = _gridDeploy.SelectedRows[0].Cells["colDb"].Value?.ToString() ?? "";
        var s = _lastResult.Summaries.FirstOrDefault(x =>
            string.Equals(x.TargetDatabase, db, StringComparison.OrdinalIgnoreCase));
        if (s == null) { _txtDeployDetail.Text = ""; return; }

        var sb = new StringBuilder();
        sb.AppendLine($"Target database : {s.TargetDatabase}");
        sb.AppendLine($"Apply status    : {s.ApplyStatus}  ({s.AppliedCount} applied, {s.FailedCount} failed of {s.AutoScripts} auto script(s))");
        sb.AppendLine($"Verification    : {DescribeVerify(s)}");
        if (s.ManualScripts > 0)
            sb.AppendLine($"Manual scripts  : {s.ManualScripts} (never auto-applied - see Manual Actions tab)");
        if (s.FailedCount > 0)
        {
            sb.AppendLine();
            sb.AppendLine("Failed scripts:");
            foreach (var f in s.FailedScripts)
                sb.AppendLine($"  {f.FileName}\r\n    {f.Error}");
        }
        _txtDeployDetail.Text = sb.ToString();
    }

    private static string DescribeVerify(CompareSummary s) => s.VerifyStatus switch
    {
        "Synced" => "Synced - re-compare found no remaining differences",
        "Diffs" => $"{s.RemainingDiffs} difference(s) remain (pending manual scripts or failed applies)",
        "VerifyError" => "Verification re-compare failed - see Progress Log",
        _ => "Not verified"
    };

    /// <summary>Populates the Deployment tab after a run where Apply executed.</summary>
    private void UpdateDeploymentTab(CompareResult? result)
    {
        if (_tabDeploy == null) return;
        _gridDeploy.Rows.Clear();

        if (result == null || !result.AppliedRun)
        {
            _tabDeploy.Text = "Deployment";
            _lblDeployBanner.Text = "Run a compare with Apply enabled to see deployment status.";
            _lblDeployBanner.ForeColor = UiTheme.TextMuted;
            _txtDeployDetail.Text = "Select a database row to see failed scripts and verification details.";
            return;
        }

        var failedDbs = 0;
        var unsyncedDbs = 0;
        foreach (var s in result.Summaries)
        {
            var row = _gridDeploy.Rows[_gridDeploy.Rows.Add(
                s.TargetDatabase,
                $"{s.AppliedCount} / {s.AutoScripts}",
                s.ApplyStatus,
                s.FailedCount,
                DescribeVerify(s))];

            if (s.FailedCount > 0 || s.ApplyStatus == "Failed")
            {
                row.DefaultCellStyle.BackColor = Color.FromArgb(255, 235, 238);
                row.DefaultCellStyle.ForeColor = UiTheme.Danger;
                failedDbs++;
            }
            else if (s.VerifyStatus == "Diffs" || s.VerifyStatus == "VerifyError")
            {
                row.DefaultCellStyle.BackColor = Color.FromArgb(255, 247, 237);
                unsyncedDbs++;
            }
            else if (s.VerifyStatus == "Synced")
            {
                row.DefaultCellStyle.ForeColor = UiTheme.Success;
            }
        }

        var attention = failedDbs + unsyncedDbs;
        _tabDeploy.Text = attention > 0 ? $"\u26A0 Deployment ({attention})" : "Deployment";
        if (failedDbs > 0)
        {
            _lblDeployBanner.Text = $"{failedDbs} database(s) had script failures - review details below and re-run after fixing.";
            _lblDeployBanner.ForeColor = UiTheme.Danger;
        }
        else if (unsyncedDbs > 0)
        {
            _lblDeployBanner.Text = $"Auto scripts applied. {unsyncedDbs} database(s) still have differences (pending manual scripts).";
            _lblDeployBanner.ForeColor = UiTheme.Warning;
        }
        else
        {
            _lblDeployBanner.Text = "All auto scripts applied and every database verified in sync with the source.";
            _lblDeployBanner.ForeColor = UiTheme.Success;
        }
    }

    private void BuildStatusBar()
    {
        _status.Dock = DockStyle.Bottom;
        _status.Items.Add(_statusText);
        _status.Items.Add(_statusSource);
        _status.Items.Add(_statusTarget);
        _status.Items.Add(_statusObjects);
        _status.Items.Add(_statusTime);
    }

    private void ShowOptionsDialog(OptionsFocus focus = OptionsFocus.Settings)
    {
        using var dlg = new OptionsForm(_options, focus);
        if (dlg.ShowDialog(this) == DialogResult.OK)
            _options = dlg.Options;
    }

    /// <summary>Swaps the source and target connections (mockup swap control).</summary>
    internal void SwapConnections()
    {
        var src = _sourcePanel.GetConnectionInfo();
        var tgt = _targetPanel.GetConnectionInfo();
        _sourcePanel.Apply(tgt);
        _sourcePanel.SetPassword(tgt.Password);
        _targetPanel.Apply(src);
        _targetPanel.SetPassword(src.Password);
        _sourceBrowseDb = "";
        _targetBrowseDb = "";
        _sourceObjects = Array.Empty<SchemaObjectInfo>();
        _targetObjects = Array.Empty<SchemaObjectInfo>();
        UpdateHeaderProject();
        if (_lastResult == null)
            RebuildTree(_txtFilter.Text);
        SetStatus("Source and target swapped.");
    }

    /// <summary>Auto-collapses the connection card so results get the workspace.</summary>
    internal void CollapseConnectionCardForCompare() => _connCard.Collapsed = true;

    // ----- Test seams (internal; exercised by unit tests) -----
    internal TabControl Tabs => _tabs;
    internal IReadOnlyList<StatusBadge> Badges =>
        new[] { _badgeAdded, _badgeRemoved, _badgeChanged, _badgeIdentical, _badgeIgnored };
    internal CollapsibleCard ConnectionCard => _connCard;
    internal NavRail Rail => _navRail;
    internal ModernButton CompareHeaderButton => _btnCompare;
    internal ModernButton CompareNowButton => _btnCompareNow;
    internal ModernButton SaveScriptButton => _btnSaveDeploy;
    internal ModernButton PresetsButton => _btnPresets;
    internal ConnectionPanel SourcePanelForTest => _sourcePanel;
    internal ConnectionPanel TargetPanelForTest => _targetPanel;
    internal TextBox ExplorerSearchBox => _txtFilter;
    internal string StatusTextForTest => _statusText.Text ?? "";
    internal string StatusSourceForTest => _statusSource.Text ?? "";
    internal string StatusTargetForTest => _statusTarget.Text ?? "";
    internal string StatusObjectsForTest => _statusObjects.Text ?? "";

    /// <summary>
    /// Applies min sizes and SplitterDistance only when the split has a usable Width.
    /// Safe to call from constructor, Shown, and Resize — never throws on init.
    /// </summary>
    private void ApplyMainSplitterDistance(int preferredDistance = 280)
    {
        if (_mainSplit == null || _mainSplit.IsDisposed) return;
        var split = _mainSplit;
        const int panel1Min = 160;
        const int panel2Min = 200;
        try
        {
            var minWidth = panel1Min + panel2Min + split.SplitterWidth;
            if (split.Width < minWidth) return;

            // Set mins only once Width can satisfy them (setting earlier throws).
            if (split.Panel1MinSize != panel1Min) split.Panel1MinSize = panel1Min;
            if (split.Panel2MinSize != panel2Min) split.Panel2MinSize = panel2Min;

            // Keep splitter user-draggable
            split.IsSplitterFixed = false;
            split.FixedPanel = FixedPanel.None;

            var maxDist = split.Width - split.SplitterWidth - split.Panel2MinSize;
            if (maxDist < split.Panel1MinSize) return;

            split.SplitterDistance = Math.Clamp(preferredDistance, split.Panel1MinSize, maxDist);
        }
        catch
        {
            /* ignore until control is fully laid out */
        }
    }

    private void BuildImageList()
    {
        AddGlyph("root", UiTheme.Primary);
        AddGlyph("type", Color.FromArgb(100, 116, 139));
        AddGlyph("table", Color.FromArgb(37, 99, 235));
        AddGlyph("view", Color.FromArgb(8, 145, 178));
        AddGlyph("proc", Color.FromArgb(124, 58, 237));
        AddGlyph("func", Color.FromArgb(217, 119, 6));
        AddGlyph("trig", Color.FromArgb(225, 29, 72));
        AddGlyph("index", Color.FromArgb(22, 163, 74));
        AddGlyph("column", Color.FromArgb(14, 165, 233));
        AddGlyph("key", Color.FromArgb(234, 179, 8));
        AddGlyph("constraint", Color.FromArgb(168, 85, 247));
        AddGlyph("folder", Color.FromArgb(100, 116, 139));
        AddGlyph("add", UiTheme.AddAccent);
        AddGlyph("upd", UiTheme.ChangeAccent);
        AddGlyph("extra", UiTheme.ExtraAccent);
        AddGlyph("other", Color.Gray);
    }

    private void AddGlyph(string key, Color color)
    {
        var bmp = MakeGlyph(color, key);
        _ownedBitmaps.Add(bmp);
        _treeImages.Images.Add(key, bmp);
    }

    private static Bitmap MakeGlyph(Color color, string key)
    {
        var bmp = new Bitmap(16, 16);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.Clear(Color.Transparent);
        using var b = new SolidBrush(color);
        if (key is "add" or "upd" or "extra")
            g.FillEllipse(b, 2, 2, 12, 12);
        else
            g.FillRectangle(b, 2, 2, 12, 12);
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
        _sourcePanel.DatabaseSelectionChanged += (_, _) => SafeUi(() => _ = LoadBrowseObjectsAsync(true));
        _targetPanel.DatabaseSelectionChanged += (_, _) => SafeUi(() => _ = LoadBrowseObjectsAsync(false));

        _btnOptions.Click += (_, _) => SafeUi(() => ShowOptionsDialog(OptionsFocus.Settings));
        _btnAdvanced.Click += (_, _) => SafeUi(() => ShowOptionsDialog(OptionsFocus.Advanced));
        _btnSwap.Click += (_, _) => SafeUi(SwapConnections);
        _btnPresets.Click += (_, _) => SafeUi(() =>
            _presetsMenu.Show(_btnPresets, new Point(0, _btnPresets.Height)));
        _btnHelp.Click += (_, _) => SafeUi(() => MessageBox.Show(this,
            "Workflow\r\n\r\n" +
            "1. Connect - enter Source and Target, Test Connection, pick databases.\r\n" +
            "2. Compare - click Compare Now (or Compare Schemas).\r\n" +
            "3. Review - browse differences in the Object Explorer and result tabs.\r\n" +
            "4. Deploy - Save Script and run it on the TARGET server.\r\n\r\n" +
            "Navigation\r\n\r\n" +
            "History - opens the shared output folder (SchemaSync_* compare runs).\r\n" +
            "Scripts - shows Script Preview in the app, or the same output folder.\r\n" +
            "Reports - opens the latest HTML report from that same output root.\r\n" +
            "Settings - connection defaults (protocol / timeout / TLS).\r\n\r\n" +
            "Options entry points\r\n\r\n" +
            "Configure ignore rules - schemas to skip during compare.\r\n" +
            "Advanced Options / Profile pencil - script generation and apply behaviour.\r\n" +
            "Settings (gear / rail) - connection defaults; all tabs remain available.\r\n\r\n" +
            "All generated SQL scripts and reports use one output root:\r\n" +
            "  schema_compare\\output\\  (or the folder set under Output).",
            "Help", MessageBoxButtons.OK, MessageBoxIcon.Information));
        _btnExplorerRefresh.Click += (_, _) => SafeUi(() =>
        {
            _sourceBrowseDb = "";
            _targetBrowseDb = "";
            _ = LoadBrowseObjectsAsync(true);
            _ = LoadBrowseObjectsAsync(false);
        });
        _navRail.ItemClicked += (_, key) => SafeUi(() => OnRailItemClicked(key));

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
        _btnCompareNow.Click += async (_, _) => await RunCompareAsync();
        _btnSaveDeploy.Click += (_, _) => SafeUi(SaveDeployScript);
        _btnCopyScript.Click += (_, _) => SafeUi(() =>
        {
            if (string.IsNullOrWhiteSpace(_txtScript.Text)) return;
            Clipboard.SetText(_txtScript.Text);
            SetStatus("Deployable script copied to clipboard.");
        });

        _txtFilter.TextChanged += (_, _) => SafeUi(() => RebuildTree(_txtFilter.Text.Trim()));
        _tree.BeforeExpand += (_, e) =>
        {
            if (_lastResult != null) return;
            SafeUi(() => _ = LoadTableFolderChildrenAsync(e.Node));
        };
        _tree.AfterSelect += (_, e) => SafeUi(() =>
        {
            if (e.Node?.Tag is TableChildItem child)
            {
                ShowSingleDetailText(string.IsNullOrWhiteSpace(child.DetailText)
                    ? child.DisplayText
                    : child.DetailText);
                _tabs.SelectedTab = _tabDetails;
                return;
            }

            if (e.Node?.Tag is TableFolderNode folder)
            {
                ShowSingleDetailText(
                    $"Folder\r\n  {ObjectExplorerFormat.FolderLabel(folder.Kind)}\r\n\r\n" +
                    $"Table\r\n  {folder.Table.FullName}\r\n\r\n" +
                    $"Database\r\n  {folder.Table.Side.Database}\r\n\r\n" +
                    "Tip\r\n  Expand to load children from system catalogs.");
                _tabs.SelectedTab = _tabDetails;
                return;
            }

            if (e.Node?.Tag is TableBrowseNode tableNode)
            {
                ShowSingleDetailText(
                    $"Table\r\n  {tableNode.FullName}\r\n\r\n" +
                    $"Database\r\n  {tableNode.Side.Database}\r\n\r\n" +
                    $"Side\r\n  {(tableNode.Side.IsSource ? "Source" : "Target")}\r\n\r\n" +
                    "Scripting CREATE TABLE from system catalogs...");
                _tabs.SelectedTab = _tabDetails;
                _ = ScriptTableAsync(tableNode);
                return;
            }

            if (e.Node?.Tag is SchemaObjectInfo obj)
            {
                ShowSingleDetailText(
                    $"Object\r\n  {obj.FullName}\r\n\r\n" +
                    $"Type\r\n  {obj.ObjectType}\r\n\r\n" +
                    $"Schema\r\n  {obj.SchemaName}\r\n\r\n" +
                    $"Name\r\n  {obj.ObjectName}\r\n\r\n" +
                    "Tip\r\n  Run Compare schemas to see differences vs the other side.");
                _tabs.SelectedTab = _tabDetails;
                return;
            }

            if (e.Node?.Tag is not DifferenceItem d) return;
            _tabs.SelectedTab = _tabDetails;
            _steps.Active = WorkflowStep.Review;
            _ = ShowDifferenceCompareAsync(d);
        });

        FormClosing += OnFormClosing;
        Shown += (_, _) => SafeUi(() => ApplyMainSplitterDistance(300));
        Resize += (_, _) => SafeUi(() => ApplyMainSplitterDistance(_mainSplit?.SplitterDistance ?? 300));
    }

    private void OnRailItemClicked(string key)
    {
        switch (key)
        {
            case "history":
                OpenHistory();
                break;
            case "scripts":
                OpenScripts();
                break;
            case "reports":
                OpenReports();
                break;
            case "settings":
                ShowOptionsDialog(OptionsFocus.Settings);
                break;
            case "compare":
            default:
                break;
        }
    }

    /// <summary>
    /// Single root for generated scripts, HTML reports, and SchemaSync run folders.
    /// Always under the bundled engine unless the user overrides it in Options.
    /// </summary>
    internal string EnsureOutputRoot()
    {
        var root = _options.OutputPath;
        if (string.IsNullOrWhiteSpace(root))
            root = Path.Combine(_engine.SchemaCompareRoot, "output");
        try { Directory.CreateDirectory(root); } catch { /* best effort */ }
        _options.OutputPath = root;
        return root;
    }

    /// <summary>History = past SchemaSync_* compare runs under the shared output root.</summary>
    private void OpenHistory()
    {
        var root = EnsureOutputRoot();
        var latest = FindLatestRunFolder(root);
        var open = latest ?? root;
        SetStatus($"History — {open}");
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{open}\"") { UseShellExecute = true });
    }

    /// <summary>
    /// Scripts = show the in-app Script Preview when available; otherwise open the
    /// shared output root (same folder Save Script / compare writes to).
    /// </summary>
    private void OpenScripts()
    {
        var root = EnsureOutputRoot();
        if (_tabScript != null && !string.IsNullOrWhiteSpace(_txtScript.Text) &&
            !_txtScript.Text.StartsWith("-- No", StringComparison.Ordinal))
        {
            _tabs.SelectedTab = _tabScript;
            SetStatus($"Scripts — preview (saved under {root})");
            return;
        }

        SetStatus($"Scripts — {root}");
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{root}\"") { UseShellExecute = true });
    }

    /// <summary>Reports = open the latest HTML report under the shared output root.</summary>
    private void OpenReports()
    {
        var root = EnsureOutputRoot();
        var report = _lastResult?.ReportPath;
        if (string.IsNullOrWhiteSpace(report) || !File.Exists(report))
            report = FindLatestHtmlReport(root);

        if (!string.IsNullOrWhiteSpace(report) && File.Exists(report))
        {
            SetStatus($"Reports — {Path.GetFileName(report)}");
            Process.Start(new ProcessStartInfo(report) { UseShellExecute = true });
            return;
        }

        MessageBox.Show(this,
            "No HTML report found yet.\r\n\r\nRun a comparison first — reports are written to:\r\n" + root,
            "Reports", MessageBoxButtons.OK, MessageBoxIcon.Information);
        SetStatus($"Reports — none in {root}");
    }

    private static string? FindLatestRunFolder(string outputRoot)
    {
        if (!Directory.Exists(outputRoot)) return null;
        return Directory.EnumerateDirectories(outputRoot, "SchemaSync_*")
            .OrderByDescending(d => d, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private static string? FindLatestHtmlReport(string outputRoot)
    {
        if (!Directory.Exists(outputRoot)) return null;
        return Directory.EnumerateFiles(outputRoot, "SchemaCompare_*.html", SearchOption.AllDirectories)
            .OrderByDescending(f => f, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private void OpenOutputFolder()
    {
        var root = EnsureOutputRoot();
        var dir = _lastResult?.RunFolder;
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
            dir = root;
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true });
        SetStatus($"Output — {dir}");
    }

    private void OpenHtmlReport() => OpenReports();

    private static void StyleModeRadio(RadioButton rb)
    {
        rb.AutoSize = true;
        rb.FlatStyle = FlatStyle.System;
        rb.ForeColor = UiTheme.TextPrimary;
        rb.Font = UiTheme.SemiBold(10f);
        rb.BackColor = Color.Transparent;
        rb.UseCompatibleTextRendering = true;
        rb.MinimumSize = new Size(TextRenderer.MeasureText(rb.Text, rb.Font).Width + 28, 22);
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
            try { _browseCts?.Cancel(); } catch { /* ignore */ }
            try { _browseCts?.Dispose(); } catch { /* ignore */ }
            _browseCts = null;
            try { _scriptCts?.Cancel(); } catch { /* ignore */ }
            try { _scriptCts?.Dispose(); } catch { /* ignore */ }
            _scriptCts = null;
            _browseScriptSnapshot = null;
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
                    _txtSourceDef.Clear();
                    _txtTargetDef.Clear();
                    _lblDetailHeader.Text = "";
                    ShowDetailSingleMode();
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

    private void UpdateModeUi()
    {
        var many = _rbOneToMany.Checked;

        SuspendLayout();
        _connCard.SuspendLayout();
        try
        {
            _txtListFile.Enabled = many;
            _btnBrowseList.Enabled = many;
            if (_listFileHost != null)
                _listFileHost.Visible = many;

            _targetPanel.SetMultiSelectVisible(many);
            // Keep ExpandedHeight stable — height jumps caused the flicker/spacing.
            SyncConnCardHeight();
        }
        finally
        {
            _connCard.ResumeLayout(true);
            ResumeLayout(true);
        }

        SetStatus(many
            ? "One-to-Many: pick one source DB, then check multiple destination DBs (or use a list file)."
            : "One-to-One: select one source database and one destination database.");
        UpdateHeaderProject();
        if (_lastResult == null)
            RebuildTree(_txtFilter.Text);
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
        _btnCompareNow.Enabled = !busy;
        _btnOptions.Enabled = !busy;
        _btnSaveDeploy.Enabled = !busy && (_deployResult?.HasAuto == true || _deployResult?.HasManual == true);
        if (_summaryStrip != null)
            _summaryStrip.Visible = busy;
        if (busy)
        {
            _progress.Style = ProgressBarStyle.Marquee;
            _progress.MarqueeAnimationSpeed = 30;
        }
        else
        {
            _progress.Style = ProgressBarStyle.Continuous;
            _progress.MarqueeAnimationSpeed = 0;
            _progress.Value = 0;
            if (_compareStarted is DateTime started)
            {
                var elapsed = DateTime.Now - started;
                _lblElapsed.Text = $"Elapsed  {elapsed:mm\\:ss}";
                _statusTime.Text = $"Elapsed: {elapsed.TotalSeconds:0}s";
            }
        }
    }

    private void AppendLogUi(string line)
    {
        if (IsDisposed || !IsHandleCreated) return;
        void Write()
        {
            // Structured deploy progress from the engine (##GUI:...) drives the
            // progress bar / stage label and is kept out of the raw log text.
            if (DeployProgressParser.TryParse(line, out var p))
            {
                HandleDeployProgress(p);
                return;
            }

            _logBuffer.AppendLine(line);
            if (_txtLog.TextLength > CompareEngine.MaxLogChars)
                _txtLog.Text = _logBuffer.Snapshot();
            else
                _txtLog.AppendText(line + Environment.NewLine);

            if (_compareStarted is DateTime started)
                _lblElapsed.Text = $"Elapsed  {(DateTime.Now - started):mm\\:ss}";

            // Structured progress owns the stage label once a run is underway.
            if (_deployDbTotal > 0) return;

            // Surface stage hints from PowerShell log lines
            var lower = line.ToLowerInvariant();
            if (lower.Contains("connecting") || lower.Contains("connect"))
                _lblProgressStage.Text = "Connecting...";
            else if (lower.Contains("comparing"))
                _lblProgressStage.Text = "Comparing objects...";
            else if (lower.Contains("script") || lower.Contains("writing"))
                _lblProgressStage.Text = "Generating scripts...";
            else if (lower.Contains("report"))
                _lblProgressStage.Text = "Building report...";
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

    /// <summary>Applies a structured engine progress event to the progress UI.</summary>
    private void HandleDeployProgress(DeployProgressUpdate p)
    {
        switch (p.Kind)
        {
            case "DB":
                _deployDbIndex = p.Index;
                _deployDbTotal = p.Total;
                SetDeterminateProgress(DeployProgressParser.ComputePercent(p.Index, p.Total, "compare", 0, 0));
                _lblProgressStage.Text = _deployDbTotal > 1
                    ? $"Database {p.Index}/{p.Total}: {p.Database}"
                    : $"Processing {p.Database}...";
                _lblProgressStage.ForeColor = UiTheme.Primary;
                break;

            case "PHASE":
                SetDeterminateProgress(DeployProgressParser.ComputePercent(
                    _deployDbIndex, _deployDbTotal, p.Stage, p.Index, p.Total));
                _lblProgressStage.Text = p.Stage switch
                {
                    "apply" => $"Applying {p.Database} ({p.Index}/{p.Total})...",
                    "verify" => $"Verifying {p.Database}...",
                    _ => _deployDbTotal > 1
                        ? $"Comparing {p.Database} ({_deployDbIndex}/{_deployDbTotal})..."
                        : $"Comparing {p.Database}..."
                };
                _lblProgressStage.ForeColor = UiTheme.Primary;
                break;

            case "APPLYRESULT":
                if (p.Failed > 0)
                {
                    _lblProgressStage.Text = $"{p.Database}: {p.Applied} applied, {p.Failed} FAILED";
                    _lblProgressStage.ForeColor = UiTheme.Danger;
                }
                else
                {
                    _lblProgressStage.Text = $"{p.Database}: {p.Applied} script(s) applied";
                    _lblProgressStage.ForeColor = UiTheme.Success;
                }
                break;

            case "VERIFY":
                _lblProgressStage.Text = p.Status switch
                {
                    "Synced" => $"{p.Database}: verified in sync",
                    "Diffs" => $"{p.Database}: {p.Remaining} difference(s) remain",
                    _ => $"{p.Database}: verification failed"
                };
                _lblProgressStage.ForeColor = p.Status == "Synced" ? UiTheme.Success : UiTheme.Warning;
                break;
        }
    }

    /// <summary>Switches the progress bar out of marquee and sets a percent value.</summary>
    private void SetDeterminateProgress(int percent)
    {
        if (_progress.Style != ProgressBarStyle.Continuous)
        {
            _progress.Style = ProgressBarStyle.Continuous;
            _progress.MarqueeAnimationSpeed = 0;
        }
        _progress.Value = Math.Max(0, Math.Min(100, percent));
    }

    private void UpdateManualTabCaption()
    {
        if (_tabManual == null) return;
        var count = _deployResult?.ManualFileCount ?? 0;
        _tabManual.Text = count > 0 ? $"\u26A0 Manual Actions ({count})" : "Manual Actions";
    }

    /// <summary>
    /// Exports a single self-contained, deployable .sql for the auto/safe changes,
    /// and (when present) a separate manual .sql the operator must run by hand.
    /// Always defaults to the same shared output root used by compare / History / Scripts.
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
        var outputRoot = EnsureOutputRoot();
        using var dlg = new SaveFileDialog
        {
            Title = "Save deployable SQL script",
            Filter = "SQL script (*.sql)|*.sql|All files|*.*",
            FileName = $"Deploy_AutoChanges_{stamp}.sql",
            OverwritePrompt = true,
            // Same root directory as compare output / History / Scripts / Reports.
            InitialDirectory = outputRoot
        };

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
        _steps.Active = WorkflowStep.Deploy;
        _lblProgressStage.Text = "Deploy script saved — run on the TARGET server";
        _lblProgressStage.ForeColor = UiTheme.Success;
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
        linked.CancelAfter(TimeSpan.FromSeconds(60));
        try
        {
            SetBusy(true);
            var info = source ? _sourcePanel.GetConnectionInfo(false) : _targetPanel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Testing {(source ? "source" : "target")} connection...");
            await SqlConnectionService.TestAsync(info, linked.Token).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed) return;

            SetStatus($"Loading {(source ? "source" : "target")} databases...");
            var dbs = await SqlConnectionService.ListUserDatabasesAsync(info, linked.Token).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed) return;
            if (source)
            {
                _sourceBrowseDb = "";
                _sourceObjects = Array.Empty<SchemaObjectInfo>();
                _sourcePanel.SetDatabases(dbs);
                _sourcePanel.SetConnectionStatus(true, $"{dbs.Count} databases");
            }
            else
            {
                _targetBrowseDb = "";
                _targetObjects = Array.Empty<SchemaObjectInfo>();
                _targetPanel.SetDatabases(dbs);
                _targetPanel.SetConnectionStatus(true, $"{dbs.Count} databases");
            }

            _steps.Active = WorkflowStep.Connect;
            UpdateHeaderProject();
            SetStatus($"Connected — select a database ({dbs.Count} available).");
            _lblProgressStage.Text = "Select a database";
        }
        catch (OperationCanceledException)
        {
            SetStatus("Connection test cancelled.");
        }
        catch (Exception ex)
        {
            if (source) _sourcePanel.SetConnectionStatus(false, "Failed");
            else _targetPanel.SetConnectionStatus(false, "Failed");
            UpdateHeaderProject();
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
            _lblProgressStage.Text = "Reading databases...";
            var dbs = await SqlConnectionService.ListUserDatabasesAsync(info, linked.Token).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed) return;
            if (source)
            {
                _sourceBrowseDb = "";
                _sourceObjects = Array.Empty<SchemaObjectInfo>();
                _sourcePanel.SetDatabases(dbs);
                _sourcePanel.SetConnectionStatus(true, $"{dbs.Count} databases");
            }
            else
            {
                _targetBrowseDb = "";
                _targetObjects = Array.Empty<SchemaObjectInfo>();
                _targetPanel.SetDatabases(dbs);
                _targetPanel.SetConnectionStatus(true, $"{dbs.Count} databases");
            }
            _steps.Active = WorkflowStep.Connect;
            SetStatus($"Loaded {dbs.Count} database(s). Select a database to browse objects.");
            _lblProgressStage.Text = "Select a database";
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

    private async Task LoadBrowseObjectsAsync(bool source)
    {
        if (_isShuttingDown || IsDisposed) return;

        var panel = source ? _sourcePanel : _targetPanel;
        var db = panel.SelectedDatabase;
        if (string.IsNullOrWhiteSpace(db))
        {
            if (source)
            {
                _sourceObjects = Array.Empty<SchemaObjectInfo>();
                _sourceBrowseDb = "";
            }
            else
            {
                _targetObjects = Array.Empty<SchemaObjectInfo>();
                _targetBrowseDb = "";
            }
            if (_lastResult == null)
                RebuildTree(_txtFilter.Text);
            UpdateHeaderProject();
            return;
        }

        if (source && string.Equals(_sourceBrowseDb, db, StringComparison.OrdinalIgnoreCase) && _sourceObjects.Count > 0)
            return;
        if (!source && string.Equals(_targetBrowseDb, db, StringComparison.OrdinalIgnoreCase) && _targetObjects.Count > 0)
            return;

        _browseCts?.Cancel();
        _browseCts?.Dispose();
        _browseCts = new CancellationTokenSource();
        var ct = _browseCts.Token;

        try
        {
            var info = panel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Loading objects from {(source ? "source" : "target")}  ·  {db}...");
            _lblProgressStage.Text = $"Reading {db}...";

            var objects = await SqlConnectionService.ListSchemaObjectsAsync(info, db, ct).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed || ct.IsCancellationRequested) return;

            if (source)
            {
                _sourceObjects = objects;
                _sourceBrowseDb = db;
            }
            else
            {
                _targetObjects = objects;
                _targetBrowseDb = db;
            }

            panel.SetConnectionStatus(true, db);
            UpdateHeaderProject();

            if (_lastResult == null)
                RebuildTree(_txtFilter.Text);

            SetStatus($"Loaded {objects.Count} object(s) from {db}.");
            _lblProgressStage.Text = "Ready to compare";
            _steps.Active = WorkflowStep.Connect;
        }
        catch (OperationCanceledException)
        {
            // newer selection cancelled this load
        }
        catch (Exception ex)
        {
            if (!_isShuttingDown && !IsDisposed)
            {
                SetStatus($"Could not list objects: {ex.Message}");
                _lblProgressStage.Text = "Object list failed";
            }
        }
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
                var deployTargets = targets.Count > 0 ? targets : new List<string> { target.Database };
                var targetList = string.Join("\r\n", deployTargets.Select(t => $"    \u2022 {t}"));
                var confirm = MessageBox.Show(this,
                    "APPLY is enabled.\r\n\r\n" +
                    $"Auto_ scripts will be executed on {deployTargets.Count} target database(s) on [{target.Instance}]:\r\n\r\n" +
                    targetList + "\r\n\r\n" +
                    "A failing database will NOT stop the others; each result is shown in the\r\n" +
                    "Deployment tab, and every database is re-compared afterwards to verify sync.\r\n" +
                    "manual_ scripts (including any DROP TABLE) are never auto-applied.\r\n\r\nContinue?",
                    "Confirm Apply", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                if (confirm != DialogResult.Yes) return;
            }

            _cts?.Dispose();
            _cts = new CancellationTokenSource();
            _compareStarted = DateTime.Now;
            // Mockup behaviour: reclaim workspace once the comparison starts.
            CollapseConnectionCardForCompare();
            _steps.Active = WorkflowStep.Compare;
            _lblProgressStage.Text = "Comparing schemas...";
            _lblProgressStage.ForeColor = UiTheme.Primary;
            _lblElapsed.Text = "Elapsed  00:00";
            _deployDbIndex = 0;
            _deployDbTotal = 0;
            UpdateDeploymentTab(null);
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
            UpdateOverviewDashboard(result.Success ? result : null);
            UpdateDeploymentTab(result.Success ? result : null);

            if (!result.Success)
            {
                _steps.Active = WorkflowStep.Compare;
                _lblProgressStage.Text = "Compare failed";
                _lblProgressStage.ForeColor = UiTheme.Danger;
                MessageBox.Show(this, result.Error ?? "Compare failed. See Progress log.",
                    "Compare failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                SetStatus("Compare failed.");
            }
            else if (result.AppliedRun)
            {
                // Apply ran: report per-DB deployment + verification outcome.
                var deployed = result.Summaries.Count(s => s.Applied || s.ApplyStatus == "NothingToApply");
                var failedDbs = result.Summaries.Count(s => s.FailedCount > 0 || s.ApplyStatus == "Failed");
                var synced = result.Summaries.Count(s => s.VerifyStatus == "Synced");
                var totalApplied = result.Summaries.Sum(s => s.AppliedCount);
                var totalFailed = result.Summaries.Sum(s => s.FailedCount);

                _steps.Active = WorkflowStep.Deploy;
                if (failedDbs > 0)
                {
                    _lblProgressStage.Text = $"Deployed with errors - {failedDbs} database(s) failed";
                    _lblProgressStage.ForeColor = UiTheme.Danger;
                }
                else if (synced == deployed)
                {
                    _lblProgressStage.Text = "Deployed - all databases verified in sync";
                    _lblProgressStage.ForeColor = UiTheme.Success;
                }
                else
                {
                    _lblProgressStage.Text = "Deployed - some databases still have differences (manual scripts)";
                    _lblProgressStage.ForeColor = UiTheme.Warning;
                }
                _tabs.SelectedTab = _tabDeploy;

                var manualNote = _deployResult.HasManual
                    ? $"\r\n\u26A0  {_deployResult.ManualFileCount} MANUAL script(s) still require review\r\n" +
                      "(see the 'Manual Actions' tab - never auto-applied)."
                    : "";
                MessageBox.Show(this,
                    $"Deployment finished.\r\n\r\n" +
                    $"Databases deployed: {deployed} of {result.Summaries.Count}\r\n" +
                    $"Scripts applied: {totalApplied}   Failed: {totalFailed}\r\n" +
                    $"Verified in sync: {synced} of {deployed}\r\n" +
                    manualNote +
                    "\r\nSee the Deployment tab for per-database status, errors and verification.",
                    failedDbs > 0 ? "Deployed with errors" : "Deployment done",
                    MessageBoxButtons.OK,
                    failedDbs > 0 ? MessageBoxIcon.Error
                        : (_deployResult.HasManual ? MessageBoxIcon.Warning : MessageBoxIcon.Information));
                SetStatus($"Deploy done - {totalApplied} applied, {totalFailed} failed, {synced}/{deployed} in sync.");
            }
            else
            {
                _steps.Active = WorkflowStep.Review;
                _lblProgressStage.Text = result.AllDifferences.Count == 0
                    ? "Schemas match — nothing to deploy"
                    : "Review differences, then save deploy script";
                _lblProgressStage.ForeColor = UiTheme.Success;
                _tabs.SelectedTab = _tabOverview;
                var manualNote = _deployResult.HasManual
                    ? $"\r\n\r\n\u26A0  {_deployResult.ManualFileCount} MANUAL script(s) were produced.\r\n" +
                      "These are NOT applied automatically - open the 'Manual Actions' tab\r\nand run them by hand on the target after review.\r\n" +
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
        var (add, upd, extra, _) = DiffQuery.CountByKind(diffs);
        _cardAdded.SetValue(add);
        _cardChanged.SetValue(upd);
        _cardExtra.SetValue(extra);
        _cardManual.SetValue(_deployResult?.ManualFileCount ?? 0);
        _badgeAdded.SetValue(add);
        _badgeRemoved.SetValue(extra);
        _badgeChanged.SetValue(upd);
        // Identical / Ignored are reserved for future engine metrics; keep visible at 0 per mockup.
        _badgeIdentical.SetValue(0);
        _badgeIgnored.SetValue(_deployResult?.ManualFileCount ?? 0);
        _statusObjects.Text = $"Objects: {diffs.Count:N0}";
        UpdateHeaderProject();
    }

    private void UpdateHeaderProject()
    {
        try
        {
            var src = _sourcePanel.GetConnectionInfo();
            var tgt = _targetPanel.GetConnectionInfo(false);
            var srcDb = _sourcePanel.SelectedDatabase;
            var tgtDb = _targetPanel.SelectedDatabase;

            _statusSource.Text = string.IsNullOrWhiteSpace(src.Instance)
                ? "Source: Not selected"
                : $"Source: {src.Instance}" + (string.IsNullOrWhiteSpace(srcDb) ? "" : $"  \u00B7  {srcDb}");
            _statusTarget.Text = string.IsNullOrWhiteSpace(tgt.Instance)
                ? "Target: Not selected"
                : $"Target: {tgt.Instance}" + (string.IsNullOrWhiteSpace(tgtDb) ? "" : $"  \u00B7  {tgtDb}");
            var objectCount = _lastResult?.AllDifferences?.Count
                ?? (_sourceObjects.Count + _targetObjects.Count);
            _statusObjects.Text = $"Objects: {objectCount}";
        }
        catch { /* ignore */ }
    }

    /// <summary>Maps a raw engine object type to the mockup's explorer categories.</summary>
    private static string TypeCategory(string objectType) => objectType.ToUpperInvariant() switch
    {
        "TABLE" or "U" => "Tables",
        "VIEW" or "V" => "Views",
        "PROCEDURE" or "STORED PROCEDURE" or "P" => "Stored Procedures",
        "FUNCTION" or "FN" or "TF" or "IF" => "User Defined Functions",
        "INDEX" => "Indexes",
        "TRIGGER" or "TR" => "Triggers",
        "SCHEMA" => "Schemas",
        _ => "Others"
    };

    private void UpdateOverviewDashboard(CompareResult? result)
    {
        if (result == null)
        {
            _overviewDash.Visible = false;
            _overviewEmpty.Visible = true;
            return;
        }

        var sb = new StringBuilder();
        sb.AppendLine($"Compared {result.Summaries.Count} database pair(s)  \u00B7  {result.AllDifferences.Count} difference(s) found.");
        if (_deployResult != null)
            sb.AppendLine($"Deploy scripts:  {_deployResult.AutoFileCount} auto (safe)  \u00B7  {_deployResult.ManualFileCount} manual (review required).");
        if (!string.IsNullOrWhiteSpace(result.RunFolder))
            sb.AppendLine($"Run folder:  {result.RunFolder}");
        sb.AppendLine();
        sb.AppendLine("Open Object Details for per-object impact, Script Preview for the deployable SQL,");
        sb.AppendLine("and Manual Actions for statements that must be reviewed by hand.");
        _txtOverview.Text = sb.ToString();
        _overviewEmpty.Visible = false;
        _overviewDash.Visible = true;
    }

    private void RebuildTree(string filter)
    {
        if (IsDisposed) return;
        _tree.BeginUpdate();
        try
        {
            _tree.Nodes.Clear();

            // After a compare, show differences. Before that, browse selected DBs.
            if (_lastResult != null)
            {
                var source = _lastResult.AllDifferences ?? (IReadOnlyList<DifferenceItem>)Array.Empty<DifferenceItem>();
                // Object Types filter from the action bar applies first.
                var typed = source.Where(d => _enabledTypes.Contains(TypeCategory(d.ObjectType))).ToList();
                var diffs = DiffQuery.Filter(typed, filter);
                _lblTreePlaceholder.Visible = diffs.Count == 0;
                _tree.Visible = true;
                if (diffs.Count == 0)
                {
                    _lblTreePlaceholder.Text = "No differences match the current filter.";
                    _lblTreePlaceholder.Visible = true;
                    return;
                }

                var root = new TreeNode($"Differences ({diffs.Count})") { ImageKey = "root", SelectedImageKey = "root" };
                foreach (var byDb in DiffQuery.GroupByDatabaseThenType(diffs))
                {
                    var dbNode = new TreeNode(byDb.Key) { ImageKey = "root", SelectedImageKey = "root" };
                    foreach (var byType in byDb.GroupBy(d => d.ObjectType).OrderBy(g => g.Key))
                    {
                        var (label, icon) = DiffQuery.DescribeObjectType(byType.Key);
                        var typeNode = new TreeNode($"{label} ({byType.Count()})")
                        {
                            ImageKey = icon,
                            SelectedImageKey = icon
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
                            typeNode.Nodes.Add(new TreeNode($"{d.ObjectName}  ·  {d.ActionLabel}")
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
                // Show the difference roots collapsed — expand folders on demand.
                return;
            }

            BuildBrowseTree(filter);
        }
        finally
        {
            _tree.EndUpdate();
        }
    }

    private void BuildBrowseTree(string filter)
    {
        var q = (filter ?? "").Trim();
        var src = FilterBrowseObjects(_sourceObjects, q)
            .Where(o => _enabledTypes.Contains(TypeCategory(o.ObjectType))).ToList();
        var tgt = FilterBrowseObjects(_targetObjects, q)
            .Where(o => _enabledTypes.Contains(TypeCategory(o.ObjectType))).ToList();
        var hasAny = src.Count > 0 || tgt.Count > 0;

        _tree.Visible = true;
        _lblTreePlaceholder.Visible = false;
        if (!hasAny)
        {
            // Mockup initial state: category folders visible (collapsed) before browse/compare.
            _tree.Visible = true;
            _lblTreePlaceholder.Visible = false;
            foreach (var cat in new[]
                     {
                         "Databases", "Schemas", "Tables", "Views", "Stored Procedures",
                         "User Defined Functions", "Indexes", "Triggers", "Others"
                     })
            {
                _tree.Nodes.Add(new TreeNode(cat) { ImageKey = "folder", SelectedImageKey = "folder" });
            }
            return;
        }

        if (src.Count > 0)
            _tree.Nodes.Add(BuildSideBrowseNode("Source", true, _sourceBrowseDb, src));
        if (tgt.Count > 0)
            _tree.Nodes.Add(BuildSideBrowseNode("Target", false, _targetBrowseDb, tgt));

        // Keep Source/Target trees collapsed after connect (expand on demand).
    }

    private static IReadOnlyList<SchemaObjectInfo> FilterBrowseObjects(
        IReadOnlyList<SchemaObjectInfo> objects, string filter)
    {
        if (string.IsNullOrWhiteSpace(filter)) return objects;
        return objects
            .Where(o =>
                o.FullName.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                o.ObjectType.Contains(filter, StringComparison.OrdinalIgnoreCase))
            .ToList();
    }

    private static TreeNode BuildSideBrowseNode(
        string side, bool isSource, string database, IReadOnlyList<SchemaObjectInfo> objects)
    {
        var title = string.IsNullOrWhiteSpace(database)
            ? $"{side} ({objects.Count})"
            : $"{side}: {database} ({objects.Count})";
        var root = new TreeNode(title) { ImageKey = "root", SelectedImageKey = "root" };
        var sideCtx = new BrowseSideContext(isSource, database ?? "");

        foreach (var byType in objects.GroupBy(o => o.ObjectType).OrderBy(g => TypeSort(g.Key)))
        {
            var (label, icon) = DiffQuery.DescribeObjectType(byType.Key);
            var typeNode = new TreeNode($"{label} ({byType.Count()})")
            {
                ImageKey = icon,
                SelectedImageKey = icon
            };
            foreach (var o in byType.OrderBy(x => x.FullName, StringComparer.OrdinalIgnoreCase))
            {
                var isTable = o.ObjectType.Equals("TABLE", StringComparison.OrdinalIgnoreCase);
                if (isTable)
                {
                    var tableTag = new TableBrowseNode(sideCtx, o.SchemaName, o.ObjectName);
                    var tableNode = new TreeNode(o.FullName)
                    {
                        Tag = tableTag,
                        ImageKey = icon,
                        SelectedImageKey = icon
                    };
                    foreach (TableFolderKind kind in Enum.GetValues<TableFolderKind>())
                    {
                        var folderIcon = ObjectExplorerFormat.FolderIcon(kind);
                        var folderNode = new TreeNode(ObjectExplorerFormat.FolderLabel(kind))
                        {
                            Tag = new TableFolderNode(tableTag, kind, Loaded: false),
                            ImageKey = folderIcon,
                            SelectedImageKey = folderIcon
                        };
                        folderNode.Nodes.Add(new TreeNode("Loading...")
                        {
                            ImageKey = "other",
                            SelectedImageKey = "other"
                        });
                        tableNode.Nodes.Add(folderNode);
                    }
                    typeNode.Nodes.Add(tableNode);
                }
                else
                {
                    typeNode.Nodes.Add(new TreeNode(o.FullName)
                    {
                        Tag = o,
                        ImageKey = icon,
                        SelectedImageKey = icon
                    });
                }
            }
            root.Nodes.Add(typeNode);
        }
        return root;
    }

    private async Task LoadTableFolderChildrenAsync(TreeNode? node)
    {
        if (node?.Tag is not TableFolderNode folder || folder.Loaded) return;
        if (_isShuttingDown || IsDisposed || _lastResult != null) return;

        var panel = folder.Table.Side.IsSource ? _sourcePanel : _targetPanel;
        var db = folder.Table.Side.Database;
        if (string.IsNullOrWhiteSpace(db)) return;

        try
        {
            var info = panel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Loading {ObjectExplorerFormat.FolderLabel(folder.Kind)} for {folder.Table.FullName}...");

            var children = await ObjectExplorerCatalog.ListTableFolderAsync(
                info, db, folder.Table.SchemaName, folder.Table.TableName, folder.Kind).ConfigureAwait(true);

            if (_isShuttingDown || IsDisposed || _lastResult != null) return;
            if (node.Tag is not TableFolderNode current || current.Loaded) return;
            if (!ReferenceEquals(node.Tag, folder) &&
                (current.Kind != folder.Kind ||
                 !string.Equals(current.Table.FullName, folder.Table.FullName, StringComparison.OrdinalIgnoreCase)))
                return;

            node.Nodes.Clear();
            var icon = ObjectExplorerFormat.ChildIcon(folder.Kind);
            if (children.Count == 0)
            {
                node.Nodes.Add(new TreeNode("(empty)")
                {
                    ImageKey = "other",
                    SelectedImageKey = "other"
                });
            }
            else
            {
                foreach (var child in children)
                {
                    node.Nodes.Add(new TreeNode(child.DisplayText)
                    {
                        Tag = child,
                        ImageKey = icon,
                        SelectedImageKey = icon
                    });
                }
            }

            node.Tag = folder with { Loaded = true };
            node.Text = $"{ObjectExplorerFormat.FolderLabel(folder.Kind)} ({children.Count})";
            SetStatus($"Loaded {children.Count} {ObjectExplorerFormat.FolderLabel(folder.Kind).ToLowerInvariant()} for {folder.Table.FullName}.");
        }
        catch (OperationCanceledException)
        {
            // ignore
        }
        catch (Exception ex)
        {
            if (_isShuttingDown || IsDisposed) return;
            node.Nodes.Clear();
            node.Nodes.Add(new TreeNode($"(error: {ex.Message})")
            {
                ImageKey = "extra",
                SelectedImageKey = "extra"
            });
            node.Tag = folder with { Loaded = true };
            SetStatus($"Could not load {ObjectExplorerFormat.FolderLabel(folder.Kind)}: {ex.Message}");
        }
    }

    private async Task ShowDifferenceCompareAsync(DifferenceItem d)
    {
        if (_isShuttingDown || IsDisposed) return;

        var impact = d.Kind switch
        {
            DiffKind.Add => "Low - object will be created on target",
            DiffKind.Update => "Medium - definition will change on target",
            DiffKind.Extra => "High - target-only object (review before drop)",
            _ => "Unknown"
        };

        var srcInfo = _sourcePanel.GetConnectionInfo(false);
        srcInfo.TrustServerCertificate = _options.TrustServerCertificate;
        var tgtInfo = _targetPanel.GetConnectionInfo(false);
        tgtInfo.TrustServerCertificate = _options.TrustServerCertificate;

        var srcDb = !string.IsNullOrWhiteSpace(srcInfo.Database)
            ? srcInfo.Database
            : (_lastResult?.Summaries.FirstOrDefault()?.Database ?? "");
        var tgtDb = ResolveTargetDatabaseForDiff(d);

        _lblDetailHeader.Text =
            $"{d.ObjectName}    ·    {d.ObjectType}    ·    {d.ActionLabel} ({d.Status})    ·    {impact}";
        _lblSourceCaption.Text = $"SOURCE  ·  {srcInfo.Instance} / {srcDb}";
        _lblTargetCaption.Text = $"TARGET  ·  {tgtInfo.Instance} / {tgtDb}";

        ShowDetailDualMode();
        _txtSourceDef.Text = d.Kind == DiffKind.Extra
            ? "-- Not present on source.\r\n-- This object exists only on the target."
            : "-- Loading source definition...";
        _txtTargetDef.Text = d.Kind == DiffKind.Add
            ? "-- Not present on target.\r\n-- This object will be created from the source definition."
            : "-- Loading target definition...";

        if (!ObjectExplorerFormat.TryParseObjectName(d.ObjectName, out var schema, out var name))
        {
            _txtSourceDef.Text = $"-- Could not parse object name: {d.ObjectName}";
            _txtTargetDef.Text = _txtSourceDef.Text;
            return;
        }

        _scriptCts?.Cancel();
        _scriptCts?.Dispose();
        _scriptCts = new CancellationTokenSource();
        var ct = _scriptCts.Token;
        var selectedKey = $"{d.Database}|{d.ObjectType}|{d.ObjectName}|{d.Status}";

        try
        {
            SetStatus($"Loading definitions for {d.ObjectName}...");

            Task<string> srcTask = d.Kind == DiffKind.Extra
                ? Task.FromResult(_txtSourceDef.Text)
                : ObjectExplorerCatalog.ScriptObjectDefinitionAsync(
                    srcInfo, srcDb, d.ObjectType, schema, name, ct);

            Task<string> tgtTask = d.Kind == DiffKind.Add
                ? Task.FromResult(_txtTargetDef.Text)
                : ObjectExplorerCatalog.ScriptObjectDefinitionAsync(
                    tgtInfo, tgtDb, d.ObjectType, schema, name, ct);

            await Task.WhenAll(srcTask, tgtTask).ConfigureAwait(true);
            if (_isShuttingDown || IsDisposed || ct.IsCancellationRequested) return;
            if (!IsDiffStillSelected(selectedKey)) return;

            var srcText = await srcTask.ConfigureAwait(true);
            var tgtText = await tgtTask.ConfigureAwait(true);

            _txtSourceDef.Text = srcText;
            _txtTargetDef.Text = tgtText;
            SetStatus($"Loaded source/target definitions for {d.ObjectName}.");
        }
        catch (OperationCanceledException)
        {
            // newer selection cancelled this load
        }
        catch (Exception ex)
        {
            if (_isShuttingDown || IsDisposed) return;
            _txtSourceDef.Text = $"-- Failed to load source definition:\r\n-- {ex.Message}";
            _txtTargetDef.Text = $"-- Failed to load target definition:\r\n-- {ex.Message}";
            SetStatus($"Could not load definitions: {ex.Message}");
        }
    }

    private string ResolveTargetDatabaseForDiff(DifferenceItem d)
    {
        if (!string.IsNullOrWhiteSpace(d.Database))
            return d.Database;
        var fromPanel = _targetPanel.GetConnectionInfo(false).Database;
        if (!string.IsNullOrWhiteSpace(fromPanel))
            return fromPanel;
        return _lastResult?.Summaries.FirstOrDefault()?.TargetDatabase ?? "";
    }

    private bool IsDiffStillSelected(string selectedKey)
    {
        if (_tree.SelectedNode?.Tag is not DifferenceItem cur) return false;
        var key = $"{cur.Database}|{cur.ObjectType}|{cur.ObjectName}|{cur.Status}";
        return string.Equals(key, selectedKey, StringComparison.OrdinalIgnoreCase);
    }

    private async Task ScriptTableAsync(TableBrowseNode table)
    {
        if (_isShuttingDown || IsDisposed || _lastResult != null) return;

        _scriptCts?.Cancel();
        _scriptCts?.Dispose();
        _scriptCts = new CancellationTokenSource();
        var ct = _scriptCts.Token;

        try
        {
            var panel = table.Side.IsSource ? _sourcePanel : _targetPanel;
            var db = table.Side.Database;
            if (string.IsNullOrWhiteSpace(db)) return;

            var info = panel.GetConnectionInfo(false);
            info.TrustServerCertificate = _options.TrustServerCertificate;
            SetStatus($"Scripting CREATE TABLE for {table.FullName}...");

            var script = await ObjectExplorerCatalog.ScriptCreateTableAsync(
                info, db, table.SchemaName, table.TableName, ct).ConfigureAwait(true);

            if (_isShuttingDown || IsDisposed || ct.IsCancellationRequested) return;
            // Only apply if this table is still selected.
            if (_tree.SelectedNode?.Tag is not TableBrowseNode selected ||
                !string.Equals(selected.FullName, table.FullName, StringComparison.OrdinalIgnoreCase) ||
                selected.Side.IsSource != table.Side.IsSource)
                return;

            _browseScriptSnapshot = script;
            ShowSingleDetailText(
                $"Table\r\n  {table.FullName}\r\n\r\n" +
                $"Database\r\n  {db}\r\n\r\n" +
                $"Side\r\n  {(table.Side.IsSource ? "Source" : "Target")}\r\n\r\n" +
                "CREATE TABLE script loaded in the Deployable script tab.\r\n" +
                "Expand Columns / Keys / Constraints / Indexes / Triggers under this table.");
            _txtScript.Text = script;
            // Prefer showing the script like SSMS "Script Table as → CREATE To"
            _tabs.SelectedTab = _tabScript;
            SetStatus($"Scripted CREATE TABLE for {table.FullName}.");
        }
        catch (OperationCanceledException)
        {
            // newer selection cancelled this script
        }
        catch (Exception ex)
        {
            if (_isShuttingDown || IsDisposed) return;
            ShowSingleDetailText(
                $"Table\r\n  {table.FullName}\r\n\r\n" +
                $"Could not script CREATE TABLE:\r\n  {ex.Message}");
            SetStatus($"Script failed: {ex.Message}");
        }
    }

    private static int TypeSort(string type) => type.ToUpperInvariant() switch
    {
        "TABLE" => 1,
        "VIEW" => 2,
        "PROCEDURE" => 3,
        "FUNCTION" => 4,
        "TRIGGER" => 5,
        _ => 9
    };

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
            if (s.TargetDatabases.Count > 0)
                _targetPanel.SetDatabases(s.TargetDatabases, s.TargetDatabases);
            _txtListFile.Text = s.DestinationListFile;
            _options = s.Options ?? new CompareOptions();
            if (string.IsNullOrWhiteSpace(_options.OutputPath))
                _options.OutputPath = Path.Combine(_engine.SchemaCompareRoot, "output");

            if (s.WindowWidth >= MinimumSize.Width && s.WindowHeight >= MinimumSize.Height)
            {
                StartPosition = FormStartPosition.Manual;
                Bounds = new Rectangle(
                    s.WindowX == int.MinValue ? Left : s.WindowX,
                    s.WindowY == int.MinValue ? Top : s.WindowY,
                    s.WindowWidth,
                    s.WindowHeight);
                // Keep on-screen
                var wa = Screen.FromControl(this).WorkingArea;
                if (!wa.IntersectsWith(Bounds))
                    Location = wa.Location;
            }
            if (s.WindowMaximized)
                WindowState = FormWindowState.Maximized;
        }
        catch { /* ignore corrupt settings */ }
        UpdateHeaderProject();
    }

    private void SaveSettings()
    {
        try
        {
            var source = _sourcePanel.GetConnectionInfo();
            var target = _targetPanel.GetConnectionInfo(false);
            var bounds = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
            SettingsStore.Save(new AppSessionSettings
            {
                Mode = _rbOneToMany.Checked ? CompareMode.OneToMany : CompareMode.OneToOne,
                Source = source,
                Target = target,
                TargetDatabases = _targetPanel.GetCheckedDatabases().ToList(),
                DestinationListFile = _txtListFile.Text.Trim(),
                Options = _options,
                WindowX = bounds.X,
                WindowY = bounds.Y,
                WindowWidth = bounds.Width,
                WindowHeight = bounds.Height,
                WindowMaximized = WindowState == FormWindowState.Maximized
            });
        }
        catch { /* ignore */ }
    }
}
