using NexaIQ.Connector.Core;

namespace NexaIQ.Connector;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        var paths = new ConnectorDataPaths();
        Application.Run(new TrayApplicationContext(paths));
    }
}
