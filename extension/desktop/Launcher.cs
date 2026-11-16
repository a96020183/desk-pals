using System;

internal static class DeskPalsLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string pipeName = args.Length > 0 && !string.IsNullOrEmpty(args[0]) ? args[0] : "desk-pals";
        string pet = args.Length > 1 && !string.IsNullOrEmpty(args[1]) ? args[1] : "spidey";
        string lineup = args.Length > 2 ? args[2] : "";
        DeskPals.App.Run(pipeName, pet, lineup);
        return 0;
    }
}
