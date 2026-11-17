# Check App State (`NCheckAppState`)

`UiPath.UIAutomationNext.Activities.NCheckAppState`

Checks whether a UI element appears or disappears within a timeout and executes the `IfExists` or `IfNotExists` branch.

**Package:** `UiPath.UIAutomation.Activities`
**Namespace:** `xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`

## Properties

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Timeout` | `Double` | `5` | Timeout in seconds to wait for element state |
| `Target` | `TargetAnchorable` | Required | Target UI element to check |
| `IfExists` | `Activity` | Required | `<Sequence DisplayName="Target appears">` |
| `IfNotExists` | `Activity` | Required | `<Sequence DisplayName="Target does not appear">` |

## XAML Example

```xml
<uix:NCheckAppState DisplayName="Check App State - Save Dialog"
                    ScopeIdentifier="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
                    Timeout="5"
                    Version="V3"
                    sap2010:WorkflowViewState.IdRef="NCheckAppState_1">
  <uix:NCheckAppState.IfExists>
    <Sequence DisplayName="Target appears" sap2010:WorkflowViewState.IdRef="Sequence_3">
      <ui:LogMessage DisplayName="Log Found" Level="Info" Message="[&quot;Dialog appeared&quot;]" sap2010:WorkflowViewState.IdRef="LogMessage_1" />
    </Sequence>
  </uix:NCheckAppState.IfExists>
  <uix:NCheckAppState.IfNotExists>
    <Sequence DisplayName="Target does not appear" sap2010:WorkflowViewState.IdRef="Sequence_4" />
  </uix:NCheckAppState.IfNotExists>
  <uix:NCheckAppState.Target>
    <uix:TargetAnchorable FullSelectorArgument="&lt;wnd app='notepad.exe' cls='#32770' title='Save As' /&gt;"
                          SearchSteps="Selector"
                          Version="V2"
                          Visibility="Interactive" />
  </uix:NCheckAppState.Target>
</uix:NCheckAppState>
```
