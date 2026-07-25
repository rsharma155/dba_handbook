// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.WorkflowStepBar
// Purpose:  Four-step workflow indicator (1 Connect, 2 Compare, 3 Review,
//           4 Deploy) rendered as pills on the dark header - completed steps
//           green, current blue, future grey, per the UI mockup.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Forms;

public enum WorkflowStep
{
    Connect = 1,
    Compare = 2,
    Review = 3,
    Deploy = 4
}

/// <summary>Stepper with circled numbers; supports light and dark surfaces.</summary>
public sealed class WorkflowStepBar : UserControl
{
    private WorkflowStep _active = WorkflowStep.Connect;
    private readonly string[] _titles = { "Connect", "Compare", "Review", "Deploy" };

    public WorkflowStepBar()
    {
        Height = 56;
        DoubleBuffered = true;
        BackColor = Color.Transparent;
        SetStyle(ControlStyles.SupportsTransparentBackColor, true);
        Resize += (_, _) => Invalidate();
    }

    /// <summary>Render for a dark navy header instead of the light workspace.</summary>
    public bool OnDark { get; set; }

    public WorkflowStep Active
    {
        get => _active;
        set
        {
            if (_active == value) return;
            _active = value;
            Invalidate();
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(OnDark ? UiTheme.HeaderBackground : (Parent?.BackColor ?? UiTheme.AppBackground));

        var count = _titles.Length;
        var gap = 12;
        var totalGap = gap * (count - 1);
        var w = Math.Max(96, (Width - 16 - totalGap) / count);
        var h = 32;
        var y = Math.Max(2, (Height - h) / 2);

        for (var i = 0; i < count; i++)
        {
            var step = (WorkflowStep)(i + 1);
            var x = 8 + i * (w + gap);
            var rect = new Rectangle(x, y, w, h);
            var isActive = step == _active;
            var isDone = step < _active;

            Color back, fore, border;
            if (OnDark)
            {
                back = isActive ? UiTheme.Primary
                    : isDone ? Color.FromArgb(0x0F, 0x3D, 0x2A)
                    : Color.FromArgb(0x16, 0x22, 0x36);
                fore = isActive ? Color.White
                    : isDone ? Color.FromArgb(0x4A, 0xDE, 0x80)
                    : UiTheme.TextOnDarkMuted;
                border = isActive ? UiTheme.Primary
                    : isDone ? Color.FromArgb(0x16, 0xA3, 0x4A)
                    : Color.FromArgb(0x2A, 0x38, 0x50);
            }
            else
            {
                back = isActive ? UiTheme.Primary
                    : isDone ? Color.FromArgb(220, 252, 231)
                    : Color.White;
                fore = isActive ? Color.White
                    : isDone ? UiTheme.Success
                    : UiTheme.TextMuted;
                border = isActive ? UiTheme.Primary
                    : isDone ? Color.FromArgb(134, 239, 172)
                    : UiTheme.CardBorder;
            }

            using (var path = Round(rect, 16))
            using (var brush = new SolidBrush(back))
            using (var pen = new Pen(border, 1.5f))
            {
                g.FillPath(brush, path);
                g.DrawPath(pen, path);
            }

            var label = $"{ToCircled(i + 1)}  {_titles[i]}";
            using var font = isActive ? UiTheme.SemiBold(9.5f) : UiTheme.UiFont(9.5f);
            TextRenderer.DrawText(g, label, font, rect, fore,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);

            if (i < count - 1)
            {
                var cx = x + w + 3;
                var lineColor = OnDark
                    ? (isDone || isActive ? UiTheme.Primary : Color.FromArgb(0x2A, 0x38, 0x50))
                    : (isDone || isActive ? UiTheme.Primary : UiTheme.CardBorder);
                using var line = new Pen(lineColor, 2f);
                g.DrawLine(line, cx, y + h / 2, cx + gap - 6, y + h / 2);
            }
        }
    }

    private static string ToCircled(int n) => n switch
    {
        1 => "\u2460",
        2 => "\u2461",
        3 => "\u2462",
        4 => "\u2463",
        _ => n.ToString()
    };

    private static GraphicsPath Round(Rectangle r, int radius)
    {
        var d = Math.Min(r.Height, radius * 2);
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
