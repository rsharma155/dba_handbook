using System.Drawing.Drawing2D;
using System.Drawing.Text;

namespace SqlOptima.SchemaCompare.Forms;

/// <summary>
/// Owner-drawn button that always paints its caption in a high-contrast colour.
/// Avoids WinForms FlatStyle quirks where ForeColor can be ignored / washed out.
/// </summary>
public sealed class ModernButton : Button
{
    private Color _hoverBack;
    private Color _pressBack;
    private bool _hover;
    private bool _press;

    public int CornerRadius { get; set; } = 6;

    public ModernButton()
    {
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        FlatAppearance.MouseOverBackColor = Color.Transparent;
        FlatAppearance.MouseDownBackColor = Color.Transparent;
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
            ControlStyles.ResizeRedraw |
            ControlStyles.SupportsTransparentBackColor,
            true);
    }

    public void ApplyColors(Color back, Color fore, Color? hover = null, Color? press = null)
    {
        BackColor = back;
        ForeColor = fore;
        _hoverBack = hover ?? ControlPaint.Light(back, 0.08f);
        _pressBack = press ?? ControlPaint.Dark(back, 0.08f);
        Invalidate();
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
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        g.Clear(Parent?.BackColor ?? SystemColors.Control);

        var back = !Enabled
            ? Color.FromArgb(210, 216, 224)
            : _press ? (_pressBack.IsEmpty ? ControlPaint.Dark(BackColor, 0.1f) : _pressBack)
            : _hover ? (_hoverBack.IsEmpty ? ControlPaint.Light(BackColor, 0.1f) : _hoverBack)
            : BackColor;

        var fore = !Enabled
            ? Color.FromArgb(120, 130, 145)
            : ForeColor;

        var rect = new Rectangle(0, 0, Width - 1, Height - 1);
        using (var path = Rounded(rect, CornerRadius))
        using (var brush = new SolidBrush(back))
        {
            g.FillPath(brush, path);
            using var border = new Pen(ControlPaint.Dark(back, 0.12f));
            g.DrawPath(border, path);
        }

        TextRenderer.DrawText(
            g,
            Text,
            Font,
            ClientRectangle,
            fore,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
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
