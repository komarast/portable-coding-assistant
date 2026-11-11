# UiPath Skills & Automation Guide (`pca`)

`pca` includes first-class support for **UiPath Studio RPA & Agentic Automation** on Windows AVD environments, including automatic UiPath project detection, a token-saving `.xaml` outline inspector (`inspect_xaml`), and a customizable `skills/` system.

---

## 1. Automatic UiPath Project Detection

When you launch `pca` inside any folder containing a UiPath `project.json` file, `pca` automatically activates the **`uipath` skill** (`[Skills: uipath]` in the banner).

You can also activate it explicitly from the command line or interactive REPL:
```powershell
# via CLI flag
.\pca.cmd -Skill uipath "Check Main.xaml for hardcoded delays and selectors"

# Or inside the interactive REPL
pca> /skill uipath
```

---

## 2. How `inspect_xaml` Saves 90%+ Tokens on `.xaml` Workflows

UiPath `.xaml` files are notoriously large (often 1,500–5,000+ lines) because of embedded `sap2010:WorkflowViewState` designer coordinates and XML namespaces. Sending an entire `.xaml` file to an LLM wastes thousands of tokens.

`pca` solves this with the built-in **`inspect_xaml`** tool:
```json
{"tool": "inspect_xaml", "path": "Process.xaml"}
```
When called by the agent, `inspect_xaml`:
1. Strips out all `WorkflowViewState` visual designer blocks.
2. Lists every `InArgument`, `OutArgument`, and `InOutArgument` (`<x:Property>`) with its exact **line number** and type.
3. Lists every `<Variable>` declaration with its **line number** and type.
4. Builds a clean outline of all **Activities** (`DisplayName`, activity type, invoked workflows, and selector presence) with their exact **1-indexed line numbers**.
5. The agent then calls `read_file` on **only the 20–40 lines** around the target activity and applies a surgical `SEARCH/REPLACE` patch via `edit_file`.

---

## 3. Example UiPath Workflows with `pca` on Windows AVD

### A. Fix Broken UI Selectors
```powershell
.\pca.cmd "In Workflows/Login.xaml, find the Click Submit activity and make the selector resilient to dynamic page titles"
```

### B. Write or Debug VB.NET / C# LINQ Expressions
```powershell
.\pca.cmd "Write a VB.NET LINQ expression for an Assign activity that filters dt_Transactions where Status='New' and Amount > 100 without throwing an exception when no rows match"
```

### C. Create or Refactor Coded Workflows (`.cs`)
```powershell
.\pca.cmd "Create a new UiPath Coded Workflow in Workflows/ParseInvoice.cs that extracts InvoiceNumber and Total using regex"
```

### D. Run UiPath Workflow Analyzer or `UiRobot.exe` from `pca`
```powershell
.\pca.cmd "Run UiPath Workflow Analyzer on project.json and summarize any rule violations"
```

---

## 4. Adding Your Own Custom UiPath / Corporate Skills

You can add unlimited custom skills (such as your company's internal UiPath naming conventions, Orchestrator queue schemas, or SAP automation standards):
1. Create a folder `skills/<your-skill-name>/SKILL.md` (for example, `skills/sap-uipath/SKILL.md`).
2. Activate it anytime with:
   ```powershell
   .\pca.cmd -Skill sap-uipath
   ```
   or inside the REPL:
   ```text
   pca> /skill sap-uipath
   ```
