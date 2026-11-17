# UiPath UI Automation Guide (`UiPath.UIAutomation.Activities` 26.10)

Authoritative guide for authoring Windows Desktop and Web UI Automation workflows in **XAML** and **Coded C#** modes.

---

## 1. Mandatory: Generate or Inspect Targets Before Writing UI Code

1. **Window Baseline**: Before interacting with a live Windows desktop application, list open top-level windows using `inspect_ui_tree` (`{"tool": "inspect_ui_tree", "window_title": ""}`) or `uip rpa uia window-list --output json`.
2. **Target Inspection (`inspect_ui_tree` / `uip rpa uia inspect`)**:
   - When the target desktop application is running on the Windows machine, inspect its live UIAutomation control hierarchy (`AutomationId`, `Name`, `ControlType`, `ClassName`) using:
     ```json
     {"tool": "inspect_ui_tree", "window_title": "*Notepad*", "max_depth": 4}
     ```
     or via the built-in offline `uip` CLI shim:
     ```bash
     uip rpa uia inspect --window-title "*Notepad*" --max-depth 4 --output json
     ```
   - Use the synthesized `<wnd app='...' cls='...' title='...' />` and `<uia automationid='...' name='...' role='...' />` selectors directly inside `<uix:TargetApp>` and `<uix:TargetAnchorable>`.
3. **When Live App Access Is Unavailable (Placeholder-Selector Stub Pattern)**:
   - If the target application is not open or not installed on the current machine, emit the **real** UIA activities (`<uix:NApplicationCard>`, `<uix:NTypeInto>`, `<uix:NClick>`, `<uix:NGetText>`, `<uix:NCheckAppState>`) with a `TODO Indicate — <description>` prefix in `DisplayName` and either a valid `<uix:TargetAnchorable>` selector or placeholder target per `references/uia-policies-catalog.md § Placeholder-Selector Stub Pattern`. Never replace UIA steps with `LogMessage` stubs.

---

## 2. For XAML Workflows (`xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`)

### Required Root Namespaces & Assembly References

Add to `<Activity>`:
```xml
xmlns:ui="http://schemas.uipath.com/workflow/activities"
xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"
xmlns:uuat="clr-namespace:UiPath.UIAutomationNext.Activities.Targeting;assembly=UiPath.UIAutomationNext.Activities"
xmlns:uue="clr-namespace:UiPath.UIAutomationNext.Enums;assembly=UiPath.UIAutomationNext"
```
Add to `<TextExpression.ReferencesForImplementation>`:
```xml
<AssemblyReference>UiPath.UIAutomationCore</AssemblyReference>
<AssemblyReference>UiPath.UIAutomationNext</AssemblyReference>
<AssemblyReference>UiPath.UIAutomationNext.Activities</AssemblyReference>
```

### Container Scope: `<uix:NApplicationCard>` (Use Application/Browser)

Every sequence of UI interactions against a window or browser MUST be enclosed inside `<uix:NApplicationCard>`.
Its `<uix:NApplicationCard.Body>` MUST wrap the child `<Sequence>` inside `<ActivityAction x:TypeArguments="x:Object">` with `<DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />`:

```xml
<uix:NApplicationCard AttachMode="ByInstance"
                      DisplayName="Use Application: Notepad"
                      InteractionMode="Simulate"
                      OpenMode="IfNotOpen"
                      CloseMode="Never"
                      ScopeGuid="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
                      Version="V2"
                      sap2010:WorkflowViewState.IdRef="NApplicationCard_1">
  <uix:NApplicationCard.Body>
    <ActivityAction x:TypeArguments="x:Object">
      <ActivityAction.Argument>
        <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />
      </ActivityAction.Argument>
      <Sequence DisplayName="Do" sap2010:WorkflowViewState.IdRef="Sequence_2">
        <!-- Child <uix:N*> activities go here -->
      </Sequence>
    </ActivityAction>
  </uix:NApplicationCard.Body>
  <uix:NApplicationCard.TargetApp>
    <uix:TargetApp FilePath="notepad.exe"
                   Selector="&lt;wnd app='notepad.exe' cls='Notepad' title='*Notepad*' /&gt;" />
  </uix:NApplicationCard.TargetApp>
</uix:NApplicationCard>
```

