param(
    [string]$BaseUrl = "http://chat.mlops.com",
    [string]$Email = $env:CHAT_LOAD_EMAIL,
    [string]$Password = $env:CHAT_LOAD_PASSWORD,
    [int]$DurationSeconds = 30,
    [int]$Sessions = 3,
    [int]$MaxTokens = 700,
    [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
    throw "Email and Password are required, either as parameters or CHAT_LOAD_EMAIL/CHAT_LOAD_PASSWORD env vars."
}

$startedAt = Get-Date
$deadline = $startedAt.AddSeconds($DurationSeconds)
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogFile) | Out-Null
    "" | Set-Content -Path $LogFile
}

$worker = {
    param($SessionNo, $BaseUrl, $Email, $Password, $DeadlineIso, $MaxTokens, $LogFile)

    $deadline = [datetime]::Parse($DeadlineIso)
    $auth = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/v1/auths/signin" -ContentType "application/json" -Body (@{
        email = $Email
        password = $Password
    } | ConvertTo-Json)

    $headers = @{
        Authorization  = "Bearer $($auth.token)"
        "Content-Type" = "application/json"
    }

    $themes = @(
        "Kubernetes MLOps incident response for Open WebUI, vLLM, Prometheus, Grafana, Loki, Tempo, MinIO, and GPU operators",
        "synthetic postmortem for an inference latency spike with queueing, KV cache, GPU utilization, and alert thresholds",
        "Grafana dashboard validation plan for token throughput, request rate, p95 and p99 latency, errors, logs, and traces",
        "capacity planning analysis for chat inference including concurrency, batching, context length, and noisy neighbor effects",
        "runbook for debugging failed OpenAI-compatible chat completions routed through Open WebUI into a local vLLM service"
    )

    $systemMessage = @{
        role = "system"
        content = "You are generating verbose synthetic responses for observability traffic validation. Keep answers detailed and structured. Session: $SessionNo."
    }

    $stats = [ordered]@{
        session = $SessionNo
        ok = 0
        failed = 0
        total_tokens = 0
        prompt_tokens = 0
        completion_tokens = 0
        min_ms = $null
        max_ms = 0
        elapsed_ms = 0
    }

    $turn = 0
    while ((Get-Date) -lt $deadline) {
        $turn++
        $theme = $themes[($turn + $SessionNo) % $themes.Count]
        $requestMessages = @($systemMessage, @{
            role = "user"
            content = "Session $SessionNo turn $turn. Produce a long, technical, dashboard-useful answer about $theme. Include concrete metrics, example queries, tables, timelines, and validation steps. Make the response substantial enough to exercise prompt and completion token metrics."
        })

        $body = @{
            model = "gemma"
            messages = $requestMessages
            stream = $false
            temperature = 0.75
            top_p = 0.92
            max_tokens = $MaxTokens
        } | ConvertTo-Json -Depth 20

        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/chat/completions" -Headers $headers -Body $body -TimeoutSec 600
            $sw.Stop()

            $stats.ok++
            $stats.prompt_tokens += [int]$response.usage.prompt_tokens
            $stats.completion_tokens += [int]$response.usage.completion_tokens
            $stats.total_tokens += [int]$response.usage.total_tokens
            if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
                [pscustomobject]@{
                    at = (Get-Date).ToString("o")
                    session = $SessionNo
                    turn = $turn
                    ok = $true
                    elapsed_ms = $sw.ElapsedMilliseconds
                    prompt_tokens = [int]$response.usage.prompt_tokens
                    completion_tokens = [int]$response.usage.completion_tokens
                    total_tokens = [int]$response.usage.total_tokens
                } | ConvertTo-Json -Compress | Add-Content -Path $LogFile
            }
            if ($null -eq $stats.min_ms -or $sw.ElapsedMilliseconds -lt $stats.min_ms) {
                $stats.min_ms = $sw.ElapsedMilliseconds
            }
            if ($sw.ElapsedMilliseconds -gt $stats.max_ms) {
                $stats.max_ms = $sw.ElapsedMilliseconds
            }
        } catch {
            $sw.Stop()
            $stats.failed++
            if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
                [pscustomobject]@{
                    at = (Get-Date).ToString("o")
                    session = $SessionNo
                    turn = $turn
                    ok = $false
                    elapsed_ms = $sw.ElapsedMilliseconds
                    prompt_tokens = 0
                    completion_tokens = 0
                    total_tokens = 0
                } | ConvertTo-Json -Compress | Add-Content -Path $LogFile
            }
            Start-Sleep -Milliseconds 500
        }

        $stats.elapsed_ms += $sw.ElapsedMilliseconds

        $requestMessages = $null
    }

    [pscustomobject]$stats
}

$jobs = 1..$Sessions | ForEach-Object {
    Start-Job -ScriptBlock $worker -ArgumentList $_, $BaseUrl, $Email, $Password, $deadline.ToString("o"), $MaxTokens, $LogFile
}

$results = Wait-Job $jobs -Timeout ($DurationSeconds + 900) | Receive-Job
Remove-Job $jobs -Force

$summary = [ordered]@{
    started_at = $startedAt.ToString("o")
    ended_at = (Get-Date).ToString("o")
    duration_seconds = $DurationSeconds
    sessions = $Sessions
    ok = ($results | Measure-Object -Property ok -Sum).Sum
    failed = ($results | Measure-Object -Property failed -Sum).Sum
    prompt_tokens = ($results | Measure-Object -Property prompt_tokens -Sum).Sum
    completion_tokens = ($results | Measure-Object -Property completion_tokens -Sum).Sum
    total_tokens = ($results | Measure-Object -Property total_tokens -Sum).Sum
    min_ms = ($results | Where-Object { $null -ne $_.min_ms } | Measure-Object -Property min_ms -Minimum).Minimum
    max_ms = ($results | Measure-Object -Property max_ms -Maximum).Maximum
    per_session = $results
}

[pscustomobject]$summary | ConvertTo-Json -Depth 8
