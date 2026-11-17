#!/usr/bin/env bash
# =============================================================================
# Portable Coding Assistant (pca.sh) - Zero-Dependency POSIX / Linux VM Edition
# Runs with ZERO external libraries. Uses Python 3 stdlib if present, or falls
# back to pure Bash + curl + awk when no programming languages are installed!
# =============================================================================
set -euo pipefail

PCA_VERSION="1.0.0"

# If python3 is available on the system, use the embedded zero-dependency stdlib engine
# for full interactive agentic tool loop; otherwise run pure bash+curl mode.
if command -v python3 >/dev/null 2>&1 && [ "${PCA_FORCE_BASH:-0}" != "1" ]; then
    PCA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" exec python3 - "$@" << 'PYEOF'
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

VERSION = "1.2.0"
WORKSPACE = Path.cwd().resolve()
SCRIPT_DIR = Path(os.environ.get("PCA_SCRIPT_DIR", str(WORKSPACE))).resolve()
IGNORED_DIRS = {
    ".git", ".hg", ".svn", "node_modules", "bin", "obj", "dist",
    "build", "__pycache__", ".venv", "venv", ".vs", ".idea", "packages"
}

PROVIDER_CATALOG = {
    "gemini": {
        "name": "Google Gemini AI Studio (Gemini 3.8 Flash / 3.5 Flash-Lite)",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        "env_key": "GEMINI_API_KEY",
        "cheap_model": "gemini-3.5-flash-lite",
        "smart_model": "gemini-3.8-flash",
        "opus_model": "gemini-2.5-pro",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "DEFAULT: Supports gemini-3.8-flash & gemini-3.5-flash-lite via Google AI Studio (Free Tier or $0.75/1M intro rate)."
    },
    "claude": {
        "name": "Anthropic Claude 5.5 (Haiku / Sonnet / Opus)",
        "base_url": "https://api.anthropic.com/v1/messages",
        "env_key": "ANTHROPIC_API_KEY",
        "cheap_model": "claude-haiku-5-5",
        "smart_model": "claude-sonnet-5-5",
        "opus_model": "claude-opus-5-5",
        "in_cost": 0.10,
        "cached_cost": 0.01,
        "out_cost": 0.50,
        "notes": "Tiers: cheap=claude-haiku-5-5 ($0.10/$0.50), smart=claude-sonnet-5-5 ($2/$10), opus=claude-opus-5-5 ($4/$20). Auto prompt caching."
    },
    "openrouter": {
        "name": "OpenRouter (Free Coding Models + Claude)",
        "base_url": "https://openrouter.ai/api/v1/chat/completions",
        "env_key": "OPENROUTER_API_KEY",
        "cheap_model": "qwen/qwen3-coder:free",
        "smart_model": "deepseek/deepseek-chat-v3-0324:free",
        "opus_model": "anthropic/claude-opus-5.5",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "FREE ($0) using ':free' model variants on OpenRouter, or anthropic/claude-* models."
    },
    "groq": {
        "name": "Groq Cloud (Free Developer Tier)",
        "base_url": "https://api.groq.com/openai/v1/chat/completions",
        "env_key": "GROQ_API_KEY",
        "cheap_model": "llama-3.1-8b-instant",
        "smart_model": "llama-3.3-70b-versatile",
        "opus_model": "llama-3.3-70b-versatile",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "FREE ($0) developer tier with ultra-fast token streaming."
    },
    "deepseek": {
        "name": "DeepSeek API (Ultra-Cheap + Auto Cache)",
        "base_url": "https://api.deepseek.com/chat/completions",
        "env_key": "DEEPSEEK_API_KEY",
        "cheap_model": "deepseek-chat",
        "smart_model": "deepseek-reasoner",
        "opus_model": "deepseek-reasoner",
        "in_cost": 0.27,
        "cached_cost": 0.07,
        "out_cost": 1.10,
        "notes": "Automatic disk prompt caching ($0.07/1M cached input tokens)."
    },
    "openai": {
        "name": "OpenAI (Nano / Mini / GPT-4.1)",
        "base_url": "https://api.openai.com/v1/chat/completions",
        "env_key": "OPENAI_API_KEY",
        "cheap_model": "gpt-4.1-nano",
        "smart_model": "gpt-4.1-mini",
        "opus_model": "gpt-4.1",
        "in_cost": 0.10,
        "cached_cost": 0.025,
        "out_cost": 0.40,
        "notes": "GPT-4.1-nano costs $0.10/1M input ($0.025 cached)."
    },
    "azure-openai": {
        "name": "Corporate Azure OpenAI Gateway",
        "base_url": "",
        "env_key": "AZURE_OPENAI_API_KEY",
        "cheap_model": "gpt-4o-mini",
        "smart_model": "gpt-4o",
        "opus_model": "gpt-4o",
        "in_cost": 0.15,
        "cached_cost": 0.075,
        "out_cost": 0.60,
        "notes": "Set base_url in .pca.json to your corporate Azure OpenAI deployment URL."
    },
    "ollama": {
        "name": "Local Ollama / vLLM / llama.cpp",
        "base_url": "http://localhost:11434/v1/chat/completions",
        "env_key": "OLLAMA_API_KEY",
        "cheap_model": "qwen2.5-coder:7b",
        "smart_model": "qwen2.5-coder:14b",
        "opus_model": "qwen2.5-coder:32b",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "100% offline/local inference."
    },
    "github-models": {
        "name": "GitHub Models (RETIRED by GitHub on July 30, 2026)",
        "base_url": "https://models.github.ai/inference/chat/completions",
        "env_key": "GITHUB_TOKEN",
        "cheap_model": "openai/gpt-4o-mini",
        "smart_model": "openai/gpt-4o",
        "opus_model": "openai/gpt-4o",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "RETIRED: GitHub shut down GitHub Models API on July 30, 2026 (returns plain 'OK'). Use gemini, claude, openrouter, or groq."
    },
}


def get_model_for_tier(cat: dict, tier_name: str) -> str:
    if not cat:
        return "gemini-3.5-flash-lite"
    t = (tier_name or "cheap").lower()
    if t == "opus":
        return cat.get("opus_model") or cat.get("smart_model") or cat.get("cheap_model", "gemini-3.5-flash-lite")
    if t in ("smart", "sonnet"):
        return cat.get("smart_model") or cat.get("cheap_model", "gemini-3.5-flash-lite")
    return cat.get("cheap_model", "gemini-3.5-flash-lite")



class Session:
    def __init__(self):
        self.provider = "gemini"
        self.tier = "cheap"
        self.model = ""
        self.api_key = ""
        self.base_url = ""
        self.max_session_cost_usd = 0.50
        self.max_tool_steps = 12
        self.max_read_lines = 200
        self.keep_recent_turns = 10
        self.auto_approve = False
        self.no_tools = False
        self.pinned_files = []
        self.active_skills = []
        self.history = []
        self.undo_stack = []
        self.prompt_tokens = 0
        self.cached_tokens = 0
        self.completion_tokens = 0
        self.total_cost_usd = 0.0


SESSION = Session()


def estimate_tokens(text: str) -> int:
    if not text:
        return 0
    return max(1, (len(text) + 3) // 4)


def safe_path(rel_or_abs: str) -> Path:
    if not rel_or_abs:
        return WORKSPACE
    p = Path(rel_or_abs)
    if not p.is_absolute():
        p = WORKSPACE / p
    return p.resolve()


def rel_path(full: Path) -> str:
    try:
        return str(full.relative_to(WORKSPACE)).replace("\\", "/")
    except ValueError:
        return str(full)


def tool_list_files(sub_dir: str = ".", max_depth: int = 3, max_entries: int = 150) -> str:
    target = safe_path(sub_dir)
    if not target.exists():
        return f"Error: Directory not found: {sub_dir}"
    results = []
    queue = [(target, 0)]
    while queue and len(results) < max_entries:
        curr, depth = queue.pop(0)
        try:
            entries = sorted(curr.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))
        except OSError:
            continue
        for item in entries:
            if len(results) >= max_entries:
                break
            if item.is_dir():
                if item.name in IGNORED_DIRS:
                    continue
                results.append(f"[DIR]  {rel_path(item)}/")
                if depth + 1 < max_depth:
                    queue.append((item, depth + 1))
            elif item.is_file():
                kb = round(item.stat().st_size / 1024.0, 1)
                results.append(f"[FILE] {rel_path(item)} ({kb} KB)")
    if not results:
        return "(empty workspace)"
    if len(results) >= max_entries:
        results.append(f"... (truncated at {max_entries} entries)")
    return "\n".join(results)


def tool_search_text(pattern: str, sub_dir: str = ".", max_matches: int = 40) -> str:
    if not pattern:
        return "Error: pattern is required."
    target = safe_path(sub_dir)
    if not target.exists():
        return f"Error: Path not found: {sub_dir}"
    try:
        regex = re.compile(pattern, re.IGNORECASE)
    except re.error as e:
        return f"Error: Invalid regex '{pattern}': {e}"

    matches = []
    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]
        for fname in sorted(files):
            if len(matches) >= max_matches:
                break
            fpath = Path(root) / fname
            try:
                if fpath.stat().st_size > 1048576:
                    continue
                text = fpath.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            for idx, line in enumerate(text.splitlines(), 1):
                if regex.search(line):
                    snippet = line.strip()
                    if len(snippet) > 160:
                        snippet = snippet[:160] + "..."
                    matches.append(f"{rel_path(fpath)}:{idx}: {snippet}")
                    if len(matches) >= max_matches:
                        break
    if not matches:
        return f"No matches found for pattern: {pattern}"
    return "\n".join(matches)


def tool_read_file(path: str, start_line: int = 1, end_line: int = 0) -> str:
    if not path:
        return "Error: path is required."
    full = safe_path(path)
    if not full.is_file():
        return f"Error: File does not exist: {path}"
    lines = full.read_text(encoding="utf-8", errors="replace").splitlines()
    total = len(lines)
    if total == 0:
        return f"(File '{path}' is empty)"
    start_line = max(1, int(start_line or 1))
    if not end_line or int(end_line) <= 0:
        end_line = min(total, start_line + SESSION.max_read_lines - 1)
    else:
        end_line = min(total, int(end_line))
    if (end_line - start_line + 1) > SESSION.max_read_lines:
        end_line = start_line + SESSION.max_read_lines - 1

    out = [f"--- {rel_path(full)} (lines {start_line}-{end_line} of {total}) ---"]
    for i in range(start_line, end_line + 1):
        out.append(f"{i:4d} | {lines[i - 1]}")
    if end_line < total:
        out.append(f"... ({total - end_line} more lines; call read_file with start_line={end_line + 1})")
    return "\n".join(out)


