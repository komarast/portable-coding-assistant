<#
.SYNOPSIS
    Portable Coding Assistant (pca) - Zero-Dependency LLM Coding Agent for Windows AVD & Corporate VMs.
.DESCRIPTION
    Runs natively on stock Windows PowerShell 5.1+ (.NET Framework 4.8+) with ZERO external libraries,
    ZERO installed runtimes (no Python, no Node.js), and automatic Windows corporate proxy / Certificate Store integration.
    Supports Free ($0) and Ultra-Cheap LLM tiers:
      - github-models (models.inference.ai.azure.com - FREE with GitHub PAT, hosted on *.azure.com)
      - gemini        (Google AI Studio Free Tier - gemini-2.5-flash-lite / gemini-2.5-flash)
      - openrouter    (Free coding models: qwen/qwen3-coder:free, deepseek/deepseek-chat-v3-0324:free)
      - groq          (Free developer tier: llama-3.3-70b-versatile)
      - deepseek      (Ultra-cheap with automatic disk prompt caching: $0.07/1M cached input)
      - openai        (gpt-4.1-nano / gpt-4.1-mini)
      - azure-openai  (Corporate internal Azure OpenAI endpoint)
      - ollama        (Local air-gapped models)
.EXAMPLE
    .\pca.ps1 "Find where database retries are configured and increase max_attempts to 5"
    git diff | .\pca.ps1 "Review this diff for bugs and security issues"
    .\pca.ps1 -Provider github-models -Tier cheap
    .\pca.ps1 -CompileExe
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$PromptArgs,

    [Parameter(ValueFromPipeline = $true)]
    [string]$PipelineInput,

    [string]$Provider = "",
    [string]$Model = "",
    [ValidateSet("", "cheap", "smart")]
    [string]$Tier = "",
    [string]$ApiKey = "",
    [string]$BaseUrl = "",
    [string]$ConfigPath = "",
    [string[]]$AddFile = @(),
    [string[]]$Skill = @(),
    [switch]$AutoApprove,
    [switch]$NoTools,
    [switch]$SkipCertCheck,
    [switch]$CompileExe,
    [switch]$InitConfig,
    [switch]$ListProviders,
    [switch]$Help
)

begin {
    $ErrorActionPreference = "Stop"
    $Script:Version = "1.1.0"
    $Script:StartTime = Get-Date
    $Script:WorkspaceRoot = (Get-Location).Path
    $Script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $Script:PipeBuffer = New-Object System.Collections.Generic.List[string]

    # Enable TLS 1.2 and TLS 1.3 (3072) for modern HTTPS endpoints on Windows PowerShell 5.1
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor 3072
    } catch {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }

    if ($SkipCertCheck) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    # Built-in Provider Catalog (Free & Ultra-Cheap First)
    $Script:ProviderCatalog = @{
        "github-models" = @{
            Name        = "GitHub Models (Azure Hosted - FREE)"
            BaseUrl     = "https://models.inference.ai.azure.com/chat/completions"
            EnvKey      = "GITHUB_TOKEN"
            CheapModel  = "gpt-4o-mini"
            SmartModel  = "gpt-4o"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) with any GitHub PAT. Hosted on *.azure.com (whitelisted on most Azure AVDs)."
        }
        "gemini" = @{
            Name        = "Google Gemini AI Studio (FREE Tier / Ultra-Cheap)"
            BaseUrl     = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            EnvKey      = "GEMINI_API_KEY"
            CheapModel  = "gemini-2.5-flash-lite"
            SmartModel  = "gemini-2.5-flash"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) on Google AI Studio Free Tier (or $0.075/1M in on paid tier)."
        }
        "openrouter" = @{
            Name        = "OpenRouter (Free Coding Models)"
            BaseUrl     = "https://openrouter.ai/api/v1/chat/completions"
            EnvKey      = "OPENROUTER_API_KEY"
            CheapModel  = "qwen/qwen3-coder:free"
            SmartModel  = "deepseek/deepseek-chat-v3-0324:free"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) using ':free' model variants on OpenRouter."
        }
        "groq" = @{
            Name        = "Groq Cloud (Free Developer Tier)"
            BaseUrl     = "https://api.groq.com/openai/v1/chat/completions"
            EnvKey      = "GROQ_API_KEY"
            CheapModel  = "llama-3.1-8b-instant"
            SmartModel  = "llama-3.3-70b-versatile"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "FREE ($0) developer tier with ultra-fast token streaming."
        }
        "deepseek" = @{
            Name        = "DeepSeek API (Ultra-Cheap + Auto Cache)"
            BaseUrl     = "https://api.deepseek.com/chat/completions"
            EnvKey      = "DEEPSEEK_API_KEY"
            CheapModel  = "deepseek-chat"
            SmartModel  = "deepseek-reasoner"
            InputCostPer1M  = 0.27
            CachedCostPer1M = 0.07
            OutputCostPer1M = 1.10
            Notes       = "Automatic disk prompt caching ($0.07/1M cached input tokens)."
        }
        "openai" = @{
            Name        = "OpenAI (Nano / Mini)"
            BaseUrl     = "https://api.openai.com/v1/chat/completions"
            EnvKey      = "OPENAI_API_KEY"
            CheapModel  = "gpt-4.1-nano"
            SmartModel  = "gpt-4.1-mini"
            InputCostPer1M  = 0.10
            CachedCostPer1M = 0.025
            OutputCostPer1M = 0.40
            Notes       = "GPT-4.1-nano costs $0.10/1M input ($0.025 cached)."
        }
        "azure-openai" = @{
            Name        = "Corporate Azure OpenAI Gateway"
            BaseUrl     = ""
            EnvKey      = "AZURE_OPENAI_API_KEY"
            CheapModel  = "gpt-4o-mini"
            SmartModel  = "gpt-4o"
            InputCostPer1M  = 0.15
            CachedCostPer1M = 0.075
            OutputCostPer1M = 0.60
            Notes       = "Set base_url in config.json to your corporate Azure OpenAI deployment URL."
        }
        "ollama" = @{
            Name        = "Local Ollama / vLLM / llama.cpp"
            BaseUrl     = "http://localhost:11434/v1/chat/completions"
            EnvKey      = "OLLAMA_API_KEY"
            CheapModel  = "qwen2.5-coder:7b"
            SmartModel  = "qwen2.5-coder:14b"
            InputCostPer1M  = 0.00
            CachedCostPer1M = 0.00
            OutputCostPer1M = 0.00
            Notes       = "100% offline/local inference."
        }
    }

    # Session State
    $Script:Session = @{
        Provider          = "github-models"
        Tier              = "cheap"
        Model             = ""
        ApiKey            = ""
        BaseUrl           = ""
        MaxSessionCostUsd = 0.50
        MaxToolSteps      = 12
        MaxReadLines      = 200
        KeepRecentTurns   = 10
        AutoApprove       = [bool]$AutoApprove
        NoTools           = [bool]$NoTools
        PinnedFiles       = New-Object System.Collections.Generic.List[string]
        ActiveSkills      = New-Object System.Collections.Generic.List[string]
        History           = New-Object System.Collections.Generic.List[object]
        UndoStack         = New-Object System.Collections.Generic.List[object]
        PromptTokens      = 0
        CachedTokens      = 0
        CompletionTokens  = 0
        TotalCostUsd      = 0.0
        TurnCount         = 0
    }
}

