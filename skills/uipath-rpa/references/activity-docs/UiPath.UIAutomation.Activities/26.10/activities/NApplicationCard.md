# Use Application/Browser (`NApplicationCard`)

`UiPath.UIAutomationNext.Activities.NApplicationCard`

Opens or attaches to a desktop application or web browser window and provides a scope for all child UI Automation activities.

**Package:** `UiPath.UIAutomation.Activities`
**Namespace:** `xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`

## Properties

### Input / Options
| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `AttachMode` | `ApplicationAttachMode` | `ByInstance` | `ByInstance`, `SingleWindow`, or `MainWindow` |
| `OpenMode` | `NAppOpenMode` | `IfNotOpen` | `IfNotOpen`, `Always`, `Never` |
| `CloseMode` | `NAppCloseMode` | `Never` | `Never`, `IfOpenedByAppBrowser`, `Always` |
| `InteractionMode` | `NChildInteractionMode` | `Simulate` | `Simulate`, `WindowMessages`, `HardwareEvents`, `SameAsCard` |
| `ScopeGuid` | `String` | GUID | Unique GUID linking child activities to this card |
| `TargetApp` | `TargetApp` | Required | Contains `FilePath`, `Arguments`, `Selector`, `Url` |

## XAML Example

```xml
<uix:NApplicationCard AttachMode="ByInstance"
                      CloseMode="Never"
                      DisplayName="Use Application: Notepad"
                      InteractionMode="Simulate"
                      OpenMode="IfNotOpen"
                      ScopeGuid="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
                      Version="V2"
                      sap2010:WorkflowViewState.IdRef="NApplicationCard_1">
  <uix:NApplicationCard.Body>
    <ActivityAction x:TypeArguments="x:Object">
      <ActivityAction.Argument>
        <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />
      </ActivityAction.Argument>
      <Sequence DisplayName="Do" sap2010:WorkflowViewState.IdRef="Sequence_2">
        <!-- Child UIA activities -->
      </Sequence>
    </ActivityAction>
  </uix:NApplicationCard.Body>
  <uix:NApplicationCard.TargetApp>
    <uix:TargetApp FilePath="notepad.exe"
                   Selector="&lt;wnd app='notepad.exe' cls='Notepad' title='*Notepad*' /&gt;" />
  </uix:NApplicationCard.TargetApp>
</uix:NApplicationCard>
```