def confirm_action(title: str, preview: str) -> bool:
    if SESSION.auto_approve:
        return True
    print(f"\n  [Action Confirmation] {title}")
    if preview:
        for ln in preview.splitlines():
            print(f"    {ln}")
    try:
        ans = input("  Allow this action? [y = yes / n = no / a = always]: ").strip().lower()
    except EOFError:
        return False
    if ans in ("a", "always"):
        SESSION.auto_approve = True
        return True
    return ans in ("y", "yes")


def tool_edit_file(path: str, search: str = "", replace: str = "") -> str:
    if not path:
        return "Error: path is required."
    full = safe_path(path)
    rpath = rel_path(full)
    exists = full.is_file()
    old_content = full.read_text(encoding="utf-8", errors="replace") if exists else ""

    if not exists:
        if search:
            return f"Error: File '{rpath}' does not exist, so 'search' must be empty when creating a new file."
        if not confirm_action(f"Create new file '{rpath}'", f"+ [New File: {rpath} ({len(replace)} chars)]"):
            return f"User declined creating file '{rpath}'."
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(replace, encoding="utf-8")
        SESSION.undo_stack.append({"path": full, "existed": False, "old_content": ""})
        return f"Created file '{rpath}' ({len(replace)} bytes)."

    if not search:
        if not confirm_action(f"Overwrite '{rpath}'", f"- [Overwrite entire file '{rpath}']"):
            return f"User declined overwriting '{rpath}'."
        full.write_text(replace, encoding="utf-8")
        SESSION.undo_stack.append({"path": full, "existed": True, "old_content": old_content})
        return f"Updated file '{rpath}'."

    use_crlf = "\r\n" in old_content
    norm_old = old_content.replace("\r\n", "\n")
    norm_search = search.replace("\r\n", "\n")
    norm_replace = replace.replace("\r\n", "\n")

    idx = norm_old.find(norm_search)
    if idx < 0:
        return f"Error: Exact SEARCH block not found in '{rpath}'. Use read_file first to check exact lines."
    if norm_old.find(norm_search, idx + len(norm_search)) >= 0:
        return f"Error: SEARCH block matched multiple locations in '{rpath}'. Include more context lines."

    preview_lines = [f"- {l}" for l in norm_search.splitlines()] + [f"+ {l}" for l in norm_replace.splitlines()]
    if not confirm_action(f"Patch '{rpath}'", "\n".join(preview_lines)):
        return f"User declined editing '{rpath}'."

    new_norm = norm_old[:idx] + norm_replace + norm_old[idx + len(norm_search):]
    final_text = new_norm.replace("\n", "\r\n") if use_crlf else new_norm
    full.write_text(final_text, encoding="utf-8")
    SESSION.undo_stack.append({"path": full, "existed": True, "old_content": old_content})
    return f"Successfully patched '{rpath}'."


DEFAULT_XAML_SNIPPETS = {
    "NApplicationCard": {
        "packageId": "UiPath.UIAutomation.Activities",
        "xmlns": 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"',
        "defaultXaml": (
            '<uix:NApplicationCard AttachMode="ByInstance" DisplayName="Use Application/Browser" '
            'InteractionMode="Simulate" OpenMode="IfNotOpen" ScopeGuid="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc" Version="V2">\n'
            '  <uix:NApplicationCard.Body>\n'
            '    <ActivityAction x:TypeArguments="x:Object">\n'
            '      <ActivityAction.Argument>\n'
            '        <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />\n'
            '      </ActivityAction.Argument>\n'
            '      <Sequence DisplayName="Do" />\n'
            '    </ActivityAction>\n'
            '  </uix:NApplicationCard.Body>\n'
            '  <uix:NApplicationCard.TargetApp>\n'
            '    <uix:TargetApp FilePath="notepad.exe" Selector="&lt;wnd app=\'notepad.exe\' title=\'*Notepad*\' /&gt;" />\n'
            '  </uix:NApplicationCard.TargetApp>\n'
            '</uix:NApplicationCard>'
        ),
    },
    "NClick": {
        "packageId": "UiPath.UIAutomation.Activities",
        "xmlns": 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"',
        "defaultXaml": (
            '<uix:NClick ActivateBefore="True" ClickType="Single" DisplayName="Click Target" '
            'InteractionMode="Simulate" KeyModifiers="None" MouseButton="Left" Version="V3">\n'
            '  <uix:NClick.Target>\n'
            '    <uix:TargetAnchorable FullSelectorArgument="&lt;uia role=\'button\' name=\'OK\' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />\n'
            '  </uix:NClick.Target>\n'
            '</uix:NClick>'
        ),
    },
    "NTypeInto": {
        "packageId": "UiPath.UIAutomation.Activities",
        "xmlns": 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"',
        "defaultXaml": (
            '<uix:NTypeInto ActivateBefore="True" ClickBeforeMode="Single" DisplayName="Type Into Target" '
            'EmptyFieldMode="SingleLine" InteractionMode="Simulate" Text="[in_Text]" Version="V3">\n'
            '  <uix:NTypeInto.Target>\n'
            '    <uix:TargetAnchorable FullSelectorArgument="&lt;uia role=\'edit\' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />\n'
            '  </uix:NTypeInto.Target>\n'
            '</uix:NTypeInto>'
        ),
    },
    "NGetText": {
        "packageId": "UiPath.UIAutomation.Activities",
        "xmlns": 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"',
        "defaultXaml": (
            '<uix:NGetText DisplayName="Get Text" Text="[out_Text]" Version="V3">\n'
            '  <uix:NGetText.Target>\n'
            '    <uix:TargetAnchorable FullSelectorArgument="&lt;uia role=\'text\' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />\n'
            '  </uix:NGetText.Target>\n'
            '</uix:NGetText>'
        ),
    },
    "NCheckAppState": {
        "packageId": "UiPath.UIAutomation.Activities",
        "xmlns": 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"',
        "defaultXaml": (
            '<uix:NCheckAppState DisplayName="Check App State" Result="[bool_Appeared]" Timeout="5" Version="V3">\n'
            '  <uix:NCheckAppState.Target>\n'
            '    <uix:TargetAnchorable FullSelectorArgument="&lt;uia role=\'dialog\' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />\n'
            '  </uix:NCheckAppState.Target>\n'
            '  <uix:NCheckAppState.IfExists>\n'
            '    <Sequence DisplayName="Target Appears" />\n'
            '  </uix:NCheckAppState.IfExists>\n'
            '  <uix:NCheckAppState.IfNotExists>\n'
            '    <Sequence DisplayName="Target Does Not Appear" />\n'
            '  </uix:NCheckAppState.IfNotExists>\n'
            '</uix:NCheckAppState>'
        ),
    },
    "LogMessage": {
        "packageId": "UiPath.System.Activities",
        "xmlns": 'xmlns:ui="http://schemas.uipath.com/workflow/activities"',
        "defaultXaml": '<ui:LogMessage DisplayName="Log Message" Level="Info" Message="[&quot;Status message&quot;]" />',
    },
    "InvokeWorkflowFile": {
        "packageId": "UiPath.System.Activities",
        "xmlns": 'xmlns:ui="http://schemas.uipath.com/workflow/activities"',
        "defaultXaml": (
            '<ui:InvokeWorkflowFile ArgumentsVariable="{x:Null}" ContinueOnError="{x:Null}" '
            'DisplayName="Invoke SubWorkflow" UnSafe="False" WorkflowFileName="SubWorkflow.xaml">\n'
            '  <ui:InvokeWorkflowFile.Arguments>\n'
            '    <scg:Dictionary x:TypeArguments="x:String, Argument" />\n'
            '  </ui:InvokeWorkflowFile.Arguments>\n'
            '</ui:InvokeWorkflowFile>'
        ),
    },
    "MultipleAssign": {
        "packageId": "UiPath.System.Activities",
        "xmlns": 'xmlns:ui="http://schemas.uipath.com/workflow/activities"',
        "defaultXaml": (
            '<ui:MultipleAssign DisplayName="Multiple Assign">\n'
            '  <ui:MultipleAssign.AssignOperations>\n'
            '    <scg:List x:TypeArguments="ui:AssignOperation" Capacity="4">\n'
            '      <ui:AssignOperation Value="[&quot;val&quot;]">\n'
            '        <ui:AssignOperation.To>\n'
            '          <OutArgument x:TypeArguments="x:String">[str_Var]</OutArgument>\n'
            '        </ui:AssignOperation.To>\n'
            '      </ui:AssignOperation>\n'
            '    </scg:List>\n'
            '  </ui:MultipleAssign.AssignOperations>\n'
            '</ui:MultipleAssign>'
        ),
    },
}


def _parse_flag(tokens: list, *flags, default: str = "") -> str:
    for idx, tok in enumerate(tokens):
        if tok in flags and idx + 1 < len(tokens):
            return tokens[idx + 1]
        for fl in flags:
            if tok.startswith(fl + "="):
                return tok.split("=", 1)[1]
    return default


