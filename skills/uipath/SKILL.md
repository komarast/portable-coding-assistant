---
name: uipath
description: UiPath Studio RPA & Agentic automation skill covering .xaml workflows, project.json, REFramework, UI Selectors, VB.NET/C# LINQ expressions, Coded Workflows (.cs), Workflow Analyzer, UiRobot.exe, and Orchestrator REST APIs.
---

# UiPath Studio & Robot Coding Skill

When activated (`/skill uipath` or `-Skill uipath`), apply these UiPath-specific rules and patterns:

## 1. Token-Efficient `.xaml` Handling
- UiPath `.xaml` files contain verbose XML namespaces and `sap2010:WorkflowViewState` visual layout blocks that waste tokens.
- **Always use the `inspect_xaml` tool first** (`{"tool": "inspect_xaml", "path": "Main.xaml"}`) before reading raw lines of a `.xaml` file. `inspect_xaml` extracts:
  - Workflow Arguments (`x:Property` In/Out/InOut arguments and types)
  - Variables (`Variable` declarations and scopes)
  - Activity Hierarchy (`Sequence`, `Flowchart`, `StateMachine`, `InvokeWorkflowFile`, `Assign`, `Click`, `TypeInto`, `TryCatch`, etc.) with exact line numbers!
- When editing `.xaml` with `edit_file`, use surgical `SEARCH/REPLACE` blocks targeting only the specific Activity or Variable element, and **never** break XML tag balance or remove `x:Class` / `xmlns` declarations.

## 2. UiPath Studio Project Structure (`project.json`)
- Inspect `project.json` first to identify:
  - `expressionLanguage`: `"VisualBasic"` (VB.NET syntax: `Nothing`, `AndAlso`, `OrElse`, `Function(x)`) vs `"CSharp"` (C# syntax: `null`, `&&`, `||`, `x =>`). **Never mix VB.NET and C# syntax in expressions!**
  - `dependencies`: Installed packages (`UiPath.System.Activities`, `UiPath.UIAutomation.Activities`, `UiPath.Excel.Activities`, `UiPath.WebAPI.Activities`).
  - `main`: Entrypoint workflow (`Main.xaml` or `Main.cs`).

## 3. UI Selectors & UI Automation Best Practices
- Prefer stable attributes (`automationid`, `aaname`, `name`, `ctrlname`, `innertext`) over volatile attributes (`idx`, dynamic `cls`, pixel coordinates).
- Use wildcards (`*`, `?`) for dynamic window titles or URLs (e.g., `<html app='chrome.exe' title='*Portal*' />`).
- For Modern UI Automation (`NClick`, `NTypeInto`, `NApplicationCard`), keep both Strict Selector (`Selector`) and Fuzzy Selector (`FuzzySelector`) consistent.

## 4. Common VB.NET & C# LINQ Patterns in UiPath `Assign` Activities
- **Filter DataTable (`dt_Input`)**:
  - VB.NET: `dt_Input.AsEnumerable().Where(Function(r) r("Status").ToString.Trim.Equals("Open")).CopyToDataTable()`
  - C#: `dt_Input.AsEnumerable().Where(r => r["Status"].ToString().Trim() == "Open").CopyToDataTable()`
  - *Guard against empty result*: Check `.Any()` first before calling `.CopyToDataTable()`, otherwise it throws `"The source contains no DataRows"`, or use `dt_Input.Clone()` as fallback.
- **Safe Dictionary / Config Lookup (REFramework `in_Config`)**:
  - VB.NET: `in_Config("MaxRetryNumber").ToString.Trim`

## 5. Coded Workflows (`.cs` with `[Workflow]` attribute)
- Modern UiPath projects support C# Coded Workflows inheriting from `: CodedWorkflow`:
  ```csharp
  using UiPath.CodedWorkflows;
  namespace MyProject
  {
      public class ProcessInvoice : CodedWorkflow
      {
          [Workflow]
          public (bool Success, string Message) Execute(string invoicePath)
          {
              Log($"Processing {invoicePath}", LogLevel.Info);
              return (true, "Processed");
          }
      }
  }
  ```

## 6. Local UiPath CLI Commands on Windows AVD (`run_command`)
- **Workflow Analyzer (Static Analysis)**:
  `"& '$env:LOCALAPPDATA\Programs\UiPath\Studio\UiPath.Studio.CommandLine.exe' analyze -p .\project.json"`
- **Run Workflow Locally via UiRobot**:
  `"& '$env:LOCALAPPDATA\Programs\UiPath\Studio\UiRobot.exe' execute --file .\Main.xaml"`
