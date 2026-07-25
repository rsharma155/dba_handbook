// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.SummaryCard
// Purpose:  Color-coded metric card (Added / Changed / Removed / Warnings) for the Overview results dashboard.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Compact single-line metric chip — e.g. "Added  12" — for the status/metrics row.
/// </summary>
public sealed class SummaryCard : UserControl
{
    private readonly Label _lblTitle;
    private readonly Label _lblValue;
    private Color _accent;

    public SummaryCard(string title, Color accent, string unit = "Objects")
    {
        _ = unit; // kept for call-site compatibility; compact chips omit the unit line
        _accent = accent;
        Height = 40;
        Width = 108;
        MinimumSize = new Size(88, 36);
        BackColor = Color.Transparent;
        DoubleBuffered = true;
        Padding = new Padding(10, 0, 10, 0);

        _lblTitle = new Label
        {
            Text = title,
            AutoSize = true,
            Font = UiTheme.SemiBold(9f),
            ForeColor = UiTheme.TextMuted,
            BackColor = Color.Transparent,
            AutoEllipsis = false
        };
        _lblValue = new Label
        {
            Text = "0",
            AutoSize = true,
            Font = UiTheme.SemiBold(12f),
            ForeColor = accent,
            BackColor = Color.Transparent,
            AutoEllipsis = false
        };
        Controls.Add(_lblTitle);
        Controls.Add(_lblValue);

        Paint += (_, e) =>
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var path = Round(rect, 6);
            using var fill = new SolidBrush(UiTheme.CardBackground);
            using var border = new Pen(UiTheme.CardBorder);
            g.FillPath(fill, path);
            g.DrawPath(border, path);
            using var accentBrush = new SolidBrush(_accent);
            g.FillRectangle(accentBrush, 0, 8, 3, Height - 16);
        };

        Resize += (_, _) => LayoutLabels();
        LayoutLabels();
    }

    public void SetValue(int value)
    {
        _lblValue.Text = value.ToString("N0");
        _lblValue.ForeColor = value == 0 ? UiTheme.TextMuted : _accent;
        LayoutLabels();
        Invalidate();
    }

    private void LayoutLabels()
    {
        const int padX = 12;
        var midY = Math.Max(0, (Height - Math.Max(_lblTitle.PreferredHeight, _lblValue.PreferredHeight)) / 2);
        _lblTitle.Location = new Point(padX, midY + 2);
        _lblValue.Location = new Point(_lblTitle.Right + 6, midY - 1);

        var needed = _lblValue.Right + 10;
        if (Width < needed)
            Width = needed;
    }

    private static GraphicsPath Round(Rectangle r, int radius)
    {
        var d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
