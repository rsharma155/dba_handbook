// =============================================================================
// Module:   SqlOptima.SchemaCompare.Program
// Purpose:  Application entry point - WinForms bootstrap, global exception handling, and guaranteed resource cleanup on exit.
// Author:   Ravi Sharma
// Created:  2026-05-22
// Copyright (c) 2026 Ravi Sharma
// SPDX-License-Identifier: MIT
// =============================================================================

using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // Prevent unhandled exceptions from leaving orphan UI / silent crashes.
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
        {
            try
            {
                MessageBox.Show(
                    "An unexpected error occurred:\r\n\r\n" + e.Exception.Message,
                    "SQL Optima Schema Compare",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            catch { /* ignore */ }
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            try
            {
                var ex = e.ExceptionObject as Exception;
                MessageBox.Show(
                    "A fatal error occurred:\r\n\r\n" + (ex?.Message ?? e.ExceptionObject?.ToString()),
                    "SQL Optima Schema Compare",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            catch { /* ignore */ }
        };

        Application.ApplicationExit += (_, _) =>
        {
            try
            {
                RuntimeCleanup.ClearPasswordEnvironment();
                RuntimeCleanup.CleanupTempFolders(TimeSpan.FromMinutes(1));
                RuntimeCleanup.RequestMemoryReclaim();
            }
            catch { /* ignore */ }
        };

        MainForm? form = null;
        try
        {
            form = new MainForm();
            Application.Run(form);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Failed to start SQL Optima Schema Compare:\r\n\r\n" + ex.Message,
                "Startup error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        finally
        {
            try { form?.ShutdownResources(); } catch { /* ignore */ }
            try { form?.Dispose(); } catch { /* ignore */ }
            RuntimeCleanup.ClearPasswordEnvironment();
            RuntimeCleanup.CleanupTempFolders(TimeSpan.FromMinutes(1));
            RuntimeCleanup.RequestMemoryReclaim();
        }
    }
}
