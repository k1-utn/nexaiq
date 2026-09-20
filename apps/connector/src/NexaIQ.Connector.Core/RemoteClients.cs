using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace NexaIQ.Connector.Core;

public sealed class SupabaseAuthClient(HttpClient httpClient)
{
    public async Task<AuthSession> SignInAsync(
        Uri supabaseUrl,
        string publishableKey,
        string email,
        string password,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(supabaseUrl, "/auth/v1/token?grant_type=password"));
        request.Headers.Add("apikey", publishableKey);
        request.Content = JsonContent.Create(new { email, password });
        return await SendTokenRequestAsync(request, cancellationToken);
    }

    public async Task<AuthSession> RefreshAsync(
        ConnectorSettings settings,
        string refreshToken,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(settings.SupabaseUrl, "/auth/v1/token?grant_type=refresh_token"));
        request.Headers.Add("apikey", settings.SupabasePublishableKey);
        request.Content = JsonContent.Create(new { refresh_token = refreshToken });
        return await SendTokenRequestAsync(request, cancellationToken);
    }

    private async Task<AuthSession> SendTokenRequestAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException("Sign-in failed. Check your email and password.");
        }

        using var payload = JsonDocument.Parse(
            await response.Content.ReadAsStringAsync(cancellationToken));
        var root = payload.RootElement;
        var accessToken = root.GetProperty("access_token").GetString();
        var refreshToken = root.GetProperty("refresh_token").GetString();
        var expiresIn = root.GetProperty("expires_in").GetInt32();
        if (string.IsNullOrWhiteSpace(accessToken) || string.IsNullOrWhiteSpace(refreshToken))
        {
            throw new InvalidOperationException("Supabase returned an incomplete session.");
        }

        return new AuthSession(
            accessToken,
            refreshToken,
            DateTimeOffset.UtcNow.AddSeconds(expiresIn));
    }
}

public sealed class ConnectorApiClient(HttpClient httpClient)
{
    public async Task<DeviceRegistrationResult> RegisterDeviceAsync(
        ConnectorSettings settings,
        AuthSession session,
        CancellationToken cancellationToken = default)
    {
        using var request = CreateRequest(
            HttpMethod.Post,
            new Uri(settings.ApiBaseUrl, "/v1/connectors/windows-ems/devices/register"),
            settings,
            session);
        request.Content = JsonContent.Create(new
        {
            device_identifier = settings.DeviceIdentifier,
            location_id = settings.LocationId,
            device_name = settings.DeviceName,
            connector_version = ConnectorVersion.Current,
            watch_path_sha256 = EmsFilePolicy.ComputePathFingerprint(settings.WatchFolder),
        });
        using var response = await httpClient.SendAsync(request, cancellationToken);
        await EnsureSuccessAsync(response, "Device registration failed", cancellationToken);
        return (await response.Content.ReadFromJsonAsync<DeviceRegistrationResult>(
            cancellationToken: cancellationToken))
            ?? throw new InvalidOperationException("Device registration returned no data.");
    }

    public async Task<FileSyncResult> UploadFileAsync(
        ConnectorSettings settings,
        AuthSession session,
        PendingConnectorFile pending,
        CancellationToken cancellationToken = default)
    {
        using var request = CreateRequest(
            HttpMethod.Post,
            new Uri(settings.ApiBaseUrl, "/v1/connectors/windows-ems/files"),
            settings,
            session);
        using var content = new MultipartFormDataContent();
        await using var fileStream = new FileStream(
            pending.FullPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            64 * 1024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        using var fileContent = new StreamContent(fileStream);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        content.Add(fileContent, "file", Path.GetFileName(pending.FullPath));
        content.Add(new StringContent(settings.LocationId.ToString()), "location_id");
        content.Add(new StringContent(settings.DeviceIdentifier.ToString()), "device_identifier");
        content.Add(new StringContent(pending.ClientBatchId.ToString()), "client_batch_id");
        content.Add(new StringContent(pending.ClientFileId.ToString()), "client_file_id");
        content.Add(new StringContent(ConnectorVersion.Current), "connector_version");
        content.Add(new StringContent(pending.DiscoveredAtUtc.ToString("O")), "discovered_at");
        request.Content = content;

        using var response = await httpClient.SendAsync(request, cancellationToken);
        await EnsureSuccessAsync(response, "EMS file sync failed", cancellationToken);
        return (await response.Content.ReadFromJsonAsync<FileSyncResult>(
            cancellationToken: cancellationToken))
            ?? throw new InvalidOperationException("EMS file sync returned no data.");
    }

    private static HttpRequestMessage CreateRequest(
        HttpMethod method,
        Uri uri,
        ConnectorSettings settings,
        AuthSession session)
    {
        var request = new HttpRequestMessage(method, uri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Headers.Add("X-NexaIQ-Organization-ID", settings.OrganizationId.ToString());
        return request;
    }

    private static async Task EnsureSuccessAsync(
        HttpResponseMessage response,
        string message,
        CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var detail = await response.Content.ReadAsStringAsync(cancellationToken);
        throw new HttpRequestException($"{message} ({(int)response.StatusCode}): {detail}");
    }
}
