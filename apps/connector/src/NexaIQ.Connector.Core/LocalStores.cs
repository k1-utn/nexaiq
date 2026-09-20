using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace NexaIQ.Connector.Core;

public sealed class ConnectorDataPaths
{
    public ConnectorDataPaths(string? root = null)
    {
        Root = root ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "nexaIQ",
            "Connector");
        Directory.CreateDirectory(Root);
    }

    public string Root { get; }
    public string SettingsPath => Path.Combine(Root, "settings.json");
    public string SessionPath => Path.Combine(Root, "session.dat");
    public string QueuePath => Path.Combine(Root, "queue.json");
    public string LogPath => Path.Combine(Root, "connector.log");
}

public sealed class JsonFileStore<T>(string path)
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    public bool Exists => File.Exists(path);

    public async Task<T?> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path))
        {
            return default;
        }

        await using var stream = File.OpenRead(path);
        return await JsonSerializer.DeserializeAsync<T>(stream, Options, cancellationToken);
    }

    public async Task SaveAsync(T value, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = path + ".tmp";
        await using (var stream = File.Create(temporaryPath))
        {
            await JsonSerializer.SerializeAsync(stream, value, Options, cancellationToken);
        }
        File.Move(temporaryPath, path, true);
    }
}

public sealed class ProtectedSessionStore(string path)
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("nexaIQ.connector.session.v1");

    public bool Exists => File.Exists(path);

    public async Task SaveAsync(
        AuthSession session,
        CancellationToken cancellationToken = default)
    {
        var plaintext = JsonSerializer.SerializeToUtf8Bytes(session);
        var protectedBytes = ProtectedData.Protect(
            plaintext,
            Entropy,
            DataProtectionScope.CurrentUser);
        await File.WriteAllBytesAsync(path, protectedBytes, cancellationToken);
        CryptographicOperations.ZeroMemory(plaintext);
    }

    public async Task<AuthSession?> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        var protectedBytes = await File.ReadAllBytesAsync(path, cancellationToken);
        byte[] plaintext;
        try
        {
            plaintext = ProtectedData.Unprotect(
                protectedBytes,
                Entropy,
                DataProtectionScope.CurrentUser);
        }
        catch (CryptographicException)
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<AuthSession>(plaintext);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
        }
    }

    public void Clear()
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }
}

public sealed class ConnectorLog(string path)
{
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task WriteAsync(string message)
    {
        var safeMessage = message.Replace('\r', ' ').Replace('\n', ' ');
        await _gate.WaitAsync();
        try
        {
            await File.AppendAllTextAsync(
                path,
                $"{DateTimeOffset.UtcNow:O}\t{safeMessage}{Environment.NewLine}");
        }
        finally
        {
            _gate.Release();
        }
    }
}
