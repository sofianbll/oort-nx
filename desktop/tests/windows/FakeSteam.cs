// An invented Steam for the proofs: it is given steam://rungameid/<number> and starts the game of that manifest, the way
// <number>.play says: update=<s> (the manifest says so meanwhile), again=<s> (the game is ended, then started again),
// nothing=1. Compiled on the runner; never shipped.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;

static class FakeSteam {
    static int Main(string[] args) {
        string here = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
        var link = Regex.Match(string.Join(" ", args), "^steam://rungameid/([0-9]+)/?$");
        File.AppendAllText(Path.Combine(here, "asked.txt"), string.Join(" ", args) + "\n");
        if (!link.Success) return 2;
        string number = link.Groups[1].Value, manifest = null;
        foreach (Match m in Regex.Matches(File.ReadAllText(Path.Combine(here, "steamapps", "libraryfolders.vdf")), "\"path\"\\s*\"([^\"]+)\"")) {
            string file = Path.Combine(m.Groups[1].Value.Replace("\\\\", "\\"), "steamapps", "appmanifest_" + number + ".acf");
            if (File.Exists(file)) manifest = file;
        }
        if (manifest == null) return 1;
        var does = new Dictionary<string, int>();
        string play = Path.Combine(here, number + ".play");
        if (File.Exists(play)) foreach (var line in File.ReadAllLines(play)) { int at = line.IndexOf('='); if (at > 0) does[line.Substring(0, at)] = int.Parse(line.Substring(at + 1)); }
        string name = Regex.Match(File.ReadAllText(manifest), "\"installdir\"\\s*\"([^\"]+)\"").Groups[1].Value;
        string folder = Path.Combine(Path.GetDirectoryName(manifest), "common", name), game = Path.Combine(folder, "game.exe");
        Action<string> state = s => File.WriteAllText(manifest, Regex.Replace(File.ReadAllText(manifest), "(\"StateFlags\"\\s*)\"[0-9]+\"", "$1\"" + s + "\""));
        Thread.Sleep(1000);
        if (does.ContainsKey("nothing")) return 0;
        if (does.ContainsKey("update")) { state("1026"); Thread.Sleep(does["update"] * 1000); state("4"); }
        var start = new ProcessStartInfo(game) { WorkingDirectory = folder, UseShellExecute = false };
        if (does.ContainsKey("again")) { var first = Process.Start(start); Thread.Sleep(1000); first.Kill(); Thread.Sleep(does["again"] * 1000); }
        Process.Start(start);
        return 0;
    }
}
