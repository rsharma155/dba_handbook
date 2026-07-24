using SqlOptima.SchemaCompare.Services;

namespace SqlOptima.SchemaCompare.Tests;

public class FormValidatorTests
{
    [Fact]
    public void ValidateServer_RequiresHost()
    {
        var r = FormValidator.ValidateServer(new Models.ConnectionInfo { Instance = "" }, "Source");
        Assert.False(r.Ok);
        Assert.Contains(r.Errors, e => e.Contains("server host", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void ValidateServer_SqlAuthRequiresCredentials()
    {
        var r = FormValidator.ValidateServer(new Models.ConnectionInfo
        {
            Instance = "SQLDEV",
            Auth = Models.AuthMode.Sql
        }, "Source");
        Assert.False(r.Ok);
        Assert.Contains(r.Errors, e => e.Contains("user", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(r.Errors, e => e.Contains("password", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void ValidateCompare_OneToMany_NeedsTargetsOrList()
    {
        var r = FormValidator.ValidateCompare(
            new Models.ConnectionInfo { Instance = "S", Database = "Db" },
            new Models.ConnectionInfo { Instance = "T" },
            Models.CompareMode.OneToMany,
            Array.Empty<string>(),
            "");
        Assert.False(r.Ok);
    }

    [Fact]
    public void ValidatePortText_RejectsOutOfRange()
    {
        var r = FormValidator.ValidatePortText("99999", "Source");
        Assert.False(r.Ok);
    }
}
