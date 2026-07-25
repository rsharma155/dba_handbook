// =============================================================================
// Module:   SqlOptima.SchemaCompare.Tests.UiSnapshotTests
// Purpose:  Opt-in visual snapshot - renders MainForm to a PNG so the shell can
//           be compared against the design mockup. Set SQLOPTIMA_SNAPSHOT=1.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using System.Drawing.Imaging;
using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class UiSnapshotTests
{
    [StaFact]
    public void RenderMainForm_ToPng_WhenRequested()
    {
        if (Environment.GetEnvironmentVariable("SQLOPTIMA_SNAPSHOT") != "1")
            return; // opt-in only; not part of the normal suite

        Environment.SetEnvironmentVariable("SQLOPTIMA_NO_SETTINGS", "1");
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        using var form = new MainForm(engine);
        form.StartPosition = FormStartPosition.Manual;
        form.Location = new Point(-4000, -4000); // render off-screen
        form.Show();
        Application.DoEvents();

        using var bmp = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(bmp, new Rectangle(0, 0, form.Width, form.Height));
        var path = Path.Combine(AppContext.BaseDirectory, "mainform_snapshot.png");
        bmp.Save(path, ImageFormat.Png);
        form.Close();

        Assert.True(File.Exists(path));
    }
}
