using System.Drawing;
using System.Windows.Forms;
using SqlOptima.SchemaCompare.Forms;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// High-contrast modern palette + helpers. Button captions are painted by
/// <see cref="ModernButton"/> so they stay readable on every Windows theme.
/// </summary>
public static class UiTheme
{
    public static readonly Color AppBackground = Color.FromArgb(236, 241, 247);
    public static readonly Color HeaderBackground = Color.FromArgb(15, 32, 56);
    public static readonly Color HeaderAccent = Color.FromArgb(56, 189, 248);
    public static readonly Color CardBackground = Color.White;
    public static readonly Color CardBorder = Color.FromArgb(203, 213, 225);
    public static readonly Color InputBorder = Color.FromArgb(148, 163, 184);
    public static readonly Color InputFocus = Color.FromArgb(37, 99, 235);

    public static readonly Color TextPrimary = Color.FromArgb(15, 23, 42);
    public static readonly Color TextMuted = Color.FromArgb(71, 85, 105);
    public static readonly Color TextOnDark = Color.White;
    public static readonly Color TextOnDarkMuted = Color.FromArgb(186, 230, 253);

    public static readonly Color Primary = Color.FromArgb(29, 78, 216);
    public static readonly Color PrimaryHover = Color.FromArgb(30, 64, 175);
    public static readonly Color Success = Color.FromArgb(21, 128, 61);
    public static readonly Color SuccessHover = Color.FromArgb(22, 101, 52);
    public static readonly Color Danger = Color.FromArgb(185, 28, 28);
    public static readonly Color DangerHover = Color.FromArgb(153, 27, 27);
    public static readonly Color Warning = Color.FromArgb(180, 83, 9);
    public static readonly Color Neutral = Color.FromArgb(241, 245, 249);
    public static readonly Color NeutralHover = Color.FromArgb(226, 232, 240);
    public static readonly Color NeutralText = Color.FromArgb(15, 23, 42);

    public static Font UiFont(float size = 9.5f, FontStyle style = FontStyle.Regular)
        => new("Segoe UI", size, style);

    public static Font SemiBold(float size = 9.5f)
        => new("Segoe UI", size, FontStyle.Bold);

    public static void StylePrimary(ModernButton b)
        => b.ApplyColors(Primary, TextOnDark, PrimaryHover, ControlPaint.Dark(Primary, 0.15f));

    public static void StyleSuccess(ModernButton b)
        => b.ApplyColors(Success, TextOnDark, SuccessHover, ControlPaint.Dark(Success, 0.15f));

    public static void StyleDanger(ModernButton b)
        => b.ApplyColors(Danger, TextOnDark, DangerHover, ControlPaint.Dark(Danger, 0.15f));

    public static void StyleSecondary(ModernButton b)
        => b.ApplyColors(Neutral, NeutralText, NeutralHover, ControlPaint.Dark(Neutral, 0.08f));

    public static void StyleGhost(ModernButton b)
        => b.ApplyColors(CardBackground, Primary, Neutral, NeutralHover);

    /// <summary>Legacy Button fallback (prefer ModernButton).</summary>
    public static Button StyleSecondaryLegacy(Button b)
    {
        b.FlatStyle = FlatStyle.Flat;
        b.UseVisualStyleBackColor = false;
        b.BackColor = Neutral;
        b.ForeColor = NeutralText;
        b.Font = SemiBold(9.5f);
        b.FlatAppearance.BorderSize = 1;
        b.FlatAppearance.BorderColor = CardBorder;
        b.FlatAppearance.MouseOverBackColor = NeutralHover;
        b.Cursor = Cursors.Hand;
        if (b.Height < 32) b.Height = 32;
        return b;
    }

    public static void StyleTextBox(TextBox tb)
    {
        tb.BorderStyle = BorderStyle.FixedSingle;
        tb.BackColor = Color.White;
        tb.ForeColor = TextPrimary;
        tb.Font = UiFont(9.5f);
    }

    public static void StyleCombo(ComboBox cb)
    {
        cb.FlatStyle = FlatStyle.Flat;
        cb.BackColor = Color.White;
        cb.ForeColor = TextPrimary;
        cb.Font = UiFont(9.5f);
    }

    public static Label MakeLabel(string text, int x, int y, bool muted = true) => new()
    {
        Text = text,
        Location = new Point(x, y),
        AutoSize = true,
        ForeColor = muted ? TextMuted : TextPrimary,
        Font = UiFont(9f)
    };
}