def native_uip_command(raw_cmd: str) -> str:
    import shlex
    cleaned = re.sub(r">\s*/dev/null.*$", "", raw_cmd).strip()
    cleaned = re.sub(r"2>&1\s*&?\s*$", "", cleaned).strip()
    try:
        tokens = shlex.split(cleaned)
    except ValueError:
        tokens = cleaned.split()
    if not tokens:
        return json.dumps({"Result": "Failure", "Code": "InvalidCommand", "Data": {"message": "Empty command"}})
    if tokens[0] in ("uip", "uip.exe", "uip.cmd", "./uip.cmd"):
        tokens = tokens[1:]

    if not tokens or tokens[0] in ("--help", "-h", "help"):
        return json.dumps({
            "Result": "Success",
            "Code": "Help",
            "Data": {
                "emulator": "PCA Built-in Offline uip CLI Emulator",
                "commands": [
                    "uip rpa init",
                    "uip rpa validate",
                    "uip rpa build",
                    "uip rpa activities find",
                    "uip rpa activities get-default-xaml",
                    "uip rpa packages versions",
                    "uip rpa packages install",
                    "uip rpa templates search",
                    "uip rpa get-object-repository",
                    "uip rpa analyzer-rules list",
                    "uip rpa uia",
                    "uip rpa-legacy validate",
                    "uip rpa-legacy find-activities",
                    "uip rpa-legacy type-definition",
                ],
            },
        })

    if tokens[:2] == ["tools", "list"]:
        return json.dumps({
            "Result": "Success",
            "Code": "ToolsList",
            "Data": {"tools": ["rpa", "rpa-legacy", "solution", "or", "is"]},
        })

    domain = tokens[0]
    sub = tokens[1:] if len(tokens) > 1 else []

    if domain in ("rpa", "rpa-legacy"):
        action = sub[0] if sub else "--help"
        sub_2 = sub[1] if len(sub) > 1 else ""

        if action == "init":
            name = _parse_flag(sub, "--name", "-n", default="UiPathProject")
            loc = _parse_flag(sub, "--location", "-l", default=str(WORKSPACE))
            expr_lang = _parse_flag(sub, "--expression-language", default="VisualBasic")
            target_fw = _parse_flag(sub, "--target-framework", default="Windows")
            loc_path = safe_path(loc)
            proj_dir = loc_path if loc_path.name.lower() == name.lower() else (loc_path / name)
            proj_dir.mkdir(parents=True, exist_ok=True)
            proj_json = {
                "name": name,
                "projectId": "d9a8f1b2-4c3e-4a1b-9f0e-123456789abc",
                "description": f"UiPath {target_fw} automation project ({expr_lang})",
                "main": "Main.xaml",
                "dependencies": {
                    "UiPath.System.Activities": "[25.10.2]",
                    "UiPath.UIAutomation.Activities": "[26.10.0-preview]",
                },
                "webServices": [],
                "entitiesStores": [],
                "schemaVersion": "4.0",
                "studioVersion": "25.10.0.0",
                "projectVersion": "1.0.0",
                "runtimeOptions": {
                    "autoDispose": False,
                    "netFrameworkLazyLoading": False,
                    "isPausable": True,
                    "isAttended": False,
                    "requiresUserInteraction": True,
                    "supportsPersistence": False,
                    "workflowSerialization": "NewtonsoftJson",
                    "excludedLoggedData": ["Private:*", "*password*"],
                    "executionType": "Workflow",
                    "readyForPiP": False,
                    "startsInPiP": False,
                    "mustRestoreAllDependencies": True,
                    "pipType": "ChildSession",
                },
                "designOptions": {
                    "projectProfile": "Developement",
                    "outputType": "Process",
                    "libraryOptions": {"includeOriginalXaml": False, "privateWorkflows": []},
                    "processOptions": {"ignoredFiles": []},
                    "fileInfoCollection": [],
                    "saveToCloud": False,
                },
                "expressionLanguage": expr_lang,
                "entryPoints": [
                    {
                        "filePath": "Main.xaml",
                        "uniqueId": "e1a2b3c4-5678-4012-9abc-def012345678",
                        "input": [],
                        "output": [],
                    }
                ],
                "isTemplate": False,
                "templateProjectData": {},
                "publishData": {},
                "targetFramework": target_fw,
            }
            (proj_dir / "project.json").write_text(json.dumps(proj_json, indent=2), encoding="utf-8")
            main_xaml = proj_dir / "Main.xaml"
            if not main_xaml.exists():
                tool_scaffold_xaml(str(main_xaml), template="sequence")
            # Seed .local/docs/packages/UiPath.UIAutomation.Activities/ui-automation-guide.md
            bundled_uia = SCRIPT_DIR / "skills" / "uipath-rpa" / "references" / "activity-docs" / "UiPath.UIAutomation.Activities" / "26.10" / "ui-automation-guide.md"
            if bundled_uia.is_file():
                target_uia = proj_dir / ".local" / "docs" / "packages" / "UiPath.UIAutomation.Activities" / "ui-automation-guide.md"
                target_uia.parent.mkdir(parents=True, exist_ok=True)
                target_uia.write_text(bundled_uia.read_text(encoding="utf-8"), encoding="utf-8")
            return json.dumps({
                "Result": "Success",
                "Code": "Init",
                "Data": {
                    "projectDir": str(proj_dir),
                    "projectFile": str(proj_dir / "project.json"),
                    "mainFile": str(main_xaml),
                    "targetFramework": target_fw,
                    "expressionLanguage": expr_lang,
                },
            })

        if action in ("validate", "analyze"):
            file_arg = _parse_flag(sub, "--file-path", "-f")
            proj_arg = _parse_flag(sub, "--project-dir", "-p", default=str(WORKSPACE))
            if not file_arg and len(sub) > 1 and not sub[1].startswith("-"):
                file_arg = sub[1]
            targets = []
            if file_arg:
                fp = safe_path(file_arg)
                if not fp.is_file() and proj_arg:
                    fp = safe_path(str(Path(proj_arg) / file_arg))
                targets.append(fp)
            else:
                pdir = safe_path(proj_arg)
                targets.extend(sorted(pdir.rglob("*.xaml")))

            all_errors = []
            all_warnings = []
            for tf in targets:
                rep = tool_validate_xaml(str(tf))
                for line in rep.splitlines():
                    s = line.strip()
                    if s.startswith("ERROR:"):
                        all_errors.append(f"{tf.name}: {s[6:].strip()}")
                    elif s.startswith("WARN:"):
                        all_warnings.append(f"{tf.name}: {s[5:].strip()}")
                if rep.startswith("Error:"):
                    all_errors.append(rep)

            if all_errors:
                return json.dumps({
                    "Result": "Failure",
                    "Code": "ValidationErrorsFound",
                    "Data": {
                        "message": "; ".join(all_errors),
                        "errors": all_errors,
                        "warnings": all_warnings,
                    },
                })
            return json.dumps({
                "Result": "Success",
                "Code": "Validate",
                "Data": {
                    "message": f"Validation succeeded for {len(targets)} file(s) with 0 error(s) and {len(all_warnings)} warning(s).",
                    "errors": [],
                    "warnings": all_warnings,
                },
            })

        if action in ("build", "pack"):
            proj_arg = _parse_flag(sub, "--project-dir", "-p")
            if not proj_arg and len(sub) > 1 and not sub[1].startswith("-"):
                proj_arg = sub[1]
            pdir = safe_path(proj_arg or str(WORKSPACE))
            if pdir.is_file():
                pdir = pdir.parent
            xamls = sorted(pdir.rglob("*.xaml"))
            all_errors = []
            all_warnings = []
            for xf in xamls:
                rep = tool_validate_xaml(str(xf))
                for line in rep.splitlines():
                    s = line.strip()
                    if s.startswith("ERROR:"):
                        all_errors.append(f"{xf.name}: {s[6:].strip()}")
                    elif s.startswith("WARN:"):
                        all_warnings.append(f"{xf.name}: {s[5:].strip()}")
            local_content = pdir / ".local" / "content"
            local_content.mkdir(parents=True, exist_ok=True)
            (local_content / "entry-points.json").write_text(
                json.dumps({"entryPoints": [{"filePath": "Main.xaml"}]}, indent=2),
                encoding="utf-8",
            )
            (local_content / "bindings_v2.json").write_text(
                json.dumps({"version": "2.0", "resources": []}, indent=2),
                encoding="utf-8",
            )
            if all_errors:
                return json.dumps({
                    "Result": "Failure",
                    "Code": "BuildFailed",
                    "Data": {
                        "projectDir": str(pdir),
                        "message": "; ".join(all_errors),
                        "errors": all_errors,
                        "warnings": all_warnings,
                    },
                })
            return json.dumps({
                "Result": "Success",
                "Code": "Build",
                "Data": {
                    "projectDir": str(pdir),
                    "filesValidated": len(xamls),
                    "errors": [],
                    "warnings": all_warnings,
                    "message": f"Build succeeded ({len(xamls)} workflow(s) validated, 0 errors).",
                },
            })

        if (action == "activities" and sub_2 == "find") or action == "find-activities":
            query = _parse_flag(sub, "--query", "-q", default="").lower()
            if not query and len(sub) >= 2 and not sub[-1].startswith("-"):
                query = sub[-1].lower()
            matches = []
            for cls_name, info in DEFAULT_XAML_SNIPPETS.items():
                if not query or query in cls_name.lower() or query in info["packageId"].lower():
                    matches.append({
                        "className": cls_name,
                        "displayName": cls_name,
                        "packageId": info["packageId"],
                        "xmlns": info["xmlns"],
                        "isTrigger": False,
                        "triggerType": None,
                    })
            docs_root = SCRIPT_DIR / "skills" / "uipath-rpa" / "references" / "activity-docs"
            if docs_root.is_dir():
                for md_file in sorted(docs_root.rglob("activities/*.md")):
                    act_name = md_file.stem
                    if not query or query in act_name.lower():
                        pkg_id = md_file.parents[2].name
                        if not any(m["className"] == act_name for m in matches):
                            matches.append({
                                "className": act_name,
                                "displayName": act_name,
                                "packageId": pkg_id,
                                "docPath": str(md_file.relative_to(SCRIPT_DIR / "skills" / "uipath-rpa")),
                                "isTrigger": "Trigger" in act_name,
                                "triggerType": "integration" if "IntegrationService" in pkg_id else ("local" if "Trigger" in act_name else None),
                            })
            return json.dumps({
                "Result": "Success",
                "Code": "ActivitiesFind",
                "Data": {"query": query, "count": len(matches), "activities": matches[:30]},
            })

        if (action == "activities" and sub_2 == "get-default-xaml") or action == "type-definition":
            cls_name = _parse_flag(sub, "--activity-class-name", "--type", "-t", default="LogMessage")
            short_cls = cls_name.split(".")[-1].split(":")[-1]
            info = DEFAULT_XAML_SNIPPETS.get(short_cls)
            if not info:
                is_uia = short_cls.startswith("N")
                ns = 'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"' if is_uia else 'xmlns:ui="http://schemas.uipath.com/workflow/activities"'
                prefix = "uix" if is_uia else "ui"
                info = {
                    "packageId": "UiPath.UIAutomation.Activities" if is_uia else "UiPath.System.Activities",
                    "xmlns": ns,
                    "defaultXaml": f'<{prefix}:{short_cls} DisplayName="{short_cls}" sap2010:WorkflowViewState.IdRef="{short_cls}_1" />',
                }
            return json.dumps({
                "Result": "Success",
                "Code": "GetDefaultXaml",
                "Data": {
                    "className": short_cls,
                    "packageId": info["packageId"],
                    "xmlns": info["xmlns"],
                    "defaultXaml": info["defaultXaml"],
                },
            })

        if action == "packages" and sub_2 == "versions":
            pkg_id = _parse_flag(sub, "--package-id", "-p", default="UiPath.System.Activities")
            versions = ["26.10.0-preview", "25.12.2", "25.10.2", "24.10.6"]
            pkg_dir = SCRIPT_DIR / "skills" / "uipath-rpa" / "references" / "activity-docs" / pkg_id
            if pkg_dir.is_dir():
                for vd in sorted(pkg_dir.iterdir(), reverse=True):
                    if vd.is_dir() and vd.name not in versions:
                        versions.insert(0, vd.name)
            return json.dumps({
                "Result": "Success",
                "Code": "PackageVersions",
                "Data": {"packageId": pkg_id, "versions": versions},
            })

        if action == "packages" and sub_2 == "install":
            pkg_spec = _parse_flag(sub, "--packages", default="")
            proj_arg = _parse_flag(sub, "--project-dir", default=str(WORKSPACE))
            pdir = safe_path(proj_arg)
            pjson_path = pdir / "project.json"
            installed = []
            if pjson_path.is_file():
                try:
                    pdata = json.loads(pjson_path.read_text(encoding="utf-8"))
                except Exception:
                    pdata = {"dependencies": {}}
            else:
                pdata = {"dependencies": {}}
            deps = pdata.setdefault("dependencies", {})
            m_id = re.search(r"id=([^,\s'\"]+)", pkg_spec)
            m_ver = re.search(r"version=([^,\s'\"]+)", pkg_spec)
            if m_id:
                pid = m_id.group(1)
                pver = m_ver.group(1) if m_ver else "25.10.2"
                deps[pid] = f"[{pver}]"
                installed.append({"id": pid, "version": pver})
            if pjson_path.is_file():
                pjson_path.write_text(json.dumps(pdata, indent=2), encoding="utf-8")
            return json.dumps({
                "Result": "Success",
                "Code": "PackagesInstall",
                "Data": {"installed": installed, "projectDir": str(pdir)},
            })

        if action == "templates" and sub_2 == "search":
            q = _parse_flag(sub, "--query", default="").lower()
            templates = [
                {"id": "blank-process", "name": "Blank Process", "source": "Official", "description": "Standard modern XAML process"},
                {"id": "reframework", "name": "Robotic Enterprise Framework (REFramework)", "source": "Official", "description": "Transactional state-machine template with Init, GetTransactionData, Process, EndProcess"},
                {"id": "transactional-process", "name": "Transactional Process", "source": "Official", "description": "Flowchart transactional process"},
            ]
            return json.dumps({
                "Result": "Success",
                "Code": "TemplatesSearch",
                "Data": {"query": q, "templates": templates},
            })

        if action == "get-object-repository":
            return json.dumps({
                "Result": "Success",
                "Code": "GetObjectRepository",
                "Data": {"applications": [], "note": "Offline PCA mode: use inline TargetAnchorable selectors or inspect_ui_tree."},
            })

        if action == "analyzer-rules" and sub_2 == "list":
            return json.dumps({
                "Result": "Success",
                "Code": "AnalyzerRulesList",
                "Data": {
                    "rules": [
                        {"id": "ST-NMG-002", "severity": "Warning", "description": "Prefix arguments with in_, out_, or io_"},
                        {"id": "ST-SEC-007", "severity": "Error", "description": "Keep secrets inside scope using Get Credential/Secret"},
                        {"id": "ST-USG-010", "severity": "Warning", "description": "Avoid hardcoded Delay; prefer NCheckAppState"},
                        {"id": "UI-ANA-001", "severity": "Warning", "description": "Avoid volatile idx >= 2 in selectors"},
                    ]
                },
            })

        if action == "uia":
            win_title = _parse_flag(sub, "--window-title", "--title", default="")
            tree_out = tool_inspect_ui_tree(win_title, 3)
            return json.dumps({
                "Result": "Success",
                "Code": "UiaInspect",
                "Data": {"windowTitle": win_title, "uiTree": tree_out},
            })

    return json.dumps({
        "Result": "Success",
        "Code": "EmulatedCommand",
        "Data": {"command": raw_cmd, "message": "Executed in PCA offline uip emulator."},
    })


