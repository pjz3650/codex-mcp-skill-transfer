param(
    [ValidateSet('scan','publish','install')][string]$Mode = 'scan',
    [string]$Repository = 'https://github.com/pjz3650/codex-mcp-skill-transfer.git'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$skillsRoot = Join-Path $codexHome 'skills'
$agentsSkillsRoot = Join-Path (Join-Path $HOME '.agents') 'skills'
$payload = Join-Path $root 'package'
$skillDst = Join-Path $payload 'skills'
$manifestFile = Join-Path $payload 'mcps.json'

function Assert-Tools {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git nao encontrado. Instale Git for Windows e autentique com GitHub.' }
}
function Test-Private([string]$value) {
    return ($value -match '(?i)(gh[pousr]_[A-Za-z0-9_]+|github_pat_|sk-[A-Za-z0-9_-]{15,}|AIza[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----|mongodb(\+srv)?://|postgres(ql)?://|https?://[^/\s:@]+:[^/\s@]+@|(?i:password|secret|token|api[_-]?key|authorization)\s*[:=]\s*[\x22\x27]?[A-Za-z0-9_\-]{24,})' )
}
function Test-SafeArg([string]$value) {
    return ($value -match '^[a-zA-Z0-9_./:@+=,-]+$' -and -not (Test-Private $value))
}
function Read-Mcps {
    $config = Join-Path $codexHome 'config.toml'
    $entries = @()
    if (-not (Test-Path $config)) { return ,$entries }
    $section = $null
    $command = $null
    $mcpArgs = @()
    function Emit-Mcp {
        if ($section -and $command -and (Test-SafeArg $command) -and @($mcpArgs | Where-Object { -not (Test-SafeArg $_) }).Count -eq 0) {
            return @{name=$section; command=$command; args=@($mcpArgs)}
        }
        return $null
    }
    foreach ($line in (Get-Content -LiteralPath $config -Encoding UTF8)) {
        if ($line -match '^\s*\[mcp_servers\.([A-Za-z0-9_-]+)\]\s*(?:#.*)?$') {
            $item = Emit-Mcp; if ($item) { $entries += $item }
            $section=$Matches[1]; $command=$null; $mcpArgs=@(); continue
        }
        if ($line -match '^\s*\[') {
            $item = Emit-Mcp; if ($item) { $entries += $item }
            $section=$null; $command=$null; $mcpArgs=@(); continue
        }
        if (-not $section) { continue }
        if ($line -match '^\s*command\s*=\s*"([^"]+)"\s*(?:#.*)?$') { $command=$Matches[1]; continue }
        if ($line -match '^\s*args\s*=\s*\[(.*)\]\s*(?:#.*)?$') {
            $raw=$Matches[1]; $mcpArgs=@()
            if ($raw.Trim()) {
                $stripped=[regex]::Replace($raw, '"[^"]*"', '')
                if ($stripped -replace '[\s,]','') { $command=$null; continue }
                foreach ($m in [regex]::Matches($raw,'"([^"]*)"')) { $mcpArgs += $m.Groups[1].Value }
            }
        }
    }
    $item = Emit-Mcp; if ($item) { $entries += $item }
    return ,$entries
}
function Get-SkillSources {
    $items = @()
    foreach ($source in @(@{Path=$skillsRoot; Location='codex'}, @{Path=$agentsSkillsRoot; Location='agents'})) {
        if (-not (Test-Path $source.Path)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $source.Path -Directory -Force | Where-Object { $_.Name -ne '.system' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
            $items += [pscustomobject]@{Name=$dir.Name; FullName=$dir.FullName; Location=$source.Location}
        }
    }
    return ,$items
}
function Check-SkillFile($file) {
    $ext = [IO.Path]::GetExtension($file.Name).ToLowerInvariant()
    $allowed = @('.md','.txt','.json','.yaml','.yml','.toml','.py','.ps1','.js','.ts','.sh','.html','.css','.xml','.csv')
    $knownNoExtension = @('LICENSE','LICENCE','COPYING','NOTICE','AUTHORS','CONTRIBUTORS')
    if (($allowed -notcontains $ext) -and ($knownNoExtension -notcontains $file.Name.ToUpperInvariant())) {
        throw "Arquivo nao permitido: $($file.FullName)"
    }
    if ($file.Length -gt 1MB) { throw "Arquivo acima de 1 MB: $($file.FullName)" }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link nao permitido: $($file.FullName)" }
    $body = [IO.File]::ReadAllText($file.FullName)
    if (Test-Private $body) { throw "Possivel credencial em $($file.FullName). Publicacao bloqueada; revise manualmente." }
}
function Ensure-Repo {
    Assert-Tools
    if (-not (Test-Path (Join-Path $root '.git'))) {
        throw "Execute a partir de um clone Git: git clone $Repository; cd codex-mcp-skill-transfer"
    }
    $origin = (& git -C $root remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or ($origin -notmatch '(^|[:/])pjz3650/codex-mcp-skill-transfer(\.git)?$')) {
        throw 'Remote origin diferente do repositorio autorizado.'
    }
}
switch ($Mode) {
    scan {
        $localSkills = @(Get-SkillSources)
        $mcps = @(Read-Mcps)
        $cfgPath = Join-Path $codexHome 'config.toml'
        $configured = @()
        if (Test-Path $cfgPath) {
            $rawConfig = Get-Content -LiteralPath $cfgPath -Encoding UTF8
            foreach ($line in $rawConfig) {
                if ($line -match '^\s*\[mcp_servers\.([A-Za-z0-9_-]+)\]') {
                    $configured += $Matches[1]
                }
            }
        }
        $safeNames = @($mcps | ForEach-Object { $_.name })
        $omitted = @($configured | Sort-Object -Unique | Where-Object { $safeNames -notcontains $_ })
        Write-Host ''
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '           INVENTARIO DE MCPs E SKILLS DO CODEX' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host "Computador: $env:COMPUTERNAME"
        Write-Host "CODEX_HOME: $codexHome"
        Write-Host ''
        Write-Host "SKILLS ENCONTRADAS: $($localSkills.Count)" -ForegroundColor Green
        foreach ($location in @('agents','codex')) {
            $path = if ($location -eq 'agents') { $agentsSkillsRoot } else { $skillsRoot }
            $items = @($localSkills | Where-Object { $_.Location -eq $location } | Sort-Object Name)
            Write-Host "  [$location] $path - $($items.Count) skill(s)" -ForegroundColor Yellow
            foreach ($item in $items) { Write-Host "    + $($item.Name)" }
            if ($items.Count -eq 0) { Write-Host '    (nenhuma encontrada)' -ForegroundColor DarkGray }
        }
        Write-Host ''
        Write-Host "MCPs CONFIGURADOS: $(@($configured | Sort-Object -Unique).Count)" -ForegroundColor Green
        foreach ($mcp in @($mcps | Sort-Object name)) {
            Write-Host "  [EXPORTAVEL] $($mcp.name)" -ForegroundColor Green
            Write-Host "    Comando: $($mcp.command)"
        }
        foreach ($name in $omitted) {
            Write-Host "  [NAO EXPORTADO] $name - exige revisao/manual" -ForegroundColor Yellow
        }
        if ($configured.Count -eq 0) { Write-Host '  (nenhum MCP encontrado no config.toml)' -ForegroundColor DarkGray }
        Write-Host ''
        Write-Host 'Resumo: MCPs nao exportaveis nao sao enviados; credenciais nunca sao exibidas.' -ForegroundColor Cyan
        Write-Host 'Use -Mode publish para verificar arquivos e publicar com confirmacao.' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'COMANDOS PARA SINCRONIZAR' -ForegroundColor Magenta
        Write-Host '  SUBIR skills e MCPs para o GitHub:' -ForegroundColor Yellow
        Write-Host '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode publish' -ForegroundColor White
        Write-Host ''
        Write-Host '  PUXAR e instalar do GitHub nesta maquina:' -ForegroundColor Yellow
        Write-Host '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode install' -ForegroundColor White
        Write-Host ''
    }
    publish {
        Ensure-Repo
        & git -C $root pull --rebase; if ($LASTEXITCODE -ne 0) { throw 'Git pull falhou. Resolva o conflito antes de publicar.' }
        $localSkills=@(Get-SkillSources)
        $mcps=@(Read-Mcps)
        $tmp = Join-Path $root ('.stage-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $tmpSkills = Join-Path $tmp 'skills'
            New-Item -ItemType Directory -Path $tmpSkills | Out-Null
            foreach ($skill in $localSkills) {
                $files = @(Get-ChildItem -LiteralPath $skill.FullName -Recurse -File -Force)
                foreach ($dir in @(Get-ChildItem -LiteralPath $skill.FullName -Recurse -Directory -Force)) {
                    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Link de diretorio nao permitido: $($dir.FullName)" }
                }
                foreach ($file in $files) { Check-SkillFile $file }
                $namespace = Join-Path $tmpSkills $skill.Location
                New-Item -ItemType Directory -Path $namespace -Force | Out-Null
                $target = Join-Path $namespace $skill.Name
                Copy-Item -LiteralPath $skill.FullName -Destination $target -Recurse
            }
            $mcps | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $tmp 'mcps.json') -Encoding UTF8
            New-Item -ItemType Directory -Path $payload -Force | Out-Null
            New-Item -ItemType Directory -Path $skillDst -Force | Out-Null
            # Preserva skills compartilhadas por outros PCs; atualiza apenas nomes locais.
            foreach ($skill in $localSkills) {
                $namespace = Join-Path $skillDst $skill.Location
                New-Item -ItemType Directory -Path $namespace -Force | Out-Null
                $target = Join-Path $namespace $skill.Name
                if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
                Copy-Item -LiteralPath (Join-Path (Join-Path $tmpSkills $skill.Location) $skill.Name) -Destination $target -Recurse
            }
            $allMcps=@{}
            if (Test-Path $manifestFile) {
                foreach ($m in @(Get-Content $manifestFile -Raw | ConvertFrom-Json)) { if ($m.name) { $allMcps[$m.name]=$m } }
            }
            foreach ($m in $mcps) { $allMcps[$m.name]=$m }
            @($allMcps.Values | Sort-Object name) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestFile -Encoding UTF8
            & git -C $root add -- package/skills package/mcps.json
            & git -C $root diff --cached --quiet
            if ($LASTEXITCODE -eq 0) { Write-Host 'Sem alteracoes para publicar.'; break }
            Write-Host 'Revisao do diff antes do envio:'
            & git -C $root diff --cached --stat
            $answer=Read-Host 'Conferiu que nao ha dados pessoais/sensiveis? Digite PUBLICAR para enviar'
            if ($answer -cne 'PUBLICAR') { & git -C $root reset -- package/skills package/mcps.json | Out-Null; throw 'Publicacao cancelada.' }
            & git -C $root commit -m "sync: atualizar skills e MCPs seguros"
            if ($LASTEXITCODE -ne 0) { throw 'Commit falhou.' }
            & git -C $root push
            if ($LASTEXITCODE -ne 0) { throw 'Push falhou; commit ficou apenas local.' }
            Write-Host 'Publicado no GitHub.'
        } finally { if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force } }
    }
    install {
        Ensure-Repo
        & git -C $root pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw 'Git pull falhou.' }
        if (Test-Path $skillDst) {
            foreach ($location in @('codex','agents')) {
                $sourceRoot = Join-Path $skillDst $location
                if (-not (Test-Path $sourceRoot)) { continue }
                $destinationRoot = if ($location -eq 'agents') { $agentsSkillsRoot } else { $skillsRoot }
                New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
                foreach ($skill in @(Get-ChildItem -LiteralPath $sourceRoot -Directory)) {
                    $dest=Join-Path $destinationRoot $skill.Name
                    if (Test-Path $dest) {
                        Write-Warning "Skill ja existe; ignorando para nao sobrescrever: $($location)/$($skill.Name)"
                        continue
                    }
                    Copy-Item -LiteralPath $skill.FullName -Destination $dest -Recurse
                    Write-Host "Skill instalada: $($location)/$($skill.Name)"
                }
            }
        }
        if (Test-Path $manifestFile) {
            $mcps=@(Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json)
            $installed=@(Read-Mcps | ForEach-Object { $_.name })
            $codex=Get-Command codex -ErrorAction SilentlyContinue
            foreach ($m in $mcps) {
                if (-not $m.name -or $m.name -notmatch '^[A-Za-z0-9_-]+$' -or -not (Test-SafeArg $m.command)) { continue }
                if ($installed -contains $m.name) { Write-Host "MCP existente, mantido: $($m.name)"; continue }
                if (@($m.args | Where-Object { -not (Test-SafeArg $_) }).Count) { continue }
                if (-not $codex) { Write-Warning "Codex CLI indisponivel; MCP pendente: $($m.name)"; continue }
                Write-Host "MCP disponivel: $($m.name) - $($m.command) $($m.args -join ' ')"
                if ((Read-Host 'Registrar este MCP? Digite SIM') -cne 'SIM') { continue }
                & codex mcp add $m.name -- $m.command @($m.args)
                if ($LASTEXITCODE -ne 0) { Write-Warning "Falha ao registrar MCP: $($m.name)" }
            }
        }
        Write-Host 'Concluido. Dependencias e logins dos MCPs devem ser configurados localmente.'
    }
}
