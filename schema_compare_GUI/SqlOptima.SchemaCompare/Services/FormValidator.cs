using System.Text.RegularExpressions;
using SqlOptima.SchemaCompare.Models;

namespace SqlOptima.SchemaCompare.Services;

/// <summary>
/// Shared validation for connection panels and compare actions.
/// </summary>
public static class FormValidator
{
    private static readonly Regex PortPattern = new(@"^\d{1,5}$", RegexOptions.Compiled);

    public sealed class ValidationResult
    {
        public bool Ok => Errors.Count == 0;
        public List<string> Errors { get; } = new();
        public void Add(string message) => Errors.Add(message);
        public string AsMessage() => string.Join(Environment.NewLine, Errors);
    }

    public static ValidationResult ValidateServer(ConnectionInfo info, string sideLabel)
    {
        var r = new ValidationResult();
        if (string.IsNullOrWhiteSpace(info.Instance))
            r.Add($"{sideLabel}: server host is required.");

        if (!string.IsNullOrWhiteSpace(info.Port.ToString()) && info.Port != 0)
        {
            if (info.Port < 1 || info.Port > 65535)
                r.Add($"{sideLabel}: port must be between 1 and 65535.");
        }

        if (info.Auth == AuthMode.Sql)
        {
            if (string.IsNullOrWhiteSpace(info.UserName))
                r.Add($"{sideLabel}: SQL login user is required.");
            if (string.IsNullOrWhiteSpace(info.Password))
                r.Add($"{sideLabel}: SQL login password is required.");
        }

        return r;
    }

    public static ValidationResult ValidatePortText(string? portText, string sideLabel)
    {
        var r = new ValidationResult();
        var t = (portText ?? "").Trim();
        if (string.IsNullOrEmpty(t)) return r;
        if (!PortPattern.IsMatch(t) || !int.TryParse(t, out var p) || p < 1 || p > 65535)
            r.Add($"{sideLabel}: port must be a number from 1 to 65535.");
        return r;
    }

    public static ValidationResult ValidateCompare(
        ConnectionInfo source,
        ConnectionInfo target,
        CompareMode mode,
        IReadOnlyList<string> checkedTargets,
        string listFile,
        string? sourcePortText = null,
        string? targetPortText = null)
    {
        var r = new ValidationResult();
        Merge(r, ValidatePortText(sourcePortText, "Source"));
        Merge(r, ValidatePortText(targetPortText, "Destination"));
        Merge(r, ValidateServer(source, "Source"));
        Merge(r, ValidateServer(target, "Destination"));

        if (string.IsNullOrWhiteSpace(source.Database))
            r.Add("Source: select a source database.");

        if (mode == CompareMode.OneToOne)
        {
            if (checkedTargets.Count == 0 && string.IsNullOrWhiteSpace(target.Database))
                r.Add("Destination: select one destination database.");
            else if (checkedTargets.Count > 1)
                r.Add("Destination: One-to-One allows only one destination database (or switch to One-to-Many).");
        }
        else
        {
            var hasList = !string.IsNullOrWhiteSpace(listFile);
            if (hasList && !File.Exists(listFile))
                r.Add($"Destination list file not found:\r\n{listFile}");
            if (!hasList && checkedTargets.Count == 0)
                r.Add("Destination: check at least one database, or choose a destination list file.");
        }

        return r;
    }

    private static void Merge(ValidationResult into, ValidationResult from)
    {
        foreach (var e in from.Errors) into.Add(e);
    }
}