def _is_uip_invocation(seg: str) -> bool:
    s = seg.strip()
    return bool(re.match(r"^(?:uip(?:\.exe|\.cmd)?|\./uip\.cmd)\b", s))


def tool_run_command(command: str) -> str:
    if not command:
        return "Error: command is required."
    if not confirm_action("Execute Shell Command", f"  $ {command}"):
        return f"User declined executing command: {command}"

    import shutil
    has_system_uip = bool(shutil.which("uip")) and os.environ.get("PCA_FORCE_BUILTIN_UIP") != "1"
    segments = [s.strip() for s in command.split("&&") if s.strip()]
    if segments and any(_is_uip_invocation(s) for s in segments) and not has_system_uip:
        outputs = []
        exit_code = 0
        for seg in segments:
            if _is_uip_invocation(seg):
                res_json = native_uip_command(seg)
                outputs.append(res_json)
                if '"Result": "Failure"' in res_json:
                    exit_code = 1
            else:
                proc = subprocess.run(
                    seg, shell=True, cwd=str(WORKSPACE),
                    capture_output=True, text=True, timeout=30
                )
                out_piece = f"{proc.stdout.strip()}\n{proc.stderr.strip()}".strip()
                if out_piece:
                    outputs.append(out_piece)
                if proc.returncode != 0:
                    exit_code = proc.returncode
                    break
        combined = f"ExitCode: {exit_code}\n" + "\n".join(outputs)
        if len(combined) > 3500:
            combined = combined[:3500] + "\n... [Output truncated to save tokens]"
        return combined.strip()

    try:
        proc = subprocess.run(
            command, shell=True, cwd=str(WORKSPACE),
            capture_output=True, text=True, timeout=30
        )
        combined = f"ExitCode: {proc.returncode}\n{proc.stdout.strip()}\n{proc.stderr.strip()}".strip()
        if len(combined) > 3500:
            combined = combined[:3500] + "\n... [Output truncated to save tokens]"
        return combined
    except Exception as e:
        return f"Command execution failed: {e}"


def tool_inspect_xaml(path: str) -> str:
    if not path:
        return "Error: path is required."
    full = safe_path(path)
    if not full.is_file():
        return f"Error: XAML file does not exist: {path}"
    lines = full.read_text(encoding="utf-8", errors="replace").splitlines()
    out = [f"=== UiPath XAML Outline: {rel_path(full)} ({len(lines)} total lines) ==="]
    args_list, vars_list, acts_list, sels_list = [], [], [], []
    in_view_state = False

    for idx, ln in enumerate(lines, 1):
        if "<sap2010:WorkflowViewState" in ln or ("<scg:Dictionary" in ln and "ViewState" in ln):
            if "/>" not in ln:
                in_view_state = True
            continue
        if in_view_state:
            if "</sap2010:WorkflowViewState" in ln or "</scg:Dictionary>" in ln:
                in_view_state = False
            continue
        m_arg = re.search(r'<x:Property\s+[^>]*Name="([^"]+)"[^>]*Type="([^"]+)"', ln)
        if m_arg:
            args_list.append(f"  Line {idx:4d}: Argument {m_arg.group(1)} ({m_arg.group(2)})")
            continue
        m_var = re.search(r'<Variable\s+[^>]*x:TypeArguments="([^"]+)"[^>]*Name="([^"]+)"', ln)
        if m_var:
            vars_list.append(f"  Line {idx:4d}: Variable {m_var.group(2)} : {m_var.group(1)}")
            continue
        m_var2 = re.search(r'<Variable\s+[^>]*Name="([^"]+)"[^>]*x:TypeArguments="([^"]+)"', ln)
        if m_var2:
            vars_list.append(f"  Line {idx:4d}: Variable {m_var2.group(1)} : {m_var2.group(2)}")
            continue
        m_sel = re.search(r'(?:FullSelectorArgument|Selector)="([^"]+)"', ln)
        if m_sel and len(sels_list) < 40:
            s_val = (
                m_sel.group(1)
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "'")
            )
            sels_list.append(f"  Line {idx:4d}: {s_val}")
        m_act = re.match(r'^\s*<([A-Za-z0-9_:]+)\s+[^>]*DisplayName="([^"]+)"', ln)
        if m_act:
            tag, disp = m_act.group(1), m_act.group(2)
            extra = ""
            m_wf = re.search(r'WorkflowFileName="([^"]+)"', ln)
            if m_wf:
                extra = f" -> Calls: {m_wf.group(1)}"
            elif 'Selector="' in ln or 'FullSelectorArgument="' in ln:
                extra = " [Selector]"
            acts_list.append(f"  Line {idx:4d}: [{tag}] `{disp}`{extra}")

    out.append(f"Arguments ({len(args_list)}):")
    out.extend(args_list or ["  (none)"])
    out.append(f"Variables ({len(vars_list)}):")
    out.extend(vars_list or ["  (none)"])
    out.append(f"Activities ({len(acts_list)}):")
    out.extend(acts_list[:120] or ["  (none with DisplayName)"])
    if len(acts_list) > 120:
        out.append(f"  ... ({len(acts_list) - 120} more activities)")
    if sels_list:
        out.append(f"UI Selectors ({len(sels_list)}):")
        out.extend(sels_list)
    out.append("Tip: Use read_file with start_line/end_line around the specific Line number above before calling edit_file.")
    return "\n".join(out)


def tool_inspect_ui_tree(window_title: str = "", max_depth: int = 3) -> str:
    if sys.platform != "win32":
        return (
            "=== Windows UI Automation Tree Inspector ===\n"
            "Note: Live Windows UIAutomationClient inspection requires Windows (.NET Framework / pca.ps1). "
            f"Requested window_title='{window_title}', max_depth={max_depth}.\n"
            "On Linux/macOS, craft selectors using standard UiPath attributes: "
            "<wnd app='app.exe' title='*Window*' /><uia role='button' name='Submit' automationid='btnSubmit' />"
        )
    return "Run pca.ps1 on Windows to inspect live UIAutomationClient desktop elements."


