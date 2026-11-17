# Get Text (`NGetText`)

`UiPath.UIAutomationNext.Activities.NGetText`

Extracts text from a specified UI element into an output string variable.

**Package:** `UiPath.UIAutomation.Activities`
**Namespace:** `xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"`

## Properties

| Name | Kind | Type | Required | Description |
| :--- | :--- | :--- | :--- | :--- |
| `TextString` | `OutArgument<String>` | `String` | Yes | The output string variable receiving the extracted text (NEVER use `Value`) |
| `Target` | `TargetAnchorable` | `TargetAnchorable` | Yes | Target UI element to read from |

## XAML Example

```xml
<uix:NGetText DisplayName="Get Status Text"
              ScopeIdentifier="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc"
              TextString="[out_StatusText]"
              Version="V3"
              sap2010:WorkflowViewState.IdRef="NGetText_1">
  <uix:NGetText.Target>
    <uix:TargetAnchorable FullSelectorArgument="&lt;uia automationid='lblStatus' role='text' /&gt;"
                          ScopeSelectorArgument="&lt;wnd app='app.exe' title='*Main*' /&gt;"
                          SearchSteps="Selector"
                          Version="V2"
                          Visibility="Interactive" />
  </uix:NGetText.Target>
</uix:NGetText>
```

## Notes
- **Critical Gotcha**: The output property is **`TextString`** (or legacy `Text`), **NEVER** `Value`. Setting `Value="[var]"` causes a build failure (`Cannot set unknown member 'UiPath.UIAutomationNext.Activities.NGetText.Value'`).
