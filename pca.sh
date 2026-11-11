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
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

VERSION = "1.1.0"
WORKSPACE = Path.cwd().resolve()
SCRIPT_DIR = Path(os.environ.get("PCA_SCRIPT_DIR", str(WORKSPACE))).resolve()
IGNORED_DIRS = {
    ".git", ".hg", ".svn", "node_modules", "bin", "obj", "dist",
    "build", "__pycache__", ".venv", "venv", ".vs", ".idea", "packages"
}

PROVIDER_CATALOG = {
    "github-models": {
        "name": "GitHub Models (Azure Hosted - FREE)",
        "base_url": "https://models.inference.ai.azure.com/chat/completions",
        "env_key": "GITHUB_TOKEN",
        "cheap_model": "gpt-4o-mini",
        "smart_model": "gpt-4o",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "FREE ($0) with any GitHub PAT. Hosted on *.azure.com (whitelisted on most Azure AVDs)."
    },
    "gemini": {
        "name": "Google Gemini AI Studio (Gemini 3.8 Flash / 3.5 Flash-Lite)",
        "base_url": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        "env_key": "GEMINI_API_KEY",
        "cheap_model": "gemini-3.5-flash-lite",
        "smart_model": "gemini-3.8-flash",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "Supports gemini-3.8-flash & gemini-3.5-flash-lite via Google AI Studio (Free Tier or $0.75/1M intro rate)."
    },
    "openrouter": {
        "name": "OpenRouter (Free Coding Models)",
        "base_url": "https://openrouter.ai/api/v1/chat/completions",
        "env_key": "OPENROUTER_API_KEY",
        "cheap_model": "qwen/qwen3-coder:free",
        "smart_model": "deepseek/deepseek-chat-v3-0324:free",
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "FREE ($0) using ':free' model variants on OpenRouter."
    },
    "groq": {
        "name": "Groq Cloud (Free Developer Tier)",
        "base_url": "https://api.groq.com/openai/v1/chat/completions",
        "env_key": "GROQ_API_KEY",
        "cheap_model": "llama-3.1-8b-instant",
        "smart_model": "llama-3.3-70b-versatile",
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
        "in_cost": 0.27,
        "cached_cost": 0.07,
        "out_cost": 1.10,
        "notes": "Automatic disk prompt caching ($0.07/1M cached input tokens)."
    },
    "openai": {
        "name": "OpenAI (Nano / Mini)",
        "base_url": "https://api.openai.com/v1/chat/completions",
        "env_key": "OPENAI_API_KEY",
        "cheap_model": "gpt-4.1-nano",
        "smart_model": "gpt-4.1-mini",
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
        "in_cost": 0.00,
        "cached_cost": 0.00,
        "out_cost": 0.00,
        "notes": "100% offline/local inference."
    },
}


class Session:
    def __init__(self):
        self.provider = "github-models"
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