process {
    if ($null -ne $PipelineInput -and $PipelineInput -ne "") {
        $Script:PipeBuffer.Add($PipelineInput)
    }
}

end {
    # =========================================================================
    # Helper Functions: UI & Formatting
    # =========================================================================
    function Write-Banner {
        Write-Host ""
        Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |  PCA v$($Script:Version) - Portable Coding Assistant (Windows AVD Zero-Dep Edition) |" -ForegroundColor Cyan
        Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor Cyan
        $provInfo = $Script:ProviderCatalog[$Script:Session.Provider]
        $provLabel = if ($provInfo) { $Script:Session.Provider } else { "custom" }
        $skillsLabel = if ($Script:Session.ActiveSkills.Count -gt 0) { ($Script:Session.ActiveSkills -join ", ") } else { "none" }
        Write-Host ("  Provider : {0} | Model: {1} ({2} tier) | Skills: {3}" -f $provLabel, $Script:Session.Model, $Script:Session.Tier, $skillsLabel) -ForegroundColor Gray
        Write-Host ("  Workspace: {0}" -f $Script:WorkspaceRoot) -ForegroundColor Gray
        Write-Host "  Type '/help' for commands, '/skill uipath' for UiPath mode, or '/exit' to quit." -ForegroundColor DarkGray
        Write-Host ""
    }

    function Write-StatusFooter {
        param([int]$InTok, [int]$CachedTok, [int]$OutTok, [double]$TurnCost)
        $costStr = ("`${0:N5}" -f $TurnCost)
        $totStr  = ("`${0:N5}" -f $Script:Session.TotalCostUsd)
        Write-Host ("  [Tokens: {0} in ({1} cached) / {2} out | Turn: {3} | Session: {4} / `${5:N2} cap]" -f `
            $InTok, $CachedTok, $OutTok, $costStr, $totStr, $Script:Session.MaxSessionCostUsd) -ForegroundColor DarkGray
    }

    function Estimate-Tokens {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return 0 }
        return [Math]::Max(1, [int][Math]::Ceiling($Text.Length / 4.0))
    }

    # =========================================================================
    # Configuration Loading & Saving
    # =========================================================================
    function Get-DefaultConfigPath {
        if (-not [string]::IsNullOrEmpty($ConfigPath)) { return $ConfigPath }
        $localCfg = Join-Path $Script:WorkspaceRoot ".pca.json"
        if (Test-Path $localCfg) { return $localCfg }
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        return (Join-Path $userHome ".pca.json")
    }

    function Initialize-ConfigFile {
        $target = Join-Path $Script:WorkspaceRoot ".pca.json"
        $sample = [ordered]@{
            provider             = "github-models"
            tier                 = "cheap"
            model                = ""
            api_key              = ""
            base_url             = ""
            proxy_url            = ""
            skills               = @("uipath")
            max_session_cost_usd = 0.50
            max_tool_steps       = 12
            max_read_lines       = 200
            auto_approve         = $false
        }
        $json = $sample | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($target, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Created configuration file at: $target" -ForegroundColor Green
    }

    function Resolve-Configuration {
        $cfgFile = Get-DefaultConfigPath
        $fileCfg = $null
        if (Test-Path $cfgFile) {
            try {
                $raw = [System.IO.File]::ReadAllText($cfgFile, [System.Text.Encoding]::UTF8)
                $fileCfg = $raw | ConvertFrom-Json
            } catch {
                Write-Warning "Failed to parse config file $cfgFile : $($_.Exception.Message)"
            }
        }

        # 1. Provider resolution: CLI > Env > Config > Auto-detect from Env Keys > Default
        if (-not [string]::IsNullOrEmpty($Provider)) {
            $Script:Session.Provider = $Provider.ToLower()
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_PROVIDER)) {
            $Script:Session.Provider = $env:PCA_PROVIDER.ToLower()
        } elseif ($fileCfg -and $fileCfg.provider) {
            $Script:Session.Provider = ([string]$fileCfg.provider).ToLower()
        } else {
            # Auto-detect whichever free/cheap key exists in environment
            foreach ($key in @("github-models", "gemini", "openrouter", "groq", "deepseek", "openai")) {
                $envName = $Script:ProviderCatalog[$key].EnvKey
                $val = [Environment]::GetEnvironmentVariable($envName)
                if (-not [string]::IsNullOrEmpty($val)) {
                    $Script:Session.Provider = $key
                    break
                }
            }
        }

        # 2. Tier resolution
        if (-not [string]::IsNullOrEmpty($Tier)) {
            $Script:Session.Tier = $Tier.ToLower()
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_TIER)) {
            $Script:Session.Tier = $env:PCA_TIER.ToLower()
        } elseif ($fileCfg -and $fileCfg.tier) {
            $Script:Session.Tier = ([string]$fileCfg.tier).ToLower()
        }

        $cat = $Script:ProviderCatalog[$Script:Session.Provider]

        # 3. Model resolution
        if (-not [string]::IsNullOrEmpty($Model)) {
            $Script:Session.Model = $Model
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_MODEL)) {
            $Script:Session.Model = $env:PCA_MODEL
        } elseif ($fileCfg -and $fileCfg.model) {
            $Script:Session.Model = [string]$fileCfg.model
        } elseif ($cat) {
            $Script:Session.Model = if ($Script:Session.Tier -eq "smart") { $cat.SmartModel } else { $cat.CheapModel }
        } else {
            $Script:Session.Model = "gpt-4o-mini"
        }

        # 4. BaseUrl resolution
        if (-not [string]::IsNullOrEmpty($BaseUrl)) {
            $Script:Session.BaseUrl = $BaseUrl
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_BASE_URL)) {
            $Script:Session.BaseUrl = $env:PCA_BASE_URL
        } elseif ($fileCfg -and $fileCfg.base_url) {
            $Script:Session.BaseUrl = [string]$fileCfg.base_url
        } elseif ($cat) {
            $Script:Session.BaseUrl = $cat.BaseUrl
        }

        # 5. API Key resolution
        if (-not [string]::IsNullOrEmpty($ApiKey)) {
            $Script:Session.ApiKey = $ApiKey
        } elseif (-not [string]::IsNullOrEmpty($env:PCA_API_KEY)) {
            $Script:Session.ApiKey = $env:PCA_API_KEY
        } elseif ($cat -and -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($cat.EnvKey))) {
            $Script:Session.ApiKey = [Environment]::GetEnvironmentVariable($cat.EnvKey)
        } elseif ($fileCfg -and $fileCfg.api_key) {
            $Script:Session.ApiKey = [string]$fileCfg.api_key
        }

        # 6. Budget & limits
        if ($fileCfg) {
            if ($null -ne $fileCfg.max_session_cost_usd) { $Script:Session.MaxSessionCostUsd = [double]$fileCfg.max_session_cost_usd }
            if ($null -ne $fileCfg.max_tool_steps)       { $Script:Session.MaxToolSteps      = [int]$fileCfg.max_tool_steps }
            if ($null -ne $fileCfg.max_read_lines)       { $Script:Session.MaxReadLines      = [int]$fileCfg.max_read_lines }
            if ($null -ne $fileCfg.auto_approve -and -not $AutoApprove) { $Script:Session.AutoApprove = [bool]$fileCfg.auto_approve }
            if ($fileCfg.skills) {
                foreach ($sk in $fileCfg.skills) {
                    $skName = ([string]$sk).ToLower()
                    if (-not [string]::IsNullOrEmpty($skName) -and -not $Script:Session.ActiveSkills.Contains($skName)) {
                        $Script:Session.ActiveSkills.Add($skName)
                    }
                }
            }
        }

        # Pin initial files
        foreach ($f in $AddFile) {
            if (-not [string]::IsNullOrEmpty($f) -and -not $Script:Session.PinnedFiles.Contains($f)) {
                $Script:Session.PinnedFiles.Add($f)
            }
        }

        # Activate skills from CLI or auto-detect UiPath project (project.json + .xaml)
        foreach ($sk in $Skill) {
            $skName = ([string]$sk).ToLower()
            if (-not [string]::IsNullOrEmpty($skName) -and -not $Script:Session.ActiveSkills.Contains($skName)) {
                $Script:Session.ActiveSkills.Add($skName)
            }
        }
        $uipathProj = Join-Path $Script:WorkspaceRoot "project.json"
        if ((Test-Path $uipathProj) -and -not $Script:Session.ActiveSkills.Contains("uipath")) {
            try {
                $projRaw = [System.IO.File]::ReadAllText($uipathProj, [System.Text.Encoding]::UTF8)
                if ($projRaw -match "UiPath" -or $projRaw -match "expressionLanguage") {
                    $Script:Session.ActiveSkills.Add("uipath")
                }
            } catch {}
        }
    }

    # =========================================================================
    # Self-Compiling Native Windows .EXE Generator (Uses Built-in .NET csc.exe)
    # =========================================================================
    function Invoke-CompileNativeExe {
        $outExe = Join-Path $Script:WorkspaceRoot "pca.exe"
        $scriptFull = $MyInvocation.PSCommandPath
        if ([string]::IsNullOrEmpty($scriptFull)) {
            $scriptFull = Join-Path $Script:WorkspaceRoot "pca.ps1"
        }
        Write-Host "Compiling native Windows launcher '$outExe' using built-in .NET compiler..." -ForegroundColor Cyan

        $csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

public class PcaLauncher {
    public static int Main(string[] args) {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1Path = Path.Combine(exeDir, "pca.ps1");
        if (!File.Exists(ps1Path)) {
            Console.Error.WriteLine("Error: pca.ps1 not found alongside pca.exe at " + ps1Path);
            return 1;
        }
        StringBuilder sb = new StringBuilder();
        sb.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"");
        sb.Append(ps1Path);
        sb.Append("\"");
        foreach (string a in args) {
            sb.Append(" \"");
            sb.Append(a.Replace("\"", "\\\""));
            sb.Append("\"");
        }
        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", sb.ToString());
        psi.UseShellExecute = false;
        Process p = Process.Start(psi);
        p.WaitForExit();
        return p.ExitCode;
    }
}
"@
        Add-Type -TypeDefinition $csharpSource -OutputAssembly $outExe -OutputType ConsoleApplication
        Write-Host "Successfully compiled zero-dependency binary: $outExe" -ForegroundColor Green
    }

    # =========================================================================
    # Workspace & Context Optimization Tools
    # =========================================================================
    $Script:IgnoredDirs = @(".git", ".hg", ".svn", "node_modules", "bin", "obj", "dist", "build", "__pycache__", ".venv", "venv", ".vs", ".idea", "packages")

    function Get-SafePath {
        param([string]$RelOrAbsPath)
        if ([string]::IsNullOrEmpty($RelOrAbsPath)) { return $Script:WorkspaceRoot }
        $candidate = if ([System.IO.Path]::IsPathRooted($RelOrAbsPath)) {
            $RelOrAbsPath
        } else {
            Join-Path $Script:WorkspaceRoot $RelOrAbsPath
        }
        return [System.IO.Path]::GetFullPath($candidate)
    }

    function Get-RelativePath {
        param([string]$FullPath)
        if ($FullPath.StartsWith($Script:WorkspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $sub = $FullPath.Substring($Script:WorkspaceRoot.Length).TrimStart('\', '/')
            if ([string]::IsNullOrEmpty($sub)) { return "." }
            return $sub.Replace('\', '/')
        }
        return $FullPath
    }

    function Invoke-ToolListFiles {
        param([string]$SubDir = ".", [int]$MaxDepth = 3, [int]$MaxEntries = 150)
        $targetDir = Get-SafePath $SubDir
        if (-not (Test-Path $targetDir)) {
            return "Error: Directory not found: $SubDir"
        }
        $results = New-Object System.Collections.Generic.List[string]
        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue(@{ Path = $targetDir; Depth = 0 })

        while ($queue.Count -gt 0 -and $results.Count -lt $MaxEntries) {
            $curr = $queue.Dequeue()
            $items = Get-ChildItem -LiteralPath $curr.Path -Force -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($results.Count -ge $MaxEntries) { break }
                if ($item.PSIsContainer) {
                    if ($Script:IgnoredDirs -contains $item.Name) { continue }
                    $rel = Get-RelativePath $item.FullName
                    $results.Add("[DIR]  $rel/")
                    if ($curr.Depth + 1 -lt $MaxDepth) {
                        $queue.Enqueue(@{ Path = $item.FullName; Depth = ($curr.Depth + 1) })
                    }
                } else {
                    $rel = Get-RelativePath $item.FullName
                    $kb = [Math]::Round($item.Length / 1024.0, 1)
                    $results.Add(("[FILE] {0} ({1} KB)" -f $rel, $kb))
                }
            }
        }
        if ($results.Count -eq 0) { return "(empty workspace)" }
        if ($results.Count -ge $MaxEntries) {
            $results.Add("... (truncated at $MaxEntries entries; specify a subdirectory to inspect deeper)")
        }
        return ($results -join "`n")
    }

    function Invoke-ToolSearchText {
        param([string]$Pattern, [string]$SubDir = ".", [int]$MaxMatches = 40)
        if ([string]::IsNullOrEmpty($Pattern)) { return "Error: pattern is required." }
        $targetDir = Get-SafePath $SubDir
        if (-not (Test-Path $targetDir)) { return "Error: Path not found: $SubDir" }

        $matchesList = New-Object System.Collections.Generic.List[string]
        $files = Get-ChildItem -Path $targetDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $full = $_.FullName
            $skip = $false
            foreach ($ig in $Script:IgnoredDirs) {
                if ($full -match ([regex]::Escape([IO.Path]::DirectorySeparatorChar + $ig + [IO.Path]::DirectorySeparatorChar))) {
                    $skip = $true; break
                }
            }
            (-not $skip) -and ($_.Length -lt 1048576)
        }

        foreach ($f in $files) {
            if ($matchesList.Count -ge $MaxMatches) { break }
            try {
                $sel = Select-String -LiteralPath $f.FullName -Pattern $Pattern -ErrorAction SilentlyContinue
                foreach ($m in $sel) {
                    if ($matchesList.Count -ge $MaxMatches) { break }
                    $rel = Get-RelativePath $f.FullName
                    $lineText = $m.Line.Trim()
                    if ($lineText.Length -gt 160) { $lineText = $lineText.Substring(0, 160) + "..." }
                    $matchesList.Add(("{0}:{1}: {2}" -f $rel, $m.LineNumber, $lineText))
                }
            } catch {}
        }

        if ($matchesList.Count -eq 0) { return "No matches found for pattern: $Pattern" }
        return ($matchesList -join "`n")
    }

    function Invoke-ToolReadFile {
        param([string]$Path, [int]$StartLine = 1, [int]$EndLine = 0)
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        if (-not (Test-Path $full -PathType Leaf)) {
            return "Error: File does not exist: $Path"
        }
        $lines = [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)
        $total = $lines.Count
        if ($total -eq 0) { return "(File '$Path' is empty)" }

        if ($StartLine -lt 1) { $StartLine = 1 }
        if ($EndLine -le 0) { $EndLine = [Math]::Min($total, $StartLine + $Script:Session.MaxReadLines - 1) }
        if (($EndLine - $StartLine + 1) -gt $Script:Session.MaxReadLines) {
            $EndLine = $StartLine + $Script:Session.MaxReadLines - 1
        }
        if ($EndLine -gt $total) { $EndLine = $total }

        $out = New-Object System.Collections.Generic.List[string]
        $out.Add(("--- {0} (lines {1}-{2} of {3}) ---" -f (Get-RelativePath $full), $StartLine, $EndLine, $total))
        for ($i = $StartLine; $i -le $EndLine; $i++) {
            $out.Add(("{0,4} | {1}" -f $i, $lines[$i - 1]))
        }
        if ($EndLine -lt $total) {
            $out.Add(("... ({0} more lines; call read_file with start_line={1} to continue)" -f ($total - $EndLine), ($EndLine + 1)))
        }
        return ($out -join "`n")
    }

    function Confirm-UserAction {
        param([string]$Title, [string]$PreviewText)
        if ($Script:Session.AutoApprove) { return $true }
        Write-Host ""
        Write-Host "  [Action Confirmation] $Title" -ForegroundColor Yellow
        if (-not [string]::IsNullOrEmpty($PreviewText)) {
            foreach ($ln in ($PreviewText -split "`r?`n")) {
                if ($ln.StartsWith("+")) {
                    Write-Host "    $ln" -ForegroundColor Green
                } elseif ($ln.StartsWith("-")) {
                    Write-Host "    $ln" -ForegroundColor Red
                } else {
                    Write-Host "    $ln" -ForegroundColor Gray
                }
            }
        }
        Write-Host -NoNewline "  Allow this action? [y = yes / n = no / a = always in session]: " -ForegroundColor Cyan
        $ans = [Console]::ReadLine()
        if ($null -eq $ans) { return $false }
        $ans = $ans.Trim().ToLower()
        if ($ans -eq "a" -or $ans -eq "always") {
            $Script:Session.AutoApprove = $true
            return $true
        }
        return ($ans -eq "y" -or $ans -eq "yes")
    }

    function Invoke-ToolEditFile {
        param([string]$Path, [string]$Search = "", [string]$Replace = "")
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        $rel = Get-RelativePath $full
        $exists = Test-Path $full -PathType Leaf

        $oldContent = if ($exists) { [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8) } else { "" }

        if (-not $exists) {
            if (-not [string]::IsNullOrEmpty($Search)) {
                return "Error: File '$rel' does not exist, so 'search' must be empty when creating a new file."
            }
            $preview = "+ [New File: $rel ($($Replace.Length) chars)]"
            if (-not (Confirm-UserAction -Title "Create new file '$rel'" -PreviewText $preview)) {
                return "User declined creating file '$rel'."
            }
            $parent = Split-Path -Parent $full
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [System.IO.File]::WriteAllText($full, $Replace, (New-Object System.Text.UTF8Encoding($false)))
            $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $false; OldContent = "" })
            return "Created file '$rel' ($($Replace.Length) bytes)."
        }

        # Existing file: apply SEARCH / REPLACE block
        if ([string]::IsNullOrEmpty($Search)) {
            # Full overwrite
            $preview = "- [Overwrite entire file '$rel' ($($oldContent.Length) -> $($Replace.Length) chars)]"
            if (-not (Confirm-UserAction -Title "Overwrite '$rel'" -PreviewText $preview)) {
                return "User declined overwriting '$rel'."
            }
            [System.IO.File]::WriteAllText($full, $Replace, (New-Object System.Text.UTF8Encoding($false)))
            $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $true; OldContent = $oldContent })
            return "Updated file '$rel'."
        }

        # Normalize CRLF vs LF for matching
        $useCrLf = $oldContent.Contains("`r`n")
        $normOld = $oldContent.Replace("`r`n", "`n")
        $normSearch = $Search.Replace("`r`n", "`n")
        $normReplace = $Replace.Replace("`r`n", "`n")

        $idx = $normOld.IndexOf($normSearch, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) {
            return "Error: Exact SEARCH block not found in '$rel'. Use read_file first to verify exact lines and indentation."
        }
        $secondIdx = $normOld.IndexOf($normSearch, $idx + $normSearch.Length, [System.StringComparison]::Ordinal)
        if ($secondIdx -ge 0) {
            return "Error: SEARCH block matched multiple locations in '$rel'. Include more surrounding context lines."
        }

        $previewLines = New-Object System.Collections.Generic.List[string]
        foreach ($l in ($normSearch -split "`n"))  { $previewLines.Add("- $l") }
        foreach ($l in ($normReplace -split "`n")) { $previewLines.Add("+ $l") }

        if (-not (Confirm-UserAction -Title "Patch '$rel'" -PreviewText ($previewLines -join "`n"))) {
            return "User declined editing '$rel'."
        }

        $newNorm = $normOld.Substring(0, $idx) + $normReplace + $normOld.Substring($idx + $normSearch.Length)
        $finalText = if ($useCrLf) { $newNorm.Replace("`n", "`r`n") } else { $newNorm }

        [System.IO.File]::WriteAllText($full, $finalText, (New-Object System.Text.UTF8Encoding($false)))
        $Script:Session.UndoStack.Add(@{ Path = $full; Existed = $true; OldContent = $oldContent })
        return "Successfully patched '$rel'."
    }

    function Invoke-ToolRunCommand {
        param([string]$Command)
        if ([string]::IsNullOrEmpty($Command)) { return "Error: command is required." }
        if (-not (Confirm-UserAction -Title "Execute Shell Command" -PreviewText "  > $Command")) {
            return "User declined executing command: $Command"
        }
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -Command `"$($Command.Replace('"', '\"'))`""
            $psi.WorkingDirectory = $Script:WorkspaceRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit(30000) | Out-Null

            $combined = ("ExitCode: {0}`n{1}`n{2}" -f $proc.ExitCode, $stdout.Trim(), $stderr.Trim()).Trim()
            if ($combined.Length -gt 3500) {
                $combined = $combined.Substring(0, 3500) + "`n... [Output truncated to save tokens]"
            }
            return $combined
        } catch {
            return "Command execution failed: $($_.Exception.Message)"
        }
    }

    function Invoke-ToolInspectXaml {
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { return "Error: path is required." }
        $full = Get-SafePath $Path
        if (-not (Test-Path $full -PathType Leaf)) {
            return "Error: XAML file does not exist: $Path"
        }
        $lines = [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)
        $out = New-Object System.Collections.Generic.List[string]
        $out.Add("=== UiPath XAML Outline: $(Get-RelativePath $full) ($($lines.Count) total lines) ===")

        $argsList = New-Object System.Collections.Generic.List[string]
        $varsList = New-Object System.Collections.Generic.List[string]
        $actsList = New-Object System.Collections.Generic.List[string]
        $inViewState = $false

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            $lineNum = $i + 1
            if ($ln -match "<sap2010:WorkflowViewState" -or $ln -match "<scg:Dictionary.*ViewState") {
                if ($ln -notmatch "/>") { $inViewState = $true }
                continue
            }
            if ($inViewState) {
                if ($ln -match "</sap2010:WorkflowViewState" -or $ln -match "</scg:Dictionary>") {
                    $inViewState = $false
                }
                continue
            }

            if ($ln -match '<x:Property\s+[^>]*Name="([^"]+)"[^>]*Type="([^"]+)"') {
                $argsList.Add(("  Line {0,4}: Argument {1} ({2})" -f $lineNum, $Matches[1], $Matches[2]))
            } elseif ($ln -match '<Variable\s+[^>]*x:TypeArguments="([^"]+)"[^>]*Name="([^"]+)"') {
                $varsList.Add(("  Line {0,4}: Variable {1} : {2}" -f $lineNum, $Matches[2], $Matches[1]))
            } elseif ($ln -match '<Variable\s+[^>]*Name="([^"]+)"[^>]*x:TypeArguments="([^"]+)"') {
                $varsList.Add(("  Line {0,4}: Variable {1} : {2}" -f $lineNum, $Matches[1], $Matches[2]))
            } elseif ($ln -match '^\s*<([A-Za-z0-9_:]+)\s+[^>]*DisplayName="([^"]+)"') {
                $tag = $Matches[1]
                $disp = $Matches[2]
                $extra = ""
                if ($ln -match 'WorkflowFileName="([^"]+)"') { $extra = " -> Calls: $($Matches[1])" }
                elseif ($ln -match 'Selector="([^"]+)"') { $extra = " [Selector]" }
                $actsList.Add(("  Line {0,4}: [{1}] `{2}`{3}" -f $lineNum, $tag, $disp, $extra))
            }
        }

        $out.Add("Arguments ($($argsList.Count)):")
        if ($argsList.Count -gt 0) { foreach ($a in $argsList) { $out.Add($a) } } else { $out.Add("  (none)") }
        $out.Add("Variables ($($varsList.Count)):")
        if ($varsList.Count -gt 0) { foreach ($v in $varsList) { $out.Add($v) } } else { $out.Add("  (none)") }
        $out.Add("Activities ($($actsList.Count)):")
        if ($actsList.Count -gt 0) {
            $maxAct = [Math]::Min($actsList.Count, 120)
            for ($j = 0; $j -lt $maxAct; $j++) { $out.Add($actsList[$j]) }
            if ($actsList.Count -gt $maxAct) { $out.Add("  ... ($($actsList.Count - $maxAct) more activities)") }
        } else {
            $out.Add("  (none with DisplayName)")
        }
        $out.Add("Tip: Use read_file with start_line/end_line around the specific Line number above before calling edit_file.")
        return ($out -join "`n")
    }

    function Get-SkillContent {
        param([string]$SkillName)
        $candidates = @(
            (Join-Path $Script:WorkspaceRoot "skills\$SkillName\SKILL.md"),
            (Join-Path $Script:ScriptDir "skills\$SkillName\SKILL.md")
        )
        foreach ($c in $candidates) {
            if (Test-Path $c -PathType Leaf) {
                return [System.IO.File]::ReadAllText($c, [System.Text.Encoding]::UTF8)
            }
        }
        if ($SkillName -eq "uipath") {
            return @"
# UiPath Studio & Robot Built-in Skill
- Always call `inspect_xaml` first on `.xaml` files to get Arguments, Variables, and Activity line numbers without wasting tokens on ViewState XML.
- Check `project.json` for `expressionLanguage` (`VisualBasic` vs `CSharp`) and never mix VB.NET (`Nothing`, `AndAlso`, `Function(x)`) with C# (`null`, `&&`, `x =>`).
- Preserve XML tag balance and namespaces when patching `.xaml` files with `edit_file`.
"@
        }
        return ""
    }

    function Invoke-UndoLastEdit {
        if ($Script:Session.UndoStack.Count -eq 0) {
            Write-Host "  Nothing to undo." -ForegroundColor Yellow
            return
        }
        $last = $Script:Session.UndoStack[$Script:Session.UndoStack.Count - 1]
        $Script:Session.UndoStack.RemoveAt($Script:Session.UndoStack.Count - 1)
        $rel = Get-RelativePath $last.Path
        if ($last.Existed) {
            [System.IO.File]::WriteAllText($last.Path, $last.OldContent, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Reverted '$rel' to previous state." -ForegroundColor Green
        } else {
            if (Test-Path $last.Path) { Remove-Item -LiteralPath $last.Path -Force }
            Write-Host "  Removed newly created file '$rel'." -ForegroundColor Green
        }
    }

    # =========================================================================
    # Prompt Cache-Aligned System Prompt & Compact Tool Protocol
    # =========================================================================
    function Build-SystemPrompt {
        # Static instructions come first for 100% prefix cache hits on DeepSeek / OpenAI / Gemini
        $sys = @"
You are PCA (Portable Coding Assistant), an expert, token-efficient coding agent running on a Windows corporate/AVD environment.
Be concise, accurate, and surgical. Minimize unnecessary prose and avoid repeating unchanged code.

When you need to inspect files, search code, edit files, or run commands, you may either use native tool_calls OR emit a fenced tool block in your response using this exact JSON format:
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
6. run_command: {"tool": "run_command", "command": "powershell command"}

Rules for Token Efficiency:
- Never dump or rewrite an entire large file when a small SEARCH/REPLACE block in edit_file suffices.
- For UiPath `.xaml` files, call `inspect_xaml` first to locate exact activity line numbers, then `read_file` only that small line range.
- Emit at most ONE ```pca-tool``` block per turn when waiting for tool output, then wait for the [Tool Result] before continuing.
"@
        if ($Script:Session.ActiveSkills.Count -gt 0) {
            foreach ($sk in $Script:Session.ActiveSkills) {
                $skText = Get-SkillContent -SkillName $sk
                if (-not [string]::IsNullOrEmpty($skText)) {
                    $sys += "`n`n--- Active Skill: $sk ---`n$skText"
                }
            }
        }
        if ($Script:Session.PinnedFiles.Count -gt 0) {
            $sys += "`n`n--- Pinned Workspace Files ---"
            foreach ($pf in $Script:Session.PinnedFiles) {
                $sys += "`n" + (Invoke-ToolReadFile -Path $pf -StartLine 1 -EndLine 150)
            }
        }
        return $sys
    }

    function Compact-HistoryIfNeeded {
        param([switch]$Force)
        $count = $Script:Session.History.Count
        $limit = $Script:Session.KeepRecentTurns
        if (-not $Force -and $count -le $limit) { return }

        $Compacted = 0
        for ($i = 0; $i -lt ($count - 4); $i++) {
            $msg = $Script:Session.History[$i]
            if ($msg.content -and $msg.content.Length -gt 600) {
                $msg.content = $msg.content.Substring(0, 400) + "`n... [Older turn compacted to save tokens]"
                $Compacted++
            }
        }
        if ($Force) {
            Write-Host "  Compacted $Compacted older message(s) in conversation history." -ForegroundColor Green
        }
    }

    # =========================================================================
    # HTTP Client with Automatic Windows Corporate Proxy & Certificate Store
    # =========================================================================
    function Invoke-LlmChatCompletion {
        param([array]$Messages)

        if ($Script:Session.TotalCostUsd -ge $Script:Session.MaxSessionCostUsd -and $Script:Session.MaxSessionCostUsd -gt 0) {
            throw "Session cost cap (`$$($Script:Session.MaxSessionCostUsd)) reached! Increase max_session_cost_usd or run /clear."
        }

        $url = $Script:Session.BaseUrl
        if ([string]::IsNullOrEmpty($url)) {
            throw "No BaseUrl configured for provider '$($Script:Session.Provider)'."
        }
        if ([string]::IsNullOrEmpty($Script:Session.ApiKey) -and $Script:Session.Provider -ne "ollama") {
            $cat = $Script:ProviderCatalog[$Script:Session.Provider]
            $envHint = if ($cat) { $cat.EnvKey } else { "PCA_API_KEY" }
            throw "Missing API Key for provider '$($Script:Session.Provider)'. Set `$env:$envHint or `$env:PCA_API_KEY, or pass -ApiKey."
        }

        $payloadObj = @{
            model       = $Script:Session.Model
            messages    = $Messages
            temperature = 0.1
        }
        $jsonBody = $payloadObj | ConvertTo-Json -Depth 10 -Compress
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        $req.Accept = "application/json"
        $req.Timeout = 120000
        $req.UserAgent = "pca-cli/$($Script:Version)"

        # Automatic Corporate Proxy & Default Windows Credentials (vital on Windows AVD)
        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        if ($null -ne $sysProxy) {
            $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
            $req.Proxy = $sysProxy
        }

        if (-not [string]::IsNullOrEmpty($Script:Session.ApiKey)) {
            if ($Script:Session.Provider -eq "azure-openai" -and $url -match "openai\.azure\.com") {
                $req.Headers.Add("api-key", $Script:Session.ApiKey)
            } else {
                $req.Headers.Add("Authorization", "Bearer $($Script:Session.ApiKey)")
            }
        }

        $reqStream = $req.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()

        try {
            $resp = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $respText = $reader.ReadToEnd()
            $reader.Close()
            $resp.Close()
        } catch [System.Net.WebException] {
            $errMsg = $_.Exception.Message
            if ($null -ne $_.Exception.Response) {
                try {
                    $errReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                    $errBody = $errReader.ReadToEnd()
                    $errReader.Close()
                    if (-not [string]::IsNullOrEmpty($errBody)) { $errMsg += " | Body: $errBody" }
                } catch {}
            }
            throw "LLM API HTTP Error: $errMsg"
        }

        $parsed = $respText | ConvertFrom-Json
        $replyText = ""
        if ($parsed.choices -and $parsed.choices.Count -gt 0) {
            $replyText = [string]$parsed.choices[0].message.content
        }

        # Calculate token usage & cost
        $inTok = 0; $cachedTok = 0; $outTok = 0
        if ($parsed.usage) {
            if ($null -ne $parsed.usage.prompt_tokens)     { $inTok  = [int]$parsed.usage.prompt_tokens }
            if ($null -ne $parsed.usage.completion_tokens) { $outTok = [int]$parsed.usage.completion_tokens }
            if ($parsed.usage.prompt_tokens_details -and $null -ne $parsed.usage.prompt_tokens_details.cached_tokens) {
                $cachedTok = [int]$parsed.usage.prompt_tokens_details.cached_tokens
            } elseif ($null -ne $parsed.usage.prompt_cache_hit_tokens) {
                $cachedTok = [int]$parsed.usage.prompt_cache_hit_tokens
            }
        }
        if ($inTok -eq 0)  { $inTok  = Estimate-Tokens $jsonBody }
        if ($outTok -eq 0) { $outTok = Estimate-Tokens $replyText }

        $cat = $Script:ProviderCatalog[$Script:Session.Provider]
        $inRate     = if ($cat) { [double]$cat.InputCostPer1M }  else { 0.15 }
        $cachedRate = if ($cat) { [double]$cat.CachedCostPer1M } else { 0.075 }
        $outRate    = if ($cat) { [double]$cat.OutputCostPer1M } else { 0.60 }

        $uncachedIn = [Math]::Max(0, $inTok - $cachedTok)
        $turnCost = (($uncachedIn / 1000000.0) * $inRate) + (($cachedTok / 1000000.0) * $cachedRate) + (($outTok / 1000000.0) * $outRate)

        $Script:Session.PromptTokens     += $inTok
        $Script:Session.CachedTokens     += $cachedTok
        $Script:Session.CompletionTokens += $outTok
        $Script:Session.TotalCostUsd     += $turnCost

        return @{
            Content      = $replyText
            InputTokens  = $inTok
            CachedTokens = $cachedTok
            OutputTokens = $outTok
            TurnCostUsd  = $turnCost
        }
    }

    # =========================================================================
    # Agentic Tool Execution Loop
    # =========================================================================
    function Parse-ToolBlock {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return $null }
        $pattern = '(?s)```pca-tool\s*(\{.*?\})\s*```'
        $m = [regex]::Match($Text, $pattern)
        if (-not $m.Success) { return $null }
        try {
            return ($m.Groups[1].Value | ConvertFrom-Json)
        } catch {
            return $null
        }
    }

    function Invoke-DispatchTool {
        param($ToolCall)
        $name = ([string]$ToolCall.tool).ToLower()
        Write-Host ("  -> [Tool: {0}]" -f $name) -ForegroundColor Cyan
        switch ($name) {
            "list_files" {
                $sd = if ($ToolCall.sub_dir) { [string]$ToolCall.sub_dir } else { "." }
                $md = if ($ToolCall.max_depth) { [int]$ToolCall.max_depth } else { 2 }
                return Invoke-ToolListFiles -SubDir $sd -MaxDepth $md
            }
            "search_text" {
                $pat = [string]$ToolCall.pattern
                $sd  = if ($ToolCall.sub_dir) { [string]$ToolCall.sub_dir } else { "." }
                return Invoke-ToolSearchText -Pattern $pat -SubDir $sd
            }
            "read_file" {
                $p  = [string]$ToolCall.path
                $sl = if ($ToolCall.start_line) { [int]$ToolCall.start_line } else { 1 }
                $el = if ($ToolCall.end_line)   { [int]$ToolCall.end_line }   else { 0 }
                return Invoke-ToolReadFile -Path $p -StartLine $sl -EndLine $el
            }
            "inspect_xaml" {
                $p = [string]$ToolCall.path
                return Invoke-ToolInspectXaml -Path $p
            }
            "edit_file" {
                $p   = [string]$ToolCall.path
                $s   = if ($null -ne $ToolCall.search)  { [string]$ToolCall.search }  else { "" }
                $rep = if ($null -ne $ToolCall.replace) { [string]$ToolCall.replace } else { "" }
                return Invoke-ToolEditFile -Path $p -Search $s -Replace $rep
            }
            "run_command" {
                $cmd = [string]$ToolCall.command
                return Invoke-ToolRunCommand -Command $cmd
            }
            default {
                return "Error: Unknown tool '$name'."
            }
        }
    }

    function Invoke-AgentTurn {
        param([string]$UserMessage)
        $Script:Session.TurnCount++
        Compact-HistoryIfNeeded

        $Script:Session.History.Add(@{
            role    = "user"
            content = $UserMessage
        })

        $step = 0
        while ($step -lt $Script:Session.MaxToolSteps) {
            $step++
            $messages = New-Object System.Collections.Generic.List[object]
            $messages.Add(@{
                role    = "system"
                content = (Build-SystemPrompt)
            })
            foreach ($h in $Script:Session.History) {
                $messages.Add($h)
            }

            $res = Invoke-LlmChatCompletion -Messages $messages.ToArray()
            $reply = $res.Content

            $Script:Session.History.Add(@{
                role    = "assistant"
                content = $reply
            })

            Write-Host ""
            Write-Host $reply -ForegroundColor White
            Write-StatusFooter -InTok $res.InputTokens -CachedTok $res.CachedTokens -OutTok $res.OutputTokens -TurnCost $res.TurnCostUsd

            if ($Script:Session.NoTools) { break }

            $toolObj = Parse-ToolBlock -Text $reply
            if ($null -eq $toolObj) { break }

            $toolOut = Invoke-DispatchTool -ToolCall $toolObj
            $Script:Session.History.Add(@{
                role    = "user"
                content = "[Tool Result for $($toolObj.tool)]`n$toolOut"
            })
        }
    }

    # =========================================================================
    # Interactive Slash Commands
    # =========================================================================
    function Show-ProvidersTable {
        Write-Host ""
        Write-Host "  Available Free & Ultra-Cheap LLM Providers:" -ForegroundColor Cyan
        Write-Host "  -----------------------------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($k in @("github-models", "gemini", "openrouter", "groq", "deepseek", "openai", "azure-openai", "ollama")) {
            $p = $Script:ProviderCatalog[$k]
            $active = if ($Script:Session.Provider -eq $k) { "*" } else { " " }
            Write-Host ("  [{0}] {1,-14} | Cheap: {2,-26} | Env: {3}" -f $active, $k, $p.CheapModel, $p.EnvKey) -ForegroundColor White
            Write-Host ("      {0}" -f $p.Notes) -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    function Handle-SlashCommand {
        param([string]$InputLine)
        $parts = $InputLine.Trim() -split "\s+", 2
        $cmd = $parts[0].ToLower()
        $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

        switch ($cmd) {
            "/help" {
                Write-Host @"

  Slash Commands:
    /provider [name]   List providers or switch active provider (e.g. /provider github-models)
    /model [name]      Switch active model name (e.g. /model gpt-4o-mini)
    /tier [cheap|smart] Switch between cheap and smart model tiers
    /skill [name|off]  Activate a domain skill (e.g. /skill uipath) or clear skills (/skill off)
    /add <file>        Pin a file to system context
    /drop [file|all]   Unpin a file or clear all pinned files
    /files             List workspace files
    /undo              Revert the most recent file edit or creation
    /compact           Compress older conversation history to save tokens
    /cost              Show session token and USD cost breakdown
    /init              Create a default .pca.json config file in current workspace
    /clear             Clear conversation history
    /exit              Exit PCA
"@ -ForegroundColor Gray
            }
            "/skill" {
                if ([string]::IsNullOrEmpty($arg)) {
                    $activeStr = if ($Script:Session.ActiveSkills.Count -gt 0) { ($Script:Session.ActiveSkills -join ", ") } else { "none" }
                    Write-Host "  Active skills: $activeStr (Try '/skill uipath' or '/skill off')" -ForegroundColor Cyan
                } elseif ($arg.ToLower() -eq "off" -or $arg.ToLower() -eq "none" -or $arg.ToLower() -eq "clear") {
                    $Script:Session.ActiveSkills.Clear()
                    Write-Host "  Cleared all active skills." -ForegroundColor Green
                } else {
                    $skName = $arg.ToLower()
                    if (-not $Script:Session.ActiveSkills.Contains($skName)) {
                        $Script:Session.ActiveSkills.Add($skName)
                    }
                    Write-Host "  Activated skill '$skName'." -ForegroundColor Green
                }
            }
            "/provider" {
                if ([string]::IsNullOrEmpty($arg)) {
                    Show-ProvidersTable
                } elseif ($Script:ProviderCatalog.ContainsKey($arg.ToLower())) {
                    $Script:Session.Provider = $arg.ToLower()
                    $cat = $Script:ProviderCatalog[$Script:Session.Provider]
                    $Script:Session.BaseUrl = $cat.BaseUrl
                    $Script:Session.Model = if ($Script:Session.Tier -eq "smart") { $cat.SmartModel } else { $cat.CheapModel }
                    $envKeyVal = [Environment]::GetEnvironmentVariable($cat.EnvKey)
                    if (-not [string]::IsNullOrEmpty($envKeyVal)) { $Script:Session.ApiKey = $envKeyVal }
                    Write-Host "  Switched provider to '$($Script:Session.Provider)' (model: $($Script:Session.Model))." -ForegroundColor Green
                } else {
                    Write-Host "  Unknown provider '$arg'. Run /provider to see valid options." -ForegroundColor Red
                }
            }
            "/model" {
                if ([string]::IsNullOrEmpty($arg)) {
                    Write-Host "  Current model: $($Script:Session.Model)" -ForegroundColor Cyan
                } else {
                    $Script:Session.Model = $arg
                    Write-Host "  Switched model to '$arg'." -ForegroundColor Green
                }
            }
            "/tier" {
                if ($arg -eq "cheap" -or $arg -eq "smart") {
                    $Script:Session.Tier = $arg
                    $cat = $Script:ProviderCatalog[$Script:Session.Provider]
                    if ($cat) {
                        $Script:Session.Model = if ($arg -eq "smart") { $cat.SmartModel } else { $cat.CheapModel }
                    }
                    Write-Host "  Switched tier to '$arg' (model: $($Script:Session.Model))." -ForegroundColor Green
                } else {
                    Write-Host "  Usage: /tier cheap  OR  /tier smart" -ForegroundColor Yellow
                }
            }
            "/add" {
                if ([string]::IsNullOrEmpty($arg)) {
                    Write-Host "  Pinned files: $($Script:Session.PinnedFiles -join ', ')" -ForegroundColor Cyan
                } else {
                    $Script:Session.PinnedFiles.Add($arg)
                    Write-Host "  Pinned '$arg' to context." -ForegroundColor Green
                }
            }
            "/drop" {
                if ($arg -eq "all" -or [string]::IsNullOrEmpty($arg)) {
                    $Script:Session.PinnedFiles.Clear()
                    Write-Host "  Cleared all pinned files." -ForegroundColor Green
                } else {
                    $Script:Session.PinnedFiles.Remove($arg) | Out-Null
                    Write-Host "  Unpinned '$arg'." -ForegroundColor Green
                }
            }
            "/files" {
                Write-Host (Invoke-ToolListFiles -SubDir "." -MaxDepth 2) -ForegroundColor Gray
            }
            "/undo" {
                Invoke-UndoLastEdit
            }
            "/compact" {
                Compact-HistoryIfNeeded -Force
            }
            "/cost" {
                Write-Host ""
                Write-Host ("  Session Token & Cost Summary:") -ForegroundColor Cyan
                Write-Host ("    Prompt Tokens     : {0}" -f $Script:Session.PromptTokens)
                Write-Host ("    Cached Hit Tokens : {0}" -f $Script:Session.CachedTokens)
                Write-Host ("    Completion Tokens : {0}" -f $Script:Session.CompletionTokens)
                Write-Host ("    Estimated USD     : `${0:N5} (Cap: `${1:N2})" -f $Script:Session.TotalCostUsd, $Script:Session.MaxSessionCostUsd)
                Write-Host ""
            }
            "/init" {
                Initialize-ConfigFile
            }
            "/clear" {
                $Script:Session.History.Clear()
                Write-Host "  Cleared conversation history." -ForegroundColor Green
            }
            "/exit" { return "EXIT" }
            "/quit" { return "EXIT" }
            default {
                Write-Host "  Unknown command '$cmd'. Type /help for available commands." -ForegroundColor Yellow
            }
        }
        return "CONTINUE"
    }

    # =========================================================================
    # Entrypoint Execution
    # =========================================================================
    Resolve-Configuration

    if ($Help) {
        Write-Banner
        Handle-SlashCommand "/help" | Out-Null
        Show-ProvidersTable
        return
    }

    if ($ListProviders) {
        Show-ProvidersTable
        return
    }

    if ($InitConfig) {
        Initialize-ConfigFile
        return
    }

    if ($CompileExe) {
        Invoke-CompileNativeExe
        return
    }

    $initialPrompt = if ($PromptArgs -and $PromptArgs.Count -gt 0) { ($PromptArgs -join " ").Trim() } else { "" }
    $pipedText = if ($Script:PipeBuffer.Count -gt 0) { ($Script:PipeBuffer -join "`n").Trim() } else { "" }

    # One-Shot Mode (if prompt or piped stdin was supplied)
    if (-not [string]::IsNullOrEmpty($initialPrompt) -or -not [string]::IsNullOrEmpty($pipedText)) {
        $combinedPrompt = $initialPrompt
        if (-not [string]::IsNullOrEmpty($pipedText)) {
            if ($pipedText.Length -gt 12000) {
                $pipedText = $pipedText.Substring(0, 12000) + "`n... [Piped input truncated to 12,000 chars to save tokens]"
            }
            $combinedPrompt = "$initialPrompt`n`n--- Piped Input ---`n```text`n$pipedText`n```"
        }
        Invoke-AgentTurn -UserMessage $combinedPrompt.Trim()
        return
    }

    # Interactive REPL Mode
    Write-Banner
    while ($true) {
        Write-Host -NoNewline "pca ($($Script:Session.Provider):$($Script:Session.Tier))> " -ForegroundColor Green
        $line = [Console]::ReadLine()
        if ($null -eq $line) { break }
        $trimmed = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmed)) { continue }

        if ($trimmed.StartsWith("/")) {
            $status = Handle-SlashCommand -InputLine $trimmed
            if ($status -eq "EXIT") { break }
            continue
        }

        try {
            Invoke-AgentTurn -UserMessage $trimmed
        } catch {
            Write-Host "  [Error] $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
