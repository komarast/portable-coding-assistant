# Click (`NClick`)

`UiPath.UIAutomationNext.Activities.NClick`

Clicks a specified desktop or web UI element inside an `NApplicationCard` scope.

**Package:** `UiPath.UIAutomation.Activities`
**Namespace:** `xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`

## Properties

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `ClickType` | `NClickType` | `Single` | `Single`, `Double`, `Down`, `Up` |
| `MouseButton` | `NMouseButton` | `Left` | `Left`, `Right`, `Middle` |
| `InteractionMode` | `NChildInteractionMode` | `SameAsCard` | `SameAsCard`, `Simulate`, `WindowMessages`, `HardwareEvents` |
| `KeyModifiers` | `NKeyModifiers` | `None` | `None`, `Alt`, `Ctrl`, `Shift`, `Win` |
| `ActivateBefore` | `Boolean` | `True` | Brings window to foreground before clicking |
| `Target` | `TargetAnchorable` | Required | Element selector (`FullSelectorArgument` / `ScopeSelectorArgument`) |

## XAML Example

```xml
<uix:NClick ActivateBefore="True"
            ClickType="Single"
            DisplayName="Click Save Button"
            InteractionMode="SameAsCard"
            KeyModifiers="None"
            MouseButton="Left"
            ScopeIdentifier="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
            Version="V3"
            sap2010:WorkflowViewState.IdRef="NClick_1">
  <uix:NClick.Target>
    <uix:TargetAnchorable FullSelectorArgument="&lt;uia automationid='btnSave' name='Save' role='button' /&gt;"
                          ScopeSelectorArgument="&lt;wnd app='notepad.exe' cls='Notepad' title='*Notepad*' /&gt;"
                          SearchSteps="Selector"
                          Version="V2"
                          Visibility="Interactive" />
  </uix:NClick.Target>
</uix:NClick>
```
