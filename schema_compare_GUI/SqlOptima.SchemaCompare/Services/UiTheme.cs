// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.UiTheme
// Purpose:  Central design tokens (colors, fonts, spacing) and control styling
//           helpers for the mockup-aligned shell UI. Single source of truth so
//           no screen invents its own palette or truncates captions.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing;
using System.Windows.Forms;
using SqlOptima.SchemaCompare.Forms;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Design tokens per review_feedback3.md and the UI mockup:
/// light workspace, dark navy chrome, single teal/green primary CTA.
/// Tokens are mutable so <see cref="SetDarkMode"/> can swap the whole palette;
/// owner-drawn controls read them at paint time and only need an Invalidate.
/// </summary>
public static class UiTheme
{
    /// <summary>Light palette (default) - values match the original mockup tokens.</summary>
    public static class Lt
    {
        public static readonly Color AppBackground = Color.FromArgb(0xF5, 0xF7, 0xFA);
        public static readonly Color HeaderBackground = Color.FromArgb(0x0B, 0x12, 0x20);
        public static readonly Color SidebarBackground = Color.FromArgb(0x0B, 0x12, 0x20);
        public static readonly Color SidebarActive = Color.FromArgb(0x13, 0x2B, 0x3A);
        public static readonly Color HeaderAccent = Color.FromArgb(0x18, 0xB6, 0x63);
        public static readonly Color CardBackground = Color.White;
        public static readonly Color CardBorder = Color.FromArgb(0xE4, 0xE8, 0xEE);
        public static readonly Color PanelBackground = Color.FromArgb(0xF9, 0xFA, 0xFB);
        public static readonly Color InputBackground = Color.White;
        public static readonly Color InputBorder = Color.FromArgb(0xD5, 0xDC, 0xE5);
        public static readonly Color InputFocus = Color.FromArgb(0x25, 0x63, 0xEB);
        public static readonly Color TextPrimary = Color.FromArgb(0x1F, 0x29, 0x37);
        public static readonly Color TextMuted = Color.FromArgb(0x6B, 0x72, 0x80);
        public static readonly Color TextOnDark = Color.White;
        public static readonly Color TextOnDarkMuted = Color.FromArgb(0x9C, 0xA3, 0xAF);
        public static readonly Color Cta = Color.FromArgb(0x18, 0xB6, 0x63);
        public static readonly Color CtaHover = Color.FromArgb(0x14, 0x98, 0x54);
        public static readonly Color Primary = Color.FromArgb(0x25, 0x63, 0xEB);
        public static readonly Color PrimaryHover = Color.FromArgb(0x1D, 0x4E, 0xD8);
        public static readonly Color Success = Color.FromArgb(0x16, 0xA3, 0x4A);
        public static readonly Color SuccessHover = Color.FromArgb(0x15, 0x80, 0x3D);
        public static readonly Color Danger = Color.FromArgb(0xDC, 0x26, 0x26);
        public static readonly Color DangerHover = Color.FromArgb(0xB9, 0x1C, 0x1C);
        public static readonly Color Warning = Color.FromArgb(0xF5, 0x9E, 0x0B);
        public static readonly Color Neutral = Color.FromArgb(0xF3, 0xF4, 0xF6);
        public static readonly Color NeutralHover = Color.FromArgb(0xEE, 0xF3, 0xF9);
        public static readonly Color NeutralText = Color.FromArgb(0x1F, 0x29, 0x37);
        public static readonly Color AddAccent = Color.FromArgb(0x16, 0xA3, 0x4A);
        public static readonly Color ChangeAccent = Color.FromArgb(0x25, 0x63, 0xEB);
        public static readonly Color ExtraAccent = Color.FromArgb(0xDC, 0x26, 0x26);
        public static readonly Color WarnAccent = Color.FromArgb(0xF5, 0x9E, 0x0B);
        public static readonly Color BadgeAdded = Color.FromArgb(0x16, 0xA3, 0x4A);
        public static readonly Color BadgeRemoved = Color.FromArgb(0xDC, 0x26, 0x26);
        public static readonly Color BadgeChanged = Color.FromArgb(0xF5, 0x9E, 0x0B);
        public static readonly Color BadgeIdentical = Color.FromArgb(0x25, 0x63, 0xEB);
        public static readonly Color BadgeIgnored = Color.FromArgb(0x6B, 0x72, 0x80);
    }

