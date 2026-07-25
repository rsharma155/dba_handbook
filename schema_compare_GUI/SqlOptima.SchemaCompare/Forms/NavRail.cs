// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.NavRail
// Purpose:  Dark left navigation rail - Compare, History, Scripts, Reports,
//           and Settings with an active indicator, plus Theme / Ready chrome.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Vertical icon rail. Raises <see cref="ItemClicked"/> with the item key;
/// the host decides what each destination does.
/// </summary>
public sealed class NavRail : UserControl
{
    private sealed record RailItem(string Key, string Label, string Glyph);

    private static readonly RailItem[] Items =
    {
        new("compare", "Compare", "\uE8AB"),   // Switch
        new("history", "History", "\uE81C"),   // History
        new("scripts", "Scripts", "\uE8A5"),   // Document
        new("reports", "Reports", "\uE9D9"),   // Diagnostic/chart
        new("settings", "Settings", "\uE713")  // Settings gear
    };

    private const int ItemHeight = 56;
    private const int TopOffset = 8;

    private string _activeKey = "compare";
    private string? _hoverKey;
    private readonly ToolTip _tips = new();

    public event EventHandler<string>? ItemClicked;

    public NavRail()
    {
        Width = 72;
        Dock = DockStyle.Left;
        BackColor = UiTheme.SidebarBackground;
        DoubleBuffered = true;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        MouseMove += (_, e) =>
        {
            var key = HitTest(e.Location);
            if (key != _hoverKey)
            {
                _hoverKey = key;
                Cursor = key == null ? Cursors.Default : Cursors.Hand;
                Invalidate();
            }
        };
        MouseLeave += (_, _) => { _hoverKey = null; Invalidate(); };
        MouseClick += (_, e) =>
        {
            var key = HitTest(e.Location);
            if (key != null) PerformItemClick(key);
        };
    }

    public IReadOnlyList<string> ItemKeys => Items.Select(i => i.Key).ToList();

    public string LabelFor(string key) =>
        Items.FirstOrDefault(i => i.Key == key)?.Label
        ?? throw new ArgumentOutOfRangeException(nameof(key), key, "Unknown rail item");

    public string ActiveKey
    {
        get => _activeKey;
        set
        {
            if (_activeKey == value) return;
            _activeKey = value;
            Invalidate();
        }
    }

    /// <summary>Activates an item and raises <see cref="ItemClicked"/> (also used by tests).</summary>
    public void PerformItemClick(string key)
    {
        if (Items.All(i => i.Key != key)) return;
        ActiveKey = key;
        ItemClicked?.Invoke(this, key);
    }

    private static Rectangle ItemBounds(int index, int width)
        => new(0, TopOffset + index * ItemHeight, width, ItemHeight);

    private string? HitTest(Point p)
    {
        for (var i = 0; i < Items.Length; i++)
        {
            if (ItemBounds(i, Width).Contains(p))
                return Items[i].Key;
        }
        return null;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(UiTheme.SidebarBackground);

        using var iconFont = UiTheme.IconFont(14f);
        using var labelFont = UiTheme.UiFont(7.5f);

        for (var i = 0; i < Items.Length; i++)
        {
            var item = Items[i];
            var rect = ItemBounds(i, Width);
            var isActive = item.Key == _activeKey;
            var isHover = item.Key == _hoverKey;

            if (isActive || isHover)
            {
                using var back = new SolidBrush(isActive ? UiTheme.SidebarActive : Color.FromArgb(0x10, 0x1C, 0x2E));
                var pill = new Rectangle(6, rect.Y + 4, Width - 12, rect.Height - 8);
                using var path = Rounded(pill, 8);
                g.FillPath(back, path);
            }

            if (isActive)
            {
                using var accent = new SolidBrush(UiTheme.Cta);
                g.FillRectangle(accent, 0, rect.Y + 12, 3, rect.Height - 24);
            }

            var fore = isActive ? Color.White : UiTheme.TextOnDarkMuted;
            TextRenderer.DrawText(g, item.Glyph, iconFont,
                new Rectangle(rect.X, rect.Y + 8, rect.Width, 20), fore,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            TextRenderer.DrawText(g, item.Label, labelFont,
                new Rectangle(rect.X, rect.Y + 30, rect.Width, 16), fore,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }

        // Bottom chrome per mockup: Theme hint + Ready micro-status (visual parity).
        using var bottomFont = UiTheme.UiFont(7.5f);
        using var moonFont = UiTheme.IconFont(12f);
        var themeY = Height - 76;
        TextRenderer.DrawText(g, "\uE708", moonFont, new Rectangle(0, themeY, Width, 18),
            UiTheme.TextOnDarkMuted, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
        TextRenderer.DrawText(g, "Theme", bottomFont, new Rectangle(0, themeY + 18, Width, 14),
            UiTheme.TextOnDarkMuted, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
        TextRenderer.DrawText(g, "Ready", bottomFont, new Rectangle(0, Height - 22, Width, 14),
            UiTheme.TextOnDarkMuted, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
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

    protected override void Dispose(bool disposing)
    {
        if (disposing) _tips.Dispose();
        base.Dispose(disposing);
    }
}