def tool_validate_xaml(path: str) -> str:
    if not path:
        return "Error: path is required."
    full = safe_path(path)
    if not full.is_file():
        return f"Error: XAML file does not exist: {path}"
    raw = full.read_text(encoding="utf-8", errors="replace")
    errors = []
    warnings = []

    import xml.etree.ElementTree as ET
    try:
        ET.fromstring(raw)
    except Exception as e:
        errors.append(f"[XML Syntax Error] Not well-formed XML: {e}")

    if "<uix:" in raw and "xmlns:uix=" not in raw:
        errors.append("[Missing Namespace] File uses <uix:*> Modern UI activities but is missing xmlns:uix declaration on <Activity>.")
    if "<ui:" in raw and "xmlns:ui=" not in raw:
        errors.append("[Missing Namespace] File uses <ui:*> activities but is missing xmlns:ui declaration on <Activity>.")

    scope_tags = [
        "uix:NApplicationCard.Body",
        "ui:WindowScope.Body",
        "ui:BrowserScope.Body",
        "ui:ExcelApplicationScope.Body",
    ]
    for st in scope_tags:
        pattern = rf"<{re.escape(st)}>\s*<(?!ActivityAction\b)([A-Za-z0-9_:]+)"
        m = re.search(pattern, raw)
        if m:
            errors.append(
                f"[Invalid Scope Body] <{st}> contains <{m.group(1)}> directly without an <ActivityAction> wrapper. "
                "UiPath Studio requires <ActivityAction><ActivityAction.Argument><DelegateInArgument .../></ActivityAction.Argument>...</ActivityAction>."
            )

    for m_fc in re.finditer(r"<Flowchart\b[^>]*>([\s\S]*?)</Flowchart>", raw):
        fc_body = m_fc.group(1)
        if re.search(r"<(Sequence|ui:Click|uix:NClick|Assign)\b", fc_body) and "<FlowStep" not in fc_body:
            errors.append(
                "[Invalid Flowchart Child] <Flowchart> cannot contain raw <Sequence> or activities directly; wrap each node in <FlowStep> and set <Flowchart.StartNode>."
            )

    if re.search(r"idx=['\"][2-9]\d*['\"]|idx=&quot;[2-9]\d*&quot;", raw):
        warnings.append("[Fragile Selector (UI-ANA-001)] Selector uses volatile idx attribute (idx >= 2). Prefer automationid, name, or innertext.")
    if re.search(r"<Delay\b", raw):
        warnings.append("[Reliability (ST-REL-005)] Hardcoded <Delay> activity detected. Prefer <uix:NCheckAppState> or dynamic element timeout.")

    proj_file = WORKSPACE / "project.json"
    if proj_file.is_file():
        proj_raw = proj_file.read_text(encoding="utf-8", errors="replace")
        if '"expressionLanguage"' in proj_raw and "CSharp" in proj_raw:
            if "VisualBasic.Settings" in raw and "CSharpValue" not in raw:
                warnings.append("[Expression Language Mismatch] project.json uses CSharp, but XAML contains VisualBasic.Settings.")

    out = [f"=== UiPath XAML Validation Report: {rel_path(full)} ==="]
    if not errors and not warnings:
        out.append("STATUS: PASSED (0 errors, 0 warnings) - Ready to open in UiPath Studio.")
    elif not errors:
        out.append(f"STATUS: PASSED WITH WARNINGS (0 errors, {len(warnings)} warning(s))")
    else:
        out.append(f"STATUS: FAILED ({len(errors)} error(s), {len(warnings)} warning(s))")
    for err in errors:
        out.append(f"  ERROR: {err}")
    for w in warnings:
        out.append(f"  WARN:  {w}")
    return "\n".join(out)


def tool_scaffold_xaml(
    path: str,
    template: str = "sequence",
    app_exe: str = "notepad.exe",
    window_title: str = "*Notepad*",
) -> str:
    if not path:
        return "Error: path is required."
    full = safe_path(path)
    existed = full.is_file()
    old_content = full.read_text(encoding="utf-8", errors="replace") if existed else ""
    class_name = full.stem
    tpl = (template or "sequence").lower()

    if tpl in ("desktop", "desktop-uia", "uia"):
        xaml = f"""<Activity mc:Ignorable="sap sap2010" x:Class="{class_name}"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:sco="clr-namespace:System.Collections.ObjectModel;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:uix="http://schemas.uipath.com/workflow/activities/uix"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_InputText" Type="InArgument(x:String)" />
    <x:Property Name="out_ResultText" Type="OutArgument(x:String)" />
  </x:Members>
  <VisualBasic.Settings>
    <x:Null />
  </VisualBasic.Settings>
  <Sequence DisplayName="{class_name}" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <Sequence.Variables>
      <Variable x:TypeArguments="x:String" Default="" Name="str_Status" />
    </Sequence.Variables>
    <ui:LogMessage DisplayName="Log Start {class_name}" Level="Info" Message="[&quot;Starting desktop automation: {class_name}&quot;]" sap2010:WorkflowViewState.IdRef="LogMessage_1" />
    <uix:NApplicationCard AttachMode="ByInstance" DisplayName="Use Desktop App - {app_exe}" InteractionMode="Simulate" OpenMode="IfNotOpen" ScopeGuid="d9a8f1b2-4c3e-4a1b-9f0e-123456789abc" Version="V2" sap2010:WorkflowViewState.IdRef="NApplicationCard_1">
      <uix:NApplicationCard.Body>
        <ActivityAction x:TypeArguments="x:Object">
          <ActivityAction.Argument>
            <DelegateInArgument x:TypeArguments="x:Object" Name="WSSessionData" />
          </ActivityAction.Argument>
          <Sequence DisplayName="Do Desktop Actions" sap2010:WorkflowViewState.IdRef="Sequence_2">
            <uix:NTypeInto ActivateBefore="True" ClickBeforeMode="Single" DisplayName="Type Into Main Input" EmptyFieldMode="SingleLine" InteractionMode="Simulate" Text="[in_InputText]" Version="V3" sap2010:WorkflowViewState.IdRef="NTypeInto_1">
              <uix:NTypeInto.Target>
                <uix:TargetAnchorable FullSelectorArgument="&lt;wnd app='{app_exe}' title='{window_title}' /&gt;&lt;uia role='edit' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />
              </uix:NTypeInto.Target>
            </uix:NTypeInto>
            <uix:NClick ActivateBefore="True" ClickType="Single" DisplayName="Click Submit Button" InteractionMode="Simulate" KeyModifiers="None" MouseButton="Left" Version="V3" sap2010:WorkflowViewState.IdRef="NClick_1">
              <uix:NClick.Target>
                <uix:TargetAnchorable FullSelectorArgument="&lt;wnd app='{app_exe}' title='{window_title}' /&gt;&lt;uia role='button' name='OK' /&gt;" SearchSteps="Selector" Version="V2" Visibility="Interactive" />
              </uix:NClick.Target>
            </uix:NClick>
          </Sequence>
        </ActivityAction>
      </uix:NApplicationCard.Body>
      <uix:NApplicationCard.TargetApp>
        <uix:TargetApp FilePath="{app_exe}" Selector="&lt;wnd app='{app_exe}' title='{window_title}' /&gt;" />
      </uix:NApplicationCard.TargetApp>
    </uix:NApplicationCard>
    <ui:LogMessage DisplayName="Log End {class_name}" Level="Info" Message="[&quot;Completed desktop automation: {class_name}&quot;]" sap2010:WorkflowViewState.IdRef="LogMessage_2" />
  </Sequence>
</Activity>
"""
    elif tpl in ("try-catch-process", "try-catch", "process"):
        xaml = f"""<Activity mc:Ignorable="sap sap2010" x:Class="{class_name}"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:s="clr-namespace:System;assembly=System.Private.CoreLib"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_TransactionItem" Type="InArgument(x:String)" />
  </x:Members>
  <VisualBasic.Settings>
    <x:Null />
  </VisualBasic.Settings>
  <Sequence DisplayName="{class_name}" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <TryCatch DisplayName="Try Catch - {class_name}" sap2010:WorkflowViewState.IdRef="TryCatch_1">
      <TryCatch.Try>
        <Sequence DisplayName="Try Processing" sap2010:WorkflowViewState.IdRef="Sequence_2">
          <ui:LogMessage DisplayName="Log Start" Level="Info" Message="[&quot;Processing item: &quot; &amp; in_TransactionItem]" sap2010:WorkflowViewState.IdRef="LogMessage_1" />
        </Sequence>
      </TryCatch.Try>
      <TryCatch.Catches>
        <Catch x:TypeArguments="ui:BusinessRuleException" sap2010:WorkflowViewState.IdRef="Catch_1">
          <ActivityAction x:TypeArguments="ui:BusinessRuleException">
            <ActivityAction.Argument>
              <DelegateInArgument x:TypeArguments="ui:BusinessRuleException" Name="bre" />
            </ActivityAction.Argument>
            <Sequence DisplayName="Handle BusinessRuleException" sap2010:WorkflowViewState.IdRef="Sequence_3">
              <ui:LogMessage DisplayName="Log BRE" Level="Warn" Message="[&quot;Business Rule Exception: &quot; &amp; bre.Message]" sap2010:WorkflowViewState.IdRef="LogMessage_2" />
              <Rethrow DisplayName="Rethrow BRE" sap2010:WorkflowViewState.IdRef="Rethrow_1" />
            </Sequence>
          </ActivityAction>
        </Catch>
        <Catch x:TypeArguments="s:Exception" sap2010:WorkflowViewState.IdRef="Catch_2">
          <ActivityAction x:TypeArguments="s:Exception">
            <ActivityAction.Argument>
              <DelegateInArgument x:TypeArguments="s:Exception" Name="exception" />
            </ActivityAction.Argument>
            <Sequence DisplayName="Handle System Exception" sap2010:WorkflowViewState.IdRef="Sequence_4">
              <ui:LogMessage DisplayName="Log System Exception" Level="Error" Message="[&quot;System Exception: &quot; &amp; exception.Message]" sap2010:WorkflowViewState.IdRef="LogMessage_3" />
              <Rethrow DisplayName="Rethrow System Exception" sap2010:WorkflowViewState.IdRef="Rethrow_2" />
            </Sequence>
          </ActivityAction>
        </Catch>
      </TryCatch.Catches>
    </TryCatch>
  </Sequence>
</Activity>
"""
    else:
        xaml = f"""<Activity mc:Ignorable="sap sap2010" x:Class="{class_name}"
 xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities"
 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
 xmlns:sap="http://schemas.microsoft.com/netfx/2009/xaml/activities/presentation"
 xmlns:sap2010="http://schemas.microsoft.com/netfx/2010/xaml/activities/presentation"
 xmlns:scg="clr-namespace:System.Collections.Generic;assembly=System.Private.CoreLib"
 xmlns:sco="clr-namespace:System.Collections.ObjectModel;assembly=System.Private.CoreLib"
 xmlns:ui="http://schemas.uipath.com/workflow/activities"
 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <x:Members>
    <x:Property Name="in_Config" Type="InArgument(scg:Dictionary(x:String, x:Object))" />
  </x:Members>
  <VisualBasic.Settings>
    <x:Null />
  </VisualBasic.Settings>
  <Sequence DisplayName="{class_name}" sap2010:WorkflowViewState.IdRef="Sequence_1">
    <Sequence.Variables>
      <Variable x:TypeArguments="x:String" Default="" Name="str_Result" />
    </Sequence.Variables>
    <ui:LogMessage DisplayName="Log Start {class_name}" Level="Info" Message="[&quot;Starting workflow: {class_name}&quot;]" sap2010:WorkflowViewState.IdRef="LogMessage_1" />
  </Sequence>
</Activity>
"""

    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(xaml, encoding="utf-8")
    SESSION.undo_stack.append({"path": full, "existed": existed, "old_content": old_content})
    val_report = tool_validate_xaml(path)
    return f"Successfully scaffolded '{rel_path(full)}' using template '{tpl}'.\n{val_report}"


