using NexaIQ.Connector.Core;

var failures = new List<string>();

Check(EmsFilePolicy.IsCandidate("repair.AD1"), "EMS-style extension should be accepted");
Check(!EmsFilePolicy.IsCandidate("malware.exe"), "Executable extension should be rejected");
Check(!EmsFilePolicy.IsCandidate("archive.zip"), "Archive extension should be rejected");
Check(EmsFilePolicy.UploadPriority("repair.VEH") > EmsFilePolicy.UploadPriority("repair.AD1"),
    "Vehicle table should upload after non-core files so it finalizes a complete snapshot");
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

    var queue = ConnectorQueueState.Empty;
    var firstSnapshots = new[]
    {
        new ConnectorFileSnapshot("one.env", "one.env", ".", "env-v1"),
        new ConnectorFileSnapshot("one.lin", "one.lin", ".", "lin-v1"),
        new ConnectorFileSnapshot("one.veh", "one.veh", ".", "veh-v1"),
    };
    var firstQueued = ConnectorSnapshotPlanner.QueueChangedSnapshots(
        queue, firstSnapshots, DateTimeOffset.UtcNow);
    Check(firstQueued == 3, "Initial discovery should queue the complete EMS snapshot");
    Check(queue.Pending.Select(item => item.ClientBatchId).Distinct().Count() == 1,
        "A complete EMS snapshot should share one batch identity");
    Check(Path.GetExtension(queue.Pending[^1].RelativePath).Equals(".veh",
            StringComparison.OrdinalIgnoreCase),
        "The final core table should be queued last");

    var firstBatchId = queue.Pending[0].ClientBatchId;
    foreach (var item in firstSnapshots)
    {
        queue.CompletedHashes[item.RelativePath] = item.ContentSha256;
    }
    queue.Pending.Clear();
    Check(ConnectorSnapshotPlanner.QueueChangedSnapshots(
            queue, firstSnapshots, DateTimeOffset.UtcNow) == 0,
        "An unchanged snapshot should not be queued again");

    var revisedSnapshots = firstSnapshots
        .Select(item => item.RelativePath == "one.lin" ? item with { ContentSha256 = "lin-v2" } : item)
        .ToArray();
    Check(ConnectorSnapshotPlanner.QueueChangedSnapshots(
            queue, revisedSnapshots, DateTimeOffset.UtcNow) == 3,
        "One changed file should queue the complete revised snapshot");
    Check(queue.Pending.All(item => item.ClientBatchId != firstBatchId),
        "A revised snapshot must receive a new batch identity");
    Check(ConnectorSnapshotPlanner.QueueChangedSnapshots(
            queue, revisedSnapshots, DateTimeOffset.UtcNow) == 0,
        "A pending snapshot should not be duplicated by the next scan");
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
