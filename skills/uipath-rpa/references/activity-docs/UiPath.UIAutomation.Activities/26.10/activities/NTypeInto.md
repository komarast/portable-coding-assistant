# Type Into (`NTypeInto`)

`UiPath.UIAutomationNext.Activities.NTypeInto`

Types text or secure credentials into a target desktop or web UI element.

**Package:** `UiPath.UIAutomation.Activities`
**Namespace:** `xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`

## Properties

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Text` | `InArgument<String>` | — | Standard string text to type |
| `SecureText` | `InArgument<SecureString>` | — | SecureString password to type |
| `EmptyFieldMode` | `NEmptyFieldMode` | `SingleLine` | `SingleLine`, `MultiLine`, `None` |
| `ClickBeforeMode` | `NClickBeforeMode` | `Single` | `Single`, `Double`, `None` |
| `InteractionMode` | `NChildInteractionMode` | `SameAsCard` | `SameAsCard`, `Simulate`, `WindowMessages`, `HardwareEvents` |
| `ActivateBefore` | `Boolean` | `True` | Activates target window before typing |
| `Target` | `TargetAnchorable` | Required | Target UI element |

## XAML Example

```xml
<uix:NTypeInto ActivateBefore="True"
               ClickBeforeMode="Single"
               DisplayName="Type Into Editor"
               EmptyFieldMode="SingleLine"
               InteractionMode="SameAsCard"
               ScopeIdentifier="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
               Text="[in_InputText]"
               Version="V3"
               sap2010:WorkflowViewState.IdRef="NTypeInto_1">
  <uix:NTypeInto.Target>
    <uix:TargetAnchorable FullSelectorArgument="&lt;uia role='edit' /&gt;"
                          ScopeSelectorArgument="&lt;wnd app='notepad.exe' cls='Notepad' title='*Notepad*' /&gt;"
                          SearchSteps="Selector"
                          Version="V2"
                          Visibility="Interactive" />
  </uix:NTypeInto.Target>
</uix:NTypeInto>
```

## Notes
- When `Text` includes special keys like `[k(enter)]` or `[k(tab)]`, use child-element syntax `<uix:NTypeInto.Text><InArgument x:TypeArguments="x:String">...</InArgument></uix:NTypeInto.Text>` and set `InteractionMode="WindowMessages"` or `"HardwareEvents"` (`Simulate` types `[k(enter)]` literally).
