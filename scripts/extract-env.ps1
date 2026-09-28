<#
.SYNOPSIS
  Extrai segredos do Infisical para um arquivo .env local.

.DESCRIPTION
  Combina as pastas de segredos consumidas pelo serviço selecionado. Se serviço
  ou ambiente não forem informados, apresenta menus interativos. Uma exportação
  sem variáveis é tratada como erro e não substitui o arquivo de saída existente.
#>

param(
    [Alias('s')]
    [string] $Service,

    [Alias('e')]
    [ValidateSet('local', 'qa', 'prod')]
    [string] $Environment,

    [Alias('o')]
    [string] $OutputPath = '.env'
)

$ErrorActionPreference = 'Stop'
$InfisicalProjectId = '2296d19c-5f3b-41e1-afa3-fcde39966a71'

$ServiceFolderMap = @{
    'api-core'           = @('/database', '/redis', '/cloudinary', '/google', '/otel')
    'api-auth'            = @('/database', '/redis', '/auth', '/outbox')
    'api-messenger'       = @('/database', '/auth')
    'api-recommendation'  = @('/database', '/recommendation')
    'api-mcp'             = @('/database', '/mcp')
    'ai-assistant'        = @('/database', '/redis', '/llm', '/agent-queue')
    'ai-validation'       = @('/llm')
    'web-app'             = @('/vite', '/service-urls')
    'mobile-app'          = @('/service-urls')
    'google-registry'     = @('/google')
    'databricks-sync'     = @('/database', '/databricks')
    'database-console'    = @('/database')
}

$ServiceAliases = @{
    'console-database' = 'database-console'
}

function Read-MenuChoice {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string[]] $Options
    )

    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}. {1}" -f ($i + 1), $Options[$i])
    }

    while ($true) {
        $answer = Read-Host 'Digite o número da opção'
        $selection = 0
        if ([int]::TryParse($answer, [ref] $selection) -and $selection -ge 1 -and $selection -le $Options.Count) {
            return $selection
        }
        Write-Host ("Escolha um número entre 1 e {0}." -f $Options.Count) -ForegroundColor Yellow
    }
}

$selectAllServices = $false
if ([string]::IsNullOrWhiteSpace($Service)) {
    $serviceNames = @($ServiceFolderMap.Keys | Sort-Object)
    $serviceOptions = @($serviceNames) + @('Todos os serviços (exportação completa)')
    $serviceChoice = Read-MenuChoice -Title 'Qual serviço?' -Options $serviceOptions
    if ($serviceChoice -eq $serviceOptions.Count) {
        $Service = $null
        $selectAllServices = $true
    }
    else {
        $Service = $serviceNames[$serviceChoice - 1]
    }
}
elseif ($ServiceAliases.ContainsKey($Service)) {
    $Service = $ServiceAliases[$Service]
}

if ($Service -and -not $ServiceFolderMap.ContainsKey($Service)) {
    throw "Serviço '$Service' não mapeado. Adicione suas pastas ao ServiceFolderMap em infra-scripts antes de executar."
}

if (-not $PSBoundParameters.ContainsKey('Environment')) {
    $environmentOptions = @('local', 'qa', 'prod')
    $environmentChoice = Read-MenuChoice -Title 'Qual ambiente?' -Options @('LOCAL', 'QA', 'PROD')
    $Environment = $environmentOptions[$environmentChoice - 1]
}

$InfisicalCommand = Get-Command infisical.exe -ErrorAction SilentlyContinue
if (-not $InfisicalCommand) {
    $InfisicalCommand = Get-Command infisical -ErrorAction SilentlyContinue
}
if (-not $InfisicalCommand) {
    throw "Infisical CLI não instalado. Instale-o e execute 'infisical login' antes de usar extract-env."
}

& $InfisicalCommand.Source user get token --silent *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Infisical CLI sem sessão ativa. Execute 'infisical login' antes de usar extract-env."
}

$folders = if ($selectAllServices) {
    $ServiceFolderMap.Values | ForEach-Object { $_ } | Select-Object -Unique
}
else {
    $ServiceFolderMap[$Service]
}
$label = if ($selectAllServices) { 'todos os serviços' } else { $Service }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Gerado por infra-scripts/extract-env.ps1 - Service=$label Environment=$Environment - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")

foreach ($folder in $folders) {
    Write-Host "Extraindo $folder (env=$Environment)..." -ForegroundColor Cyan
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $InfisicalCommand.Source export --env=$Environment --path=$folder --format=dotenv --projectId=$InfisicalProjectId --silent 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "Falha ao extrair '$folder' no ambiente '$Environment' (exit code $exitCode). Confira o acesso, o ambiente e o caminho no Infisical."
    }
    if (@($output | Where-Object { $_ -match 'serving secrets from last successful fetch' }).Count -gt 0) {
        throw "Infisical não conseguiu consultar o servidor para '$folder' no ambiente '$Environment' e retornou dados do cache. O arquivo '$OutputPath' não foi alterado."
    }

    $dotenvLines = @($output | Where-Object { $_ -match '^\s*(?:export\s+)?[^#\s][^=]*=' })
    if ($dotenvLines.Count -eq 0) {
        throw "Nenhum segredo retornado para '$folder' no ambiente '$Environment'. O arquivo '$OutputPath' não foi alterado. Confira se a pasta tem segredos nesse ambiente e se sua conta tem acesso."
    }

    $lines.Add('')
    $lines.Add("# --- $folder ---")
    $lines.AddRange([string[]] $dotenvLines)
}

[System.IO.File]::WriteAllLines($OutputPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK: '$OutputPath' gerado com $($folders.Count) pasta(s) do Infisical para '$label' (env=$Environment)." -ForegroundColor Green
