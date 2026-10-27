# Codex MCP & Skill Transfer

Sincroniza **referências de instalação** de skills e definições seguras de MCP. **Não publica nenhum arquivo das skills**.

## Uso (PowerShell no diretório do clone)

```powershell
git pull
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode scan
```

Skills podem conter qualquer tipo de arquivo, e a instalação original não fica necessariamente registrada. Assim, quando a origem não for conhecida, o scan mostra **ORIGEM DESCONHECIDA**, e você cadastra a URL real do repositório que disponibiliza a skill:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode register -Skill impeccable -Location agents -Source https://github.com/USUARIO/REPO
```

Substitua a URL por uma **origem verificada**. Não presuma que o nome da skill equivale ao nome do repositório. O arquivo `skill-sources.local.json` fica apenas no PC.

Para publicar as referências e MCPs seguros (com confirmação):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode publish
```

No outro computador, para puxar e instalar (com confirmação individual):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\sync-codex.ps1" -Mode install
```

## Arquivos publicados

- `package/skills.json`: nome da skill, origem GitHub e localização original
- `package/mcps.json`: somente MCPs de comando com argumentos que passaram pelo filtro

## Limitações e segurança

- Não compartilha pastas `~/.agents/skills` ou `~/.codex/skills`, somente fontes para reinstalação.
- Skills locais, privadas ou sem origem cadastrada ficam pendentes; não são copiadas nem instaladas automaticamente.
- Usa `npx --yes skills add URL --skill NOME --global --yes`; a localização da instalação fica a cargo da CLI `skills`, não necessariamente preserva `agents/codex`.
- A instalação de skills executa código de terceiros: confirme somente URLs confiáveis.
- O filtro de MCPs é conservador, mas não garante detectar toda informação sensível. Revise o diff antes de publicar.
- Os MCPs podem exigir login, ambiente, dependências e parâmetros locais.
- A execução não é automática em segundo plano.
- Se já tiverem sido publicados arquivos de skills antes desta versão, a remoção do índice atual **não os apaga do histórico Git**. Examine o histórico e remova segredos que tenham vazado, inclusive revogando credenciais comprometidas.
