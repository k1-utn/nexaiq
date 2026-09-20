using System.Text.Json.Serialization;

namespace NexaIQ.Connector.Core;

public static class ConnectorVersion
{
    public const string Current = "0.1.0";
}

public sealed record ConnectorSettings(
    Uri ApiBaseUrl,
    Uri SupabaseUrl,
    string SupabasePublishableKey,
    Guid OrganizationId,
    Guid LocationId,
    string WatchFolder,
    Guid DeviceIdentifier,
    string DeviceName);

public sealed record AuthSession(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAtUtc);

public sealed record PendingConnectorFile(
    Guid ClientBatchId,
    Guid ClientFileId,
    string FullPath,
    string RelativePath,
    DateTimeOffset DiscoveredAtUtc,
    int Attempts,
    DateTimeOffset NextAttemptAtUtc,
    string? LastError);

public sealed record ConnectorQueueState(
    List<PendingConnectorFile> Pending,
    Dictionary<string, string> CompletedHashes,
    Dictionary<string, Guid> DirectoryBatchIds)
{
    public static ConnectorQueueState Empty => new([], new(StringComparer.OrdinalIgnoreCase),
        new(StringComparer.OrdinalIgnoreCase));
}

public sealed record DeviceRegistrationResult(
    [property: JsonPropertyName("connector_device_id")] Guid ConnectorDeviceId,
    [property: JsonPropertyName("device_status")] string DeviceStatus);

public sealed record FileSyncResult(
    [property: JsonPropertyName("connector_sync_file_id")] Guid ConnectorSyncFileId,
    [property: JsonPropertyName("persistence_status")] string PersistenceStatus,
    [property: JsonPropertyName("parse_status")] string ParseStatus);
