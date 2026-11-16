<#
.SYNOPSIS
    Extracts the full recursive UI element tree from the TIA Java desktop application.

.DESCRIPTION
    Discovers open windows belonging to the TIA Java application and extracts their UI
    element hierarchy using a dual-engine pipeline:
      1. Java Access Bridge (JAB) via P/Invoke (WindowsAccessBridge-64.dll / -32.dll)
         for deep inspection of Swing, AWT, and Oracle Forms controls.
      2. Windows UI Automation (System.Windows.Automation) fallback for native frames,
         dialogs, SWT/JavaFX containers, or environments without JAB active.

    Outputs a structured JSON file containing both the hierarchical UI tree (rootTree)
    and a flattened element inventory (flatElements) with coordinates, roles, names,
    descriptions, states, values, actions, and hierarchical paths.

.PARAMETER WindowTitlePattern
    Wildcard pattern(s) to match against window titles. Default: "*tia*"

.PARAMETER ProcessNamePattern
    Regex pattern to match against process names hosting TIA.
    Default: "(?i)^(java|javaw|jp2launcher|jinitiator|tia)"

.PARAMETER IncludeAllJavaWindows
    If set, extracts all detected Java windows (SunAwtFrame, SunAwtDialog, etc.)
    even if their window title does not match -WindowTitlePattern.

.PARAMETER MaxDepth
    Maximum recursion depth when walking the element tree. Default: 50

.PARAMETER VisibleOnly
    If set, skips elements that are offscreen or do not have the 'visible'/'showing' state.

.PARAMETER EnableJabSwitch
    If set, attempts to locate and run 'jabswitch.exe -enable' before initializing JAB.

.PARAMETER JabDllPath
    Optional explicit path to WindowsAccessBridge-64.dll or WindowsAccessBridge-32.dll.

.PARAMETER OutputPath
    File path for the exported JSON report.
    Default: ".\tia_ui_elements_<timestamp>.json"

.EXAMPLE
    .\Extract-TiaUiElements.ps1 -EnableJabSwitch

.EXAMPLE
    .\Extract-TiaUiElements.ps1 -IncludeAllJavaWindows -OutputPath ".\tia_dump.json"

