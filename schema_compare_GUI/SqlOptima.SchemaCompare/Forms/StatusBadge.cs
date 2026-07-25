// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.StatusBadge
// Purpose:  Rounded count badge for the results header - e.g. "Added 12".
//           Auto-sizes to its caption so text can never truncate.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>Color-coded pill badge showing a category name and a count.</summary>
public sealed class StatusBadge : UserControl
{
    private readonly Color _accent;
    private int _value;

    public StatusBadge(string title, Color accent)
    {
        Title = title;
        _accent = accent;
        Height = 26;
        BackColor = Color.Transparent;
        DoubleBuffered = true;
        Font = UiTheme.SemiBold(8.5f);
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
        FitToCaption();
    }

    public string Title { get; }

    public int Value => _value;

    public string CaptionText => $"{Title}  {_value:N0}";

    public void SetValue(int value)
    {
        _value = value;
        FitToCaption();
        Invalidate();
    }

    private void FitToCaption()
    {
        // Dot (10) + gaps + text + pill padding; never smaller than the caption.
        var textW = TextRenderer.MeasureText(CaptionText, Font).Width;
        Width = textW + 34;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Rounded(rect, Height / 2))
        {
            using var fill = new SolidBrush(Color.White);
            using var border = new Pen(UiTheme.CardBorder);
            g.FillPath(fill, path);
            g.DrawPath(border, path);
        }

        using (var dot = new SolidBrush(_value == 0 ? Color.FromArgb(120, _accent) : _accent))
        {
            g.FillEllipse(dot, 10, Height / 2 - 4, 8, 8);
        }

        var fore = _value == 0 ? UiTheme.TextMuted : _accent;
        TextRenderer.DrawText(g, CaptionText, Font,
            new Rectangle(22, 0, Width - 24, Height), fore,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
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