### Core Modern UIA Activities (`<uix:N*>`)

| Activity Tag | Class Name | Key Properties | Critical Gotchas |
| :--- | :--- | :--- | :--- |
| `<uix:NApplicationCard>` | `UiPath.UIAutomationNext.Activities.NApplicationCard` | `AttachMode`, `OpenMode`, `CloseMode`, `InteractionMode`, `ScopeGuid`, `TargetApp` | Body MUST use `<ActivityAction x:TypeArguments="x:Object">` + `<Sequence DisplayName="Do">`. |
| `<uix:NClick>` | `UiPath.UIAutomationNext.Activities.NClick` | `ClickType="Single\|Double"`, `MouseButton="Left\|Right"`, `InteractionMode`, `KeyModifiers`, `Target` | Target is `<uix:TargetAnchorable FullSelectorArgument="..." SearchSteps="Selector" Visibility="Interactive" />`. |
| `<uix:NTypeInto>` | `UiPath.UIAutomationNext.Activities.NTypeInto` | `Text="[str_Val]"`, `SecureText="[sec_Pwd]"`, `EmptyFieldMode="SingleLine\|MultiLine\|None"`, `ClickBeforeMode="Single"`, `InteractionMode` | If `Text` contains special key tokens like `[k(enter)]`, use child element `<uix:NTypeInto.Text>` or `WindowMessages`/`HardwareEvents` (`Simulate` types `[k(enter)]` literally). |
| `<uix:NGetText>` | `UiPath.UIAutomationNext.Activities.NGetText` | `TextString="[out_Text]"` | Output property is **`TextString`** (or `Text`), NEVER `Value` (`NGetText.Value` fails build with `Cannot set unknown member`). |
| `<uix:NCheckAppState>` | `UiPath.UIAutomationNext.Activities.NCheckAppState` | `Timeout="5"`, `Target`, `IfExists`, `IfNotExists` | Replaces legacy `ElementExists` + `If`. Both `<uix:NCheckAppState.IfExists>` and `<uix:NCheckAppState.IfNotExists>` MUST wrap children in `<Sequence>`. |
| `<uix:NSelectItem>` | `UiPath.UIAutomationNext.Activities.NSelectItem` | `Item="[str_Option]"`, `Target` | Selects a dropdown (`combobox` / `list`) item by visible text. |
| `<uix:NKeyboardShortcuts>` | `UiPath.UIAutomationNext.Activities.NKeyboardShortcuts` | `Shortcuts="[d(ctrl)]s[u(ctrl)]"`, `InteractionMode="WindowMessages"` | Use for keyboard shortcuts (`Ctrl+S`, `Alt+F4`, `Enter`). |

---

## 3. Selector Rules for Windows Desktop Applications

1. **Attribute Stability Hierarchy**:
   - Prefer `automationid` (WPF/WinForms/UWP) > `name` / `aaname` > `role` > `cls`.
   - **Never rely on `idx='2+'`** — use `<uix:TargetAnchorable.Anchors>` with a nearby stable label instead.
2. **XML Escaping in XAML Attributes**:
   - Inside `Selector="..."` and `FullSelectorArgument="..."`, escape `<` as `&lt;`, `>` as `&gt;`, `&` as `&amp;`, and `"` as `&quot;`. Use single quotes `'` around selector attribute values (`app='notepad.exe'`).
3. **Standard `#32770` Windows Open/Save Dialogs**:
   - File dialogs spawned by desktop apps are separate top-level windows (`<wnd app='...' cls='#32770' title='Save As' />`). Handle them in a dedicated `<uix:NApplicationCard OpenMode="Never" CloseMode="Never">`.

---

## 4. For Coded Workflows (`.cs`)

Use `uiAutomation.Open(...)` or `uiAutomation.Attach(...)` with `Descriptors.<App>.<Screen>` (or placeholder strings marked with `// TODO[Indicate]` when live capture is deferred).

---

## 5. Documentation Index

- `activities/NApplicationCard.md`
- `activities/NClick.md`
- `activities/NTypeInto.md`
- `activities/NGetText.md`
- `activities/NCheckAppState.md`
- `activities/NSelectItem.md`
- `activities/NKeyboardShortcuts.md`
