<#
.SYNOPSIS
    Interactive mouse-hover UI element inspector for the TIA Java desktop application.

.DESCRIPTION
    Tracks the mouse cursor in real time and inspects the exact UI element under (X, Y)
    using a dual-engine pipeline:
      1. Java Access Bridge (JAB): Uses getAccessibleContextAt() plus a recursive
         bounding-box hit-test fallback to pinpoint the deepest Swing/AWT/Oracle Forms
         control under the cursor, and walks getAccessibleParentFromContext() to build
         the full hierarchy path and UiPath selector.
      2. Windows UI Automation (UIA) Fallback: Uses AutomationElement::FromPoint(X, Y)
         for native Win32 frames, dialogs, SWT/JavaFX controls, or when JAB is inactive.

    Supports two modes:
      - Interactive Live Hover Mode (default): Live-streams element details as you move
        the mouse. Hold CTRL (or press SPACE / F2) to capture/pin an element into the
        saved JSON list and copy its selector to the clipboard. Press ESC or Q to finish.
      - Single-Shot Countdown Mode (-SingleShot): Counts down N seconds while you hover
        over the target element, captures it, saves JSON, and exits.

.PARAMETER SingleShot
    If set, waits -CountdownSeconds, captures the single element under the cursor, and exits.

.PARAMETER CountdownSeconds
    Countdown duration in seconds when -SingleShot is enabled. Default: 5

.PARAMETER PollIntervalMs
    Mouse polling interval in milliseconds during live hover mode. Default: 200

.PARAMETER EnableJabSwitch
    If set, attempts to locate and run 'jabswitch.exe -enable' before initializing JAB.

.PARAMETER JabDllPath
    Optional explicit path to WindowsAccessBridge-64.dll or WindowsAccessBridge-32.dll.

.PARAMETER CopySelectorToClipboard
    If set (default: $true), copies the captured element's UiPath selector to the clipboard.

.PARAMETER OutputPath
    File path for the exported JSON report of captured elements.
    Default: ".\tia_hovered_elements_<timestamp>.json"

.EXAMPLE
    .\Inspect-TiaElementOnHover.ps1 -EnableJabSwitch

.EXAMPLE
    .\Inspect-TiaElementOnHover.ps1 -SingleShot -CountdownSeconds 5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SingleShot,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$CountdownSeconds = 5,

    [Parameter(Mandatory = $false)]
    [ValidateRange(50, 2000)]
    [int]$PollIntervalMs = 200,

    [Parameter(Mandatory = $false)]
    [switch]$EnableJabSwitch,

    [Parameter(Mandatory = $false)]
    [string]$JabDllPath = "",

    [Parameter(Mandatory = $false)]
    [bool]$CopySelectorToClipboard = $true,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath "tia_hovered_elements_$timestamp.json"
}

