---
name: uipath
description: Master UiPath Studio XAML & RPA Agent Skill distilled from UiPath/skills (uipath-rpa). Covers the 3-phase Discovery -> Generation -> Validation loop, Modern & Classic UI Automation XAML templates, ActivityAction scope rules, Object Repository (.objects), and VB.NET/C# expressions.
---

# UiPath XAML & RPA Agent Skill (`uipath`)

You are operating in **UiPath XAML & Desktop Automation Agent Mode**. Follow the official **3-Phase UiPath Agent Loop** (`Discovery -> Generation -> Validation`) on every task:

## Phase 1: Discovery (Never Generate XAML Blind)
1. **Check `project.json` first**:
   - Read `expressionLanguage`: `"VisualBasic"` (VB.NET: `Nothing`, `AndAlso`, `OrElse`, `Function(x)`) vs `"CSharp"` (C#: `null`, `&&`, `||`, `x =>`). **Never mix VB.NET and C# syntax inside `[...]` expressions!**
   - Check `dependencies` (`UiPath.System.Activities`, `UiPath.UIAutomation.Activities`, `UiPath.Excel.Activities`).
2. **Inspect Existing `.xaml` & Object Repository (`.objects`)**:
   - **Always call `inspect_xaml`** (`{"tool": "inspect_xaml", "path": "Main.xaml"}`) before calling `read_file` on any `.xaml` file. `inspect_xaml` strips `WorkflowViewState` designer noise and returns exact 1-indexed line numbers for Arguments, Variables, Activities, and UI Selectors.
3. **Inspect Live Windows Desktop UI (`inspect_ui_tree`)**:
   - When automating a desktop or browser application on Windows, call `inspect_ui_tree` (`{"tool": "inspect_ui_tree", "window_title": "*App*", "max_depth": 3}`) to discover live running windows, `AutomationId`, `Name`, `ControlType`, and synthesized UiPath `<wnd ... /><uia ... />` selectors instead of guessing selectors or leaving `TODO` placeholders.

---

## Phase 2: XAML Authoring & Generation Rules (`xaml-basics-and-rules`)

### Rule 1: Use `scaffold_xaml` for New `.xaml` Files
- Never write 40 lines of raw XML namespace declarations from scratch. Call `scaffold_xaml` first:
  ```json
  {"tool": "scaffold_xaml", "path": "Workflows/Login.xaml", "template": "desktop-uia", "app_exe": "saplogon.exe", "window_title": "*SAP*"}
  ```
  Supported templates:
  - `"sequence"`: Clean Sequence workflow with standard `in_Config` argument.
  - `"desktop-uia"`: Desktop UI Automation workflow with `xmlns:uix`, `<uix:NApplicationCard>`, `<ActivityAction>`, `<uix:NTypeInto>`, and `<uix:NClick>` ready to customize.
  - `"flowchart"`: Flowchart workflow with `<Flowchart.StartNode>` and `<FlowStep>` direct children.
  - `"try-catch-process"`: Resilient process workflow with `<TryCatch>` separating `ui:BusinessRuleException` (no retry) from `s:Exception` (system fault).

### Rule 2: Scope Activities MUST Use `<ActivityAction>` Body Wrappers
In UiPath XAML, container scopes (`<uix:NApplicationCard>`, `<ui:WindowScope>`, `<ui:BrowserScope>`, `<ui:ExcelApplicationScope>`, `<ui:RetryScope>`) **cannot** contain child `<Sequence>` tags directly. They MUST wrap their body inside `<ActivityAction x:TypeArguments="..."><ActivityAction.Argument><DelegateInArgument ... /></ActivityAction.Argument><Sequence>...</Sequence></ActivityAction>`:

```xml
<uix:NApplicationCard AttachMode="ByInstance" DisplayName="Use Desktop Application" OpenMode="IfNotOpen" ScopeGuid="d1a2b3c4-0000-4000-8000-000000000001" Version="V2">
  <uix:NApplicationCard.Body>
    <ActivityAction x:TypeArguments="x:Object">
      <ActivityAction.Argument>
        <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />
      </ActivityAction.Argument>
      <Sequence DisplayName="Do Desktop Actions">
        <!-- Child UIA activities go here -->
      </Sequence>
    </ActivityAction>
  </uix:NApplicationCard.Body>
  <uix:NApplicationCard.TargetApp>
    <uix:TargetApp FilePath="notepad.exe" Selector="&lt;wnd app='notepad.exe' cls='Notepad' title='*Notepad*' /&gt;" />
  </uix:NApplicationCard.TargetApp>
</uix:NApplicationCard>
```

### Rule 3: Modern UI Automation (`<uix:N*>`) Activity Templates
Always use real UiPath UIA activities (`<uix:NClick>`, `<uix:NTypeInto>`, `<uix:NGetText>`, `<uix:NCheckState>`, `<uix:NKeyboardShortcuts>`, `<uix:NSelectItem>`) inside `<uix:NApplicationCard>` with `<uix:TargetAnchorable>` selectors (note XML-escaped `&lt;` and `&gt;` inside `FullSelectorArgument` / `FuzzySelectorArgument`):

- **Click (`<uix:NClick>`)**:
  ```xml
  <uix:NClick ActivateBefore="True" ClickType="Single" DisplayName="Click 'Submit'" InteractionMode="Simulate" KeyModifiers="None" MouseButton="Left" ScopeIdentifier="d1a2b3c4-0000-4000-8000-000000000001" Version="V3">
    <uix:NClick.Target>
      <uix:TargetAnchorable DesignTimeRectangle="0, 0, 100, 30" ElementType="Button" FullSelectorArgument="&lt;uia automationid='btnSubmit' name='Submit' role='button' /&gt;" FuzzySelectorArgument="&lt;uia automationid='btnSubmit' role='button' check:text='Submit' /&gt;" Guid="a1b2c3d4-0001-4000-8000-000000000002" SearchSteps="Selector, FuzzySelector" Version="V2" Visibility="Interactive" />
    </uix:NClick.Target>
  </uix:NClick>
  ```
- **Type Into (`<uix:NTypeInto>`)**:
  ```xml
  <uix:NTypeInto ActivateBefore="True" ClickBeforeMode="Single" DisplayName="Type Into 'Username'" EmptyFieldMode="SingleLine" InteractionMode="Simulate" ScopeIdentifier="d1a2b3c4-0000-4000-8000-000000000001" Text="[in_Username]" Version="V3">
    <uix:NTypeInto.Target>
      <uix:TargetAnchorable DesignTimeRectangle="0, 0, 200, 24" ElementType="InputBox" FullSelectorArgument="&lt;uia automationid='txtUsername' role='edit' /&gt;" FuzzySelectorArgument="&lt;uia automationid='txtUsername' role='edit' /&gt;" Guid="a1b2c3d4-0002-4000-8000-000000000003" SearchSteps="Selector, FuzzySelector" Version="V2" Visibility="Interactive" />
    </uix:NTypeInto.Target>
  </uix:NTypeInto>
  ```
- **Get Text (`<uix:NGetText>`)**:
  ```xml
  <uix:NGetText DisplayName="Get Text 'Status'" ScopeIdentifier="d1a2b3c4-0000-4000-8000-000000000001" Value="[out_StatusText]" Version="V3">
    <uix:NGetText.Target>
      <uix:TargetAnchorable DesignTimeRectangle="0, 0, 200, 24" ElementType="Text" FullSelectorArgument="&lt;uia automationid='lblStatus' role='text' /&gt;" Guid="a1b2c3d4-0003-4000-8000-000000000004" SearchSteps="Selector" Version="V2" Visibility="Interactive" />
    </uix:NGetText.Target>
  </uix:NGetText>
  ```

### Rule 4: Classic UI Automation (`<ui:WindowScope>`, `<ui:Click>`, `<ui:TypeInto>`)
When editing legacy projects that use `<ui:*>` instead of `<uix:N*>`:
```xml
<ui:Click AlterIfDisabled="{x:Null}" DelayBefore="{x:Null}" DelayMS="{x:Null}" SendWindowMessages="{x:Null}" ClickType="CLICK_SINGLE" DisplayName="Click 'OK'" KeyModifiers="None" MouseButton="BTN_LEFT" SimulateClick="True">
  <ui:Click.CursorPosition>
    <ui:CursorPosition Position="Center">
      <ui:CursorPosition.OffsetX>
        <InArgument x:TypeArguments="x:Int32" />
      </ui:CursorPosition.OffsetX>
      <ui:CursorPosition.OffsetY>
        <InArgument x:TypeArguments="x:Int32" />
      </ui:CursorPosition.OffsetY>
    </ui:CursorPosition>
  </ui:Click.CursorPosition>
  <ui:Click.Target>
    <ui:Target ClippingRegion="{x:Null}" Element="{x:Null}" Selector="&lt;wnd app='app.exe' title='*' /&gt;&lt;ctrl name='OK' role='push button' /&gt;" WaitForReady="INTERACTIVE">
      <ui:Target.TimeoutMS>
        <InArgument x:TypeArguments="x:Int32" />
      </ui:Target.TimeoutMS>
    </ui:Target>
  </ui:Click.Target>
</ui:Click>
```

### Rule 5: Flowchart Structure Rule
Every `<FlowStep>`, `<FlowDecision>`, and `<FlowSwitch>` **MUST** be a direct child of `<Flowchart>` (in addition to being referenced via `<FlowStep.Next>`).

---

## Phase 3: Mandatory Validation Gate (`validate_xaml`)
- After creating or editing any `.xaml` file, **always call `validate_xaml`**:
  ```json
  {"tool": "validate_xaml", "path": "Workflows/Login.xaml"}
  ```
- Fix all reported errors by category (`XML Structure -> Scope ActivityAction -> Expression Language -> Selector Quality`) before finishing the turn.
