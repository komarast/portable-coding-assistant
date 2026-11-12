# UiPath XAML & Desktop Automation Agent Guide (`pca`)

`pca` includes a complete **UiPath Studio RPA, XAML & Windows Desktop UI Automation Agent** suite modeled after the official [`UiPath/skills`](https://github.com/uipath/skills) ecosystem, engineered to run natively on **Windows PowerShell 5.1 / .NET Framework 4.8** with zero external dependencies.

---

## 1. Specialized UiPath Skills (`skills/`)

When you launch `pca` inside any folder containing a UiPath `project.json` file, `pca` automatically activates **`uipath`** and **`uipath-desktop`**.

| Skill Name | Purpose | Slash Command Shortcut |
| :--- | :--- | :--- |
| **`uipath`** ([`skills/uipath/SKILL.md`](../skills/uipath/SKILL.md)) | **Master XAML & RPA Agent Skill**: Enforces the 3-Phase Discovery -> Generation -> Validation loop, exact `<uix:NApplicationCard>`, `<ActivityAction>` scope wrappers, `<uix:NClick>`, `<uix:NTypeInto>`, `<uix:NGetText>`, Classic `<ui:Click>`, and VB.NET/C# expression syntax. | `/uipath` or `/skill uipath` |
| **`uipath-desktop`** ([`skills/uipath-desktop/SKILL.md`](../skills/uipath-desktop/SKILL.md)) | **Windows Desktop UI Automation Skill**: Live `.NET UIAutomationClient` desktop inspection (`inspect_ui_tree`), Win32/WPF/WinForms/SAP GUI/Java Swing/`#32770` Save/Open dialog selector patterns, `InteractionMode` matrix (`Simulate` vs `WindowMessages` vs `HardwareEvents`), anchors, and `<uix:NCheckAppState>`. | `/uipath` or `/skill uipath-desktop` |
| **`uipath-planner`** ([`skills/uipath-planner/SKILL.md`](../skills/uipath-planner/SKILL.md)) | **PDD-to-XAML Solution Architect**: Decomposes business requirements into REFramework / Dispatcher-Performer / Linear architectures, workflow call graphs, `InArgument`/`OutArgument` contracts, and Desktop UI Target inventories before writing `.xaml`. | `/uipath plan` or `/skill uipath-planner` |
| **`uipath-review`** ([`skills/uipath-review/SKILL.md`](../skills/uipath-review/SKILL.md)) | **XAML Workflow Analyzer & Auditor**: Audits `.xaml` files against UiPath Studio Workflow Analyzer rules (`UI-ANA-001` volatile `idx`, `ST-NMG-001` variable naming, `ST-USG-010` unused variables, `ST-SEC-008` plaintext passwords, `ST-REL-005` hardcoded `<Delay>`, `ST-DBP-002` empty Catch blocks). | `/uipath review` or `/skill uipath-review` |

Activate all 4 skills at once inside the REPL:
```text
pca> /uipath full
```

---

## 2. Built-in UiPath XAML & Desktop UI Tools

`pca` equips the LLM with 4 dedicated UiPath tools alongside `read_file` and `edit_file`:

### A. `inspect_ui_tree` — Live Windows Desktop UI Automation Tree Inspector
Uses Windows' built-in `.NET Framework` `UIAutomationClient` & `UIAutomationTypes` (`System.Windows.Automation.AutomationElement`) to inspect running desktop applications on your Windows AVD and automatically synthesize UiPath `<wnd ... /><uia ... />` selectors.
```json
{"tool": "inspect_ui_tree", "window_title": "Notepad", "max_depth": 3}
```
- Omit `"window_title"` (or pass `""`) to list all open top-level desktop windows with their Process Name (`app='...'`), ClassName (`cls='...'`), and Title (`title='...'`).
- Specify `"window_title": "SAP"` (or any substring) to walk the live control hierarchy (`AutomationId`, `Name`, `ControlType`, `ClassName`) and output ready-to-use UiPath selectors.

### B. `scaffold_xaml` — Studio-Compatible `.xaml` Workflow Generator
Generates a 100% schema-valid UiPath `.xaml` file with all required XML namespaces (`xmlns:ui`, `xmlns:uix`, `xmlns:sap2010`, `xmlns:scg`), `<x:Members>`, `<VisualBasic.Settings>`, `<ActivityAction>` wrappers, and `sap2010:WorkflowViewState.IdRef` IDs:
```json
{"tool": "scaffold_xaml", "path": "Workflows/EnterOrder.xaml", "template": "desktop-uia", "app_exe": "saplogon.exe", "window_title": "*SAP Easy Access*"}
```
Supported templates:
- `"desktop-uia"`: Scaffolds a Modern `<uix:NApplicationCard>` desktop workflow with `<ActivityAction>`, `<uix:NTypeInto>`, and `<uix:NClick>`.
- `"try-catch-process"`: Scaffolds a transactional workflow with `<TryCatch>` catching both `ui:BusinessRuleException` and `s:Exception`.
- `"sequence"`: Scaffolds a clean modular Sequence workflow with `in_Config` argument and logging.
- `"flowchart"`: Scaffolds a `<Flowchart>` workflow with `<Flowchart.StartNode>` and `<FlowStep>`.

### C. `inspect_xaml` — Token-Saving `.xaml` Outline & Selector Extractor
Strips out thousands of lines of `sap2010:WorkflowViewState` designer noise and returns a compact outline of:
1. All `InArgument`, `OutArgument`, and `InOutArgument` (`<x:Property>`) declarations with line numbers.
2. All `<Variable>` declarations with line numbers and types.
3. All **Activities** (`DisplayName`, tag type, invoked workflows, and selector flags) with 1-indexed line numbers.
4. All **UI Selectors** (`FullSelectorArgument` / `Selector`) with line numbers.
```json
{"tool": "inspect_xaml", "path": "Main.xaml"}
```

### D. `validate_xaml` — 5-Point UiPath Studio XAML Validator
Validates any `.xaml` file before you open it in UiPath Studio:
1. **XML Well-Formedness**: Parses with `.NET` `[xml]` / `ElementTree` to catch unclosed tags or unescaped `<`, `>`, `&`, `"`.
2. **Namespace Integrity**: Verifies `xmlns:uix` and `xmlns:ui` declarations when Modern or Classic UI activities are used.
3. **`ActivityAction` Scope Wrapper Check**: Verifies `<uix:NApplicationCard.Body>`, `<ui:WindowScope.Body>`, `<ui:BrowserScope.Body>`, and `<ui:ExcelApplicationScope.Body>` wrap their child `<Sequence>` inside `<ActivityAction><ActivityAction.Argument><DelegateInArgument .../></ActivityAction.Argument>...</ActivityAction>`.
4. **Flowchart Structure Check**: Verifies `<Flowchart>` nodes wrap activities inside `<FlowStep>`.
5. **Selector & Analyzer Linting**: Warns on volatile `idx='2+'` selectors (`UI-ANA-001`), hardcoded `<Delay>` activities (`ST-REL-005`), and `project.json` `expressionLanguage` (`VisualBasic` vs `CSharp`) mismatches.
```json
{"tool": "validate_xaml", "path": "Workflows/EnterOrder.xaml"}
```

---

## 3. End-to-End Desktop Automation Examples on Windows AVD

### A. Inspect a Live Desktop App & Build a New `.xaml` Workflow
```powershell
.\pca.cmd "Inspect the running Notepad window using inspect_ui_tree, then scaffold a desktop-uia workflow in Workflows/WriteNote.xaml that types in_InputText into the editor and clicks File"
```

### B. Plan a Multi-Workflow Desktop RPA Project from Requirements
```powershell
.\pca.cmd -Skill uipath-planner "Plan a desktop automation that reads invoices from Excel, enters them into SAP GUI, and handles #32770 Save As dialogs"
```

### C. Audit & Fix Existing `.xaml` Workflows
```powershell
.\pca.cmd -Skill uipath-review "Inspect and validate Main.xaml, fix any fragile idx selectors or missing TryCatch blocks, and run validate_xaml"
```