def tool_run_command(command: str) -> str:
    if not command:
        return "Error: command is required."
    if not confirm_action("Execute Shell Command", f"  $ {command}"):
        return f"User declined executing command: {command}"
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
    args_list, vars_list, acts_list = [], [], []
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
        m_act = re.match(r'^\s*<([A-Za-z0-9_:]+)\s+[^>]*DisplayName="([^"]+)"', ln)
        if m_act:
            tag, disp = m_act.group(1), m_act.group(2)
            extra = ""
            m_wf = re.search(r'WorkflowFileName="([^"]+)"', ln)
            if m_wf:
                extra = f" -> Calls: {m_wf.group(1)}"
            elif 'Selector="' in ln:
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
    out.append("Tip: Use read_file with start_line/end_line around the specific Line number above before calling edit_file.")
    return "\n".join(out)


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
    sys_prompt = """You are PCA (Portable Coding Assistant), an expert, token-efficient coding agent.
Be concise, accurate, and surgical. Minimize unnecessary prose and avoid repeating unchanged code.

When you need to inspect files, search code, edit files, or run commands, emit a fenced tool block using this exact JSON format:
```pca-tool
{"tool": "list_files", "sub_dir": ".", "max_depth": 2}
```
Available tools:
1. list_files: {"tool": "list_files", "sub_dir": ".", "max_depth": 2}
2. search_text: {"tool": "search_text", "pattern": "regex", "sub_dir": "."}
3. read_file: {"tool": "read_file", "path": "relative/path", "start_line": 1, "end_line": 120}
4. inspect_xaml: {"tool": "inspect_xaml", "path": "Main.xaml"} (Extracts UiPath .xaml Arguments, Variables & Activity line numbers, skipping ViewState noise)
5. edit_file: {"tool": "edit_file", "path": "relative/path", "search": "exact existing lines", "replace": "new lines"}
   (To create a new file, set "search": "" and put full file content in "replace".)
6. run_command: {"tool": "run_command", "command": "shell command"}

Rules for Token Efficiency:
- Never dump or rewrite an entire large file when a small SEARCH/REPLACE block in edit_file suffices.
- For UiPath `.xaml` files, call `inspect_xaml` first to locate exact activity line numbers, then `read_file` only that small line range.
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
        if SESSION.provider == "azure-openai" and "openai.azure.com" in SESSION.base_url:
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

    parsed = json.loads(resp_text)
    reply_text = ""
    choices = parsed.get("choices") or []
    if choices:
        reply_text = choices[0].get("message", {}).get("content") or ""

    usage = parsed.get("usage") or {}
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
        "Authorization": f"Bearer {probe_key}"
    }
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
        if t_low in PROVIDER_CATALOG:
            p = PROVIDER_CATALOG[t_low]
            targets.append((t_low, p["base_url"], p["cheap_model"], p["env_key"]))
        elif target.startswith("http://") or target.startswith("https://"):
            targets.append(("custom-url", target, SESSION.model or "gpt-4o-mini", "PCA_API_KEY"))
        else:
            print(f"  Unknown provider or URL '{target}'.")
            return
    else:
        for k in ("github-models", "gemini", "openrouter", "groq", "deepseek", "openai"):
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
    print("\n  Available Free & Ultra-Cheap LLM Providers:")
    print("  " + "-" * 82)
    for k, p in PROVIDER_CATALOG.items():
        mark = "*" if SESSION.provider == k else " "
        print(f"  [{mark}] {k:<14} | Cheap: {p['cheap_model']:<26} | Env: {p['env_key']}")
        print(f"      {p['notes']}")
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
    if not SESSION.provider:
        for k, p in PROVIDER_CATALOG.items():
            if os.environ.get(p["env_key"]):
                SESSION.provider = k
                break
        else:
            SESSION.provider = "github-models"

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
        if a in ("-h", "--help", "-Help"):
            print("Usage: pca [options] [prompt]")
            print("Options: --test-endpoints [provider|url], --provider <name>, --model <name>, --tier <cheap|smart>, --skill <name>, --api-key <key>, --base-url <url>, --auto-approve, --list-providers")
            show_providers()
            sys.exit(0)
        elif a in ("--list-providers", "-ListProviders"):
            show_providers()
            sys.exit(0)
        elif a in ("--test-endpoints", "-TestEndpoints"):
            test_endpoints_flag = True
        elif a in ("--provider", "-Provider") and i + 1 < len(argv):
            SESSION.provider = argv[i + 1].lower()
            i += 1
        elif a in ("--model", "-Model") and i + 1 < len(argv):
            SESSION.model = argv[i + 1]
            i += 1
        elif a in ("--tier", "-Tier") and i + 1 < len(argv):
            SESSION.tier = argv[i + 1].lower()
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
    if uipath_proj.is_file() and "uipath" not in SESSION.active_skills:
        try:
            raw_proj = uipath_proj.read_text(encoding="utf-8", errors="ignore")
            if "UiPath" in raw_proj or "expressionLanguage" in raw_proj:
                SESSION.active_skills.append("uipath")
        except OSError:
            pass

    cat = PROVIDER_CATALOG.get(SESSION.provider, {})
    if not SESSION.model:
        SESSION.model = os.environ.get("PCA_MODEL") or file_cfg.get("model") or (
            cat.get("smart_model") if SESSION.tier == "smart" else cat.get("cheap_model", "gpt-4o-mini")
        )
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
    print("  Type '/help' for commands, '/test' to check firewall, '/skill uipath' for UiPath mode, or '/exit' to quit.\n")
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
                print("  Commands: /test [prov|url], /provider [name], /model [name], /tier [cheap|smart], /skill [name|off], /add <file>, /drop, /files, /undo, /compact, /cost, /clear, /exit")
            elif cmd == "/test":
                run_endpoint_tests(arg)
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
                if not arg:
                    show_providers()
                elif arg.lower() in PROVIDER_CATALOG:
                    SESSION.provider = arg.lower()
                    cat = PROVIDER_CATALOG[SESSION.provider]
                    SESSION.base_url = cat["base_url"]
                    SESSION.model = cat["smart_model"] if SESSION.tier == "smart" else cat["cheap_model"]
                    SESSION.api_key = os.environ.get(cat["env_key"], SESSION.api_key)
                    print(f"  Switched to {SESSION.provider} ({SESSION.model})")
            elif cmd == "/model":
                if arg:
                    SESSION.model = arg
                print(f"  Model: {SESSION.model}")
            elif cmd == "/tier" and arg in ("cheap", "smart"):
                SESSION.tier = arg
                cat = PROVIDER_CATALOG.get(SESSION.provider, {})
                SESSION.model = cat.get("smart_model" if arg == "smart" else "cheap_model", SESSION.model)
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