    /// <summary>Dark palette - navy workspace matching the existing chrome.</summary>
    public static class Dk
    {
        public static readonly Color AppBackground = Color.FromArgb(0x0F, 0x15, 0x22);
        public static readonly Color HeaderBackground = Color.FromArgb(0x0B, 0x12, 0x20);
        public static readonly Color SidebarBackground = Color.FromArgb(0x0B, 0x12, 0x20);
        public static readonly Color SidebarActive = Color.FromArgb(0x13, 0x2B, 0x3A);
        public static readonly Color HeaderAccent = Color.FromArgb(0x18, 0xB6, 0x63);
        public static readonly Color CardBackground = Color.FromArgb(0x16, 0x20, 0x2E);
        public static readonly Color CardBorder = Color.FromArgb(0x26, 0x33, 0x49);
        public static readonly Color PanelBackground = Color.FromArgb(0x12, 0x1A, 0x28);
        public static readonly Color InputBackground = Color.FromArgb(0x10, 0x18, 0x26);
        public static readonly Color InputBorder = Color.FromArgb(0x33, 0x40, 0x5A);
        public static readonly Color InputFocus = Color.FromArgb(0x3B, 0x82, 0xF6);
        public static readonly Color TextPrimary = Color.FromArgb(0xE5, 0xEA, 0xF2);
        public static readonly Color TextMuted = Color.FromArgb(0x94, 0xA0, 0xB4);
        public static readonly Color TextOnDark = Color.White;
        public static readonly Color TextOnDarkMuted = Color.FromArgb(0x9C, 0xA3, 0xAF);
        public static readonly Color Cta = Color.FromArgb(0x18, 0xB6, 0x63);
        public static readonly Color CtaHover = Color.FromArgb(0x14, 0x98, 0x54);
        public static readonly Color Primary = Color.FromArgb(0x3B, 0x82, 0xF6);
        public static readonly Color PrimaryHover = Color.FromArgb(0x25, 0x63, 0xEB);
        public static readonly Color Success = Color.FromArgb(0x22, 0xC5, 0x5E);
        public static readonly Color SuccessHover = Color.FromArgb(0x16, 0xA3, 0x4A);
        public static readonly Color Danger = Color.FromArgb(0xF8, 0x71, 0x71);
        public static readonly Color DangerHover = Color.FromArgb(0xDC, 0x26, 0x26);
        public static readonly Color Warning = Color.FromArgb(0xFB, 0xBF, 0x24);
        public static readonly Color Neutral = Color.FromArgb(0x1E, 0x2A, 0x3C);
        public static readonly Color NeutralHover = Color.FromArgb(0x25, 0x33, 0x49);
        public static readonly Color NeutralText = Color.FromArgb(0xE5, 0xEA, 0xF2);
        public static readonly Color AddAccent = Color.FromArgb(0x22, 0xC5, 0x5E);
        public static readonly Color ChangeAccent = Color.FromArgb(0x60, 0xA5, 0xFA);
        public static readonly Color ExtraAccent = Color.FromArgb(0xF8, 0x71, 0x71);
        public static readonly Color WarnAccent = Color.FromArgb(0xFB, 0xBF, 0x24);
        public static readonly Color BadgeAdded = Color.FromArgb(0x22, 0xC5, 0x5E);
        public static readonly Color BadgeRemoved = Color.FromArgb(0xF8, 0x71, 0x71);
        public static readonly Color BadgeChanged = Color.FromArgb(0xFB, 0xBF, 0x24);
        public static readonly Color BadgeIdentical = Color.FromArgb(0x60, 0xA5, 0xFA);
        public static readonly Color BadgeIgnored = Color.FromArgb(0x94, 0xA0, 0xB4);
    }

    /// <summary>True while the dark palette is active.</summary>
    public static bool IsDark { get; private set; }

