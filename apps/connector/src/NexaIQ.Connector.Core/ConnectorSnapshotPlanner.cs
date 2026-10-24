namespace NexaIQ.Connector.Core;

public sealed record ConnectorFileSnapshot(
    string FullPath,
    string RelativePath,
    string RelativeDirectory,
    string ContentSha256);

public static class ConnectorSnapshotPlanner
{
    public static int QueueChangedSnapshots(
        ConnectorQueueState state,
        IReadOnlyCollection<ConnectorFileSnapshot> snapshots,
        DateTimeOffset discoveredAtUtc)
    {
        var queued = 0;
        var pendingDirectories = state.Pending
            .Select(item => NormalizeDirectory(Path.GetDirectoryName(item.RelativePath)))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var directoryGroup in snapshots
                     .GroupBy(item => item.RelativeDirectory, StringComparer.OrdinalIgnoreCase)
                     .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase))
        {
            if (pendingDirectories.Contains(directoryGroup.Key))
            {
                continue;
            }

            var files = directoryGroup
                .OrderBy(item => EmsFilePolicy.UploadPriority(item.RelativePath))
                .ThenBy(item => item.RelativePath, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var hasChange = files.Any(file =>
                !state.CompletedHashes.TryGetValue(file.RelativePath, out var completedHash)
                || !string.Equals(completedHash, file.ContentSha256, StringComparison.Ordinal));
            if (!hasChange)
            {
                continue;
            }

            var batchId = Guid.NewGuid();
            state.DirectoryBatchIds[directoryGroup.Key] = batchId;
            foreach (var file in files)
            {
                state.Pending.Add(new PendingConnectorFile(
                    batchId,
                    Guid.NewGuid(),
                    file.FullPath,
                    file.RelativePath,
                    discoveredAtUtc,
                    0,
                    discoveredAtUtc,
                    null));
                queued++;
            }
        }

        return queued;
    }

    private static string NormalizeDirectory(string? directory)
    {
        return string.IsNullOrWhiteSpace(directory) ? "." : directory;
    }
}
