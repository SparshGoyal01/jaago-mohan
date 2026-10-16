# Jaago Mohan helper - the part a website can't do.
#
# Stay Active: once you've been idle 60s, sends an invisible F15 key + zero-pixel mouse move,
# so Slack/Teams' idle timer resets (and Windows' sleep timer with it).
#
# Lives in the system tray. The Jaago Mohan website talks to it on http://localhost:47474
# (GET /status, POST /active/on, POST /active/off) so the site's "Stay Active" toggle drives it.
# Run via "Start Jaago Mohan.cmd" (no console window).

$ErrorActionPreference = 'Stop'

$mutex = New-Object System.Threading.Mutex($false, 'Local\JaagoMohanHelper')
if (-not $mutex.WaitOne(0)) { exit }   # already running

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Text;
using System.Runtime.InteropServices;

public static class JaagoNative
{
    // ---- Idle detection -------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    public static uint IdleMilliseconds()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref lii);
        return unchecked((uint)Environment.TickCount - lii.dwTime);
    }

    // ---- Fake input -----------------------------------------------------------------
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion u; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT
    {
        public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT
    {
        public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo;
    }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);

    // Zero-pixel mouse move + F15 tap: resets the OS idle clock, invisible to every app.
    public static uint Nudge()
    {
        INPUT[] inp = new INPUT[3];
        inp[0].type = 0; inp[0].u.mi.dwFlags = 0x0001;                         // MOUSEEVENTF_MOVE, dx=dy=0
        inp[1].type = 1; inp[1].u.ki.wVk = 0x7E;                               // VK_F15 down
        inp[2].type = 1; inp[2].u.ki.wVk = 0x7E; inp[2].u.ki.dwFlags = 0x0002; // VK_F15 up
        return SendInput(3, inp, Marshal.SizeOf(typeof(INPUT)));
    }

    // ---- Local bridge for the website -----------------------------------------------
    public static volatile bool Active = true;
    public static volatile int Nudges = 0;
    static HttpListener listener;

    // Sites allowed to read/drive the helper. Add the custom domain here once it's live.
    static readonly string[] AllowedOrigins = {
        "https://sparshgoyal01.github.io",
        "https://sparshgoyal.work",
        "null"                                  // index.html opened straight from disk
    };

    static bool IsAllowed(string origin)
    {
        if (origin == null) return false;
        if (origin.StartsWith("http://localhost:") || origin.StartsWith("http://127.0.0.1:")) return true;
        return Array.IndexOf(AllowedOrigins, origin) >= 0;
    }

    public static string StartBridge(int port)
    {
        try
        {
            listener = new HttpListener();
            listener.Prefixes.Add("http://localhost:" + port + "/");
            listener.Start();
            listener.BeginGetContext(OnRequest, null);
            return null;
        }
        catch (Exception e) { return e.Message; }
    }

    public static void StopBridge()
    {
        try { if (listener != null) listener.Close(); } catch { }
    }

    static void OnRequest(IAsyncResult ar)
    {
        HttpListenerContext ctx;
        try { ctx = listener.EndGetContext(ar); } catch { return; }
        try { listener.BeginGetContext(OnRequest, null); } catch { }
        try { Handle(ctx); } catch { try { ctx.Response.Abort(); } catch { } }
    }

    static void Handle(HttpListenerContext ctx)
    {
        HttpListenerRequest req = ctx.Request;
        HttpListenerResponse res = ctx.Response;
        string origin = req.Headers["Origin"];

        if (!IsAllowed(origin)) { res.StatusCode = 403; res.Close(); return; }
        res.AddHeader("Access-Control-Allow-Origin", origin);
        res.AddHeader("Vary", "Origin");
        res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        res.AddHeader("Access-Control-Allow-Private-Network", "true");
        res.AddHeader("Access-Control-Allow-Local-Network", "true");

        if (req.HttpMethod == "OPTIONS") { res.StatusCode = 204; res.Close(); return; }

        string path = req.Url.AbsolutePath;
        if (req.HttpMethod == "POST" && path == "/active/on") Active = true;
        else if (req.HttpMethod == "POST" && path == "/active/off") Active = false;
        else if (!(req.HttpMethod == "GET" && path == "/status")) { res.StatusCode = 404; res.Close(); return; }

        string json = "{\"app\":\"jaago-mohan\",\"version\":1,\"active\":" + (Active ? "true" : "false") +
                      ",\"idleMs\":" + IdleMilliseconds() + ",\"nudges\":" + Nudges + "}";
        byte[] body = Encoding.UTF8.GetBytes(json);
        res.ContentType = "application/json";
        res.ContentLength64 = body.Length;
        res.OutputStream.Write(body, 0, body.Length);
        res.Close();
    }
}
'@

$bridgeError = [JaagoNative]::StartBridge(47474)

# ---- Tray icon: an eye, open while Stay Active is on ---------------------------------
function New-EyeIcon([bool]$open) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $amber = [System.Drawing.Color]::FromArgb(245, 166, 35)
    $grey  = [System.Drawing.Color]::FromArgb(140, 140, 140)
    if ($open) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush $amber), 1, 7, 30, 18)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(20, 22, 28))), 10, 9, 13, 13)
        $g.FillEllipse([System.Drawing.Brushes]::White, 17, 11, 4, 4)
    } else {
        $pen = New-Object System.Drawing.Pen $grey, 4
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
        $g.DrawArc($pen, 3, 2, 26, 20, 20, 140)
    }
    $g.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iconOn  = New-EyeIcon $true
$iconOff = New-EyeIcon $false

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$activeItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Stay Active (Slack/Teams)'
$activeItem.CheckOnClick = $true
$activeItem.add_CheckedChanged({ [JaagoNative]::Active = $activeItem.Checked })
[void]$menu.Items.Add($activeItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$exit = $menu.Items.Add('Quit Jaago Mohan helper')
$exit.add_Click({
    $timer.Stop()
    [JaagoNative]::StopBridge()
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$tray.ContextMenuStrip = $menu

# The website can flip Active from another thread, so the tray re-syncs on every tick.
function Sync-Tray {
    $on = [JaagoNative]::Active
    if ($activeItem.Checked -ne $on) { $activeItem.Checked = $on }
    $tray.Icon = if ($on) { $iconOn } else { $iconOff }
    $status = if ($on) { 'staying active' } else { 'paused' }
    $tray.Text = if ($bridgeError) { "Jaago Mohan - $status (website link off)" } else { "Jaago Mohan - $status" }
}

# Check every second; nudge only after 60s of real idleness.
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({
    Sync-Tray
    if ([JaagoNative]::Active -and [JaagoNative]::IdleMilliseconds() -ge 60000) {
        [void][JaagoNative]::Nudge()
        [JaagoNative]::Nudges++
    }
})

Sync-Tray
$timer.Start()
if ($bridgeError) {
    $tray.ShowBalloonTip(5000, 'Jaago Mohan', "Running, but the website can't reach it: $bridgeError", 'Warning')
} else {
    $tray.ShowBalloonTip(3000, 'Jaago Mohan', 'Running in the tray. Right-click the eye to pause or quit.', 'Info')
}

[System.Windows.Forms.Application]::Run()
$mutex.ReleaseMutex()
