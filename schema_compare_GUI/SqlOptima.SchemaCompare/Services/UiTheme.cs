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
/// </summary>
public static class UiTheme
{
    // Surfaces
    public static readonly Color AppBackground = Color.FromArgb(0xF5, 0xF7, 0xFA);
    public static readonly Color HeaderBackground = Color.FromArgb(0x0B, 0x12, 0x20);
    public static readonly Color SidebarBackground = Color.FromArgb(0x0B, 0x12, 0x20);
    public static readonly Color SidebarActive = Color.FromArgb(0x13, 0x2B, 0x3A);
    public static readonly Color HeaderAccent = Color.FromArgb(0x18, 0xB6, 0x63);
    public static readonly Color CardBackground = Color.White;
    public static readonly Color CardBorder = Color.FromArgb(0xE4, 0xE8, 0xEE);
    public static readonly Color PanelBackground = Color.FromArgb(0xF9, 0xFA, 0xFB);
    public static readonly Color InputBorder = Color.FromArgb(0xD5, 0xDC, 0xE5);
    public static readonly Color InputFocus = Color.FromArgb(0x25, 0x63, 0xEB);

    // Text
    public static readonly Color TextPrimary = Color.FromArgb(0x1F, 0x29, 0x37);
    public static readonly Color TextMuted = Color.FromArgb(0x6B, 0x72, 0x80);
    public static readonly Color TextOnDark = Color.White;
    public static readonly Color TextOnDarkMuted = Color.FromArgb(0x9C, 0xA3, 0xAF);

    // Primary CTA - teal/green per mockup ("Compare Schemas ->", "Compare Now")
    public static readonly Color Cta = Color.FromArgb(0x18, 0xB6, 0x63);
    public static readonly Color CtaHover = Color.FromArgb(0x14, 0x98, 0x54);

    // Accents
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

    // Difference accents (tree glyphs, overview cards)
    public static readonly Color AddAccent = Color.FromArgb(0x16, 0xA3, 0x4A);
    public static readonly Color ChangeAccent = Color.FromArgb(0x25, 0x63, 0xEB);
    public static readonly Color ExtraAccent = Color.FromArgb(0xDC, 0x26, 0x26);
    public static readonly Color WarnAccent = Color.FromArgb(0xF5, 0x9E, 0x0B);

    // Result badges per mockup: Added / Removed / Changed / Identical / Ignored
    public static readonly Color BadgeAdded = Color.FromArgb(0x16, 0xA3, 0x4A);
    public static readonly Color BadgeRemoved = Color.FromArgb(0xDC, 0x26, 0x26);
    public static readonly Color BadgeChanged = Color.FromArgb(0xF5, 0x9E, 0x0B);
    public static readonly Color BadgeIdentical = Color.FromArgb(0x25, 0x63, 0xEB);
    public static readonly Color BadgeIgnored = Color.FromArgb(0x6B, 0x72, 0x80);

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
        b.ApplyColors(Color.White, NeutralText, NeutralHover, Neutral);
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
        b.ApplyColors(Color.White, Cta, Color.FromArgb(0xEC, 0xF8, 0xF2), Color.FromArgb(0xD8, 0xF0, 0xE4));
        b.BorderColor = Cta;
        b.CornerRadius = 8;
        b.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
    }

    public static void StyleTextBox(TextBox tb)
    {
        tb.BorderStyle = BorderStyle.FixedSingle;
        tb.BackColor = Color.White;
        tb.ForeColor = TextPrimary;
        tb.Font = UiFont(10f);
    }

    public static void StyleCombo(ComboBox cb)
    {
        cb.FlatStyle = FlatStyle.Flat;
        cb.BackColor = Color.White;
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
        nud.BackColor = Color.White;
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
