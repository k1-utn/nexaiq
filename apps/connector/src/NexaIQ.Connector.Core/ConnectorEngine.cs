namespace NexaIQ.Connector.Core;

public sealed class ConnectorEngine(
    ConnectorSettings settings,
    JsonFileStore<ConnectorQueueState> queueStore,
    ProtectedSessionStore sessionStore,
    SupabaseAuthClient authClient,
    ConnectorApiClient apiClient,
    ConnectorLog log)
{
    private readonly SemaphoreSlim _syncGate = new(1, 1);

    public string LastStatus { get; private set; } = "Ready";

    public async Task SyncNowAsync(CancellationToken cancellationToken = default)
    {
        if (!await _syncGate.WaitAsync(0, cancellationToken))
        {
            return;
        }

        try
        {
            LastStatus = "Scanning EMS folder";
            var state = await queueStore.LoadAsync(cancellationToken) ?? ConnectorQueueState.Empty;
            await DiscoverFilesAsync(state, cancellationToken);
            await queueStore.SaveAsync(state, cancellationToken);
            await UploadPendingAsync(state, cancellationToken);
            LastStatus = state.Pending.Count == 0
                ? "All EMS files synchronized"
                : $"{state.Pending.Count} EMS file(s) waiting to retry";
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            LastStatus = "Synchronization needs attention";
            await log.WriteAsync($"sync_error {exception.GetType().Name}: {exception.Message}");
        }
        finally
        {
            _syncGate.Release();
        }
    }

    private async Task DiscoverFilesAsync(
        ConnectorQueueState state,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(settings.WatchFolder))
        {
            throw new DirectoryNotFoundException("The configured EMS folder is not available.");
        }

        var pendingPaths = state.Pending
            .Select(item => item.RelativePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var path in Directory.EnumerateFiles(
                     settings.WatchFolder,
                     "*",
                     SearchOption.AllDirectories))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!EmsFilePolicy.IsCandidate(path))
            {
                continue;
            }

            var information = new FileInfo(path);
            if (information.Length <= 0 || information.Length > 5 * 1024 * 1024
                || DateTimeOffset.UtcNow - information.LastWriteTimeUtc < TimeSpan.FromSeconds(2))
            {
                continue;
            }

            var relativePath = Path.GetRelativePath(settings.WatchFolder, path);
            if (pendingPaths.Contains(relativePath))
            {
                continue;
            }

            var hash = await EmsFilePolicy.ComputeFileHashAsync(path, cancellationToken);
            if (state.CompletedHashes.TryGetValue(relativePath, out var completedHash)
                && string.Equals(completedHash, hash, StringComparison.Ordinal))
            {
                continue;
            }

            var relativeDirectory = Path.GetDirectoryName(relativePath) ?? ".";
            if (!state.DirectoryBatchIds.TryGetValue(relativeDirectory, out var batchId))
            {
                batchId = Guid.NewGuid();
                state.DirectoryBatchIds[relativeDirectory] = batchId;
            }

            state.Pending.Add(new PendingConnectorFile(
                batchId,
                Guid.NewGuid(),
                path,
                relativePath,
                DateTimeOffset.UtcNow,
                0,
                DateTimeOffset.UtcNow,
                null));
            pendingPaths.Add(relativePath);
        }
    }

    private async Task UploadPendingAsync(
        ConnectorQueueState state,
        CancellationToken cancellationToken)
    {
        var session = await sessionStore.LoadAsync(cancellationToken)
            ?? throw new InvalidOperationException("Sign in again to resume connector sync.");
        if (session.ExpiresAtUtc <= DateTimeOffset.UtcNow.AddMinutes(2))
        {
            session = await authClient.RefreshAsync(settings, session.RefreshToken, cancellationToken);
            await sessionStore.SaveAsync(session, cancellationToken);
        }

        foreach (var pending in state.Pending.ToArray())
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (pending.NextAttemptAtUtc > DateTimeOffset.UtcNow)
            {
                continue;
            }

            try
            {
                await apiClient.UploadFileAsync(settings, session, pending, cancellationToken);
                var hash = await EmsFilePolicy.ComputeFileHashAsync(
                    pending.FullPath,
                    cancellationToken);
                state.CompletedHashes[pending.RelativePath] = hash;
                state.Pending.Remove(pending);
                await log.WriteAsync($"sync_ok {Path.GetFileName(pending.RelativePath)}");
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                var attempts = pending.Attempts + 1;
                var delaySeconds = Math.Min(300, 5 * Math.Pow(2, Math.Min(attempts, 6)));
                var retry = pending with
                {
                    Attempts = attempts,
                    NextAttemptAtUtc = DateTimeOffset.UtcNow.AddSeconds(delaySeconds),
                    LastError = exception.Message,
                };
                state.Pending[state.Pending.IndexOf(pending)] = retry;
                await log.WriteAsync(
                    $"sync_retry {Path.GetFileName(pending.RelativePath)} attempt={attempts}");
            }

            await queueStore.SaveAsync(state, cancellationToken);
        }
    }
}