def get_skill_content(skill_name: str) -> str:
    for base in (WORKSPACE, SCRIPT_DIR):
        p = base / "skills" / skill_name / "SKILL.md"
        if p.is_file():
            return p.read_text(encoding="utf-8", errors="replace")
    if skill_name == "uipath":
        return (
            "# UiPath Studio & Robot Built-in Skill\n"
            "- Always call `inspect_xaml` first on `.xaml` files to get Arguments, Variables, and Activity line numbers.\n"
            "- Check `project.json` for `expressionLanguage` (`VisualBasic` vs `CSharp`)."
        )
    return ""


def undo_last_edit():
    if not SESSION.undo_stack:
        print("  Nothing to undo.")
        return
    last = SESSION.undo_stack.pop()
    rpath = rel_path(last["path"])
    if last["existed"]:
        last["path"].write_text(last["old_content"], encoding="utf-8")
        print(f"  Reverted '{rpath}' to previous state.")
    else:
        if last["path"].exists():
            last["path"].unlink()
        print(f"  Removed newly created file '{rpath}'.")


def build_system_prompt() -> str:
    sys_prompt = """You are PCA (Portable Coding Assistant), an expert, token-efficient coding & UiPath XAML/Desktop Automation agent.
Be concise, accurate, and surgical. Minimize unnecessary prose and avoid repeating unchanged code.

When you need to inspect files, search code, inspect/scaffold/validate UiPath XAML, inspect live Windows desktop UI trees, edit files, or run commands, emit a fenced tool block using this exact JSON format:
```pca-tool
{"tool": "list_files", "sub_dir": ".", "max_depth": 2}
```
Available tools:
1. list_files: {"tool": "list_files", "sub_dir": ".", "max_depth": 2}
2. search_text: {"tool": "search_text", "pattern": "regex", "sub_dir": "."}
3. read_file: {"tool": "read_file", "path": "relative/path", "start_line": 1, "end_line": 120}
4. inspect_xaml: {"tool": "inspect_xaml", "path": "Main.xaml"} (Extracts UiPath .xaml Arguments, Variables, Activity line numbers & UI Selectors, skipping ViewState noise)
5. inspect_ui_tree: {"tool": "inspect_ui_tree", "window_title": "Notepad", "max_depth": 3} (Inspects live Windows desktop UI Automation control tree and synthesizes UiPath <wnd/><uia/> selectors)
6. scaffold_xaml: {"tool": "scaffold_xaml", "path": "Workflows/DesktopAction.xaml", "template": "desktop-uia", "app_exe": "notepad.exe", "window_title": "*Notepad*"} (Templates: "sequence", "desktop-uia", "try-catch-process")
7. validate_xaml: {"tool": "validate_xaml", "path": "Main.xaml"} (Validates XAML XML syntax, namespaces, ActivityAction scope wrappers, and UiPath Studio analyzer rules)
8. edit_file: {"tool": "edit_file", "path": "relative/path", "search": "exact existing lines", "replace": "new lines"}
   (To create a new file, set "search": "" and put full file content in "replace".)
9. run_command: {"tool": "run_command", "command": "shell command"}

Rules for Token Efficiency & UiPath XAML Quality:
- Never dump or rewrite an entire large file when a small SEARCH/REPLACE block in edit_file suffices.
- For UiPath `.xaml` files, follow the 3-Phase Loop: (1) Discovery (`inspect_xaml` / `inspect_ui_tree`), (2) Generation (`scaffold_xaml` / `edit_file`), (3) Validation (always call `validate_xaml` after modifying `.xaml`).
- Emit at most ONE ```pca-tool``` block per turn when waiting for tool output, then wait for the [Tool Result] before continuing."""
    for sk in SESSION.active_skills:
        sk_text = get_skill_content(sk)
        if sk_text:
            sys_prompt += f"\n\n--- Active Skill: {sk} ---\n{sk_text}"
    if SESSION.pinned_files:
        sys_prompt += "\n\n--- Pinned Workspace Files ---"
        for pf in SESSION.pinned_files:
            sys_prompt += "\n" + tool_read_file(pf, 1, 150)
    return sys_prompt


def compact_history(force: bool = False):
    if not force and len(SESSION.history) <= SESSION.keep_recent_turns:
        return
    compacted = 0
    for msg in SESSION.history[:-4]:
        content = msg.get("content", "")
        if len(content) > 600:
            msg["content"] = content[:400] + "\n... [Older turn compacted to save tokens]"
            compacted += 1
    if force:
        print(f"  Compacted {compacted} older message(s) in conversation history.")


