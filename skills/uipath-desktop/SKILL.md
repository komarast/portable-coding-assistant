---
name: uipath-desktop
description: Specialized Windows Desktop UI Automation skill for UiPath (.xaml). Covers live UI tree capture via inspect_ui_tree, Win32/WPF/WinForms/Java/SAP GUI selectors, TargetAnchorable anchors, Input Modes (Simulate vs HardwareEvents vs WindowMessages), and modal dialog handling.
---

# UiPath Windows Desktop Automation Skill (`uipath-desktop`)

When building or debugging **Windows Desktop Automations** (Win32, WPF, WinForms, SAP GUI, Java Swing, Electron, or Citrix/RDP), follow these desktop-specific rules and patterns:

## 1. Live Desktop UI Tree Discovery (`inspect_ui_tree`)
Never guess desktop selectors or write placeholder selectors when running on a Windows machine:
1. First, list all visible desktop windows to get the exact `app` executable, `cls` (window class), and `title`:
   ```json
   {"tool": "inspect_ui_tree", "window_title": "", "max_depth": 1}
   ```
2. Next, inspect the target window's live UI Automation tree (buttons, textboxes, menus, grids):
   ```json
   {"tool": "inspect_ui_tree", "window_title": "*SAP*", "max_depth": 4}
   ```
3. Copy the synthesized **Top-Level Window Selector** (`<wnd app='...' cls='...' title='...' />`) into `<uix:TargetApp Selector="..." />` on `<uix:NApplicationCard>`, and copy each control's **Element Selector** (`<uia automationid='...' name='...' role='...' />` or `<ctrl name='...' role='...' />`) into `FullSelectorArgument`.

---

## 2. Desktop Application Technology Matrix

| Desktop Tech | Top-Level Window Tag | Child Control Tag | Best Attributes | Recommended InteractionMode |
| :--- | :--- | :--- | :--- | :--- |
| **WPF / UWP / Modern WinUI** | `<wnd app='...' cls='HwndWrapper*' title='*' />` | `<uia ... />` | `automationid`, `name`, `role` (`button`, `edit`, `combobox`, `datagrid`) | `Simulate` (or `WindowMessages` for custom controls) |
| **WinForms (.NET)** | `<wnd app='...' ctrlname='Form*' />` | `<wnd ctrlname='...' />` or `<ctrl ... />` | `ctrlname` (maps directly to C#/VB Control.Name!), `aaname`, `role` | `Simulate` or `WindowMessages` |
| **Classic Win32 / C++ / MFC** | `<wnd app='...' cls='*' title='*' />` | `<wnd ctrlid='...' />` or `<ctrl ... />` | `ctrlid` (numeric resource ID when stable), `aaname`, `cls`, `role` | `WindowMessages` or `HardwareEvents` |
| **SAP GUI for Windows** | `<wnd app='saplogon.exe' cls='SAP_FRONTEND_SESSION' title='*' />` | `<sap id='usr/txtRSYST-BNAME' />` | `id` (SAP Scripting path `usr/ctxt...`, `usr/btn...`, `tbar[0]/btn[0]`) | `Simulate` (SAP Scripting API) |
| **Java Swing / AWT / JNLP** | `<wnd app='jp2launcher.exe' cls='SunAwtFrame' title='*' />` | `<java name='...' role='...' />` | `name`, `role`, `virtualname` (requires UiPath Java Bridge) | `Simulate` |
| **File Open / Save Dialogs** | `<wnd app='*' cls='#32770' title='Open|Save*' />` | `<wnd ctrlid='1148' />` (File name) & `<wnd ctrlid='1' title='&amp;Open|&amp;Save' />` | Standard Win32 `#32770` dialog `ctrlid='1148'` (path edit) and `ctrlid='1'` (confirm button) | `WindowMessages` or `HardwareEvents` |

---

## 3. Input Method Selection (`InteractionMode`)
- **`Simulate`**: Fastest, runs in the background without moving the physical mouse cursor, automatically empties fields before typing. Use as the default for standard buttons and textboxes.
- **`WindowMessages`**: Sends Win32 `WM_CLICK` / `WM_SETTEXT` messages. Use for Win32/MFC controls, `#32770` file dialogs, or when `Simulate` does not trigger a desktop app's `OnKeyPress` validation event.
- **`HardwareEvents`**: Moves the physical mouse/keyboard driver. Required when:
  - Sending keyboard shortcuts (`<uix:NKeyboardShortcuts Shortcuts="[d(hk)][d(ctrl)]s[u(ctrl)][u(hk)]" />`)
  - Clicking custom-drawn canvas controls, treeview expanders, or Citrix/RDP windows.
  - Always set `ActivateBefore="True"` when using `HardwareEvents`.

---

## 4. Anchors & Resilient Desktop Selectors (`<uix:TargetAnchorable.Anchors>`)
When a desktop textbox has no `automationid` (common in legacy Win32/ERP forms where inputs only have generic `cls='Edit'`), anchor it to its adjacent label (`<uia name='Invoice Number:' role='text' />`):

```xml
<uix:TargetAnchorable DesignTimeRectangle="120, 80, 180, 22" ElementType="InputBox" FullSelectorArgument="&lt;uia role='edit' /&gt;" FuzzySelectorArgument="&lt;uia role='edit' /&gt;" Guid="b1c2d3e4-0001-4000-8000-000000000010" SearchSteps="Selector, FuzzySelector" Version="V2" Visibility="Interactive">
  <uix:TargetAnchorable.Anchors>
    <scg:List x:TypeArguments="uix:ITarget" Capacity="1">
      <uix:Target DesignTimeRectangle="20, 80, 95, 22" ElementType="Text" FullSelectorArgument="&lt;uia name='Invoice Number:' role='text' /&gt;" FuzzySelectorArgument="&lt;uia role='text' check:text='Invoice Number:' /&gt;" SearchSteps="Selector, FuzzySelector" />
    </scg:List>
  </uix:TargetAnchorable.Anchors>
</uix:TargetAnchorable>
```

---

## 5. Desktop Synchronization & Popup Handling (Zero Hardcoded Delays)
- **Never use `<Delay Duration="00:00:05" />`** to wait for a desktop window to load.
- Use `<uix:NCheckAppState>` (Check App State) to wait dynamically for a screen element, spinner disappearance, or popup dialog:
  ```xml
  <uix:NCheckAppState DisplayName="Check App State 'Warning Popup'" ScopeIdentifier="d1a2b3c4-0000-4000-8000-000000000001" Timeout="5" Version="V3">
    <uix:NCheckAppState.IfExists>
      <Sequence DisplayName="Target Appears">
        <!-- Click Dismiss / OK -->
      </Sequence>
    </uix:NCheckAppState.IfExists>
    <uix:NCheckAppState.IfNotExists>
      <Sequence DisplayName="Target Does Not Appear" />
    </uix:NCheckAppState.IfNotExists>
    <uix:NCheckAppState.Target>
      <uix:TargetAnchorable ElementType="Dialog" FullSelectorArgument="&lt;wnd cls='#32770' title='Warning*' /&gt;" Guid="c1d2e3f4-0001-4000-8000-000000000011" SearchSteps="Selector" Version="V2" />
    </uix:NCheckAppState.Target>
  </uix:NCheckAppState>
  ```
