using NexaIQ.Connector.Core;

namespace NexaIQ.Connector;

public sealed class TrayApplicationContext : ApplicationContext
{
    private readonly ConnectorDataPaths _paths;
    private readonly NotifyIcon _trayIcon;
    private readonly System.Windows.Forms.Timer _timer;
    private ConnectorSettings? _settings;
    private ConnectorEngine? _engine;

    public TrayApplicationContext(ConnectorDataPaths paths)
    {
        _paths = paths;
        var menu = new ContextMenuStrip();
        menu.Items.Add("Sync now", null, async (_, _) => await SyncNowAsync());
        menu.Items.Add("Open EMS folder", null, (_, _) => OpenFolder());
        menu.Items.Add("Settings", null, async (_, _) => await ShowSettingsAsync());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => Exit());
        _trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "nexaIQ EMS Connector",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _trayIcon.DoubleClick += async (_, _) => await SyncNowAsync();
        _timer = new System.Windows.Forms.Timer { Interval = 15_000 };
        _timer.Tick += async (_, _) => await SyncNowAsync();
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        _settings = await new JsonFileStore<ConnectorSettings>(_paths.SettingsPath).LoadAsync();
        if (_settings is null || !new ProtectedSessionStore(_paths.SessionPath).Exists)
        {
            await ShowSettingsAsync();
        }

        if (_settings is not null)
        {
            BuildEngine();
            _timer.Start();
            await SyncNowAsync();
        }
    }

    private void BuildEngine()
    {
        if (_settings is null)
        {
            return;
        }

        var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(90) };
        _engine = new ConnectorEngine(
            _settings,
            new JsonFileStore<ConnectorQueueState>(_paths.QueuePath),
            new ProtectedSessionStore(_paths.SessionPath),
            new SupabaseAuthClient(httpClient),
            new ConnectorApiClient(httpClient),
            new ConnectorLog(_paths.LogPath));
    }

    private async Task SyncNowAsync()
    {
        if (_engine is null)
        {
            return;
        }

        await _engine.SyncNowAsync();
        _trayIcon.Text = _engine.LastStatus.Length <= 63
            ? _engine.LastStatus
            : _engine.LastStatus[..63];
    }

    private async Task ShowSettingsAsync()
    {
        using var form = new SetupForm(_paths, _settings);
        form.ShowDialog();
        if (!form.Saved)
        {
            return;
        }

        _settings = await new JsonFileStore<ConnectorSettings>(_paths.SettingsPath).LoadAsync();
        BuildEngine();
        _timer.Start();
        await SyncNowAsync();
    }

    private void OpenFolder()
    {
        if (_settings is null || !Directory.Exists(_settings.WatchFolder))
        {
            return;
        }

        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = _settings.WatchFolder,
            UseShellExecute = true,
        });
    }

    private void Exit()
    {
        _timer.Stop();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        ExitThread();
    }
}
