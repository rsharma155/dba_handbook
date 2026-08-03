// =============================================================================
// Module:   SqlOptima.SchemaCompare.Services.ThemeSwitcher
// Purpose:  Runtime light/dark theme switching - swaps the UiTheme palette and
//           remaps colors of already-constructed controls (surfaces via a back
//           map, text/accents via a fore map) so the whole shell restyles live.
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
/// Applies a theme to live control trees. Owner-drawn controls read
/// <see cref="UiTheme"/> tokens at paint time and only need an Invalidate;
/// standard controls captured their colors at construction, so this walker
/// remaps every BackColor/ForeColor that belongs to the outgoing palette.
/// </summary>
public static class ThemeSwitcher
{
    /// <summary>
    /// Extra hard-coded surface colors used by the shell (light, dark) that are
    /// not UiTheme tokens - status bars, caption strips, highlight rows.
    /// </summary>
    private static readonly (Color Light, Color Dark)[] SurfaceLiterals =
    {
        (Color.FromArgb(248, 250, 252), Color.FromArgb(0x12, 0x1A, 0x28)),  // subtle bars
        (Color.FromArgb(255, 247, 237), Color.FromArgb(0x2E, 0x26, 0x16)),  // manual/warn amber
        (Color.FromArgb(255, 235, 238), Color.FromArgb(0x33, 0x1A, 0x1E)),  // failed row red
        (Color.FromArgb(0xEC, 0xF5, 0xFF), Color.FromArgb(0x16, 0x24, 0x38)), // source caption blue
        (Color.FromArgb(0xFE, 0xF3, 0xC7), Color.FromArgb(0x30, 0x2A, 0x14)), // target caption amber
        (Color.FromArgb(0xE5, 0xE7, 0xEB), Color.FromArgb(0x2A, 0x33, 0x46)), // splitter gray
    };

    private static readonly (Color Light, Color Dark)[] TextLiterals =
    {
        (Color.FromArgb(140, 40, 20), Color.FromArgb(0xE8, 0x9A, 0x7A)),     // manual script text
        (Color.FromArgb(0xC9, 0xD4, 0xE3), Color.FromArgb(0x3A, 0x46, 0x5C)), // empty-state glyph
    };

    /// <summary>
    /// Switches the global palette and restyles the given root controls
    /// (typically the main form). No-op when the palette already matches.
    /// </summary>
    public static void SwitchTo(bool dark, params Control[] roots)
    {
        if (UiTheme.IsDark == dark) return;
        UiTheme.SetDarkMode(dark);
        foreach (var root in roots)
            ApplyMaps(root, BuildBackMap(dark), BuildForeMap(dark));
    }

    /// <summary>
    /// Re-themes a freshly built control tree (e.g. a dialog) so any remaining
    /// light-palette literals match the active palette. No-op in light mode.
    /// </summary>
    public static void ApplyCurrentTo(Control root)
    {
        if (!UiTheme.IsDark) return;
        ApplyMaps(root, BuildBackMap(true), BuildForeMap(true));
    }

    // ------------------------------------------------------------------
    //  Map construction
    // ------------------------------------------------------------------

    private static Dictionary<int, Color> BuildBackMap(bool toDark)
    {
        var map = new Dictionary<int, Color>();
        void Add(Color light, Color dark)
        {
            var (from, to) = toDark ? (light, dark) : (dark, light);
            if (from.ToArgb() != to.ToArgb())
                map[from.ToArgb()] = to;
        }

        Add(UiTheme.Lt.AppBackground, UiTheme.Dk.AppBackground);
        Add(UiTheme.Lt.CardBackground, UiTheme.Dk.CardBackground);
        Add(UiTheme.Lt.CardBorder, UiTheme.Dk.CardBorder);
        Add(UiTheme.Lt.PanelBackground, UiTheme.Dk.PanelBackground);
        Add(UiTheme.Lt.InputBorder, UiTheme.Dk.InputBorder);
        Add(UiTheme.Lt.Neutral, UiTheme.Dk.Neutral);
        Add(UiTheme.Lt.NeutralHover, UiTheme.Dk.NeutralHover);
        Add(UiTheme.Lt.Primary, UiTheme.Dk.Primary);
        // InputBackground is White in light mode; the White->dark direction is
        // resolved per-control (inputs get InputBackground, surfaces CardBackground).
        Add(UiTheme.Lt.InputBackground, UiTheme.Dk.InputBackground);
        if (toDark)
            map[UiTheme.Lt.CardBackground.ToArgb()] = UiTheme.Dk.CardBackground;
        else
            map[UiTheme.Dk.InputBackground.ToArgb()] = UiTheme.Lt.InputBackground;

        foreach (var (light, dark) in SurfaceLiterals)
            Add(light, dark);
        return map;
    }

