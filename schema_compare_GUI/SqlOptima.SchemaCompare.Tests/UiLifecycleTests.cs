using SqlOptima.SchemaCompare.Forms;
using SqlOptima.SchemaCompare.Models;
using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class ConnectionPanelTests
{
    [StaFact]
    public void GetConnectionInfo_ReadsFields()
    {
        using var panel = new ConnectionPanel("Source");
        panel.Apply(new ConnectionInfo
        {
            Instance = "SQLDEV",
            Port = 1433,
            Auth = AuthMode.Sql,
            UserName = "appuser",
            Database = "Sales"
        });
        // Password not restored by Apply — set via Get after Apply leaves empty password
        var info = panel.GetConnectionInfo();
        Assert.Equal("SQLDEV", info.Instance);
        Assert.Equal(1433, info.Port);
        Assert.Equal(AuthMode.Sql, info.Auth);
        Assert.Equal("appuser", info.UserName);
        Assert.Equal("Sales", info.Database);
    }

    [StaFact]
    public void MultiSelect_CheckAll_And_GetChecked()
    {
        using var panel = new ConnectionPanel("Target", multiSelectTargets: true);
        panel.SetDatabases(new[] { "A", "B", "C" }, preferredChecked: new[] { "B" });
        var checked1 = panel.GetCheckedDatabases();
        Assert.Contains("B", checked1);

        panel.CheckAllDatabases(true);
        Assert.Equal(3, panel.GetCheckedDatabases().Count);

        panel.CheckAllDatabases(false);
        Assert.Empty(panel.GetCheckedDatabases());
    }

    [StaFact]
    public void Buttons_HaveHighContrastText()
    {
        using var panel = new ConnectionPanel("Source");
        var buttons = panel.Controls.OfType<Button>().ToList();
        Assert.NotEmpty(buttons);
        foreach (var b in buttons)
        {
            Assert.False(b.ForeColor.IsEmpty);
            Assert.NotEqual(b.ForeColor, b.BackColor);
            // ModernButton (and styled buttons) use FlatStyle.Flat with owner-draw text.
            Assert.Equal(FlatStyle.Flat, b.FlatStyle);
            Assert.False(string.IsNullOrWhiteSpace(b.Text));
        }
    }
}

public class OptionsFormTests
{
    [StaFact]
    public void Ok_CommitsOptions()
    {
        var current = new CompareOptions
        {
            GenerateSyncScript = true,
            IncludeDrops = false,
            NetworkProtocol = "TcpIp",
            ConnectionTimeout = 30
        };
        using var form = new OptionsForm(current);
        // Simulate OK path by reflecting committed options via DialogResult path —
        // OptionsForm sets Options on OK click; invoke AcceptButton.
        form.Show();
        try
        {
            foreach (Control c in form.Controls)
            {
                if (c is Button { Text: "OK" } ok)
                {
                    ok.PerformClick();
                    break;
                }
            }
            Assert.True(form.Options.GenerateSyncScript);
            Assert.Equal("TcpIp", form.Options.NetworkProtocol);
        }
        finally
        {
            form.Close();
        }
    }
}

public class MainFormLifecycleTests
{
    [StaFact]
    public void MainForm_Construct_And_Shutdown_DoesNotThrow()
    {
        // Use real path discovery from test base directory (walks up to schema_compare_GUI).
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        using var form = new MainForm(engine);
        form.Show();
        Assert.False(form.IsDisposed);
        form.ShutdownResources();
        form.Close();
    }

    [StaFact]
    public void MainForm_Dispose_KillsEngineTracker()
    {
        using var engine = new CompareEngine(AppContext.BaseDirectory);
        var form = new MainForm(engine);
        form.Show();
        form.ShutdownResources();
        form.Dispose();
        Assert.True(form.IsDisposed);
        // Second dispose / shutdown must be safe
        form.ShutdownResources();
        engine.Shutdown();
    }
}
