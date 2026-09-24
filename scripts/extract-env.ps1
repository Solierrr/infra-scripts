<#
.SYNOPSIS
  Extrai secrets do Infisical para um arquivo .env local.

.DESCRIPTION
  Para um serviço, combina as pastas de secrets que ele consome. Sem Service,
  combina as pastas de todos os serviços conhecidos.
#>

param(
    [Parameter(Mandatory = $false)]
    [Alias("s")]
    [string]$Service,

    [Parameter(Mandatory = $false)]
    [Alias("e")]
    [ValidateSet("local", "qa", "prod")]
    [string]$Environment = "local",

    [Parameter(Mandatory = $false)]
    [Alias("o")]
    [string]$OutputPath = ".env"
)

$ErrorActionPreference = "Stop"
$InfisicalProjectId = "2296d19c-5f3b-41e1-afa3-fcde39966a71"

$ServiceFolderMap = @{
    "api-core"           = @("/database", "/redis", "/cloudinary", "/google", "/otel")
    "api-auth"           = @("/database", "/redis", "/auth", "/outbox")
    "api-messenger"      = @("/database", "/auth")
    "api-recommendation" = @("/database", "/recommendation")
    "api-mcp"            = @("/database", "/mcp")
    "ai-assistant"       = @("/database", "/redis", "/llm", "/agent-queue")
    "ai-validation"      = @("/llm")
    "web-app"            = @("/vite", "/service-urls")
    "google-registry"    = @("/google")
    "databricks-sync"    = @("/database", "/databricks")
    "database-console"   = @("/database")
}

if ($Service -and -not $ServiceFolderMap.ContainsKey($Service)) {
    throw "Servico '$Service' não mapeado. Adicione suas pastas ao ServiceFolderMap em org-scripts antes de executar."
}

if (-not (Get-Command infisical -ErrorAction SilentlyContinue)) {
    throw "Infisical CLI não instalado. Instale-o e execute 'infisical login' antes de usar extract-env."
}

& infisical user get token --silent *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Infisical CLI sem sessão ativa. Execute 'infisical login' antes de usar extract-env."
}

$folders = if ($Service) {
    $ServiceFolderMap[$Service]
} else {
    $ServiceFolderMap.Values | ForEach-Object { $_ } | Select-Object -Unique
}
$label = if ($Service) { $Service } else { "todos os serviços" }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Gerado por infra-scripts/extract-env.ps1 - Service=$label Environment=$Environment - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")

foreach ($folder in $folders) {
    Write-Host "Extraindo $folder (env=$Environment)..." -ForegroundColor Cyan
    $output = @(& infisical export --env=$Environment --path=$folder --format=dotenv --projectId=$InfisicalProjectId --silent 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao extrair '$folder': $output"
    }

    $lines.Add("")
    $lines.Add("# --- $folder ---")
    $lines.AddRange([string[]]$output)
}

[System.IO.File]::WriteAllLines($OutputPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK: '$OutputPath' gerado com $($folders.Count) pasta(s) do Infisical para '$label' (env=$Environment)." -ForegroundColor Green
