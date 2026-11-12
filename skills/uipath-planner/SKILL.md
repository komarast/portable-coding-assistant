---
name: uipath-planner
description: UiPath Solution Planner & PDD-to-XAML Architect skill distilled from UiPath/skills (uipath-planner & uipath-genome). Decomposes Process Definition Documents (PDDs) or user requirements into modular .xaml workflows, Argument contracts, and REFramework or Linear architectures.
---

# UiPath Solution Planner & XAML Architect Skill (`uipath-planner`)

When asked to design, plan, or build a multi-step UiPath automation from a Process Definition Document (PDD) or business description:

## 1. Choose the Right Process Architecture
| Process Pattern | Recommended Architecture | Workflow Structure |
| :--- | :--- | :--- |
| **Transactional Queue Process** (e.g. invoices, orders, tickets from Orchestrator Queue or Excel rows) | **Transactional REFramework** (`Dispatcher` + `Performer`) | `Main.xaml` (State Machine: Init -> Get Transaction Data -> Process Transaction -> End Process) + `Framework/InitAllApplications.xaml` + `Framework/Process.xaml` + `Framework/CloseAllApplications.xaml` + `Framework/KillAllProcesses.xaml` |
| **Single-Run Desktop / Report Automation** (e.g. export report from SAP, transform, email) | **Linear Sequence with TryCatch** | `Main.xaml` (`TryCatch` wrapper) invoking modular screen workflows under `Workflows/` |
| **Event-Driven / Attended Assistant** (e.g. hotkey/button monitor on user desktop) | **Local Trigger Workflow** | `Main.xaml` with `<ui:TriggerScope>` |

## 2. One Application Screen = One Modular `.xaml` Workflow
Never build a 2,000-line monolithic `Main.xaml`. Decompose by **Application + Screen**:
- `Workflows/<App>_<Action>.xaml` (e.g., `Workflows/SAP_Login.xaml`, `Workflows/SAP_NavigateToVA01.xaml`, `Workflows/SAP_CreateSalesOrder.xaml`, `Workflows/SAP_Logout.xaml`).
- Each workflow MUST define explicit **Argument Contracts** (`<x:Property>`):
  - `in_` prefix for `InArgument` (e.g., `in_TransactionItem`, `in_Config`, `in_InvoiceNumber`)
  - `out_` prefix for `OutArgument` (e.g., `out_OrderId`, `out_StatusMessage`)
  - `io_` prefix for `InOutArgument` (e.g., `io_dt_Report`)

## 3. Exception Classification Contract (`BusinessRuleException` vs `System.Exception`)
- **`ui:BusinessRuleException`**: Throw when input data is invalid, missing a required field, or violates business rules (e.g., `"Invoice total is negative"`). **Never retry** a `BusinessRuleException`; route to human notification or mark Queue Item as Business Exception.
- **`System.Exception`**: Unhandled UI timeout, application crash, or network blip. Route to retry logic (`RetryScope` or REFramework `SetTransactionStatus.xaml` + `CloseAllApplications.xaml` -> `KillAllProcesses.xaml` -> `InitAllApplications.xaml`).

## 4. Execution Plan Cadence
1. Produce a concise **Workflow Inventory Table** listing each `.xaml` file, its `in_`/`out_` arguments, target desktop window, and exception behavior.
2. Scaffold each `.xaml` workflow using `scaffold_xaml`.
3. Populate activities using `edit_file` and verify every workflow with `validate_xaml`.
