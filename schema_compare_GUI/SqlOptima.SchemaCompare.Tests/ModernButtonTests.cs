// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.ModernButtonTests
// Purpose:  Verifies ModernButton paints clean edges (no dark corner border on CTAs).
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ModernButtonTests
{
    [StaFact]
    public void CtaButton_HasNoDarkOutlineBorder()
    {
        using var btn = new ModernButton { Text = "Compare Now" };
        UiTheme.StyleCta(btn);
        Assert.True(btn.BorderColor.IsEmpty || btn.BorderColor.A == 0,
            "Solid CTA buttons must not draw a dark outline (causes corner spots).");
    }

    [StaFact]
    public void GhostButton_UsesTealBorderNotDarkCorners()
    {
        using var btn = new ModernButton { Text = "Test Connection" };
        UiTheme.StyleGhost(btn);
        Assert.Equal(UiTheme.Cta, btn.BorderColor);
        Assert.Equal(Color.White, btn.BackColor);
    }

    [StaFact]
    public void SecondaryButton_UsesLightGrayBorder()
    {
        using var btn = new ModernButton { Text = "Browse" };
        UiTheme.StyleSecondary(btn);
        Assert.False(btn.BorderColor.IsEmpty);
        Assert.True(btn.BorderColor.GetBrightness() > 0.7f,
            "Secondary border must stay light — dark borders create corner spots.");
    }

    [StaFact]
    public void Button_PaintsOpaqueSurface_NotTransparentClear()
    {
        // Regression: Graphics.Clear(Transparent) paints black corner spots.
        using var host = new Panel { BackColor = Color.White, Size = new Size(200, 80) };
        using var btn = new ModernButton { Text = "Browse", Size = new Size(96, 32) };
        UiTheme.StyleSecondary(btn);
        host.Controls.Add(btn);
        using var bmp = new Bitmap(btn.Width, btn.Height);
        btn.DrawToBitmap(bmp, new Rectangle(0, 0, btn.Width, btn.Height));
        // Corner pixels must be near white (surface), never near-black.
        foreach (var pt in new[] { new Point(0, 0), new Point(btn.Width - 1, 0),
                     new Point(0, btn.Height - 1), new Point(btn.Width - 1, btn.Height - 1) })
        {
            var c = bmp.GetPixel(pt.X, pt.Y);
            Assert.True(c.R > 200 && c.G > 200 && c.B > 200,
                $"Corner {pt} is dark ({c.R},{c.G},{c.B}) — expected opaque light surface.");
        }
    }
}
