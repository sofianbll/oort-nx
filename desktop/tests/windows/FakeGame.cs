// An invented game for the proofs on Windows: it does what the .play file beside it says (scripts/fixtures.py).
// Compiled on the runner with the C# compiler Windows has; never shipped.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class FakeGame {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct Startup { public int cb; public string a, b, title; public int x, y, w, h, cw, ch, fill, flags; public short show, n; public IntPtr r, i, o, e; }
    [StructLayout(LayoutKind.Sequential)]
    struct Info { public IntPtr process, thread; public int pid, tid; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, StringBuilder line, IntPtr p, IntPtr t, bool inherit, uint flags, IntPtr env, string dir, ref Startup s, out Info i);
    const uint Breakaway = 0x01000000;

    [STAThread]
    static int Main(string[] args) {
        string exe = Application.ExecutablePath, folder = Path.GetDirectoryName(exe);
        var does = new Dictionary<string, string>();
        foreach (var line in File.ReadAllLines(Path.ChangeExtension(exe, ".play"))) {
            int at = line.IndexOf('=');
            if (at > 0) does[line.Substring(0, at)] = line.Substring(at + 1);
        }
        Func<string, int> number = k => does.ContainsKey(k) ? int.Parse(does[k]) : 0;
        var utf8 = new UTF8Encoding(false);
        if (does.ContainsKey("args")) File.WriteAllLines(Path.ChangeExtension(exe, null) + "-args.txt", args, utf8);
        string data = Environment.GetEnvironmentVariable("RECOMPLAUNCHER_DATA");
        if (does.ContainsKey("log") && data != null) {
            var lines = new List<string>();
            lines.Add(exe);
            lines.AddRange(args);
            foreach (DictionaryEntry v in Environment.GetEnvironmentVariables())
                if (v.Key.ToString().StartsWith("RECOMPLAUNCHER") || v.Key.ToString().StartsWith("ONE_")) lines.Add(v.Key + "=" + v.Value);
            File.WriteAllLines(Path.Combine(data, "last-run.txt"), lines, utf8);
        }
        var output = new StreamWriter(Console.OpenStandardOutput(), utf8);
        output.AutoFlush = true;
        for (int i = 1; i <= number("steps"); i++) { output.WriteLine("progress 0." + i + " Unpacking part " + i); Thread.Sleep(250); }
        if (does.ContainsKey("out")) { File.WriteAllText(args[1], "x"); output.WriteLine("progress 1 Done"); }
        if (does.ContainsKey("start")) {
            var startup = new Startup();
            startup.cb = Marshal.SizeOf(startup);
            Info info;
            string child = Path.Combine(folder, does["start"] + ".exe");
            if (!CreateProcessW(child, new StringBuilder("\"" + child + "\""), IntPtr.Zero, IntPtr.Zero, false, does.ContainsKey("breakaway") ? Breakaway : 0, IntPtr.Zero, folder, ref startup, out info))
                return 100;
        }
        int seconds = number("seconds");
        if (does.ContainsKey("window")) {
            var form = new Form();
            form.Text = "Invented game";
            form.BackColor = Color.FromArgb(28, 60, 72);
            form.WindowState = FormWindowState.Maximized;
            form.Controls.Add(new Label { Text = "An invented game: " + Path.GetFileName(folder), ForeColor = Color.White, Font = new Font("Segoe UI", 28), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter });
            form.Shown += (s, e) => form.Activate();
            bool over = false;
            form.FormClosing += (s, e) => { if (does.ContainsKey("ignore") && !over) e.Cancel = true; };
            var timer = new System.Windows.Forms.Timer { Interval = Math.Max(1, seconds) * 1000 };
            timer.Tick += (s, e) => { over = true; form.Close(); };
            timer.Start();
            Application.Run(form);
        } else if (seconds > 0) Thread.Sleep(seconds * 1000);
        Environment.Exit(number("code"));
        return 0;
    }
}
