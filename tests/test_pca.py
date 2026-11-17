#!/usr/bin/env python3
"""End-to-end verification suite for Portable Coding Assistant (pca.ps1 & pca.sh)."""
import http.server
import json
import os
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PCA_SH = REPO_ROOT / "pca.sh"
PCA_PS1 = REPO_ROOT / "pca.ps1"
PCA_CMD = REPO_ROOT / "pca.cmd"


class MockLLMHandler(http.server.BaseHTTPRequestHandler):
    """Simulates an OpenAI-compatible / GitHub Models chat completion endpoint."""
    step = 0

    def log_message(self, format, *args):
        pass

    def do_POST(self):
        if self.path == "/blocked-by-zscaler":
            html = b"<html><body>Access Denied by Zscaler Corporate Proxy</body></html>"
            self.send_response(403)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            return

        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length).decode("utf-8"))
        messages = body.get("messages", [])
        last_user = messages[-1]["content"] if messages else ""

        if self.path == "/v1/messages":
            # Verify Anthropic headers & payload structure
            api_key_hdr = self.headers.get("x-api-key", "")
            anth_ver = self.headers.get("anthropic-version", "")
            model_used = body.get("model", "")
            has_cache = bool(body.get("system") and body["system"][0].get("cache_control"))
            reply = f"Claude response from {model_used} (ver={anth_ver}, cache={has_cache}, key={bool(api_key_hdr)})"
            resp = {
                "id": "msg_mock_claude",
                "type": "message",
                "role": "assistant",
                "model": model_used,
                "content": [{"type": "text", "text": reply}],
                "usage": {
                    "input_tokens": 50,
                    "cache_read_input_tokens": 150,
                    "output_tokens": 30,
                },
            }
            raw = json.dumps(resp).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return

        if "Tool Result for scaffold_xaml" in last_user:
            reply = (
                "Now inspecting the scaffolded workflow:\n"
                "```pca-tool\n"
                '{"tool": "inspect_xaml", "path": "Workflows/DesktopNotepad.xaml"}\n'
                "```"
            )
        elif "Tool Result for inspect_xaml" in last_user:
            reply = (
                "Now validating Broken.xaml:\n"
                "```pca-tool\n"
                '{"tool": "validate_xaml", "path": "Workflows/Broken.xaml"}\n'
                "```"
            )
        elif "Tool Result for validate_xaml" in last_user:
            reply = f"Validation finished: {last_user.splitlines()[2] if len(last_user.splitlines()) > 2 else 'done'}"
        elif "Scaffold DesktopNotepad.xaml" in last_user:
            reply = (
                "Scaffolding desktop UIA workflow:\n"
                "```pca-tool\n"
                '{"tool": "scaffold_xaml", "path": "Workflows/DesktopNotepad.xaml", "template": "desktop-uia", "app_exe": "notepad.exe", "window_title": "*Notepad*"}\n'
                "```"
            )
        elif "Run native uipath-rpa offline uip workflow" in last_user:
            reply = (
                "Reading bundled UIA guide without uip installed:\n"
                "```pca-tool\n"
                '{"tool": "read_file", "path": "{PROJECT_DIR}/.local/docs/packages/UiPath.UIAutomation.Activities/ui-automation-guide.md", "start_line": 1, "end_line": 40}\n'
                "```"
            )
        elif "ui-automation-guide.md" in last_user and "Tool Result for read_file" in last_user:
            reply = (
                "Now running chained uip rpa commands via offline emulator:\n"
                "```pca-tool\n"
                '{"tool": "run_command", "command": "uip rpa init --name OfflineBot --location . --target-framework Windows --expression-language VisualBasic --output json && uip rpa activities find --query NClick --output json && uip rpa validate --file-path OfflineBot/Main.xaml --project-dir OfflineBot --output json && uip rpa build OfflineBot --output json"}\n'
                "```"
            )
        elif "Tool Result for run_command" in last_user and '"Code": "Build"' in last_user:
            reply = "Native UiPath skill workflow completed with 0 errors using built-in offline uip emulator!"
        elif "Tool Result for read_file" in last_user:
            reply = (
                "Now patching hello.txt:\n"
                "```pca-tool\n"
                '{"tool": "edit_file", "path": "hello.txt", "search": "timeout = 10", "replace": "timeout = 30"}\n'
                "```"
            )
        elif "Tool Result for edit_file" in last_user:
            reply = "Done! Updated `timeout` from 10 to 30 in `hello.txt`."
        else:
            reply = (
                "Let me inspect `hello.txt` first:\n"
                "```pca-tool\n"
                '{"tool": "read_file", "path": "hello.txt", "start_line": 1, "end_line": 20}\n'
                "```"
            )

        resp = {
            "id": "chatcmpl-mock",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": reply}}],
            "usage": {
                "prompt_tokens": 200,
                "completion_tokens": 45,
                "prompt_tokens_details": {"cached_tokens": 150},
            },
        }
        raw = json.dumps(resp).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class TestPortableCodingAssistant(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.chmod(PCA_SH, 0o755)
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), MockLLMHandler)
        cls.port = cls.server.server_port
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def test_list_providers_cli(self):
        proc = subprocess.run(
            [str(PCA_SH), "--list-providers"],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("github-models", proc.stdout)
        self.assertIn("gemini", proc.stdout)
        self.assertIn("claude", proc.stdout)
        self.assertIn("claude-haiku-5-5", proc.stdout)
        self.assertIn("claude-sonnet-5-5", proc.stdout)
        self.assertIn("claude-opus-5-5", proc.stdout)
        self.assertIn("openrouter", proc.stdout)
        self.assertIn("deepseek", proc.stdout)

    def test_claude_messages_api_and_tiers(self):
        url = f"http://127.0.0.1:{self.port}/v1/messages"
        for tier_arg, expected_model in (
            ("cheap", "claude-haiku-5-5"),
            ("smart", "claude-sonnet-5-5"),
            ("opus", "claude-opus-5-5"),
        ):
            proc = subprocess.run(
                [
                    str(PCA_SH),
                    "--provider", "claude",
                    "--tier", tier_arg,
                    "--base-url", url,
                    "--api-key", "sk-ant-test",
                    "--no-tools",
                    "Hello Claude",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn(f"Claude response from {expected_model}", proc.stdout)
            self.assertIn("ver=2023-06-01, cache=True, key=True", proc.stdout)
            self.assertIn("150 cached", proc.stdout)

    def test_endpoint_firewall_probe_allowed_and_blocked(self):
        allowed_url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
        proc_ok = subprocess.run(
            [str(PCA_SH), "--test-endpoints", allowed_url],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("ALLOWED", proc_ok.stdout)

        blocked_url = f"http://127.0.0.1:{self.port}/blocked-by-zscaler"
        proc_blk = subprocess.run(
            [str(PCA_SH), "--test-endpoints", blocked_url],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("BLOCKED (Firewall HTTP 403)", proc_blk.stdout)

    def test_agentic_read_and_search_replace_patch_loop(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            target_file = tmp_path / "hello.txt"
            target_file.write_text("host = localhost\ntimeout = 10\nretries = 3\n", encoding="utf-8")

            url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
            proc = subprocess.run(
                [
                    str(PCA_SH),
                    "--provider", "deepseek",
                    "--base-url", url,
                    "--api-key", "test-key",
                    "--auto-approve",
                    "Increase timeout to 30 in hello.txt",
                ],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("[Tool: read_file]", proc.stdout)
            self.assertIn("[Tool: edit_file]", proc.stdout)
            self.assertIn("Updated `timeout` from 10 to 30", proc.stdout)
            self.assertIn("cached", proc.stdout)
            updated = target_file.read_text(encoding="utf-8")
            self.assertEqual(updated, "host = localhost\ntimeout = 30\nretries = 3\n")

    def test_uipath_xaml_scaffold_inspect_and_validate(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            wf_dir = tmp_path / "Workflows"
            wf_dir.mkdir(parents=True, exist_ok=True)
            # Create a deliberately broken XAML missing ActivityAction inside NApplicationCard.Body
            broken_xaml = wf_dir / "Broken.xaml"
            broken_xaml.write_text(
                '<Activity xmlns="http://schemas.microsoft.com/netfx/2009/xaml/activities" '
                'xmlns:uix="http://schemas.uipath.com/workflow/activities/uix">\n'
                '  <uix:NApplicationCard DisplayName="Use App">\n'
                '    <uix:NApplicationCard.Body>\n'
                '      <Sequence DisplayName="Missing ActivityAction Wrapper" />\n'
                '    </uix:NApplicationCard.Body>\n'
                '  </uix:NApplicationCard>\n'
                '</Activity>\n',
                encoding="utf-8",
            )

            url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
            proc = subprocess.run(
                [
                    str(PCA_SH),
                    "--provider", "gemini",
                    "--base-url", url,
                    "--api-key", "test-key",
                    "--skill", "uipath",
                    "--skill", "uipath-desktop",
                    "--auto-approve",
                    "Scaffold DesktopNotepad.xaml",
                ],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("[Tool: scaffold_xaml]", proc.stdout)
            self.assertIn("[Tool: inspect_xaml]", proc.stdout)
            self.assertIn("[Tool: validate_xaml]", proc.stdout)
            self.assertIn("STATUS: FAILED", proc.stdout)

            scaffolded = wf_dir / "DesktopNotepad.xaml"
            self.assertTrue(scaffolded.is_file())
            xaml_content = scaffolded.read_text(encoding="utf-8")
            self.assertIn("<uix:NApplicationCard", xaml_content)
            self.assertIn("<ActivityAction x:TypeArguments=\"x:Object\">", xaml_content)
            self.assertIn("FullSelectorArgument=\"&lt;wnd app='notepad.exe'", xaml_content)

    def test_native_uipath_skills_and_offline_uip_cli_emulator(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            env = os.environ.copy()
            env["PCA_FORCE_BUILTIN_UIP"] = "1"

            # 1. Test direct --uip CLI mode (get-default-xaml)
            proc_uip = subprocess.run(
                [
                    str(PCA_SH),
                    "--uip", "rpa", "activities", "get-default-xaml",
                    "--activity-class-name", "NClick", "--output", "json",
                ],
                cwd=tmpdir,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            uip_data = json.loads(proc_uip.stdout.strip())
            self.assertEqual(uip_data["Result"], "Success")
            self.assertEqual(uip_data["Code"], "GetDefaultXaml")
            self.assertIn("<uix:NClick", uip_data["Data"]["defaultXaml"])

            # 2. Test agentic loop with native uipath-rpa skill reading .local/docs/packages/... and running chained uip commands
            url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
            proc_agent = subprocess.run(
                [
                    str(PCA_SH),
                    "--provider", "gemini",
                    "--base-url", url,
                    "--api-key", "test-key",
                    "--skill", "uipath-rpa",
                    "--auto-approve",
                    "Run native uipath-rpa offline uip workflow",
                ],
                cwd=tmpdir,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn("[Tool: read_file]", proc_agent.stdout)
            self.assertIn("[Tool: run_command]", proc_agent.stdout)
            self.assertIn("Native UiPath skill workflow completed with 0 errors", proc_agent.stdout)
            self.assertTrue((tmp_path / "OfflineBot" / "project.json").is_file())
            self.assertTrue((tmp_path / "OfflineBot" / "Main.xaml").is_file())
            self.assertTrue((tmp_path / "OfflineBot" / ".local" / "content" / "entry-points.json").is_file())

    def test_pure_bash_no_python_fallback(self):
        url = f"http://127.0.0.1:{self.port}/v1/chat/completions"
        env = os.environ.copy()
        env["PCA_FORCE_BASH"] = "1"
        env["PCA_BASE_URL"] = url
        env["PCA_API_KEY"] = "test-key"
        proc = subprocess.run(
            [str(PCA_SH), "Quick question"],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn("chatcmpl-mock", proc.stdout)

    def test_powershell_script_integrity_and_ps51_compatibility(self):
        content = PCA_PS1.read_text(encoding="utf-8")
        # Ensure all core tools & providers are defined in pca.ps1
        for provider in ("github-models", "gemini", "claude", "openrouter", "groq", "deepseek", "openai", "azure-openai", "ollama"):
            self.assertIn(f'"{provider}"', content)
        for fn in (
            "Invoke-ToolListFiles",
            "Invoke-ToolSearchText",
            "Invoke-ToolReadFile",
            "Invoke-ToolInspectXaml",
            "Invoke-ToolInspectUiTree",
            "Invoke-ToolValidateXaml",
            "Invoke-ToolScaffoldXaml",
            "Invoke-NativeUipCommand",
            "Save-EncryptedApiKey",
            "Get-EncryptedApiKey",
            "Get-SkillContent",
            "Get-ModelForTier",
            "Invoke-ToolEditFile",
            "Invoke-ToolRunCommand",
            "Invoke-UndoLastEdit",
            "Invoke-CompileNativeExe",
            "Test-SingleEndpoint",
            "Invoke-TestEndpoints",
            "GetSystemWebProxy",
        ):
            self.assertIn(fn, content)
        # Ensure pca.cmd and uip.cmd exist and use ExecutionPolicy Bypass
        cmd_content = PCA_CMD.read_text(encoding="utf-8")
        self.assertIn("-ExecutionPolicy Bypass", cmd_content)
        uip_cmd_file = REPO_ROOT / "uip.cmd"
        self.assertTrue(uip_cmd_file.is_file())
        self.assertIn("-Uip", uip_cmd_file.read_text(encoding="utf-8"))
        # Ensure all native & PCA UiPath SKILL.md files exist and are populated
        for sk_dir, expected_kw in (
            ("uipath", "NApplicationCard"),
            ("uipath-rpa", "uip rpa"),
            ("uipath-desktop", "inspect_ui_tree"),
            ("uipath-planner", "REFramework"),
            ("uipath-review", "validate_xaml"),
            ("uipath-troubleshoot", "Troubleshooting"),
            ("uipath-activity-migrator", "Migration"),
        ):
            sk_file = REPO_ROOT / "skills" / sk_dir / "SKILL.md"
            self.assertTrue(sk_file.is_file(), f"Missing skill file: {sk_file}")
            self.assertIn(expected_kw, sk_file.read_text(encoding="utf-8"))

        # Verify PowerShell single/double quotes, here-strings, braces/parens, and $() subexpressions are 100% PS 5.1 valid
        in_squote = in_dquote = in_hered = in_heres = in_comment = in_block_comment = False
        braces = parens = brackets = 0
        line_num = 1
        i = 0
        n = len(content)
        while i < n:
            ch = content[i]
            if ch == "\n":
                line_num += 1
                in_comment = False
                i += 1
                continue
            if in_block_comment:
                if content[i : i + 2] == "#>":
                    in_block_comment = False
                    i += 2
                    continue
                i += 1
                continue
            if in_comment:
                i += 1
                continue
            if in_heres:
                if content[i - 1 : i + 2] == "\n'@":
                    in_heres = False
                    i += 2
                    continue
                i += 1
                continue
            if in_hered:
                if content[i - 1 : i + 2] == '\n"@':
                    in_hered = False
                    i += 2
                    continue
                i += 1
                continue
            if not in_squote and not in_dquote:
                if content[i : i + 2] == "<#":
                    in_block_comment = True
                    i += 2
                    continue
                elif ch == "#":
                    in_comment = True
                elif content[i : i + 3] == "@'\n":
                    in_heres = True
                    i += 2
                elif content[i : i + 3] == '@"\n':
                    in_hered = True
                    i += 2
                elif ch == "'":
                    in_squote = True
                elif ch == '"':
                    in_dquote = True
                elif ch == "{":
                    braces += 1
                elif ch == "}":
                    braces -= 1
                    self.assertGreaterEqual(braces, 0, f"Unmatched closing brace at line {line_num}")
                elif ch == "(":
                    parens += 1
                elif ch == ")":
                    parens -= 1
                    self.assertGreaterEqual(parens, 0, f"Unmatched closing paren at line {line_num}")
                elif ch == "[":
                    brackets += 1
                elif ch == "]":
                    brackets -= 1
            elif in_squote:
                if ch == "'":
                    if i + 1 < n and content[i + 1] == "'":
                        i += 2
                        continue
                    in_squote = False
            elif in_dquote:
                if ch == "`":
                    i += 2
                    continue
                if content[i : i + 2] == "$(":
                    sub_end = content.find(")", i + 2)
                    sub_str = content[i + 2 : sub_end] if sub_end != -1 else ""
                    self.assertNotIn(
                        '"',
                        sub_str,
                        f"Nested double quote inside $() subexpression at line {line_num}: {sub_str}",
                    )
                    self.assertNotIn(
                        "'",
                        sub_str,
                        f"Nested single quote inside $() subexpression at line {line_num}: {sub_str}",
                    )
                if ch == '"':
                    in_dquote = False
            i += 1
        self.assertFalse(
            in_squote or in_dquote or in_heres or in_hered,
            "Unclosed string or here-string detected in pca.ps1",
        )
        self.assertEqual(braces, 0, f"Unbalanced curly braces in pca.ps1: {braces}")
        self.assertEqual(parens, 0, f"Unbalanced parentheses in pca.ps1: {parens}")
        self.assertEqual(brackets, 0, f"Unbalanced square brackets in pca.ps1: {brackets}")


if __name__ == "__main__":
    unittest.main(verbosity=2)

