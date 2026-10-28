param(
    [ValidateSet('scan','publish','install','register')][string]$Mode = 'scan',
    [string]$Skill,
    [string]$Source,
    [ValidateSet('agents','codex')][string]$Location = 'agents',
    [string]$Repository = 'https://github.com/pjz3650/codex-mcp-skill-transfer.git'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$skillsRoot = Join-Path $codexHome 'skills'
$agentsSkillsRoot = Join-Path (Join-Path $HOME '.agents') 'skills'
$payload = Join-Path $root 'package'
$skillsManifest = Join-Path $payload 'skills.json'
$localSources = Join-Path $root 'skill-sources.local.json'
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
function ValidSource($url) {
    return ($url -match '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$')
}
function Read-Sources {
    $map = @{}
    foreach ($file in @($skillsManifest,$localSources)) {
        if (-not (Test-Path $file)) { continue }
        foreach ($entry in @(Get-Content $file -Raw | ConvertFrom-Json)) {
            if ($entry.name -and $entry.location -and (ValidSource $entry.source)) {
                $map["$($entry.location)/$($entry.name)"] = $entry
            }
        }
    }
    return $map
}
function Find-SkillOrigin($skill) {
    # Somente fontes explicitas e verificaveis. Links soltos em tutoriais nao sao proveniencia.
    $gitDir = Join-Path $skill.FullName '.git'
    if (Test-Path $gitDir) {
        $remote = (& git -C $skill.FullName remote get-url origin 2>$null)
        if ($LASTEXITCODE -eq 0 -and $remote -match '^https://github\.com/[^/\s]+/[^/\s]+(?:\.git)?$') {
            $url = $remote.Trim() -replace '\.git$',''
            if (ValidSource $url) { return $url }
        }
    }
    # Frontmatter do SKILL.md: somente chaves canonicas explicitas de origem.
    $doc = Join-Path $skill.FullName 'SKILL.md'
    if (Test-Path $doc) {
        $lines = @(Get-Content -LiteralPath $doc -TotalCount 100 -Encoding UTF8)
        if ($lines.Count -gt 1 -and $lines[0].Trim() -eq '---') {
            foreach ($line in $lines[1..($lines.Count-1)]) {
                if ($line.Trim() -eq '---') { break }
                if ($line -match '^\s*(?:source_repository|source_repo|repository_url)\s*:\s*["'']?(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?)["'']?\s*$') {
                    $url = $Matches[1] -replace '\.git$',''
                    if (ValidSource $url) { return $url }
                }
            }
        }
    }
    return $null
}
function Resolve-Sources($skills) {
    $sources = Read-Sources
    foreach ($skill in $skills) {
        $key="$($skill.Location)/$($skill.Name)"
        if (-not $sources.ContainsKey($key)) {
            $url=Find-SkillOrigin $skill
            if ($url) { $sources[$key]=[pscustomobject]@{name=$skill.Name;location=$skill.Location;source=$url} }
        }
    }
    return $sources
}
function Print-Commands {
    Write-Host 'SUBIR: powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode publish'
    Write-Host 'PUXAR: powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode install'
    Write-Host 'ORIGEM: .\sync-codex.ps1 -Mode register -Skill NOME -Source https://github.com/USUARIO/REPO'
}
switch ($Mode) {
    register {
        if ($Skill -notmatch '^[A-Za-z0-9_.-]+$' -or -not (ValidSource $Source)) { throw 'Informe -Skill NOME -Source https://github.com/USUARIO/REPO e opcionalmente -Location agents|codex.' }
        if (-not @(Get-SkillSources | Where-Object { $_.Name -eq $Skill -and $_.Location -eq $Location }).Count) { throw 'Skill local nao encontrada.' }
        $entries = @()
        if (Test-Path $localSources) { $entries = @(Get-Content $localSources -Raw | ConvertFrom-Json | Where-Object { -not ($_.name -eq $Skill -and $_.location -eq $Location) }) }
        $entries += [pscustomobject]@{name=$Skill;location=$Location;source=$Source}
        ConvertTo-Json -InputObject @($entries) -Depth 5 | Set-Content $localSources -Encoding UTF8
        Write-Host "Fonte registrada: $Location/$Skill -> $Source" -ForegroundColor Green
    }
    scan {
        $sources=Resolve-Sources @(Get-SkillSources)
        Write-Host '======== SKILLS ========' -ForegroundColor Cyan
        foreach ($skill in @(Get-SkillSources | Sort-Object Location,Name)) {
            $key="$($skill.Location)/$($skill.Name)"
            if ($sources.ContainsKey($key)) {
                $item=$sources[$key]
                Write-Host "[COMANDO] $key : npx --yes skills add $($item.source) --skill $($item.name) --global --yes" -ForegroundColor Green
            } else {
                Write-Host "[ORIGEM DESCONHECIDA] $key" -ForegroundColor Yellow
            }
        }
        $mcps=@(Read-Mcps)
        Write-Host "======== MCPs exportaveis: $($mcps.Count) ========" -ForegroundColor Cyan
        foreach ($m in $mcps) { Write-Host "$($m.name): $($m.command)" }
        Print-Commands
    }
    publish {
        Ensure-Repo
        & git -C $root pull --rebase
        if ($LASTEXITCODE -ne 0) { throw 'git pull falhou.' }
        $sources=Resolve-Sources @(Get-SkillSources)
        $export=@{}
        if (Test-Path $skillsManifest) {
            foreach ($item in @(Get-Content $skillsManifest -Raw | ConvertFrom-Json)) {
                if ($item.name -and $item.location -and (ValidSource $item.source)) { $export["$($item.location)/$($item.name)"]=$item }
            }
        }
        foreach ($skill in @(Get-SkillSources)) {
            $key="$($skill.Location)/$($skill.Name)"
            if ($sources.ContainsKey($key)) { $export[$key]=$sources[$key] }
            else { Write-Host "Sem origem (nao exportada): $key" -ForegroundColor Yellow }
        }
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        ConvertTo-Json -InputObject @($export.Values | Sort-Object location,name) -Depth 5 | Set-Content $skillsManifest -Encoding UTF8
        $allMcps=@{}
        if (Test-Path $manifestFile) { foreach ($m in @(Get-Content $manifestFile -Raw | ConvertFrom-Json)) { if ($m.name) { $allMcps[$m.name]=$m } } }
        foreach ($m in @(Read-Mcps)) { $allMcps[$m.name]=$m }
        ConvertTo-Json -InputObject @($allMcps.Values | Sort-Object name) -Depth 10 | Set-Content $manifestFile -Encoding UTF8
        & git -C $root rm -r --ignore-unmatch -- package/skills
        & git -C $root add -- package/skills.json package/mcps.json
        & git -C $root diff --cached --stat
        & git -C $root diff --cached --quiet
        if ($LASTEXITCODE -eq 0) { Write-Host 'Sem mudancas.'; break }
        if ((Read-Host 'Revise as fontes e MCPs. Digite PUBLICAR para fazer push') -cne 'PUBLICAR') {
            & git -C $root reset HEAD -- package/skills package/skills.json package/mcps.json | Out-Null
            throw 'Cancelado.'
        }
        & git -C $root commit -m 'sync: manifestos de instalacao sem arquivos de skills'
        if ($LASTEXITCODE -ne 0) { throw 'Commit falhou.' }
        & git -C $root push
        if ($LASTEXITCODE -ne 0) { throw 'Push falhou.' }
        Write-Host 'Publicado: apenas manifestos, nenhuma pasta de skills.' -ForegroundColor Green
    }
    install {
        Ensure-Repo
        & git -C $root pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw 'git pull falhou.' }
        if (Test-Path $skillsManifest) {
            foreach ($item in @(Get-Content $skillsManifest -Raw | ConvertFrom-Json)) {
                if (-not $item.name -or $item.name -notmatch '^[A-Za-z0-9_.-]+$' -or -not (ValidSource $item.source)) { continue }
                if (@(Get-SkillSources | Where-Object { $_.Name -eq $item.name }).Count) { Write-Host "Ja existe: $($item.name)"; continue }
                Write-Host "Instalar: npx --yes skills add $($item.source) --skill $($item.name) --global --yes"
                if ((Read-Host 'Executar instalacao de codigo externo? Digite SIM') -cne 'SIM') { continue }
                if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { Write-Warning 'npx ausente: instale Node.js/npm.'; continue }
                & npx --yes skills add $item.source --skill $item.name --global --yes
                if ($LASTEXITCODE -ne 0) { Write-Warning "Falha: $($item.name)" }
            }
        }
        if (Test-Path $manifestFile) {
            $installed=@(Read-Mcps | ForEach-Object { $_.name })
            foreach ($m in @(Get-Content $manifestFile -Raw | ConvertFrom-Json)) {
                if (-not $m.name -or $m.name -notmatch '^[A-Za-z0-9_-]+$' -or -not (Test-SafeArg $m.command)) { continue }
                if ($installed -contains $m.name) { continue }
                if (@($m.args | Where-Object { -not (Test-SafeArg $_) }).Count) { continue }
                Write-Host "MCP: $($m.name) ($($m.command))"
                if ((Read-Host 'Registrar este MCP? Digite SIM') -cne 'SIM') { continue }
                & codex mcp add $m.name -- $m.command @($m.args)
                if ($LASTEXITCODE -ne 0) { Write-Warning "Falha MCP: $($m.name)" }
            }
        }
        Write-Host 'Concluido. Dependencias e credenciais de MCPs sao locais.'
    }
}
