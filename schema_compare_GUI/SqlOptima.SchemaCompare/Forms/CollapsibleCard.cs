// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.CollapsibleCard
// Purpose:  White rounded card with a numbered title, subtitle, and a
//           Collapse/Expand toggle. Hosts the connection panels and
//           auto-collapses when a comparison starts to maximize workspace.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Collapsible section card. Put content in <see cref="ContentHost"/>;
/// toggle with <see cref="Collapsed"/> or the built-in header button.
/// </summary>
public sealed class CollapsibleCard : UserControl
{
    private const int HeaderHeight = 46;

    private readonly Label _lblTitle;
    private readonly Label _lblSubtitle;
    private readonly ModernButton _btnToggle = new();
    private bool _collapsed;
    private int _expandedHeight = 300;

    public event EventHandler? CollapsedChanged;

    public CollapsibleCard(string title, string subtitle)
    {
        BackColor = Color.Transparent;
        DoubleBuffered = true;
        Padding = new Padding(1);
        Height = _expandedHeight;

        Paint += (_, e) =>
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var path = Rounded(rect, 10);
            using var fill = new SolidBrush(UiTheme.CardBackground);
            using var border = new Pen(UiTheme.CardBorder);
            g.FillPath(fill, path);
            g.DrawPath(border, path);
        };

        var header = new Panel { Dock = DockStyle.Top, Height = HeaderHeight, BackColor = UiTheme.CardBackground };

        _lblTitle = new Label
        {
            Text = title,
            Font = UiTheme.SectionFont(),
            ForeColor = UiTheme.TextPrimary,
            AutoSize = true,
            Location = new Point(16, 12),
            BackColor = Color.Transparent
        };
        _lblSubtitle = new Label
        {
            Text = subtitle,
            Font = UiTheme.UiFont(9f),
            ForeColor = UiTheme.TextMuted,
            AutoSize = true,
            BackColor = Color.Transparent
        };

        UiTheme.StyleSecondary(_btnToggle);
        _btnToggle.Height = 30;
        _btnToggle.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        _btnToggle.Click += (_, _) => Collapsed = !Collapsed;

        header.Controls.Add(_lblTitle);
        header.Controls.Add(_lblSubtitle);
        header.Controls.Add(_btnToggle);
        header.Resize += (_, _) => LayoutHeader(header);

        ContentHost = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = UiTheme.CardBackground,
            Padding = new Padding(16, 0, 16, 12)
        };

        Controls.Add(ContentHost);
        Controls.Add(header);

        UpdateToggleCaption();
        LayoutHeader(header);
    }

    /// <summary>Content area shown while expanded.</summary>
    public Panel ContentHost { get; }

    public string Title => _lblTitle.Text;

    public string Subtitle => _lblSubtitle.Text;

    /// <summary>Height used while expanded; setting it while expanded resizes now.</summary>
    public int ExpandedHeight
    {
        get => _expandedHeight;
        set
        {
            _expandedHeight = Math.Max(HeaderHeight + 20, value);
            if (!_collapsed) Height = _expandedHeight;
        }
    }

    public bool Collapsed
    {
        get => _collapsed;
        set
        {
            if (_collapsed == value) return;
            _collapsed = value;
            ContentHost.Visible = !value;
            Height = value ? HeaderHeight + 4 : _expandedHeight;
            UpdateToggleCaption();
            Invalidate();
            CollapsedChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void UpdateToggleCaption()
    {
        _btnToggle.Text = _collapsed ? "\u02C5  Expand" : "\u02C4  Collapse";
        UiTheme.FitButton(_btnToggle, 96);
    }

    private void LayoutHeader(Panel header)
    {
        _lblSubtitle.Location = new Point(_lblTitle.Right + 10, 16);
        _btnToggle.Location = new Point(header.Width - _btnToggle.Width - 14, 8);
    }

    private static GraphicsPath Rounded(Rectangle r, int radius)
    {
        var d = Math.Max(2, radius * 2);
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