    private static Dictionary<int, Color> BuildForeMap(bool toDark)
    {
        var map = new Dictionary<int, Color>();
        void Add(Color light, Color dark)
        {
            var (from, to) = toDark ? (light, dark) : (dark, light);
            if (from.ToArgb() != to.ToArgb())
                map[from.ToArgb()] = to;
        }

        Add(UiTheme.Lt.TextPrimary, UiTheme.Dk.TextPrimary);
        Add(UiTheme.Lt.TextMuted, UiTheme.Dk.TextMuted);
        Add(UiTheme.Lt.Success, UiTheme.Dk.Success);
        Add(UiTheme.Lt.Danger, UiTheme.Dk.Danger);
        Add(UiTheme.Lt.Warning, UiTheme.Dk.Warning);
        // Primary/ChangeAccent share the same light value; prefer the brighter
        // accent for text so tree glyphs and links stay readable on dark.
        Add(UiTheme.Lt.ChangeAccent, UiTheme.Dk.ChangeAccent);
        Add(UiTheme.Lt.AddAccent, UiTheme.Dk.AddAccent);
        Add(UiTheme.Lt.ExtraAccent, UiTheme.Dk.ExtraAccent);
        Add(UiTheme.Lt.WarnAccent, UiTheme.Dk.WarnAccent);
        Add(UiTheme.Lt.BadgeIgnored, UiTheme.Dk.BadgeIgnored);

        foreach (var (light, dark) in TextLiterals)
            Add(light, dark);
        return map;
    }

    // ------------------------------------------------------------------
    //  Control tree walk
    // ------------------------------------------------------------------

    private static void ApplyMaps(Control root, Dictionary<int, Color> back, Dictionary<int, Color> fore)
    {
        Color MapBack(Color c) => Lookup(back, c);
        Color MapFore(Color c) => Lookup(fore, c);

        void Walk(Control c)
        {
            switch (c)
            {
                case ModernButton mb:
                    mb.RemapColors(MapBack, MapFore);
                    break;

                case DataGridView gv:
                    RemapGrid(gv, MapBack, MapFore);
                    break;

                default:
                    RemapGeneric(c, MapBack, MapFore);
                    break;
            }

            if (c is TreeView tv)
                RemapNodes(tv.Nodes, MapFore, MapBack);

            if (c is ToolStrip strip)
            {
                foreach (ToolStripItem item in strip.Items)
                {
                    item.ForeColor = MapFore(item.ForeColor);
                    item.BackColor = MapBack(item.BackColor);
                }
            }

            foreach (Control child in c.Controls)
                Walk(child);

            c.Invalidate();
        }

        Walk(root);
        root.Refresh();
    }

    private static Color Lookup(Dictionary<int, Color> map, Color c)
        => !c.IsEmpty && c != Color.Transparent && map.TryGetValue(c.ToArgb(), out var mapped) ? mapped : c;

    private static void RemapGeneric(Control c, Func<Color, Color> mapBack, Func<Color, Color> mapFore)
    {
        // Inputs get the dedicated input surface so they read as editable fields.
        if (c is TextBoxBase or ComboBox or NumericUpDown or ListBox or CheckedListBox or TreeView or ListView)
        {
            if (c.BackColor.ToArgb() == (UiTheme.IsDark ? UiTheme.Lt.InputBackground : UiTheme.Dk.InputBackground).ToArgb() ||
                c.BackColor.ToArgb() == (UiTheme.IsDark ? UiTheme.Lt.CardBackground : UiTheme.Dk.CardBackground).ToArgb())
                c.BackColor = UiTheme.InputBackground;
            else
                c.BackColor = mapBack(c.BackColor);
        }
        else if (c.BackColor != Color.Transparent)
        {
            c.BackColor = mapBack(c.BackColor);
        }

        c.ForeColor = mapFore(c.ForeColor);
    }

    private static void RemapGrid(DataGridView gv, Func<Color, Color> mapBack, Func<Color, Color> mapFore)
    {
        gv.EnableHeadersVisualStyles = false;
        gv.BackgroundColor = mapBack(gv.BackgroundColor);
        gv.GridColor = mapBack(gv.GridColor);
        RemapStyle(gv.DefaultCellStyle, mapBack, mapFore, applyDefaults: true);
        RemapStyle(gv.AlternatingRowsDefaultCellStyle, mapBack, mapFore, applyDefaults: false);
        RemapStyle(gv.RowHeadersDefaultCellStyle, mapBack, mapFore, applyDefaults: false);
        RemapStyle(gv.ColumnHeadersDefaultCellStyle, mapBack, mapFore, applyDefaults: false);
        foreach (DataGridViewRow row in gv.Rows)
            RemapStyle(row.DefaultCellStyle, mapBack, mapFore, applyDefaults: false);
    }

    private static void RemapStyle(DataGridViewCellStyle style, Func<Color, Color> mapBack,
        Func<Color, Color> mapFore, bool applyDefaults)
    {
        if (!style.BackColor.IsEmpty)
            style.BackColor = mapBack(style.BackColor);
        else if (applyDefaults)
            style.BackColor = UiTheme.CardBackground;

        if (!style.ForeColor.IsEmpty)
            style.ForeColor = mapFore(style.ForeColor);
        else if (applyDefaults)
            style.ForeColor = UiTheme.TextPrimary;

        if (!style.SelectionBackColor.IsEmpty)
            style.SelectionBackColor = mapBack(style.SelectionBackColor);
        else if (applyDefaults)
            style.SelectionBackColor = UiTheme.SidebarActive;

        if (!style.SelectionForeColor.IsEmpty)
            style.SelectionForeColor = mapFore(style.SelectionForeColor);
        else if (applyDefaults)
            style.SelectionForeColor = UiTheme.TextOnDark;
    }

    private static void RemapNodes(TreeNodeCollection nodes, Func<Color, Color> mapFore, Func<Color, Color> mapBack)
    {
        foreach (TreeNode node in nodes)
        {
            if (!node.ForeColor.IsEmpty)
                node.ForeColor = mapFore(node.ForeColor);
            if (!node.BackColor.IsEmpty)
                node.BackColor = mapBack(node.BackColor);
            RemapNodes(node.Nodes, mapFore, mapBack);
        }
    }
}
