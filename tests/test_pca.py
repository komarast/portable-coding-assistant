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

        if "Tool Result for read_file" in last_user:
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
        self.assertIn("openrouter", proc.stdout)
        self.assertIn("deepseek", proc.stdout)

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
        for provider in ("github-models", "gemini", "openrouter", "groq", "deepseek", "openai", "azure-openai", "ollama"):
            self.assertIn(f'"{provider}"', content)
        for fn in (
            "Invoke-ToolListFiles",
            "Invoke-ToolSearchText",
            "Invoke-ToolReadFile",
            "Invoke-ToolInspectXaml",
            "Get-SkillContent",
            "Invoke-ToolEditFile",
            "Invoke-ToolRunCommand",
            "Invoke-UndoLastEdit",
            "Invoke-CompileNativeExe",
            "Test-SingleEndpoint",
            "Invoke-TestEndpoints",
            "GetSystemWebProxy",
        ):
            self.assertIn(fn, content)
        # Ensure pca.cmd exists and uses ExecutionPolicy Bypass
        cmd_content = PCA_CMD.read_text(encoding="utf-8")
        self.assertIn("-ExecutionPolicy Bypass", cmd_content)
        # Ensure UiPath SKILL.md exists
        uipath_skill = REPO_ROOT / "skills" / "uipath" / "SKILL.md"
        self.assertTrue(uipath_skill.is_file())
        self.assertIn("inspect_xaml", uipath_skill.read_text(encoding="utf-8"))

        # Verify PowerShell single/double quotes and here-strings are properly closed (no backtick-escaped closing quotes)
        in_squote = in_dquote = in_hered = in_heres = in_comment = False
        i = 0
        n = len(content)
        while i < n:
            ch = content[i]
            if ch == "\n":
                in_comment = False
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
                if ch == "#":
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
                if ch == '"':
                    in_dquote = False
            i += 1
        self.assertFalse(
            in_squote or in_dquote or in_heres or in_hered,
            "Unclosed string or here-string detected in pca.ps1",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

