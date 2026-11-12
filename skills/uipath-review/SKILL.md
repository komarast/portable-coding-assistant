---
name: uipath-review
description: UiPath XAML Auditor & Troubleshooter skill distilled from UiPath/skills (uipath-review & uipath-troubleshoot). Audits .xaml workflows for Studio Workflow Analyzer rules, volatile selectors, missing ActivityAction scope wrappers, and security/reliability anti-patterns.
---

# UiPath XAML Auditor & Troubleshooter Skill (`uipath-review`)

When asked to review, audit, or troubleshoot a UiPath project or `.xaml` workflow:

## 1. Automated Inspection & Validation First
1. Run `inspect_xaml` on every `.xaml` file in the workspace to extract Arguments, Variables, Activities, and UI Selectors.
2. Run `validate_xaml` on every `.xaml` file to check XML structure, required `xmlns` namespaces, `ActivityAction` scope wrappers, `Flowchart` direct children, and expression language consistency.

## 2. UiPath Studio Workflow Analyzer Audit Checklist
Check and report findings grouped by severity (**Critical**, **Warning**, **Best Practice**):

| Rule ID | Category | What to Check in `.xaml` | Fix Pattern |
| :--- | :--- | :--- | :--- |
| **`UI-ANA-001`** | **Volatile UI Selectors** | Selectors containing `idx='2'`, `idx='3'`, dynamic `cls='HwndWrapper[...]'` without wildcards, or missing `automationid`/`aaname`/`ctrlname`. | Replace `idx` with a stable attribute or add `<uix:TargetAnchorable.Anchors>` referencing a nearby text label. |
| **`ST-NMG-001/002`** | **Argument & Variable Naming** | Arguments without `in_`, `out_`, or `io_` prefixes; variables with default names (`Variable1`, `text1`). | Rename to `in_CustomerName`, `out_Result`, `str_Status`, `dt_Invoices`. |
| **`ST-USG-010`** | **Hardcoded Delays** | `<Delay Duration="..." />` used for UI synchronization. | Replace with `<uix:NCheckAppState>` or `WaitForReady="COMPLETE"`. |
| **`ST-SEC-008`** | **Plaintext Passwords** | Typing passwords via `NTypeInto.Text` (`String`) instead of `SecureText` (`SecureString`). | Use `SecureString` (`in_Password`) with `SecureText="[in_Password]"`. |
| **`ST-REL-005`** | **Unprotected UI/External Boundaries** | Top-level desktop/web/API invocations without `<TryCatch>` or `BusinessRuleException` vs `System.Exception` separation. | Wrap in `<TryCatch>` (or `try-catch-process` template via `scaffold_xaml`). |
| **`ST-DBP-002`** | **Default Activity DisplayNames** | Activities left with generic `DisplayName="Click"`, `DisplayName="Assign"`, `DisplayName="Sequence"`. | Give every activity a descriptive `DisplayName` (e.g., `DisplayName="Click 'Submit Invoice'"`). |