def llm_chat_completion(messages: list) -> dict:
    if 0 < SESSION.max_session_cost_usd <= SESSION.total_cost_usd:
        raise RuntimeError(f"Session cost cap (${SESSION.max_session_cost_usd:.2f}) reached!")
    if not SESSION.base_url:
        raise RuntimeError(f"No BaseUrl configured for provider '{SESSION.provider}'.")
    if not SESSION.api_key and SESSION.provider != "ollama":
        cat = PROVIDER_CATALOG.get(SESSION.provider, {})
        env_hint = cat.get("env_key", "PCA_API_KEY")
        raise RuntimeError(f"Missing API Key for '{SESSION.provider}'. Set {env_hint} or PCA_API_KEY.")

    is_anthropic = (SESSION.provider == "claude") or SESSION.base_url.rstrip("/").endswith("/v1/messages")
    if is_anthropic:
        sys_blocks = []
        chat_msgs = []
        for m in messages:
            if m.get("role") == "system":
                sys_blocks.append({
                    "type": "text",
                    "text": str(m.get("content", "")),
                    "cache_control": {"type": "ephemeral"},
                })
            else:
                chat_msgs.append({"role": m.get("role", "user"), "content": str(m.get("content", ""))})
        payload = {
            "model": SESSION.model,
            "max_tokens": 4096,
            "messages": chat_msgs,
            "temperature": 0.1,
        }
        if sys_blocks:
            payload["system"] = sys_blocks
    else:
        payload = {
            "model": SESSION.model,
            "messages": messages,
            "temperature": 0.1,
        }

    raw_body = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Accept": "application/json",
        "User-Agent": f"pca-cli/{VERSION}",
    }
    if SESSION.api_key:
        if is_anthropic:
            headers["x-api-key"] = SESSION.api_key
            headers["anthropic-version"] = "2023-06-01"
        elif SESSION.provider == "azure-openai" and "openai.azure.com" in SESSION.base_url:
            headers["api-key"] = SESSION.api_key
        else:
            headers["Authorization"] = f"Bearer {SESSION.api_key}"

    req = urllib.request.Request(SESSION.base_url, data=raw_body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            resp_text = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"LLM API HTTP {e.code}: {err_body}")

    if not resp_text.strip().startswith("{"):
        if "models.github.ai" in SESSION.base_url or "models.inference.ai.azure.com" in SESSION.base_url:
            raise RuntimeError(
                f"GitHub permanently retired the GitHub Models API on July 30, 2026 (endpoint returned plain '{resp_text.strip()}'). "
                "Switch to a free active provider: --provider gemini (Google AI Studio Free Tier), --provider openrouter, or --provider groq."
            )
        raise RuntimeError(f"LLM API returned non-JSON response from {SESSION.base_url}: {resp_text[:200]}")

    parsed = json.loads(resp_text)
    reply_text = ""
    choices = parsed.get("choices") or []
    if choices:
        reply_text = choices[0].get("message", {}).get("content") or ""
    elif isinstance(parsed.get("content"), list):
        parts = [
            b.get("text", "")
            for b in parsed["content"]
            if isinstance(b, dict) and (b.get("type") == "text" or "text" in b)
        ]
        reply_text = "\n".join(p for p in parts if p)

    usage = parsed.get("usage") or {}
    if "input_tokens" in usage or "output_tokens" in usage:
        cached_tok = int(usage.get("cache_read_input_tokens") or 0)
        cache_write_tok = int(usage.get("cache_creation_input_tokens") or 0)
        in_tok = int(usage.get("input_tokens") or 0) + cached_tok + cache_write_tok
        out_tok = int(usage.get("output_tokens") or estimate_tokens(reply_text))
    else:
        in_tok = int(usage.get("prompt_tokens") or estimate_tokens(raw_body.decode("utf-8")))
        out_tok = int(usage.get("completion_tokens") or estimate_tokens(reply_text))
        cached_tok = int(
            (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
            or usage.get("prompt_cache_hit_tokens")
            or 0
        )

    cat = PROVIDER_CATALOG.get(SESSION.provider, {})
    in_rate = float(cat.get("in_cost", 0.15))
    cached_rate = float(cat.get("cached_cost", 0.075))
    out_rate = float(cat.get("out_cost", 0.60))
    if SESSION.provider == "claude" or "claude-" in SESSION.model:
        if "opus" in SESSION.model:
            in_rate, cached_rate, out_rate = 4.00, 0.20, 20.00
        elif "sonnet" in SESSION.model:
            in_rate, cached_rate, out_rate = 2.00, 0.10, 10.00
        elif "haiku" in SESSION.model:
            in_rate, cached_rate, out_rate = 0.10, 0.01, 0.50

    uncached_in = max(0, in_tok - cached_tok)
    turn_cost = ((uncached_in / 1e6) * in_rate) + ((cached_tok / 1e6) * cached_rate) + ((out_tok / 1e6) * out_rate)

    SESSION.prompt_tokens += in_tok
    SESSION.cached_tokens += cached_tok
    SESSION.completion_tokens += out_tok
    SESSION.total_cost_usd += turn_cost

    return {
        "content": reply_text,
        "in_tok": in_tok,
        "cached_tok": cached_tok,
        "out_tok": out_tok,
        "turn_cost": turn_cost,
    }


def parse_tool_block(text: str):
    if not text:
        return None
    m = re.search(r"```pca-tool\s*(\{.*?\})\s*```", text, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return None


def dispatch_tool(tool_call: dict) -> str:
    name = str(tool_call.get("tool", "")).lower()
    print(f"  -> [Tool: {name}]")
    if name == "list_files":
        return tool_list_files(tool_call.get("sub_dir", "."), int(tool_call.get("max_depth", 2)))
    if name == "search_text":
        return tool_search_text(tool_call.get("pattern", ""), tool_call.get("sub_dir", "."))
    if name == "read_file":
        return tool_read_file(
            tool_call.get("path", ""),
            int(tool_call.get("start_line", 1)),
            int(tool_call.get("end_line", 0)),
        )
    if name == "inspect_xaml":
        return tool_inspect_xaml(tool_call.get("path", ""))
    if name == "inspect_ui_tree":
        return tool_inspect_ui_tree(
            str(tool_call.get("window_title", "")),
            int(tool_call.get("max_depth", 3)),
        )
    if name == "validate_xaml":
        return tool_validate_xaml(tool_call.get("path", ""))
    if name == "scaffold_xaml":
        return tool_scaffold_xaml(
            tool_call.get("path", ""),
            tool_call.get("template", "sequence"),
            tool_call.get("app_exe", "notepad.exe"),
            tool_call.get("window_title", "*Notepad*"),
        )
    if name == "edit_file":
        return tool_edit_file(
            tool_call.get("path", ""),
            tool_call.get("search", ""),
            tool_call.get("replace", ""),
        )
    if name == "run_command":
        return tool_run_command(tool_call.get("command", ""))
    return f"Error: Unknown tool '{name}'."


def run_agent_turn(user_msg: str):
    compact_history()
    SESSION.history.append({"role": "user", "content": user_msg})
    for _ in range(SESSION.max_tool_steps):
        messages = [{"role": "system", "content": build_system_prompt()}] + SESSION.history
        res = llm_chat_completion(messages)
        reply = res["content"]
        SESSION.history.append({"role": "assistant", "content": reply})
        print(f"\n{reply}")
        print(
            f"  [Tokens: {res['in_tok']} in ({res['cached_tok']} cached) / {res['out_tok']} out "
            f"| Turn: ${res['turn_cost']:.5f} | Session: ${SESSION.total_cost_usd:.5f} / ${SESSION.max_session_cost_usd:.2f} cap]"
        )
        if SESSION.no_tools:
            break
        tool_obj = parse_tool_block(reply)
        if not tool_obj:
            break
        tool_out = dispatch_tool(tool_obj)
        SESSION.history.append({"role": "user", "content": f"[Tool Result for {tool_obj.get('tool')}]\n{tool_out}"})


def test_single_endpoint(name: str, url: str, model_name: str, env_key: str) -> dict:
    import time
    from urllib.parse import urlparse

    if not url:
        return {
            "provider": name, "host": "(not configured)", "status": "SKIPPED (No URL)",
            "allowed": False, "ready": False, "ms": 0, "proxy": "-"
        }
    parsed_uri = urlparse(url)
    host_name = parsed_uri.netloc or url
    proxies = urllib.request.getproxies()
    proxy_url = proxies.get(parsed_uri.scheme) or proxies.get("https") or proxies.get("http") or "Direct"
    if proxy_url != "Direct":
        proxy_url = urlparse(proxy_url).netloc or proxy_url

    key_val = os.environ.get(env_key, "") if env_key else ""
    if not key_val and SESSION.provider == name:
        key_val = SESSION.api_key
    has_key = bool(key_val)
    probe_key = key_val if has_key else "pca-firewall-probe"

    payload = json.dumps({
        "model": model_name or "gpt-4o-mini",
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 1
    }).encode("utf-8")

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": f"pca-cli/{VERSION}",
    }
    if url.rstrip("/").endswith("/v1/messages") or name in ("claude", "anthropic"):
        headers["x-api-key"] = probe_key
        headers["anthropic-version"] = "2023-06-01"
    else:
        headers["Authorization"] = f"Bearer {probe_key}"
    t0 = time.time()
    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            ms = int((time.time() - t0) * 1000)
            ct = resp.headers.get("Content-Type", "")
            body = resp.read().decode("utf-8", errors="ignore")
            if "text/html" in ct.lower() or re.search(r"(?i)<html|<!doctype|zscaler|netskope|fortiguard|access denied", body):
                return {
                    "provider": name, "host": host_name, "status": "BLOCKED (HTML Block Page)",
                    "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
                }
            if "json" not in ct.lower() and not body.strip().startswith("{"):
                st = "RETIRED (Shut down Jul 2026)" if "models.github.ai" in host_name else "BLOCKED (Non-JSON HTTP 200)"
                return {
                    "provider": name, "host": host_name, "status": st,
                    "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
                }
            return {
                "provider": name, "host": host_name, "status": "ALLOWED (Key Valid & Ready)",
                "allowed": True, "ready": True, "ms": ms, "proxy": proxy_url
            }
    except urllib.error.HTTPError as e:
        ms = int((time.time() - t0) * 1000)
        code = e.code
        ct = e.headers.get("Content-Type", "") if e.headers else ""
        err_body = ""
        try:
            err_body = e.read().decode("utf-8", errors="ignore")
        except Exception:
            pass
        if code == 407:
            return {
                "provider": name, "host": host_name, "status": "BLOCKED (407 Proxy Auth)",
                "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
            }
        if "text/html" in ct.lower() or re.search(r"(?i)<html|<!doctype|zscaler|netskope|fortiguard|palo alto|blocked|access denied", err_body):
            return {
                "provider": name, "host": host_name, "status": f"BLOCKED (Firewall HTTP {code})",
                "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
            }
        if "json" in ct.lower() or err_body.strip().startswith("{") or code in (400, 401, 429):
            status_str = f"HTTP {code} (Check API Key)" if has_key else f"ALLOWED (Set ${env_key} to use)"
            return {
                "provider": name, "host": host_name, "status": status_str,
                "allowed": True, "ready": False, "ms": ms, "proxy": proxy_url
            }
        return {
            "provider": name, "host": host_name, "status": f"BLOCKED (HTTP {code})",
            "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
        }
    except Exception as e:
        ms = int((time.time() - t0) * 1000)
        msg = str(e)
        if re.search(r"(?i)ssl|tls|certificate", msg):
            status_str = "BLOCKED (SSL/TLS Cert)"
        else:
            status_str = "BLOCKED (Network/DNS)"
        return {
            "provider": name, "host": host_name, "status": status_str,
            "allowed": False, "ready": False, "ms": ms, "proxy": proxy_url
        }


def run_endpoint_tests(target: str = ""):
    print("\n  Testing Enterprise Firewall & Proxy Connectivity to AI Endpoints...")
    print("  " + "-" * 100)
    print(f"  {'Provider':<14} | {'Endpoint Host':<34} | {'Firewall / Status':<30} | {'Time':>6} | Proxy")
    print("  " + "-" * 100)

    targets = []
    if target:
        t_low = target.lower()
        if t_low == "anthropic":
            t_low = "claude"
        if t_low in PROVIDER_CATALOG:
            p = PROVIDER_CATALOG[t_low]
            targets.append((t_low, p["base_url"], p["cheap_model"], p["env_key"]))
        elif target.startswith("http://") or target.startswith("https://"):
            targets.append(("custom-url", target, SESSION.model or "gpt-4o-mini", "PCA_API_KEY"))
        else:
            print(f"  Unknown provider or URL '{target}'.")
            return
    else:
        for k in ("gemini", "claude", "openrouter", "groq", "deepseek", "openai", "github-models"):
            p = PROVIDER_CATALOG[k]
            targets.append((k, p["base_url"], p["cheap_model"], p["env_key"]))
        if SESSION.base_url and SESSION.provider == "azure-openai":
            targets.append(("azure-openai", SESSION.base_url, SESSION.model, "AZURE_OPENAI_API_KEY"))

    allowed_list = []
    for name, url, model_name, env_key in targets:
        res = test_single_endpoint(name, url, model_name, env_key)
        if res["allowed"]:
            allowed_list.append(res["provider"])
        print(f"  {res['provider']:<14} | {res['host']:<34} | {res['status']:<30} | {res['ms']:>4}ms | {res['proxy']}")

    print("  " + "-" * 100)
    if allowed_list:
        print(f"  Recommended Allowed Providers on this machine: {', '.join(allowed_list)}\n")
    else:
        print("  All tested AI endpoints were blocked. Configure an internal corporate gateway via --base-url.\n")


def show_providers():
    print("\n  Available Free & Ultra-Cheap LLM Providers (Tiers: cheap | smart | opus):")
    print("  " + "-" * 102)
    for k, p in PROVIDER_CATALOG.items():
        mark = "*" if SESSION.provider == k else " "
        print(f"  [{mark}] {k:<14} | Cheap: {p['cheap_model']:<22} | Smart: {p['smart_model']:<22} | Opus: {p.get('opus_model', p['smart_model'])}")
        print(f"      Env: {p['env_key']:<21} | {p['notes']}")
    print()


def load_config_and_args(argv):
    cfg_path = WORKSPACE / ".pca.json"
    if not cfg_path.exists():
        cfg_path = Path.home() / ".pca.json"
    file_cfg = {}
    if cfg_path.exists():
        try:
            file_cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    SESSION.provider = os.environ.get("PCA_PROVIDER", file_cfg.get("provider", "")).lower()
    if SESSION.provider == "anthropic":
        SESSION.provider = "claude"
    if not SESSION.provider:
        for k, p in PROVIDER_CATALOG.items():
            if os.environ.get(p["env_key"]):
                SESSION.provider = k
                break
        else:
            SESSION.provider = "gemini"

    SESSION.tier = os.environ.get("PCA_TIER", file_cfg.get("tier", "cheap")).lower()
    for sk in file_cfg.get("skills", []):
        sk_lower = str(sk).lower()
        if sk_lower and sk_lower not in SESSION.active_skills:
            SESSION.active_skills.append(sk_lower)

    prompt_parts = []
    test_endpoints_flag = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--uip", "-Uip"):
            SESSION.auto_approve = True
            uip_cmd = "uip " + " ".join(shlex.quote(x) for x in argv[i + 1:])
            out_json = native_uip_command(uip_cmd)
            print(out_json)
            sys.exit(1 if '"Result": "Failure"' in out_json else 0)
        elif a in ("-h", "--help", "-Help"):
            print("Usage: pca [options] [prompt]")
            print("Options: --test-endpoints [provider|url], --uip <uip-args...>, --provider <name>, --model <name>, --tier <cheap|smart|opus>, --skill <name>, --api-key <key>, --base-url <url>, --auto-approve, --list-providers")
            show_providers()
            sys.exit(0)
        elif a in ("--list-providers", "-ListProviders"):
            show_providers()
            sys.exit(0)
        elif a in ("--test-endpoints", "-TestEndpoints"):
            test_endpoints_flag = True
        elif a in ("--provider", "-Provider") and i + 1 < len(argv):
            p_arg = argv[i + 1].lower()
            SESSION.provider = "claude" if p_arg == "anthropic" else p_arg
            i += 1
        elif a in ("--model", "-Model") and i + 1 < len(argv):
            SESSION.model = argv[i + 1]
            i += 1
        elif a in ("--tier", "-Tier") and i + 1 < len(argv):
            t_arg = argv[i + 1].lower()
            if t_arg == "haiku":
                t_arg = "cheap"
            elif t_arg == "sonnet":
                t_arg = "smart"
            SESSION.tier = t_arg
            i += 1
        elif a in ("--skill", "-Skill") and i + 1 < len(argv):
            sk_name = argv[i + 1].lower()
            if sk_name not in SESSION.active_skills:
                SESSION.active_skills.append(sk_name)
            i += 1
        elif a in ("--api-key", "-ApiKey") and i + 1 < len(argv):
            SESSION.api_key = argv[i + 1]
            i += 1
        elif a in ("--base-url", "-BaseUrl") and i + 1 < len(argv):
            SESSION.base_url = argv[i + 1]
            i += 1
        elif a in ("--add", "-AddFile") and i + 1 < len(argv):
            SESSION.pinned_files.append(argv[i + 1])
            i += 1
        elif a in ("--auto-approve", "-AutoApprove", "-y"):
            SESSION.auto_approve = True
        elif a in ("--no-tools", "-NoTools"):
            SESSION.no_tools = True
        else:
            prompt_parts.append(a)
        i += 1

    if test_endpoints_flag:
        target_arg = prompt_parts[0] if prompt_parts else ""
        run_endpoint_tests(target_arg)
        sys.exit(0)

    # Auto-detect UiPath project
    uipath_proj = WORKSPACE / "project.json"
    if uipath_proj.is_file():
        try:
            raw_proj = uipath_proj.read_text(encoding="utf-8", errors="ignore")
            if "UiPath" in raw_proj or "expressionLanguage" in raw_proj:
                for auto_sk in ("uipath", "uipath-rpa", "uipath-desktop"):
                    if auto_sk not in SESSION.active_skills:
                        SESSION.active_skills.append(auto_sk)
        except OSError:
            pass

    if SESSION.tier == "haiku":
        SESSION.tier = "cheap"
    elif SESSION.tier == "sonnet":
        SESSION.tier = "smart"

    cat = PROVIDER_CATALOG.get(SESSION.provider, {})
    if not SESSION.model:
        SESSION.model = os.environ.get("PCA_MODEL") or file_cfg.get("model") or get_model_for_tier(cat, SESSION.tier)
    if not SESSION.base_url:
        SESSION.base_url = os.environ.get("PCA_BASE_URL") or file_cfg.get("base_url") or cat.get("base_url", "")
    if not SESSION.api_key:
        SESSION.api_key = (
            os.environ.get("PCA_API_KEY")
            or (os.environ.get(cat.get("env_key", "")) if cat else "")
            or file_cfg.get("api_key", "")
        )
    return " ".join(prompt_parts).strip()


def main():
    prompt = load_config_and_args(sys.argv[1:])
    piped = ""
    if not sys.stdin.isatty():
        piped = sys.stdin.read().strip()

    if prompt or piped:
        combined = prompt
        if piped:
            if len(piped) > 12000:
                piped = piped[:12000] + "\n... [Piped input truncated]"
            combined = f"{prompt}\n\n--- Piped Input ---\n```text\n{piped}\n```".strip()
        run_agent_turn(combined)
        return

    skills_str = ", ".join(SESSION.active_skills) if SESSION.active_skills else "none"
    print(f"\n  PCA v{VERSION} - Portable Coding Assistant | Provider: {SESSION.provider} | Model: {SESSION.model} | Skills: {skills_str}")
    print("  Type '/help' for commands, '/test' to check firewall, '/uipath' for UiPath XAML & Desktop mode, or '/exit' to quit.\n")
    while True:
        try:
            line = input(f"pca ({SESSION.provider}:{SESSION.tier})> ").strip()
        except EOFError:
            break
        if not line:
            continue
        if line.startswith("/"):
            parts = line.split(maxsplit=1)
            cmd = parts[0].lower()
            arg = parts[1].strip() if len(parts) > 1 else ""
            if cmd in ("/exit", "/quit"):
                break
            elif cmd == "/help":
                print("  Commands: /test [prov|url], /uipath [plan|review|troubleshoot|migrate|full], /provider [name], /model [name], /tier [cheap|smart|opus], /skill [name|off], /add <file>, /drop, /files, /undo, /compact, /cost, /clear, /exit")
            elif cmd == "/test":
                run_endpoint_tests(arg)
            elif cmd == "/uipath":
                sub = arg.lower()
                if sub in ("off", "none", "clear"):
                    SESSION.active_skills.clear()
                    print("  Cleared all active skills.")
                elif sub == "plan":
                    for s in ("uipath", "uipath-rpa", "uipath-desktop", "uipath-planner"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated UiPath Planner mode: {', '.join(SESSION.active_skills)}")
                elif sub == "review":
                    for s in ("uipath", "uipath-rpa", "uipath-desktop", "uipath-review"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated UiPath Reviewer mode: {', '.join(SESSION.active_skills)}")
                elif sub == "troubleshoot":
                    for s in ("uipath", "uipath-rpa", "uipath-desktop", "uipath-troubleshoot"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated UiPath Troubleshoot mode: {', '.join(SESSION.active_skills)}")
                elif sub == "migrate":
                    for s in ("uipath", "uipath-rpa", "uipath-desktop", "uipath-activity-migrator"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated UiPath Activity Migrator mode: {', '.join(SESSION.active_skills)}")
                elif sub in ("full", "all"):
                    for s in ("uipath", "uipath-rpa", "uipath-desktop", "uipath-planner", "uipath-review", "uipath-troubleshoot", "uipath-activity-migrator"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated full UiPath XAML & Desktop Automation suite: {', '.join(SESSION.active_skills)}")
                else:
                    for s in ("uipath", "uipath-rpa", "uipath-desktop"):
                        if s not in SESSION.active_skills:
                            SESSION.active_skills.append(s)
                    print(f"  Activated UiPath XAML & Desktop Automation mode: {', '.join(SESSION.active_skills)}")
            elif cmd == "/skill":
                if not arg:
                    print(f"  Active skills: {', '.join(SESSION.active_skills) or 'none'}")
                elif arg.lower() in ("off", "none", "clear"):
                    SESSION.active_skills.clear()
                    print("  Cleared all active skills.")
                else:
                    sk_name = arg.lower()
                    if sk_name not in SESSION.active_skills:
                        SESSION.active_skills.append(sk_name)
                    print(f"  Activated skill '{sk_name}'.")
            elif cmd == "/provider":
                p_arg = "claude" if arg.lower() == "anthropic" else arg.lower()
                if not p_arg:
                    show_providers()
                elif p_arg in PROVIDER_CATALOG:
                    SESSION.provider = p_arg
                    cat = PROVIDER_CATALOG[SESSION.provider]
                    SESSION.base_url = cat["base_url"]
                    SESSION.model = get_model_for_tier(cat, SESSION.tier)
                    SESSION.api_key = os.environ.get(cat["env_key"], SESSION.api_key)
                    print(f"  Switched to {SESSION.provider} ({SESSION.model})")
            elif cmd == "/model":
                if arg:
                    SESSION.model = arg
                print(f"  Model: {SESSION.model}")
            elif cmd == "/tier" and arg.lower() in ("cheap", "smart", "opus", "haiku", "sonnet"):
                t_arg = arg.lower()
                SESSION.tier = "cheap" if t_arg == "haiku" else ("smart" if t_arg == "sonnet" else t_arg)
                cat = PROVIDER_CATALOG.get(SESSION.provider, {})
                SESSION.model = get_model_for_tier(cat, SESSION.tier)
                print(f"  Tier: {SESSION.tier} ({SESSION.model})")
            elif cmd == "/files":
                print(tool_list_files(".", 2))
            elif cmd == "/undo":
                undo_last_edit()
            elif cmd == "/compact":
                compact_history(force=True)
            elif cmd == "/cost":
                print(f"  Prompt: {SESSION.prompt_tokens} ({SESSION.cached_tokens} cached) | Out: {SESSION.completion_tokens} | Total: ${SESSION.total_cost_usd:.5f}")
            elif cmd == "/clear":
                SESSION.history.clear()
                print("  History cleared.")
            continue
        try:
            run_agent_turn(line)
        except Exception as e:
            print(f"  [Error] {e}")


if __name__ == "__main__":
    main()
PYEOF
fi

# Pure Bash + curl fallback when no Python or Node is installed on a Linux VM
BASE_URL="${PCA_BASE_URL:-https://models.inference.ai.azure.com/chat/completions}"
MODEL="${PCA_MODEL:-gpt-4o-mini}"
API_KEY="${PCA_API_KEY:-${GITHUB_TOKEN:-${GEMINI_API_KEY:-${OPENROUTER_API_KEY:-${DEEPSEEK_API_KEY:-}}}}}"

if [ -z "$API_KEY" ]; then
    echo "Error: Set GITHUB_TOKEN or PCA_API_KEY environment variable." >&2
    exit 1
fi

PROMPT="$*"
if [ -z "$PROMPT" ]; then
    echo "Usage: ./pca.sh \"Your coding question\"" >&2
    exit 1
fi

ESCAPED_PROMPT=$(printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
PAYLOAD="{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"system\",\"content\":\"You are a concise coding assistant.\"},{\"role\":\"user\",\"content\":\"$ESCAPED_PROMPT\"}],\"temperature\":0.1}"

curl -sS -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$PAYLOAD"
echo ""
