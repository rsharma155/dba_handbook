using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Tests;

public class ConnectionInfoTests
{
    [Fact]
    public void BuildDataSource_AppendsPort_WhenMissing()
    {
        var c = new ConnectionInfo { Instance = "sql01", Port = 1433 };
        Assert.Equal("sql01,1433", c.BuildDataSource());
    }

    [Fact]
    public void BuildDataSource_DoesNotDuplicatePort()
    {
        var c = new ConnectionInfo { Instance = "sql01,1444", Port = 1433 };
        Assert.Equal("sql01,1444", c.BuildDataSource());
    }

    [Fact]
    public void BuildConnectionString_WindowsAuth_UsesIntegratedSecurity()
    {
        var c = new ConnectionInfo
        {
            Instance = ".",
            Auth = AuthMode.Windows,
            TrustServerCertificate = true
        };
        var cs = c.BuildConnectionString("master");
        Assert.Contains("Integrated Security=True", cs, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("User ID=", cs, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void BuildConnectionString_SqlAuth_IncludesUser()
    {
        var c = new ConnectionInfo
        {
            Instance = "host",
            Auth = AuthMode.Sql,
            UserName = "sa",
            Password = "secret",
            TrustServerCertificate = true
        };
        var cs = c.BuildConnectionString("Sales");
        Assert.Contains("User ID=sa", cs, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Initial Catalog=Sales", cs, StringComparison.OrdinalIgnoreCase);
    }
}

public class DifferenceItemTests
{
    [Theory]
    [InlineData("Missing in Target", DiffKind.Add, "Add to Target")]
    [InlineData("Definition Mismatch", DiffKind.Update, "Update on Target")]
    [InlineData("Extra in Target", DiffKind.Extra, "Extra on Target")]
    [InlineData("Something else", DiffKind.Other, "Something else")]
    public void Kind_And_ActionLabel_MapStatus(string status, DiffKind kind, string action)
    {
        var d = new DifferenceItem { Status = status };
        Assert.Equal(kind, d.Kind);
        Assert.Equal(action, d.ActionLabel);
    }
}