# ---------------------------------------------------------------------------
# 1. Embedded C# Interop: Win32 Cursor/Window Hit-Testing & Java Access Bridge
# ---------------------------------------------------------------------------
$csharpHoverSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TiaHoverInspector
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AccessibleContextInfo
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
        public string name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
        public string description;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string role;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string role_en_US;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string states;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string states_en_US;
        public int indexInParent;
        public int childrenCount;
        public int x;
        public int y;
        public int width;
        public int height;
        public int accessibleComponent;
        public int accessibleAction;
        public int accessibleSelection;
        public int accessibleText;
        public int accessibleInterfaces;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AccessibleTextInfo
    {
        public int charCount;
        public int caretIndex;
        public int indexAtPoint;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AccessibleTextItemsInfo
    {
        public char letter;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string word;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
        public string sentence;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AccessibleActionInfo
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string name;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct AccessibleActions
    {
        public int actionsCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public AccessibleActionInfo[] actionInfo;
    }

    public static class Win32Hover
    {
        public const uint GA_ROOT = 2;
        public const uint PM_REMOVE = 0x0001;
        public const int VK_CONTROL = 0x11;
        public const int VK_F2 = 0x71;
        public const int VK_ESCAPE = 0x1B;

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        public static extern IntPtr WindowFromPoint(POINT Point);

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        public static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

        [DllImport("user32.dll")]
        public static extern bool TranslateMessage(ref MSG lpMsg);

        [DllImport("user32.dll")]
        public static extern IntPtr DispatchMessage(ref MSG lpMsg);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr LoadLibrary(string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        public static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

        public static bool IsKeyDown(int vKey)
        {
            return (GetAsyncKeyState(vKey) & 0x8000) != 0;
        }

        public static void PumpMessages(int iterations = 10)
        {
            MSG msg;
            for (int i = 0; i < iterations; i++)
            {
                while (PeekMessage(out msg, IntPtr.Zero, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }
                System.Threading.Thread.Sleep(2);
            }
        }

        public static string ReadWindowTitle(IntPtr hWnd)
        {
            var sb = new StringBuilder(512);
            GetWindowText(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string ReadClassName(IntPtr hWnd)
        {
            var sb = new StringBuilder(256);
            GetClassName(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }
    }

    public class JabHoverBridge
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void Windows_run_Delegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int isJavaWindow_Delegate(IntPtr window);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleContextFromHWND_Delegate(IntPtr target, out int vmID, out long ac);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleContextAt_Delegate(int vmID, long acParent, int x, int y, out long ac);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleContextInfo_Delegate(int vmID, long ac, out AccessibleContextInfo info);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate long getAccessibleChildFromContext_Delegate(int vmID, long ac, int index);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate long getAccessibleParentFromContext_Delegate(int vmID, long ac);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void releaseJavaObject_Delegate(int vmID, long javaObject);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private delegate int getCurrentAccessibleValueFromContext_Delegate(int vmID, long av, StringBuilder value, short len);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleTextInfo_Delegate(int vmID, long at, out AccessibleTextInfo textInfo, int x, int y);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleTextItems_Delegate(int vmID, long at, out AccessibleTextItemsInfo textItems, int index);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
        private delegate int getAccessibleTextRange_Delegate(int vmID, long at, int start, int end, [Out] char[] text, short len);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleActions_Delegate(int vmID, long ac, out AccessibleActions actions);

        private IntPtr _hModule = IntPtr.Zero;
        private Windows_run_Delegate _windowsRun;
        private isJavaWindow_Delegate _isJavaWindow;
        private getAccessibleContextFromHWND_Delegate _getAccessibleContextFromHWND;
        private getAccessibleContextAt_Delegate _getAccessibleContextAt;
        private getAccessibleContextInfo_Delegate _getAccessibleContextInfo;
        private getAccessibleChildFromContext_Delegate _getAccessibleChildFromContext;
        private getAccessibleParentFromContext_Delegate _getAccessibleParentFromContext;
        private releaseJavaObject_Delegate _releaseJavaObject;
        private getCurrentAccessibleValueFromContext_Delegate _getCurrentAccessibleValueFromContext;
        private getAccessibleTextInfo_Delegate _getAccessibleTextInfo;
        private getAccessibleTextItems_Delegate _getAccessibleTextItems;
        private getAccessibleTextRange_Delegate _getAccessibleTextRange;
        private getAccessibleActions_Delegate _getAccessibleActions;

        public bool IsInitialized { get; private set; }
        public string LoadedDllPath { get; private set; }
        public string LastError { get; private set; }

        private T Bind<T>(string functionName) where T : class
        {
            IntPtr proc = Win32Hover.GetProcAddress(_hModule, functionName);
            if (proc == IntPtr.Zero) return null;
            return Marshal.GetDelegateForFunctionPointer(proc, typeof(T)) as T;
        }

        public bool Initialize(string dllPath)
        {
            try
            {
                _hModule = Win32Hover.LoadLibrary(dllPath);
                if (_hModule == IntPtr.Zero)
                {
                    LastError = "LoadLibrary failed for '" + dllPath + "' (Win32 Error: " + Marshal.GetLastWin32Error() + ")";
                    return false;
                }

                _windowsRun = Bind<Windows_run_Delegate>("Windows_run");
                _isJavaWindow = Bind<isJavaWindow_Delegate>("isJavaWindow");
                _getAccessibleContextFromHWND = Bind<getAccessibleContextFromHWND_Delegate>("getAccessibleContextFromHWND");
                _getAccessibleContextAt = Bind<getAccessibleContextAt_Delegate>("getAccessibleContextAt");
                _getAccessibleContextInfo = Bind<getAccessibleContextInfo_Delegate>("getAccessibleContextInfo");
                _getAccessibleChildFromContext = Bind<getAccessibleChildFromContext_Delegate>("getAccessibleChildFromContext");
                _getAccessibleParentFromContext = Bind<getAccessibleParentFromContext_Delegate>("getAccessibleParentFromContext");
                _releaseJavaObject = Bind<releaseJavaObject_Delegate>("releaseJavaObject");
                _getCurrentAccessibleValueFromContext = Bind<getCurrentAccessibleValueFromContext_Delegate>("getCurrentAccessibleValueFromContext");
                _getAccessibleTextInfo = Bind<getAccessibleTextInfo_Delegate>("getAccessibleTextInfo");
                _getAccessibleTextItems = Bind<getAccessibleTextItems_Delegate>("getAccessibleTextItems");
                _getAccessibleTextRange = Bind<getAccessibleTextRange_Delegate>("getAccessibleTextRange");
                _getAccessibleActions = Bind<getAccessibleActions_Delegate>("getAccessibleActions");

                if (_windowsRun == null || _isJavaWindow == null || _getAccessibleContextFromHWND == null || _getAccessibleContextInfo == null)
                {
                    LastError = "Required JAB entry points were not found in '" + dllPath + "'.";
                    return false;
                }

                _windowsRun();
                Win32Hover.PumpMessages(40);

                LoadedDllPath = dllPath;
                IsInitialized = true;
                return true;
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
                return false;
            }
        }

        public bool IsJavaWindow(IntPtr hwnd)
        {
            if (!IsInitialized || _isJavaWindow == null || hwnd == IntPtr.Zero) return false;
            Win32Hover.PumpMessages(4);
            return _isJavaWindow(hwnd) != 0;
        }

        public bool TryGetRootContext(IntPtr hwnd, out int vmID, out long ac)
        {
            vmID = 0;
            ac = 0;
            if (!IsInitialized || _getAccessibleContextFromHWND == null || hwnd == IntPtr.Zero) return false;
            Win32Hover.PumpMessages(4);
            int res = _getAccessibleContextFromHWND(hwnd, out vmID, out ac);
            return (res != 0 && ac != 0);
        }

        public bool TryGetContextAt(int vmID, long acParent, int x, int y, out long acChild)
        {
            acChild = 0;
            if (!IsInitialized || _getAccessibleContextAt == null || acParent == 0) return false;
            int res = _getAccessibleContextAt(vmID, acParent, x, y, out acChild);
            return (res != 0 && acChild != 0);
        }

        public bool TryGetContextInfo(int vmID, long ac, out AccessibleContextInfo info)
        {
            info = new AccessibleContextInfo();
            if (!IsInitialized || _getAccessibleContextInfo == null || ac == 0) return false;
            return _getAccessibleContextInfo(vmID, ac, out info) != 0;
        }

        public long GetChildContext(int vmID, long ac, int index)
        {
            if (!IsInitialized || _getAccessibleChildFromContext == null || ac == 0) return 0;
            return _getAccessibleChildFromContext(vmID, ac, index);
        }

        public long GetParentContext(int vmID, long ac)
        {
            if (!IsInitialized || _getAccessibleParentFromContext == null || ac == 0) return 0;
            return _getAccessibleParentFromContext(vmID, ac);
        }

        public void ReleaseObject(int vmID, long ac)
        {
            if (IsInitialized && _releaseJavaObject != null && ac != 0)
            {
                _releaseJavaObject(vmID, ac);
            }
        }

        public string GetAccessibleValue(int vmID, long ac)
        {
            if (!IsInitialized || _getCurrentAccessibleValueFromContext == null || ac == 0) return null;
            var sb = new StringBuilder(1024);
            int ok = _getCurrentAccessibleValueFromContext(vmID, ac, sb, (short)sb.Capacity);
            return ok != 0 ? sb.ToString() : null;
        }

        public string GetAccessibleText(int vmID, long ac, int cursorX, int cursorY)
        {
            if (!IsInitialized || _getAccessibleTextInfo == null || ac == 0) return null;
            AccessibleTextInfo textInfo;
            if (_getAccessibleTextInfo(vmID, ac, out textInfo, cursorX, cursorY) == 0) return null;
            if (textInfo.charCount <= 0) return "";

            if (_getAccessibleTextRange != null)
            {
                int maxChars = Math.Min(textInfo.charCount, 4096);
                char[] buffer = new char[maxChars + 1];
                if (_getAccessibleTextRange(vmID, ac, 0, maxChars - 1, buffer, (short)maxChars) != 0)
                {
                    return new string(buffer, 0, maxChars).TrimEnd('\0');
                }
            }

            if (_getAccessibleTextItems != null)
            {
                AccessibleTextItemsInfo items;
                if (_getAccessibleTextItems(vmID, ac, out items, 0) != 0)
                {
                    return !string.IsNullOrEmpty(items.sentence) ? items.sentence : items.word;
                }
            }

            return null;
        }

        public List<string> GetActions(int vmID, long ac)
        {
            var list = new List<string>();
            if (!IsInitialized || _getAccessibleActions == null || ac == 0) return list;
            AccessibleActions actions;
            if (_getAccessibleActions(vmID, ac, out actions) != 0 && actions.actionInfo != null)
            {
                int count = Math.Min(actions.actionsCount, actions.actionInfo.Length);
                for (int i = 0; i < count; i++)
                {
                    if (!string.IsNullOrWhiteSpace(actions.actionInfo[i].name))
                    {
                        list.Add(actions.actionInfo[i].name);
                    }
                }
            }
            return list;
        }
    }
}
"@

if (-not ("TiaHoverInspector.Win32Hover" -as [type])) {
    Add-Type -TypeDefinition $csharpHoverSource -Language CSharp
}

try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    $script:UiaAvailable = $true
}
catch {
    $script:UiaAvailable = $false
}

# ---------------------------------------------------------------------------
# 2. Locate & Initialize Java Access Bridge
# ---------------------------------------------------------------------------
function Find-JavaAccessBridgeDll {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $is64BitProcess = [Environment]::Is64BitProcess
    $dllName = if ($is64BitProcess) { "WindowsAccessBridge-64.dll" } else { "WindowsAccessBridge-32.dll" }
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:SystemRoot) {
        $candidates.Add((Join-Path $env:SystemRoot "System32\$dllName"))
        if (-not $is64BitProcess) {
            $candidates.Add((Join-Path $env:SystemRoot "SysWOW64\$dllName"))
        }
    }
    if ($env:JAVA_HOME) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\$dllName"))
        $candidates.Add((Join-Path $env:JAVA_HOME "jre\bin\$dllName"))
    }

    $programFilesDirs = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $javaRootNames = @("Java", "Eclipse Adoptium", "Temurin", "Oracle", "OpenJDK", "RedHat", "Zulu", "Amazon Corretto", "BellSoft")

    foreach ($pf in $programFilesDirs) {
        foreach ($rootName in $javaRootNames) {
            $searchRoot = Join-Path $pf $rootName
            if (Test-Path -LiteralPath $searchRoot) {
                $found = Get-ChildItem -Path $searchRoot -Filter $dllName -Recurse -ErrorAction SilentlyContinue |
                         Select-Object -ExpandProperty FullName
                foreach ($f in $found) { $candidates.Add($f) }
            }
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

if ($EnableJabSwitch) {
    $cmd = Get-Command "jabswitch.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source -enable | Out-Null
    }
}

$jabBridge = New-Object TiaHoverInspector.JabHoverBridge
$resolvedDll = Find-JavaAccessBridgeDll -ExplicitPath $JabDllPath
if ($resolvedDll) {
    [void]$jabBridge.Initialize($resolvedDll)
}

# ---------------------------------------------------------------------------
# 3. Deep Hit-Test & Ancestor Chain Builder for JAB and UIA
# ---------------------------------------------------------------------------
function Find-DeepestJabNodeByBounds {
    param(
        [TiaHoverInspector.JabHoverBridge]$Bridge,
        [int]$VmId,
        [long]$CurrentAc,
        [int]$ScreenX,
        [int]$ScreenY,
        [int]$Depth = 0
    )

    if ($Depth -gt 35 -or $CurrentAc -eq 0) { return [long]0 }

    $info = New-Object TiaHoverInspector.AccessibleContextInfo
    if (-not $Bridge.TryGetContextInfo($VmId, $CurrentAc, [ref]$info)) {
        return [long]0
    }

    # Check if (ScreenX, ScreenY) falls within current node's bounding box (when width/height > 0)
    $containsPoint = $true
    if ($info.width -gt 0 -and $info.height -gt 0) {
        $containsPoint = ($ScreenX -ge $info.x) -and ($ScreenX -le ($info.x + $info.width)) -and
                         ($ScreenY -ge $info.y) -and ($ScreenY -le ($info.y + $info.height))
    }

    if (-not $containsPoint -and $Depth -gt 0) {
        return [long]0
    }

    $childLimit = [Math]::Min($info.childrenCount, 200)
    for ($i = 0; $i -lt $childLimit; $i++) {
        $childAc = $Bridge.GetChildContext($VmId, $CurrentAc, $i)
        if ($childAc -ne 0) {
            $childInfo = New-Object TiaHoverInspector.AccessibleContextInfo
            if ($Bridge.TryGetContextInfo($VmId, $childAc, [ref]$childInfo)) {
                $rawStates = if ($childInfo.states_en_US) { $childInfo.states_en_US } else { $childInfo.states }
                $isShowing = [string]::IsNullOrEmpty($rawStates) -or ($rawStates -match "showing|visible")
                $inChild = ($childInfo.width -gt 0 -and $childInfo.height -gt 0) -and
                           ($ScreenX -ge $childInfo.x) -and ($ScreenX -le ($childInfo.x + $childInfo.width)) -and
                           ($ScreenY -ge $childInfo.y) -and ($ScreenY -le ($childInfo.y + $childInfo.height))

                if ($isShowing -and $inChild) {
                    $deeperMatch = Find-DeepestJabNodeByBounds `
                        -Bridge $Bridge `
                        -VmId $VmId `
                        -CurrentAc $childAc `
                        -ScreenX $ScreenX `
                        -ScreenY $ScreenY `
                        -Depth ($Depth + 1)

                    if ($deeperMatch -ne 0 -and $deeperMatch -ne $childAc) {
                        $Bridge.ReleaseObject($VmId, $childAc)
                        return $deeperMatch
                    }
                    return $childAc
                }
            }
            $Bridge.ReleaseObject($VmId, $childAc)
        }
    }

    return $CurrentAc
}

function Get-ElementAtCursor {
    param([int]$ScreenX, [int]$ScreenY)

    $pt = New-Object TiaHoverInspector.POINT
    $pt.X = $ScreenX
    $pt.Y = $ScreenY

    $hwndUnderCursor = [TiaHoverInspector.Win32Hover]::WindowFromPoint($pt)
    if ($hwndUnderCursor -eq [IntPtr]::Zero) { return $null }

    $rootHwnd = [TiaHoverInspector.Win32Hover]::GetAncestor($hwndUnderCursor, [TiaHoverInspector.Win32Hover]::GA_ROOT)
    if ($rootHwnd -eq [IntPtr]::Zero) { $rootHwnd = $hwndUnderCursor }

    $winTitle = [TiaHoverInspector.Win32Hover]::ReadWindowTitle($rootHwnd)
    $winClass = [TiaHoverInspector.Win32Hover]::ReadClassName($rootHwnd)
    $childClass = [TiaHoverInspector.Win32Hover]::ReadClassName($hwndUnderCursor)

    $pid = [uint32]0
    [void][TiaHoverInspector.Win32Hover]::GetWindowThreadProcessId($rootHwnd, [ref]$pid)
    $procName = ""
    try { $procName = (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName } catch {}

    # 1. Try Java Access Bridge on either child HWND or root HWND
    if ($jabBridge.IsInitialized) {
        $targetJavaHwnd = [IntPtr]::Zero
        if ($jabBridge.IsJavaWindow($hwndUnderCursor)) {
            $targetJavaHwnd = $hwndUnderCursor
        }
        elseif ($jabBridge.IsJavaWindow($rootHwnd)) {
            $targetJavaHwnd = $rootHwnd
        }

        if ($targetJavaHwnd -ne [IntPtr]::Zero) {
            $vmId = 0
            $rootAc = [long]0
            if ($jabBridge.TryGetRootContext($targetJavaHwnd, [ref]$vmId, [ref]$rootAc)) {
                $targetAc = [long]0
                try {
                    # First attempt native getAccessibleContextAt
                    [void]$jabBridge.TryGetContextAt($vmId, $rootAc, $ScreenX, $ScreenY, [ref]$targetAc)

                    # Also run recursive bounds hit-test to ensure we reach the deepest leaf control
                    $deepestAc = Find-DeepestJabNodeByBounds `
                        -Bridge $jabBridge `
                        -VmId $vmId `
                        -CurrentAc $rootAc `
                        -ScreenX $ScreenX `
                        -ScreenY $ScreenY `
                        -Depth 0

                    if ($deepestAc -ne 0 -and $deepestAc -ne $rootAc) {
                        if ($targetAc -ne 0 -and $targetAc -ne $rootAc -and $targetAc -ne $deepestAc) {
                            $jabBridge.ReleaseObject($vmId, $targetAc)
                        }
                        $targetAc = $deepestAc
                    }
                    elseif ($targetAc -eq 0) {
                        $targetAc = $rootAc
                    }

                    $info = New-Object TiaHoverInspector.AccessibleContextInfo
                    if ($jabBridge.TryGetContextInfo($vmId, $targetAc, [ref]$info)) {
                        $role = if ($info.role_en_US) { $info.role_en_US } else { $info.role }
                        $rawStates = if ($info.states_en_US) { $info.states_en_US } else { $info.states }
                        $statesList = @()
                        if ($rawStates) {
                            $statesList = @($rawStates -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
                        }

                        $val = $null
                        if ($info.accessibleInterfaces -band 1) {
                            $val = $jabBridge.GetAccessibleValue($vmId, $targetAc)
                        }
                        if ([string]::IsNullOrEmpty($val) -and ($info.accessibleText -ne 0)) {
                            $val = $jabBridge.GetAccessibleText($vmId, $targetAc, $ScreenX, $ScreenY)
                        }

                        $actions = @()
                        if ($info.accessibleAction -ne 0) {
                            $actions = @($jabBridge.GetActions($vmId, $targetAc))
                        }

                        # Walk parent chain to construct full path
                        $pathSegments = New-Object System.Collections.Generic.List[string]
                        $idx = if ($info.indexInParent -ge 0) { $info.indexInParent } else { 0 }
                        $pathSegments.Add("$role[$idx]")

                        $currParent = $jabBridge.GetParentContext($vmId, $targetAc)
                        $guard = 0
                        while ($currParent -ne 0 -and $guard -lt 40) {
                            $pInfo = New-Object TiaHoverInspector.AccessibleContextInfo
                            if ($jabBridge.TryGetContextInfo($vmId, $currParent, [ref]$pInfo)) {
                                $pRole = if ($pInfo.role_en_US) { $pInfo.role_en_US } else { $pInfo.role }
                                $pIdx = if ($pInfo.indexInParent -ge 0) { $pInfo.indexInParent } else { 0 }
                                $pathSegments.Add("$pRole[$pIdx]")
                            }
                            $nextParent = $jabBridge.GetParentContext($vmId, $currParent)
                            $jabBridge.ReleaseObject($vmId, $currParent)
                            $currParent = $nextParent
                            $guard++
                        }
                        [array]::Reverse($pathSegments)
                        $fullPath = "/" + ($pathSegments -join "/")

                        $safeWinTitle = if ($winTitle) { $winTitle -replace "'", "&apos;" } else { "*" }
                        $safeName = if ($info.name) { $info.name -replace "'", "&apos;" } else { "" }
                        $uipathSelector = if ($safeName -ne "") {
                            "<wnd app='$procName.exe' cls='$winClass' title='$safeWinTitle' /><java role='$role' name='$safeName' idx='$($idx + 1)' />"
                        }
                        else {
                            "<wnd app='$procName.exe' cls='$winClass' title='$safeWinTitle' /><java role='$role' idx='$($idx + 1)' />"
                        }

                        return [ordered]@{
                            capturedAt     = (Get-Date).ToString("o")
                            cursor         = [ordered]@{ x = $ScreenX; y = $ScreenY }
                            engine         = "JavaAccessBridge"
                            hwnd           = ("0x{0:X8}" -f $targetJavaHwnd.ToInt64())
                            windowTitle    = $winTitle
                            windowClass    = $winClass
                            processName    = $procName
                            processId      = $pid
                            name           = $info.name
                            description    = $info.description
                            role           = $role
                            indexInParent  = $info.indexInParent
                            childrenCount  = $info.childrenCount
                            states         = $statesList
                            value          = $val
                            actions        = $actions
                            bounds         = [ordered]@{
                                x      = $info.x
                                y      = $info.y
                                width  = $info.width
                                height = $info.height
                            }
                            path           = $fullPath
                            uipathSelector = $uipathSelector
                        }
                    }
                }
                finally {
                    if ($targetAc -ne 0 -and $targetAc -ne $rootAc) {
                        $jabBridge.ReleaseObject($vmId, $targetAc)
                    }
                    $jabBridge.ReleaseObject($vmId, $rootAc)
                }
            }
        }
    }

    # 2. Fallback to Windows UI Automation (UIA)
    if ($script:UiaAvailable) {
        try {
            $winPt = New-Object System.Windows.Point($ScreenX, $ScreenY)
            $uiaEl = [System.Windows.Automation.AutomationElement]::FromPoint($winPt)
            if ($null -ne $uiaEl) {
                $curr = $uiaEl.Current
                $role = if ($curr.ControlType) {
                    $curr.ControlType.ProgrammaticName -replace "^ControlType\.", ""
                }
                else { "Custom" }

                $states = New-Object System.Collections.Generic.List[string]
                if ($curr.IsEnabled) { $states.Add("enabled") }
                if (-not $curr.IsOffscreen) { $states.Add("visible") }
                if ($curr.HasKeyboardFocus) { $states.Add("focused") }

                $val = $null
                $valPatternObj = $null
                if ($uiaEl.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valPatternObj)) {
                    $val = ($valPatternObj -as [System.Windows.Automation.ValuePattern]).Current.Value
                }

                $rect = $curr.BoundingRectangle
                $bounds = if ($rect -and -not [double]::IsInfinity($rect.Width)) {
                    [ordered]@{
                        x      = [int]$rect.X
                        y      = [int]$rect.Y
                        width  = [int]$rect.Width
                        height = [int]$rect.Height
                    }
                }
                else {
                    [ordered]@{ x = 0; y = 0; width = 0; height = 0 }
                }

                # Walk UIA ancestors for path
                $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
                $pathParts = New-Object System.Collections.Generic.List[string]
                $node = $uiaEl
                $depthGuard = 0
                while ($null -ne $node -and $depthGuard -lt 25) {
                    $cRole = if ($node.Current.ControlType) {
                        $node.Current.ControlType.ProgrammaticName -replace "^ControlType\.", ""
                    } else { "Node" }
                    $cName = if ($node.Current.Name) { "('$($node.Current.Name)')" } else { "" }
                    $pathParts.Add("${cRole}${cName}")
                    if ($node.Current.NativeWindowHandle -eq $rootHwnd.ToInt32()) { break }
                    $node = $walker.GetParent($node)
                    $depthGuard++
                }
                [array]::Reverse($pathParts)
                $fullPath = "/" + ($pathParts -join "/")

                $safeWinTitle = if ($winTitle) { $winTitle -replace "'", "&apos;" } else { "*" }
                $safeName = if ($curr.Name) { $curr.Name -replace "'", "&apos;" } else { "" }
                $uipathSelector = if ($safeName -ne "") {
                    "<wnd app='$procName.exe' cls='$winClass' title='$safeWinTitle' /><ctrl role='$role' name='$safeName' />"
                }
                else {
                    "<wnd app='$procName.exe' cls='$winClass' title='$safeWinTitle' /><ctrl role='$role' automationid='$($curr.AutomationId)' />"
                }

                return [ordered]@{
                    capturedAt     = (Get-Date).ToString("o")
                    cursor         = [ordered]@{ x = $ScreenX; y = $ScreenY }
                    engine         = "WindowsUIAutomation"
                    hwnd           = ("0x{0:X8}" -f $rootHwnd.ToInt64())
                    windowTitle    = $winTitle
                    windowClass    = $winClass
                    childClass     = $childClass
                    processName    = $procName
                    processId      = $pid
                    name           = $curr.Name
                    automationId   = $curr.AutomationId
                    className      = $curr.ClassName
                    description    = $curr.HelpText
                    role           = $role
                    states         = $states
                    value          = $val
                    actions        = @()
                    bounds         = $bounds
                    path           = $fullPath
                    uipathSelector = $uipathSelector
                }
            }
        }
        catch {
            # Ignore transient UIA hit-test errors
        }
    }

    return $null
}

function Show-ElementSummaryCard {
    param([Parameter(Mandatory = $true)]$Element, [string]$HeaderPrefix = "[HOVER]")

    Write-Host "`n$HeaderPrefix ($($Element.cursor.x), $($Element.cursor.y)) | Engine: $($Element.engine)" -ForegroundColor Cyan
    Write-Host ("  Window   : '{0}' (Class: {1}, Process: {2}, HWND: {3})" -f `
        $Element.windowTitle, $Element.windowClass, $Element.processName, $Element.hwnd) -ForegroundColor Gray
    Write-Host ("  Role     : {0}  |  Name: '{1}'" -f $Element.role, $Element.name) -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($Element.value)) {
        Write-Host ("  Value    : {0}" -f $Element.value) -ForegroundColor Yellow
    }
    Write-Host ("  Bounds   : X={0}, Y={1}, W={2}, H={3}" -f `
        $Element.bounds.x, $Element.bounds.y, $Element.bounds.width, $Element.bounds.height) -ForegroundColor White
    Write-Host ("  Path     : {0}" -f $Element.path) -ForegroundColor DarkGray
    Write-Host ("  Selector : {0}" -f $Element.uipathSelector) -ForegroundColor Magenta
}

# ---------------------------------------------------------------------------
# 4. Run Interactive Hover Loop or Single-Shot Countdown
# ---------------------------------------------------------------------------
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " TIA Mouse-Hover UI Element Inspector" -ForegroundColor Cyan
Write-Host " JAB Active: $($jabBridge.IsInitialized) $(if ($jabBridge.LoadedDllPath) { "($($jabBridge.LoadedDllPath))" })" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

$capturedElements = New-Object System.Collections.Generic.List[object]

if ($SingleShot) {
    Write-Host "`n[Single-Shot Mode] Move your mouse over the target TIA element..." -ForegroundColor Yellow
    for ($s = $CountdownSeconds; $s -ge 1; $s--) {
        Write-Host "  Capturing in $s second(s)..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 1
    }

    $pt = New-Object TiaHoverInspector.POINT
    [void][TiaHoverInspector.Win32Hover]::GetCursorPos([ref]$pt)
    $el = Get-ElementAtCursor -ScreenX $pt.X -ScreenY $pt.Y
    if ($null -ne $el) {
        $capturedElements.Add($el)
        Show-ElementSummaryCard -Element $el -HeaderPrefix "[CAPTURED]"
        if ($CopySelectorToClipboard -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
            Set-Clipboard -Value $el.uipathSelector
            Write-Host "  -> Copied UiPath Selector to Clipboard!" -ForegroundColor Green
        }
    }
    else {
        Write-Warning "No accessible element was found at cursor ($($pt.X), $($pt.Y))."
    }
}
else {
    Write-Host "`nControls:" -ForegroundColor Yellow
    Write-Host "  - Move mouse over any TIA control to see live element details" -ForegroundColor White
    Write-Host "  - Hold [CTRL] or press [F2] to PIN / CAPTURE the current element" -ForegroundColor Green
    Write-Host "  - Press [Q] or [ESC] to finish and save all captured elements to JSON`n" -ForegroundColor Cyan

    $lastSignature = ""
    $lastCaptureTime = [DateTime]::MinValue

    while ($true) {
        # Check console keys (Q or ESC)
        if ([Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            if ($keyInfo.Key -eq [ConsoleKey]::Escape -or $keyInfo.Key -eq [ConsoleKey]::Q) {
                Write-Host "`nStopping hover inspector..." -ForegroundColor Cyan
                break
            }
        }

        if ([TiaHoverInspector.Win32Hover]::IsKeyDown([TiaHoverInspector.Win32Hover]::VK_ESCAPE)) {
            Write-Host "`nESC detected. Stopping hover inspector..." -ForegroundColor Cyan
            break
        }

        $pt = New-Object TiaHoverInspector.POINT
        if ([TiaHoverInspector.Win32Hover]::GetCursorPos([ref]$pt)) {
            $el = Get-ElementAtCursor -ScreenX $pt.X -ScreenY $pt.Y
            if ($null -ne $el) {
                $sig = "$($el.hwnd)|$($el.role)|$($el.name)|$($el.path)|$($el.bounds.x),$($el.bounds.y)"
                if ($sig -ne $lastSignature) {
                    $lastSignature = $sig
                    Show-ElementSummaryCard -Element $el -HeaderPrefix "[LIVE HOVER]"
                }

                # Check if user pressed CTRL or F2 to capture/pin
                $ctrlDown = [TiaHoverInspector.Win32Hover]::IsKeyDown([TiaHoverInspector.Win32Hover]::VK_CONTROL)
                $f2Down = [TiaHoverInspector.Win32Hover]::IsKeyDown([TiaHoverInspector.Win32Hover]::VK_F2)

                if (($ctrlDown -or $f2Down) -and (((Get-Date) - $lastCaptureTime).TotalMilliseconds -gt 800)) {
                    $lastCaptureTime = Get-Date
                    $capturedElements.Add($el)
                    Write-Host ("  >>> [PINNED #{0}] Captured '{1}' ({2}) at ({3}, {4}) <<<" -f `
                        $capturedElements.Count, $el.name, $el.role, $pt.X, $pt.Y) -ForegroundColor Black -BackgroundColor Green

                    if ($CopySelectorToClipboard -and (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
                        Set-Clipboard -Value $el.uipathSelector
                        Write-Host "  >>> Selector copied to clipboard! <<<" -ForegroundColor Green
                    }
                }
            }
        }

        Start-Sleep -Milliseconds $PollIntervalMs
    }
}

# ---------------------------------------------------------------------------
# 5. Save Captured Elements to JSON
# ---------------------------------------------------------------------------
$report = [ordered]@{
    metadata = [ordered]@{
        exportedAt        = (Get-Date).ToString("o")
        mode              = if ($SingleShot) { "SingleShot" } else { "InteractiveHover" }
        jabInitialized    = $jabBridge.IsInitialized
        jabDllPath        = $jabBridge.LoadedDllPath
        capturedCount     = $capturedElements.Count
    }
    capturedElements = $capturedElements
}

$json = $report | ConvertTo-Json -Depth 50
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " Saved $($capturedElements.Count) captured element(s) to:" -ForegroundColor Green
Write-Host " $OutputPath" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