.EXAMPLE
    .\Extract-TiaUiElements.ps1 -WindowTitlePattern "*TIA*","*Policy*" -VisibleOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$WindowTitlePattern = @("*tia*"),

    [Parameter(Mandatory = $false)]
    [string]$ProcessNamePattern = "(?i)^(java|javaw|jp2launcher|jinitiator|tia|msedge|jp2)",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAllJavaWindows,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 250)]
    [int]$MaxDepth = 50,

    [Parameter(Mandatory = $false)]
    [switch]$VisibleOnly,

    [Parameter(Mandatory = $false)]
    [switch]$EnableJabSwitch,

    [Parameter(Mandatory = $false)]
    [string]$JabDllPath = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. Resolve Default Output Path
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath "tia_ui_elements_$timestamp.json"
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " TIA Java Application UI Element Extractor" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 2. Embedded C# Interop for Win32 Enumeration & Java Access Bridge (JAB)
# ---------------------------------------------------------------------------
$csharpSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace TiaUiExtractor
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
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

    // Java Access Bridge Structures (per OpenJDK accessBridgePackages.h)
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

    public class Win32WindowInfo
    {
        public IntPtr Hwnd { get; set; }
        public IntPtr ParentHwnd { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public uint ProcessId { get; set; }
        public bool IsVisible { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public static class NativeMethods
    {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

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

        public const uint PM_REMOVE = 0x0001;

        public static void PumpMessages(int iterations = 25)
        {
            MSG msg;
            for (int i = 0; i < iterations; i++)
            {
                while (PeekMessage(out msg, IntPtr.Zero, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }
                System.Threading.Thread.Sleep(5);
            }
        }

        public static List<Win32WindowInfo> EnumerateAllWindows(bool includeChildWindows)
        {
            var results = new List<Win32WindowInfo>();
            EnumWindows((hWnd, lParam) =>
            {
                var info = ReadWindowInfo(hWnd, IntPtr.Zero);
                results.Add(info);

                if (includeChildWindows && info.IsVisible)
                {
                    EnumChildWindows(hWnd, (childHwnd, childParam) =>
                    {
                        var childInfo = ReadWindowInfo(childHwnd, hWnd);
                        results.Add(childInfo);
                        return true;
                    }, IntPtr.Zero);
                }
                return true;
            }, IntPtr.Zero);

            return results;
        }

        public static Win32WindowInfo ReadWindowInfo(IntPtr hWnd, IntPtr parentHwnd)
        {
            var titleSb = new StringBuilder(512);
            GetWindowText(hWnd, titleSb, titleSb.Capacity);

            var classSb = new StringBuilder(256);
            GetClassName(hWnd, classSb, classSb.Capacity);

            uint pid = 0;
            GetWindowThreadProcessId(hWnd, out pid);

            RECT rect;
            GetWindowRect(hWnd, out rect);

            return new Win32WindowInfo
            {
                Hwnd = hWnd,
                ParentHwnd = parentHwnd,
                Title = titleSb.ToString(),
                ClassName = classSb.ToString(),
                ProcessId = pid,
                IsVisible = IsWindowVisible(hWnd),
                X = rect.Left,
                Y = rect.Top,
                Width = Math.Max(0, rect.Right - rect.Left),
                Height = Math.Max(0, rect.Bottom - rect.Top)
            };
        }
    }

    public class JabBridge
    {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void Windows_run_Delegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int isJavaWindow_Delegate(IntPtr window);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleContextFromHWND_Delegate(IntPtr target, out int vmID, out long ac);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int getAccessibleContextInfo_Delegate(int vmID, long ac, out AccessibleContextInfo info);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate long getAccessibleChildFromContext_Delegate(int vmID, long ac, int index);

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
        private getAccessibleContextInfo_Delegate _getAccessibleContextInfo;
        private getAccessibleChildFromContext_Delegate _getAccessibleChildFromContext;
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
            IntPtr proc = NativeMethods.GetProcAddress(_hModule, functionName);
            if (proc == IntPtr.Zero) return null;
            return Marshal.GetDelegateForFunctionPointer(proc, typeof(T)) as T;
        }

        public bool Initialize(string dllPath)
        {
            try
            {
                _hModule = NativeMethods.LoadLibrary(dllPath);
                if (_hModule == IntPtr.Zero)
                {
                    LastError = "LoadLibrary failed for '" + dllPath + "' (Win32 Error: " + Marshal.GetLastWin32Error() + ")";
                    return false;
                }

                _windowsRun = Bind<Windows_run_Delegate>("Windows_run");
                _isJavaWindow = Bind<isJavaWindow_Delegate>("isJavaWindow");
                _getAccessibleContextFromHWND = Bind<getAccessibleContextFromHWND_Delegate>("getAccessibleContextFromHWND");
                _getAccessibleContextInfo = Bind<getAccessibleContextInfo_Delegate>("getAccessibleContextInfo");
                _getAccessibleChildFromContext = Bind<getAccessibleChildFromContext_Delegate>("getAccessibleChildFromContext");
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
                NativeMethods.PumpMessages(40);

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
            if (!IsInitialized || _isJavaWindow == null) return false;
            NativeMethods.PumpMessages(5);
            return _isJavaWindow(hwnd) != 0;
        }

        public bool TryGetRootContext(IntPtr hwnd, out int vmID, out long ac)
        {
            vmID = 0;
            ac = 0;
            if (!IsInitialized || _getAccessibleContextFromHWND == null) return false;
            NativeMethods.PumpMessages(5);
            int res = _getAccessibleContextFromHWND(hwnd, out vmID, out ac);
            return (res != 0 && ac != 0);
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

        public string GetAccessibleText(int vmID, long ac)
        {
            if (!IsInitialized || _getAccessibleTextInfo == null || ac == 0) return null;
            AccessibleTextInfo textInfo;
            if (_getAccessibleTextInfo(vmID, ac, out textInfo, 0, 0) == 0) return null;
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

if (-not ("TiaUiExtractor.NativeMethods" -as [type])) {
    Add-Type -TypeDefinition $csharpSource -Language CSharp
}

# Load Windows UI Automation Assemblies for Fallback / Hybrid Inspection
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop
    $script:UiaAvailable = $true
}
catch {
    Write-Warning "Windows UIAutomation assemblies could not be loaded: $($_.Exception.Message)"
    $script:UiaAvailable = $false
}

# ---------------------------------------------------------------------------
# 3. Helper Functions: Locate & Initialize Java Access Bridge
# ---------------------------------------------------------------------------
function Find-JavaAccessBridgeDll {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        Write-Warning "Specified -JabDllPath '$ExplicitPath' was not found. Searching standard locations..."
    }

    $is64BitProcess = [Environment]::Is64BitProcess
    $dllName = if ($is64BitProcess) { "WindowsAccessBridge-64.dll" } else { "WindowsAccessBridge-32.dll" }

    $candidates = New-Object System.Collections.Generic.List[string]

    # 1. System32 / SysWOW64
    if ($env:SystemRoot) {
        $candidates.Add((Join-Path $env:SystemRoot "System32\$dllName"))
        if (-not $is64BitProcess) {
            $candidates.Add((Join-Path $env:SystemRoot "SysWOW64\$dllName"))
            $candidates.Add((Join-Path $env:SystemRoot "SysWOW64\WindowsAccessBridge.dll"))
        }
    }

    # 2. JAVA_HOME
    if ($env:JAVA_HOME) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin\$dllName"))
        $candidates.Add((Join-Path $env:JAVA_HOME "jre\bin\$dllName"))
    }

    # 3. Common Java installation directories
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

    # 4. Also inspect running Java process paths
    $javaProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)^(java|javaw|jp2launcher)" }
    foreach ($proc in $javaProcs) {
        try {
            $procPath = $proc.MainModule.FileName
            if ($procPath) {
                $binDir = Split-Path -Parent $procPath
                $candidates.Add((Join-Path $binDir $dllName))
            }
        }
        catch {
            # Access denied or 32/64 bit mismatch on MainModule; ignore safely
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Enable-JavaAccessBridgeSwitch {
    $jabSwitchPaths = New-Object System.Collections.Generic.List[string]
    $cmd = Get-Command "jabswitch.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $jabSwitchPaths.Add($cmd.Source) }

    if ($env:JAVA_HOME) {
        $jabSwitchPaths.Add((Join-Path $env:JAVA_HOME "bin\jabswitch.exe"))
    }

    $programFilesDirs = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($pf in $programFilesDirs) {
        $javaDir = Join-Path $pf "Java"
        if (Test-Path -LiteralPath $javaDir) {
            $found = Get-ChildItem -Path $javaDir -Filter "jabswitch.exe" -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1 -ExpandProperty FullName
            if ($found) { $jabSwitchPaths.Add($found) }
        }
    }

    foreach ($exe in $jabSwitchPaths) {
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            Write-Host "[JAB] Running '$exe -enable'..." -ForegroundColor DarkCyan
            & $exe -enable | Out-Null
            return $true
        }
    }

    Write-Warning "Could not locate jabswitch.exe automatically."
    return $false
}

# ---------------------------------------------------------------------------
# 4. JAB Recursive Tree Extraction
# ---------------------------------------------------------------------------
function Get-JabElementTree {
    param(
        [Parameter(Mandatory = $true)][TiaUiExtractor.JabBridge]$Bridge,
        [Parameter(Mandatory = $true)][int]$VmId,
        [Parameter(Mandatory = $true)][long]$ContextHandle,
        [Parameter(Mandatory = $true)][int]$WindowIndex,
        [Parameter(Mandatory = $true)][int]$Depth,
        [Parameter(Mandatory = $true)][string]$ParentPath,
        [Parameter(Mandatory = $true)][string]$NodeIdPrefix,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$FlatList
    )

    if ($Depth -gt $MaxDepth -or $ContextHandle -eq 0) {
        return $null
    }

    $info = New-Object TiaUiExtractor.AccessibleContextInfo
    if (-not $Bridge.TryGetContextInfo($VmId, $ContextHandle, [ref]$info)) {
        return $null
    }

    $role = if (-not [string]::IsNullOrWhiteSpace($info.role_en_US)) { $info.role_en_US } else { $info.role }
    if ([string]::IsNullOrWhiteSpace($role)) { $role = "unknown" }

    $rawStates = if (-not [string]::IsNullOrWhiteSpace($info.states_en_US)) { $info.states_en_US } else { $info.states }
    $statesList = @()
    if (-not [string]::IsNullOrWhiteSpace($rawStates)) {
        $statesList = @($rawStates -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }

    if ($VisibleOnly -and $Depth -gt 0) {
        $isVisible = ($statesList -contains "visible") -or ($statesList -contains "showing")
        if (-not $isVisible) {
            return $null
        }
    }

    $idx = if ($info.indexInParent -ge 0) { $info.indexInParent } else { 0 }
    $currentPath = "$ParentPath/$role[$idx]"

    # Extract value or accessible text if available
    $elementValue = $null
    if ($info.accessibleInterfaces -band 1) {
        $elementValue = $Bridge.GetAccessibleValue($VmId, $ContextHandle)
    }
    if ([string]::IsNullOrEmpty($elementValue) -and ($info.accessibleText -ne 0)) {
        $elementValue = $Bridge.GetAccessibleText($VmId, $ContextHandle)
    }

    # Extract supported accessible actions
    $actions = @()
    if ($info.accessibleAction -ne 0) {
        $actions = @($Bridge.GetActions($VmId, $ContextHandle))
    }

    $bounds = [ordered]@{
        x      = $info.x
        y      = $info.y
        width  = $info.width
        height = $info.height
    }

    # Build UiPath-style Java selector hint
    $safeName = if ($info.name) { $info.name -replace "'", "&apos;" } else { "" }
    $uipathHint = if ($safeName -ne "") {
        "<java role='$role' name='$safeName' idx='$($idx + 1)' />"
    }
    else {
        "<java role='$role' idx='$($idx + 1)' />"
    }

    $flatEntry = [ordered]@{
        id             = $NodeIdPrefix
        path           = $currentPath
        uipathSelector = $uipathHint
        depth          = $Depth
        indexInParent  = $info.indexInParent
        name           = $info.name
        description    = $info.description
        role           = $role
        states         = $statesList
        value          = $elementValue
        actions        = $actions
        bounds         = $bounds
        childrenCount  = $info.childrenCount
    }
    $FlatList.Add($flatEntry)

    $childrenNodes = New-Object System.Collections.Generic.List[object]
    $childLimit = [Math]::Min($info.childrenCount, 500)

    for ($i = 0; $i -lt $childLimit; $i++) {
        $childAc = $Bridge.GetChildContext($VmId, $ContextHandle, $i)
        if ($childAc -ne 0) {
            try {
                $childId = "${NodeIdPrefix}_$i"
                $childNode = Get-JabElementTree `
                    -Bridge $Bridge `
                    -VmId $VmId `
                    -ContextHandle $childAc `
                    -WindowIndex $WindowIndex `
                    -Depth ($Depth + 1) `
                    -ParentPath $currentPath `
                    -NodeIdPrefix $childId `
                    -FlatList $FlatList

                if ($null -ne $childNode) {
                    $childrenNodes.Add($childNode)
                }
            }
            finally {
                $Bridge.ReleaseObject($VmId, $childAc)
            }
        }
    }

    return [ordered]@{
        id             = $NodeIdPrefix
        path           = $currentPath
        uipathSelector = $uipathHint
        depth          = $Depth
        indexInParent  = $info.indexInParent
        name           = $info.name
        description    = $info.description
        role           = $role
        states         = $statesList
        value          = $elementValue
        actions        = $actions
        bounds         = $bounds
        childrenCount  = $info.childrenCount
        children       = $childrenNodes
    }
}

# ---------------------------------------------------------------------------
# 5. Windows UI Automation (UIA) Fallback Recursive Tree Extraction
# ---------------------------------------------------------------------------
function Get-UiaElementTree {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Automation.AutomationElement]$Element,
        [Parameter(Mandatory = $true)][int]$Depth,
        [Parameter(Mandatory = $true)][int]$IndexInParent,
        [Parameter(Mandatory = $true)][string]$ParentPath,
        [Parameter(Mandatory = $true)][string]$NodeIdPrefix,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$FlatList
    )

    if ($Depth -gt $MaxDepth -or $null -eq $Element) {
        return $null
    }

    try {
        $current = $Element.Current
        if ($VisibleOnly -and $Depth -gt 0 -and $current.IsOffscreen) {
            return $null
        }

        $role = if ($current.ControlType) {
            $current.ControlType.ProgrammaticName -replace "^ControlType\.", ""
        }
        else {
            "Custom"
        }

        $name = $current.Name
        $autoId = $current.AutomationId
        $className = $current.ClassName
        $currentPath = "$ParentPath/$role[$IndexInParent]"

        $states = New-Object System.Collections.Generic.List[string]
        if ($current.IsEnabled) { $states.Add("enabled") }
        if (-not $current.IsOffscreen) { $states.Add("visible") }
        if ($current.IsKeyboardFocusable) { $states.Add("focusable") }
        if ($current.HasKeyboardFocus) { $states.Add("focused") }

        # Attempt to extract ValuePattern if supported
        $val = $null
        $valPatternObj = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valPatternObj)) {
            $val = ($valPatternObj -as [System.Windows.Automation.ValuePattern]).Current.Value
        }

        $rect = $current.BoundingRectangle
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

        $safeName = if ($name) { $name -replace "'", "&apos;" } else { "" }
        $uipathHint = if ($safeName -ne "") {
            "<wnd cls='$className' title='$safeName' /><ctrl role='$role' name='$safeName' />"
        }
        else {
            "<ctrl role='$role' automationid='$autoId' idx='$($IndexInParent + 1)' />"
        }

        $childrenNodes = New-Object System.Collections.Generic.List[object]
        $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
        $child = $walker.GetFirstChild($Element)
        $childIdx = 0

        # Add current node to flat list first (pre-order traversal)
        $flatEntry = [ordered]@{
            id             = $NodeIdPrefix
            path           = $currentPath
            uipathSelector = $uipathHint
            depth          = $Depth
            indexInParent  = $IndexInParent
            name           = $name
            automationId   = $autoId
            className      = $className
            description    = $current.HelpText
            role           = $role
            states         = $states
            value          = $val
            actions        = @()
            bounds         = $bounds
            childrenCount  = 0
        }
        $FlatList.Add($flatEntry)

        while ($null -ne $child -and $childIdx -lt 500) {
            $childId = "${NodeIdPrefix}_$childIdx"
            $childTree = Get-UiaElementTree `
                -Element $child `
                -Depth ($Depth + 1) `
                -IndexInParent $childIdx `
                -ParentPath $currentPath `
                -NodeIdPrefix $childId `
                -FlatList $FlatList

            if ($null -ne $childTree) {
                $childrenNodes.Add($childTree)
            }

            $child = $walker.GetNextSibling($child)
            $childIdx++
        }

        $flatEntry.childrenCount = $childrenNodes.Count

        return [ordered]@{
            id             = $NodeIdPrefix
            path           = $currentPath
            uipathSelector = $uipathHint
            depth          = $Depth
            indexInParent  = $IndexInParent
            name           = $name
            automationId   = $autoId
            className      = $className
            description    = $current.HelpText
            role           = $role
            states         = $states
            value          = $val
            actions        = @()
            bounds         = $bounds
            childrenCount  = $childrenNodes.Count
            children       = $childrenNodes
        }
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# 6. Main Execution Flow
# ---------------------------------------------------------------------------
if ($EnableJabSwitch) {
    Enable-JavaAccessBridgeSwitch | Out-Null
}

$jabBridge = New-Object TiaUiExtractor.JabBridge
$resolvedDll = Find-JavaAccessBridgeDll -ExplicitPath $JabDllPath

if ($resolvedDll) {
    Write-Host "[JAB] Loading Java Access Bridge from: $resolvedDll" -ForegroundColor Gray
    if ($jabBridge.Initialize($resolvedDll)) {
        Write-Host "[JAB] Java Access Bridge initialized successfully." -ForegroundColor Green
    }
    else {
        Write-Warning "[JAB] Initialization failed: $($jabBridge.LastError)"
    }
}
else {
    Write-Warning "[JAB] WindowsAccessBridge DLL not found. Will use Windows UI Automation (UIA) fallback."
}

Write-Host "[Scan] Enumerating Win32 windows for TIA / Java targets..." -ForegroundColor Gray
$allWindows = [TiaUiExtractor.NativeMethods]::EnumerateAllWindows($true)

# Build process lookup table
$processMap = @{}
foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    $processMap[[uint32]$p.Id] = $p.ProcessName
}

$matchedWindows = New-Object System.Collections.Generic.List[object]
$seenHwnds = New-Object "System.Collections.Generic.HashSet[long]"

foreach ($win in $allWindows) {
    if (-not $win.IsVisible) { continue }
    $hwndVal = $win.Hwnd.ToInt64()
    if ($seenHwnds.Contains($hwndVal)) { continue }

    $procName = if ($processMap.ContainsKey($win.ProcessId)) { $processMap[$win.ProcessId] } else { "" }
    $isJavaClass = $win.ClassName -match "^(SunAwtFrame|SunAwtDialog|SunAwtCanvas|SunAwtWindow| GlassWndClass)"
    $isJabWindow = if ($jabBridge.IsInitialized) { $jabBridge.IsJavaWindow($win.Hwnd) } else { $false }

    $titleMatched = $false
    foreach ($pattern in $WindowTitlePattern) {
        if (-not [string]::IsNullOrWhiteSpace($win.Title) -and ($win.Title -like $pattern)) {
            $titleMatched = $true
            break
        }
    }

    $procMatched = ($procName -match $ProcessNamePattern)

    $shouldInclude = $false
    if ($titleMatched) {
        $shouldInclude = $true
    }
    elseif ($IncludeAllJavaWindows -and ($isJavaClass -or $isJabWindow)) {
        $shouldInclude = $true
    }
    elseif (($isJavaClass -or $isJabWindow) -and $procMatched -and $win.ParentHwnd -eq [IntPtr]::Zero -and $titleMatched) {
        $shouldInclude = $true
    }

    if ($shouldInclude) {
        # Avoid adding child HWNDs if their parent HWND is already matched and handled via JAB
        if ($win.ParentHwnd -ne [IntPtr]::Zero -and $seenHwnds.Contains($win.ParentHwnd.ToInt64())) {
            if (-not $isJabWindow) { continue }
        }
        [void]$seenHwnds.Add($hwndVal)
        $matchedWindows.Add([PSCustomObject]@{
            WindowInfo  = $win
            ProcessName = $procName
            IsJavaClass = $isJavaClass
            IsJabWindow = $isJabWindow
        })
    }
}

if ($matchedWindows.Count -eq 0) {
    Write-Warning "No open windows matched Title Pattern ($($WindowTitlePattern -join ', '))."
    Write-Host "Tip: Ensure the TIA application is open, or run with -IncludeAllJavaWindows to inspect all open Java windows." -ForegroundColor Yellow
}

$extractedWindows = New-Object System.Collections.Generic.List[object]
$totalElementsExtracted = 0
$winIdx = 0

foreach ($target in $matchedWindows) {
    $win = $target.WindowInfo
    $hwndHex = "0x{0:X8}" -f $win.Hwnd.ToInt64()
    Write-Host ("`n[Window #{0}] HWND={1} | Title='{2}' | Class='{3}' | Process='{4}' (PID {5})" -f `
        $winIdx, $hwndHex, $win.Title, $win.ClassName, $target.ProcessName, $win.ProcessId) -ForegroundColor Cyan

    $flatElements = New-Object System.Collections.Generic.List[object]
    $rootTree = $null
    $engineUsed = "None"

    # 1. Try Java Access Bridge first
    if ($jabBridge.IsInitialized) {
        $vmId = 0
        $rootAc = [long]0
        if ($jabBridge.TryGetRootContext($win.Hwnd, [ref]$vmId, [ref]$rootAc)) {
            try {
                Write-Host "  -> Extracting via Java Access Bridge (vmID=$vmId)..." -ForegroundColor Green
                $rootTree = Get-JabElementTree `
                    -Bridge $jabBridge `
                    -VmId $vmId `
                    -ContextHandle $rootAc `
                    -WindowIndex $winIdx `
                    -Depth 0 `
                    -ParentPath "" `
                    -NodeIdPrefix "win${winIdx}_node_0" `
                    -FlatList $flatElements

                if ($null -ne $rootTree -and $flatElements.Count -gt 0) {
                    $engineUsed = "JavaAccessBridge"
                }
            }
            finally {
                $jabBridge.ReleaseObject($vmId, $rootAc)
            }
        }
    }

    # 2. Fallback to Windows UI Automation if JAB did not return elements
    if ($null -eq $rootTree -and $script:UiaAvailable) {
        Write-Host "  -> Extracting via Windows UI Automation (UIA) fallback..." -ForegroundColor Yellow
        try {
            $uiaRoot = [System.Windows.Automation.AutomationElement]::FromHandle($win.Hwnd)
            if ($null -ne $uiaRoot) {
                $rootTree = Get-UiaElementTree `
                    -Element $uiaRoot `
                    -Depth 0 `
                    -IndexInParent 0 `
                    -ParentPath "" `
                    -NodeIdPrefix "win${winIdx}_node_0" `
                    -FlatList $flatElements

                if ($null -ne $rootTree) {
                    $engineUsed = "WindowsUIAutomation"
                }
            }
        }
        catch {
            Write-Warning "  -> UIA extraction failed for HWND ${hwndHex}: $($_.Exception.Message)"
        }
    }

    Write-Host "  -> Engine: $engineUsed | Extracted Elements: $($flatElements.Count)" -ForegroundColor White

    $roleSummary = @{}
    foreach ($el in $flatElements) {
        $r = if ($el.role) { $el.role } else { "unknown" }
        if ($roleSummary.ContainsKey($r)) {
            $roleSummary[$r]++
        }
        else {
            $roleSummary[$r] = 1
        }
    }

    $extractedWindows.Add([ordered]@{
        hwnd         = $hwndHex
        title        = $win.Title
        className    = $win.ClassName
        processName  = $target.ProcessName
        processId    = $win.ProcessId
        isJavaClass  = $target.IsJavaClass
        isJabWindow  = $target.IsJabWindow
        engine       = $engineUsed
        windowBounds = [ordered]@{
            x      = $win.X
            y      = $win.Y
            width  = $win.Width
            height = $win.Height
        }
        elementCount = $flatElements.Count
        roleCounts   = $roleSummary
        rootTree     = $rootTree
        flatElements = $flatElements
    })

    $totalElementsExtracted += $flatElements.Count
    $winIdx++
}

# ---------------------------------------------------------------------------
# 7. Export JSON Report
# ---------------------------------------------------------------------------
$report = [ordered]@{
    metadata = [ordered]@{
        extractedAt          = (Get-Date).ToString("o")
        windowTitlePattern   = $WindowTitlePattern
        processNamePattern   = $ProcessNamePattern
        includeAllJava       = [bool]$IncludeAllJavaWindows
        visibleOnly          = [bool]$VisibleOnly
        maxDepth             = $MaxDepth
        is64BitPowerShell    = [Environment]::Is64BitProcess
        jabInitialized       = $jabBridge.IsInitialized
        jabDllPath           = $jabBridge.LoadedDllPath
        jabLastError         = $jabBridge.LastError
        windowCount          = $extractedWindows.Count
        totalElementCount    = $totalElementsExtracted
    }
    windows = $extractedWindows
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$jsonContent = $report | ConvertTo-Json -Depth 100
Set-Content -LiteralPath $OutputPath -Value $jsonContent -Encoding UTF8

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " Extraction Complete" -ForegroundColor Green
Write-Host " Windows Captured : $($extractedWindows.Count)" -ForegroundColor White
Write-Host " Total Elements   : $totalElementsExtracted" -ForegroundColor White
Write-Host " JSON Report Path : $OutputPath" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