    // Surfaces
    public static Color AppBackground = Lt.AppBackground;
    public static Color HeaderBackground = Lt.HeaderBackground;
    public static Color SidebarBackground = Lt.SidebarBackground;
    public static Color SidebarActive = Lt.SidebarActive;
    public static Color HeaderAccent = Lt.HeaderAccent;
    public static Color CardBackground = Lt.CardBackground;
    public static Color CardBorder = Lt.CardBorder;
    public static Color PanelBackground = Lt.PanelBackground;
    public static Color InputBackground = Lt.InputBackground;
    public static Color InputBorder = Lt.InputBorder;
    public static Color InputFocus = Lt.InputFocus;

    // Text
    public static Color TextPrimary = Lt.TextPrimary;
    public static Color TextMuted = Lt.TextMuted;
    public static Color TextOnDark = Lt.TextOnDark;
    public static Color TextOnDarkMuted = Lt.TextOnDarkMuted;

    // Primary CTA - teal/green per mockup ("Compare Schemas ->", "Compare Now")
    public static Color Cta = Lt.Cta;
    public static Color CtaHover = Lt.CtaHover;

    // Accents
    public static Color Primary = Lt.Primary;
    public static Color PrimaryHover = Lt.PrimaryHover;
    public static Color Success = Lt.Success;
    public static Color SuccessHover = Lt.SuccessHover;
    public static Color Danger = Lt.Danger;
    public static Color DangerHover = Lt.DangerHover;
    public static Color Warning = Lt.Warning;
    public static Color Neutral = Lt.Neutral;
    public static Color NeutralHover = Lt.NeutralHover;
    public static Color NeutralText = Lt.NeutralText;

    // Difference accents (tree glyphs, overview cards)
    public static Color AddAccent = Lt.AddAccent;
    public static Color ChangeAccent = Lt.ChangeAccent;
    public static Color ExtraAccent = Lt.ExtraAccent;
    public static Color WarnAccent = Lt.WarnAccent;

    // Result badges per mockup: Added / Removed / Changed / Identical / Ignored
    public static Color BadgeAdded = Lt.BadgeAdded;
    public static Color BadgeRemoved = Lt.BadgeRemoved;
    public static Color BadgeChanged = Lt.BadgeChanged;
    public static Color BadgeIdentical = Lt.BadgeIdentical;
    public static Color BadgeIgnored = Lt.BadgeIgnored;

    /// <summary>
    /// Switches every token to the requested palette. Existing controls must be
    /// restyled afterwards (see <c>ThemeSwitcher</c>); newly created controls
    /// pick up the active palette automatically.
    /// </summary>
    public static void SetDarkMode(bool dark)
    {
        IsDark = dark;
        var source = dark ? typeof(Dk) : typeof(Lt);
        foreach (var field in typeof(UiTheme).GetFields(
                     System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static))
        {
            if (field.FieldType != typeof(Color) || field.IsInitOnly) continue;
            var palette = source.GetField(field.Name,
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static);
            if (palette != null)
                field.SetValue(null, palette.GetValue(null));
        }
    }

    // 8-point spacing system
    public const int Grid = 8;
    public const int Margin = 16;
    public const int PanelGap = 24;
    public const int ControlGap = 12;
    public const int ButtonHeight = 40;
    public const int InputHeight = 32;

    /// <summary>Segoe MDL2 Assets glyph font for consistent single-family icons.</summary>
    public static Font IconFont(float size = 12f) => new("Segoe MDL2 Assets", size, FontStyle.Regular);

    public static Font UiFont(float size = 10f, FontStyle style = FontStyle.Regular)
        => new("Segoe UI", size, style);

    public static Font SemiBold(float size = 10f)
        => new("Segoe UI", size, FontStyle.Bold);

    public static Font TitleFont() => new("Segoe UI", 13f, FontStyle.Bold);
    public static Font SectionFont() => new("Segoe UI", 11.5f, FontStyle.Bold);

    /// <summary>Sizes a button so its caption can never be ellipsized.</summary>
    public static void FitButton(ModernButton b, int minWidth = 0, int padding = 28)
    {
        b.AutoEllipsis = false;
        var w = TextRenderer.MeasureText(b.Text, b.Font).Width + padding;
        b.Width = Math.Max(minWidth, w);
    }

