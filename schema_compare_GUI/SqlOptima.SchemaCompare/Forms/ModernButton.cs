// =============================================================================
// Module:   SqlOptima.SchemaCompare.Forms.ModernButton
// Purpose:  Owner-drawn rounded button with hover/press states and guaranteed
//           high-contrast, non-truncated captions. Corners stay clean by
//           painting an opaque parent surface first (never Clear(Transparent)).
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Owner-drawn rounded button. Corners never show dark "spots" because:
/// 1) the surface behind the rounded fill is always an opaque parent color
///    (WinForms <c>Graphics.Clear(Transparent)</c> paints black — that was the bug);
/// 2) solid CTAs draw no outline; light buttons use a soft gray/teal border.
/// </summary>
public sealed class ModernButton : Button
{
    private Color _hoverBack;
    private Color _pressBack;
    private Color _border = Color.Empty;
    private bool _hover;
    private bool _press;

    public int CornerRadius { get; set; } = 8;

    /// <summary>
    /// Optional border. Empty = auto (soft gray on light fills, none on solid CTAs).
    /// </summary>
    public Color BorderColor
    {
        get => _border;
        set { _border = value; Invalidate(); }
    }

    public ModernButton()
    {
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        FlatAppearance.BorderColor = Color.White;
        FlatAppearance.MouseOverBackColor = Color.Transparent;
        FlatAppearance.MouseDownBackColor = Color.Transparent;
        FlatAppearance.CheckedBackColor = Color.Transparent;
        UseVisualStyleBackColor = false;
        Cursor = Cursors.Hand;
        TextAlign = ContentAlignment.MiddleCenter;
        AutoEllipsis = false;
        Height = 34;
        Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        SetStyle(
            ControlStyles.UserPaint |
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw,
            true);
        // Do NOT enable SupportsTransparentBackColor — it invites black corner clears.
    }

    public void ApplyColors(Color back, Color fore, Color? hover = null, Color? press = null)
    {
        // Keep the control BackColor as the button fill so any unpainted pixel
        // matches the body (never the WinForms default dark chrome).
        BackColor = back;
        ForeColor = fore;
        _hoverBack = hover ?? ControlPaint.Light(back, 0.08f);
        _pressBack = press ?? ControlPaint.Dark(back, 0.08f);
        _border = back.GetBrightness() > 0.85f
            ? Color.FromArgb(0xD5, 0xDC, 0xE5)
            : Color.Empty;
        FlatAppearance.BorderColor = back;
        Invalidate();
    }

    /// <summary>
    /// Re-colors the button through the supplied palette maps (theme switch).
    /// Fill/hover/press/border go through <paramref name="mapBack"/>, the
    /// caption through <paramref name="mapFore"/>.
    /// </summary>
    public void RemapColors(Func<Color, Color> mapBack, Func<Color, Color> mapFore)
    {
        BackColor = mapBack(BackColor);
        ForeColor = mapFore(ForeColor);
        if (!_hoverBack.IsEmpty) _hoverBack = mapBack(_hoverBack);
        if (!_pressBack.IsEmpty) _pressBack = mapBack(_pressBack);
        if (!_border.IsEmpty) _border = mapBack(_border);
        FlatAppearance.BorderColor = BackColor;
        Invalidate();
    }

    protected override void OnParentChanged(EventArgs e)
    {
        base.OnParentChanged(e);
        Invalidate();
    }

    protected override void OnPaintBackground(PaintEventArgs pevent)
    {
        // Always paint an opaque surface — never Transparent (clears as black).
        using var brush = new SolidBrush(ResolveSurfaceColor());
        pevent.Graphics.FillRectangle(brush, ClientRectangle);
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        _hover = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        _hover = false;
        _press = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left) { _press = true; Invalidate(); }
        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        _press = false;
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnEnabledChanged(EventArgs e)
    {
        Invalidate();
        base.OnEnabledChanged(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.CompositingQuality = CompositingQuality.HighQuality;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

        var surface = ResolveSurfaceColor();
        using (var surfaceBrush = new SolidBrush(surface))
            g.FillRectangle(surfaceBrush, ClientRectangle);

        var back = !Enabled
            ? Color.FromArgb(210, 216, 224)
            : _press ? (_pressBack.IsEmpty ? ControlPaint.Dark(BackColor, 0.1f) : _pressBack)
            : _hover ? (_hoverBack.IsEmpty ? ControlPaint.Light(BackColor, 0.1f) : _hoverBack)
            : BackColor;

        var fore = !Enabled
            ? Color.FromArgb(120, 130, 145)
            : ForeColor;

        // Full client rounded fill (no Width-1 clip). Border drawn inset so AA
        // blends against the opaque surface already painted in the corners.
        var fillRect = new RectangleF(0f, 0f, Width, Height);
        using (var path = Rounded(fillRect, CornerRadius))
        using (var brush = new SolidBrush(back))
        {
            g.FillPath(brush, path);

            var border = !_border.IsEmpty
                ? _border
                : (back.GetBrightness() > 0.85f ? Color.FromArgb(0xD5, 0xDC, 0xE5) : Color.Empty);

            if (!border.IsEmpty && Enabled)
            {
                var inset = new RectangleF(0.5f, 0.5f, Math.Max(1f, Width - 1f), Math.Max(1f, Height - 1f));
                using var borderPath = Rounded(inset, CornerRadius);
                using var pen = new Pen(border, 1f);
                g.DrawPath(pen, borderPath);
            }
        }

        var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding;
        var needed = TextRenderer.MeasureText(Text, Font).Width + 8;
        if (needed > ClientSize.Width)
            flags |= TextFormatFlags.EndEllipsis;
        TextRenderer.DrawText(g, Text, Font, ClientRectangle, fore, flags);
    }

    /// <summary>
    /// Walks up the parent chain until an opaque BackColor is found.
    /// Transparent / Empty parents are skipped — clearing with those paints black.
    /// </summary>
    private Color ResolveSurfaceColor()
    {
        for (Control? c = Parent; c != null; c = c.Parent)
        {
            var bg = c.BackColor;
            if (bg.A == 255 && bg != Color.Transparent)
                return bg;
        }
        return Color.White;
    }

    private static GraphicsPath Rounded(RectangleF r, float radius)
    {
        var rad = Math.Min(radius, Math.Min(r.Width, r.Height) / 2f);
        var d = Math.Max(0.1f, rad * 2f);
        var path = new GraphicsPath();
        if (d <= 0.1f)
        {
            path.AddRectangle(r);
            return path;
        }
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
