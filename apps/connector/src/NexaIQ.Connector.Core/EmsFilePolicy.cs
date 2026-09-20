using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace NexaIQ.Connector.Core;

public static partial class EmsFilePolicy
{
    private static readonly HashSet<string> BlockedExtensions = new(
        [".bat", ".cmd", ".com", ".dll", ".exe", ".js", ".msi", ".ps1", ".scr", ".vbs", ".zip"],
        StringComparer.OrdinalIgnoreCase);

    [GeneratedRegex("^\\.[A-Za-z0-9]{1,8}$")]
    private static partial Regex ExtensionPattern();

    public static bool IsCandidate(string path)
    {
        var extension = Path.GetExtension(path);
        return ExtensionPattern().IsMatch(extension) && !BlockedExtensions.Contains(extension);
    }

    public static string ComputePathFingerprint(string path)
    {
        var normalized = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .ToUpperInvariant();
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalized)))
            .ToLowerInvariant();
    }

    public static async Task<string> ComputeFileHashAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            64 * 1024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
