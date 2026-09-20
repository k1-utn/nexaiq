using NexaIQ.Connector.Core;

var failures = new List<string>();

Check(EmsFilePolicy.IsCandidate("repair.AD1"), "EMS-style extension should be accepted");
Check(!EmsFilePolicy.IsCandidate("malware.exe"), "Executable extension should be rejected");
Check(!EmsFilePolicy.IsCandidate("archive.zip"), "Archive extension should be rejected");
Check(
    EmsFilePolicy.ComputePathFingerprint(@"C:\EMS")
        == EmsFilePolicy.ComputePathFingerprint(@"c:\ems\"),
    "Watch-path fingerprint should be stable on Windows");

var temporaryRoot = Path.Combine(Path.GetTempPath(), $"nexaiq-connector-{Guid.NewGuid():N}");
Directory.CreateDirectory(temporaryRoot);
try
{
    var paths = new ConnectorDataPaths(temporaryRoot);
    var settings = new ConnectorSettings(
        new Uri("http://localhost:8001"),
        new Uri("https://example.supabase.co"),
        "publishable-key",
        Guid.NewGuid(),
        Guid.NewGuid(),
        temporaryRoot,
        Guid.NewGuid(),
        "Test device");
    var store = new JsonFileStore<ConnectorSettings>(paths.SettingsPath);
    await store.SaveAsync(settings);
    var restored = await store.LoadAsync();
    Check(restored == settings, "Settings should round-trip atomically");

    var sessionStore = new ProtectedSessionStore(paths.SessionPath);
    var session = new AuthSession("access-token", "refresh-token", DateTimeOffset.UtcNow);
    await sessionStore.SaveAsync(session);
    var restoredSession = await sessionStore.LoadAsync();
    Check(restoredSession == session, "Session should round-trip through Windows DPAPI");
    Check(
        !File.ReadAllText(paths.SessionPath).Contains("refresh-token", StringComparison.Ordinal),
        "Stored session must not contain plaintext tokens");
}
finally
{
    Directory.Delete(temporaryRoot, true);
}

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"FAIL: {failure}");
    }
    return 1;
}

Console.WriteLine("Connector core checks passed");
return 0;

void Check(bool condition, string message)
{
    if (!condition)
    {
        failures.Add(message);
    }
}
