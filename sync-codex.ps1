param(
    [ValidateSet('scan','publish','install')][string]$Mode = 'scan',
    [string]$Repository = 'https://github.com/pjz3650/codex-mcp-skill-transfer.git'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$skillsRoot = Join-Path $codexHome 'skills'
$payload = Join-Path $root 'package'
$skillDst = Join-Path $payload 'skills'
$manifestFile = Join-Path $payload 'mcps.json'

function Assert-Tools {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git nao encontrado. Instale Git for Windows e autentique com GitHub.' }
}
function Test-Private([string]$value) {
    return ($value -match '(?i)(gh[pousr]_[A-Za-z0-9_]+|github_pat_|sk-[A-Za-z0-9_-]{15,}|AIza[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----|mongodb(\+srv)?://|postgres(ql)?://|https?://[^/\s:@]+:[^/\s@]+@|(?i:password|secret|token|api[_-]?key|authorization)\s*[:=]\s*\S+)' )
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
    if (-not (Test-Path $skillsRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $skillsRoot -Directory -Force | Where-Object {
        $_.Name -ne '.system' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
    })
}
function Check-SkillFile($file) {
    $ext = [IO.Path]::GetExtension($file.Name).ToLowerInvariant()
    $allowed = @('.md','.txt','.json','.yaml','.yml','.toml','.py','.ps1','.js','.ts','.sh','.html','.css','.xml','.csv')
    if ($allowed -notcontains $ext) { throw "Arquivo nao permitido: $($file.FullName)" }
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
        Write-Host "CODEX_HOME: $codexHome"
        Write-Host "Skills exportaveis (diretorios): $($localSkills.Count)"
        $localSkills | ForEach-Object { Write-Host "  skill: $($_.Name)" }
        Write-Host "MCPs de comando sem parametros sensiveis: $($mcps.Count)"
        $mcps | ForEach-Object { Write-Host "  mcp: $($_.name)" }
        Write-Host 'MCPs HTTP/SSE e configs complexas nao sao exportados automaticamente.'
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
                $target = Join-Path $tmpSkills $skill.Name
                Copy-Item -LiteralPath $skill.FullName -Destination $target -Recurse
            }
            $mcps | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $tmp 'mcps.json') -Encoding UTF8
            New-Item -ItemType Directory -Path $payload -Force | Out-Null
            New-Item -ItemType Directory -Path $skillDst -Force | Out-Null
            # Preserva skills compartilhadas por outros PCs; atualiza apenas nomes locais.
            foreach ($skill in $localSkills) {
                $target = Join-Path $skillDst $skill.Name
                if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
                Copy-Item -LiteralPath (Join-Path $tmpSkills $skill.Name) -Destination $target -Recurse
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
            New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
            foreach ($skill in @(Get-ChildItem $skillDst -Directory)) {
                $dest=Join-Path $skillsRoot $skill.Name
                if (Test-Path $dest) {
                    Write-Warning "Skill ja existe; ignorando para nao sobrescrever: $($skill.Name)"
                    continue
                }
                Copy-Item -LiteralPath $skill.FullName -Destination $dest -Recurse
                Write-Host "Skill instalada: $($skill.Name)"
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
