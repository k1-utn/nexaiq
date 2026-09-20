using NexaIQ.Connector.Core;

namespace NexaIQ.Connector;

public sealed class SetupForm : Form
{
    private readonly TextBox _apiUrl = new() { Text = "http://localhost:8001" };
    private readonly TextBox _supabaseUrl = new();
    private readonly TextBox _publishableKey = new();
    private readonly TextBox _email = new();
    private readonly TextBox _password = new() { UseSystemPasswordChar = true };
    private readonly TextBox _organizationId = new();
    private readonly TextBox _locationId = new();
    private readonly TextBox _watchFolder = new();
    private readonly Label _status = new() { AutoSize = true };
    private readonly ConnectorDataPaths _paths;

    public SetupForm(ConnectorDataPaths paths, ConnectorSettings? existing = null)
    {
        _paths = paths;
        Text = "nexaIQ Connector Setup";
        Width = 620;
        Height = 610;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(20),
            ColumnCount = 2,
            RowCount = 10,
            AutoSize = true,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 165));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        AddRow(layout, 0, "nexaIQ API URL", _apiUrl);
        AddRow(layout, 1, "Supabase URL", _supabaseUrl);
        AddRow(layout, 2, "Publishable key", _publishableKey);
        AddRow(layout, 3, "Login email", _email);
        AddRow(layout, 4, "Login password", _password);
        AddRow(layout, 5, "Organization ID", _organizationId);
        AddRow(layout, 6, "Location ID", _locationId);

        var folderPanel = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        _watchFolder.Width = 300;
        var browse = new Button { Text = "Browse…", AutoSize = true };
        browse.Click += (_, _) => ChooseFolder();
        folderPanel.Controls.Add(_watchFolder);
        folderPanel.Controls.Add(browse);
        AddRow(layout, 7, "Mitchell EMS folder", folderPanel);

        var save = new Button { Text = "Sign in and connect", AutoSize = true };
        save.Click += async (_, _) => await SaveAsync(save);
        layout.Controls.Add(save, 1, 8);
        layout.Controls.Add(_status, 1, 9);
        Controls.Add(layout);

        if (existing is not null)
        {
            _apiUrl.Text = existing.ApiBaseUrl.ToString();
            _supabaseUrl.Text = existing.SupabaseUrl.ToString();
            _publishableKey.Text = existing.SupabasePublishableKey;
            _organizationId.Text = existing.OrganizationId.ToString();
            _locationId.Text = existing.LocationId.ToString();
            _watchFolder.Text = existing.WatchFolder;
        }
    }

    public bool Saved { get; private set; }

    private static void AddRow(Control layout, int row, string label, Control input)
    {
        ((TableLayoutPanel)layout).Controls.Add(
            new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            row);
        input.Dock = DockStyle.Fill;
        ((TableLayoutPanel)layout).Controls.Add(input, 1, row);
    }

    private void ChooseFolder()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Select the authorized Mitchell EMS export folder",
            UseDescriptionForTitle = true,
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _watchFolder.Text = dialog.SelectedPath;
        }
    }

    private async Task SaveAsync(Button saveButton)
    {
        saveButton.Enabled = false;
        _status.Text = "Connecting…";
        try
        {
            if (!Uri.TryCreate(_apiUrl.Text.Trim(), UriKind.Absolute, out var apiUrl)
                || !Uri.TryCreate(_supabaseUrl.Text.Trim(), UriKind.Absolute, out var supabaseUrl)
                || !Guid.TryParse(_organizationId.Text.Trim(), out var organizationId)
                || !Guid.TryParse(_locationId.Text.Trim(), out var locationId)
                || !Directory.Exists(_watchFolder.Text.Trim()))
            {
                throw new InvalidOperationException("Check the URLs, IDs, and EMS folder.");
            }

            var existing = await new JsonFileStore<ConnectorSettings>(_paths.SettingsPath).LoadAsync();
            var settings = new ConnectorSettings(
                apiUrl,
                supabaseUrl,
                _publishableKey.Text.Trim(),
                organizationId,
                locationId,
                Path.GetFullPath(_watchFolder.Text.Trim()),
                existing?.DeviceIdentifier ?? Guid.NewGuid(),
                Environment.MachineName);
            using var httpClient = new HttpClient();
            var authClient = new SupabaseAuthClient(httpClient);
            var session = await authClient.SignInAsync(
                settings.SupabaseUrl,
                settings.SupabasePublishableKey,
                _email.Text.Trim(),
                _password.Text);
            await new ConnectorApiClient(httpClient).RegisterDeviceAsync(settings, session);
            await new JsonFileStore<ConnectorSettings>(_paths.SettingsPath).SaveAsync(settings);
            await new ProtectedSessionStore(_paths.SessionPath).SaveAsync(session);
            _password.Clear();
            Saved = true;
            DialogResult = DialogResult.OK;
            Close();
        }
        catch (Exception exception)
        {
            _status.Text = exception.Message;
            saveButton.Enabled = true;
        }
    }
}