    /// <summary>Primary teal CTA - only Compare actions use this style.</summary>
    public static void StyleCta(ModernButton b)
    {
        b.ApplyColors(Cta, TextOnDark, CtaHover, ControlPaint.Dark(Cta, 0.12f));
        b.Height = ButtonHeight;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
    }

    public static void StylePrimary(ModernButton b)
    {
        b.ApplyColors(Primary, TextOnDark, PrimaryHover, ControlPaint.Dark(Primary, 0.12f));
        b.Height = ButtonHeight;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
    }

    public static void StyleSuccess(ModernButton b)
    {
        b.ApplyColors(Cta, TextOnDark, CtaHover, ControlPaint.Dark(Cta, 0.12f));
        b.Height = ButtonHeight;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 10.5f, FontStyle.Bold);
    }

    public static void StyleDanger(ModernButton b)
    {
        b.ApplyColors(Danger, TextOnDark, DangerHover, ControlPaint.Dark(Danger, 0.12f));
        b.Height = ButtonHeight;
        b.CornerRadius = 8;
    }

    public static void StyleSecondary(ModernButton b)
    {
        b.ApplyColors(CardBackground, NeutralText, NeutralHover, Neutral);
        b.BorderColor = InputBorder;
        b.Height = Math.Max(32, b.Height);
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
    }

    /// <summary>Secondary button that sits on the dark header.</summary>
    public static void StyleHeaderSecondary(ModernButton b)
    {
        b.ApplyColors(Color.FromArgb(0x16, 0x22, 0x36), TextOnDark,
            Color.FromArgb(0x1E, 0x2D, 0x45), Color.FromArgb(0x10, 0x1A, 0x2C));
        b.Height = 34;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
    }

    public static void StyleGhost(ModernButton b)
    {
        b.ApplyColors(CardBackground, Cta,
            IsDark ? Color.FromArgb(0x1A, 0x2C, 0x28) : Color.FromArgb(0xEC, 0xF8, 0xF2),
            IsDark ? Color.FromArgb(0x14, 0x24, 0x20) : Color.FromArgb(0xD8, 0xF0, 0xE4));
        b.BorderColor = Cta;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
    }

    public static void StyleTextBox(TextBox tb)
    {
        tb.BorderStyle = BorderStyle.FixedSingle;
        tb.BackColor = InputBackground;
        tb.ForeColor = TextPrimary;
        tb.Font = UiFont(10f);
    }

    public static void StyleCombo(ComboBox cb)
    {
        cb.FlatStyle = FlatStyle.Flat;
        cb.BackColor = InputBackground;
        cb.ForeColor = TextPrimary;
        cb.Font = UiFont(10f);
    }

    public static void StyleCheckBox(CheckBox cb)
    {
        cb.AutoSize = true;
        cb.FlatStyle = FlatStyle.System;
        cb.UseVisualStyleBackColor = true;
        cb.Font = UiFont(10f);
        cb.ForeColor = TextPrimary;
        cb.Padding = new Padding(0, 2, 0, 2);
        cb.Margin = new Padding(0);
        // Prevent WinForms from ellipsizing caption under DPI / tight parents.
        cb.AutoEllipsis = false;
        cb.MaximumSize = Size.Empty;
    }

    public static void StyleNumeric(NumericUpDown nud)
    {
        nud.BorderStyle = BorderStyle.FixedSingle;
        nud.BackColor = InputBackground;
        nud.ForeColor = TextPrimary;
        nud.Font = UiFont(10f);
        nud.Height = InputHeight;
    }

    public static Label MakeLabel(string text, int x, int y, bool muted = true) => new()
    {
        Text = text,
        Location = new Point(x, y),
        AutoSize = true,
        ForeColor = muted ? TextMuted : TextPrimary,
        Font = UiFont(9.5f)
    };

    public static Label MakeSectionTitle(string text, int x, int y) => new()
    {
        Text = text,
        Location = new Point(x, y),
        AutoSize = true,
        ForeColor = TextPrimary,
        Font = SemiBold(11f)
    };
}
