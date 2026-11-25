// What the proofs ask Windows itself: which window is in front, a picture of the screen, a real key. Never shipped.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

static class Desk {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int l, t, r, b; }
    delegate bool Each(IntPtr w, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(Each e, IntPtr p);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w, out int pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr w);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr w);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr w, uint c);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr w);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr w, out Rect r);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr w, out Rect r);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr w, int x, int y, int wd, int h, bool paint);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr w, int how);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr w, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern void keybd_event(byte k, byte scan, uint flags, UIntPtr x);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int EnumDisplaySettingsA(string d, int n, ref Mode m);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int ChangeDisplaySettingsA(ref Mode m, int flags);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    struct Mode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string device;
        public short spec, driver, size, extra; public int fields, x, y, orientation, output;
        public short color, duplex, yres, tt, collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string form;
        public short log; public int bits, w, h, flags, hz, icm, icmi, media, dither, r1, r2, pw, ph;
    }

    static IntPtr Main_(int pid) {
        IntPtr best = IntPtr.Zero; int area = -1;
        EnumWindows((w, p) => {
            int owner; GetWindowThreadProcessId(w, out owner);
            if (owner == pid && IsWindowVisible(w) && GetWindow(w, 4) == IntPtr.Zero) {
                Rect r; GetWindowRect(w, out r);
                int a = (r.r - r.l) * (r.b - r.t);
                if (a > area) { area = a; best = w; }
            }
            return true;
        }, IntPtr.Zero);
        return best;
    }
    static string Title(IntPtr w) { var s = new StringBuilder(200); GetWindowTextW(w, s, 200); return s.ToString(); }
    static int Pid(IntPtr w) { int p; GetWindowThreadProcessId(w, out p); return p; }

    static int Main(string[] a) {
        SetProcessDPIAware();
        switch (a[0]) {
            case "screen": {
                var m = new Mode(); m.size = (short)Marshal.SizeOf(m);
                EnumDisplaySettingsA(null, -1, ref m);
                m.w = int.Parse(a[1]); m.h = int.Parse(a[2]); m.fields = 0x80000 | 0x100000;
                int result = ChangeDisplaySettingsA(ref m, 0);
                Console.WriteLine("screen " + Screen.PrimaryScreen.Bounds + " result " + result);
                return 0;
            }
            case "shot": {
                var b = Screen.PrimaryScreen.Bounds;
                using (var image = new Bitmap(b.Width, b.Height))
                using (var g = Graphics.FromImage(image)) {
                    g.CopyFromScreen(b.Location, Point.Empty, b.Size);
                    image.Save(a[1], ImageFormat.Png);
                }
                return 0;
            }
            case "state": {
                int pid = int.Parse(a[1]);
                IntPtr w = Main_(pid), f = GetForegroundWindow();
                Rect r = new Rect(), c = new Rect();
                if (w != IntPtr.Zero) { GetWindowRect(w, out r); GetClientRect(w, out c); }
                Console.WriteLine("{\"window\":" + (w != IntPtr.Zero ? "true" : "false") + ",\"minimized\":" + (IsIconic(w) ? "true" : "false") + ",\"front\":" + (Pid(f) == pid ? "true" : "false")
                    + ",\"frontTitle\":\"" + Title(f).Replace("\\", "").Replace("\"", "") + "\",\"title\":\"" + Title(w) + "\",\"width\":" + c.r + ",\"height\":" + c.b + "}");
                return 0;
            }
            case "size": {
                // The page's size: the window's own frame comes on top.
                IntPtr w = Main_(int.Parse(a[1]));
                Rect r, c; GetWindowRect(w, out r); GetClientRect(w, out c);
                MoveWindow(w, 0, 0, int.Parse(a[2]) + (r.r - r.l) - c.r, int.Parse(a[3]) + (r.b - r.t) - c.b, true);
                return 0;
            }
            case "front": {
                IntPtr w = Main_(int.Parse(a[1]));
                if (IsIconic(w)) ShowWindow(w, 9);
                // Windows lets a program take the front after a key of its own (F24: nothing listens to it). What a runner
                // leaves on its screen steps aside.
                for (int i = 0; i < 6 && Pid(GetForegroundWindow()) != int.Parse(a[1]); i++) {
                    if (i > 0) ShowWindow(GetForegroundWindow(), 6);
                    keybd_event(0x87, 0, 0, UIntPtr.Zero); keybd_event(0x87, 0, 2, UIntPtr.Zero);
                    SetForegroundWindow(w); Thread.Sleep(300);
                }
                return Pid(GetForegroundWindow()) == int.Parse(a[1]) ? 0 : 1;
            }
            case "key": {
                byte k = byte.Parse(a[1]);
                uint extended = k >= 0x21 && k <= 0x2E ? 1u : 0u;
                keybd_event(k, 0, extended, UIntPtr.Zero); Thread.Sleep(60); keybd_event(k, 0, extended | 2, UIntPtr.Zero);
                return 0;
            }
            case "count": {
                // Programs run from a folder.
                int n = 0;
                foreach (var p in Process.GetProcesses()) try { if (p.MainModule.FileName.StartsWith(a[1], StringComparison.OrdinalIgnoreCase)) n++; } catch { }
                Console.WriteLine(n);
                return 0;
            }
        }
        return 2;
    }
}
