# Codex MCP & Skill Transfer

Sincronização **manual e revisada** de skills e configurações de MCP entre PCs Windows por repositório Git privado.

## Requisitos

- Git for Windows autenticado no GitHub, com acesso a este repositório privado
- Codex instalado (o CLI \`codex\` é necessário para registrar MCPs)
- PowerShell 5.1 ou mais recente

## Primeira instalação em cada computador

\`\`\`powershell
git clone https://github.com/pjz3650/codex-mcp-skill-transfer.git
cd codex-mcp-skill-transfer
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-codex.ps1 -Mode scan
\`\`\`

Depois, **no PC de origem**:

\`\`\`powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-codex.ps1 -Mode publish
\`\`\`

E **no PC de destino**:

\`\`\`powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-codex.ps1 -Mode install
\`\`\`

## Estrutura

- \`sync-codex.ps1\`: inventário, publicação e instalação.
- \`package/skills/\`: skills compartilhadas (apenas arquivos texto permitidos).
- \`package/mcps.json\`: nomes, comandos e argumentos **não sensíveis** de MCPs locais.

## Segurança e limitações

- **O script NÃO envia** \`config.toml\`, \`auth.json\`, arquivos \`.env\`, tokens, senhas nem variáveis \`env\` dos MCPs.
- Skills com arquivos de extensão não permitida, links simbólicos, tamanho excessivo ou padrões evidentes de credenciais **bloqueiam a publicação**.
- **Não é garantia absoluta de ausência de segredos.** Antes do push, revise as skills e o diff; só publique ao digitar \`PUBLICAR\`.
- MCPs HTTP/SSE, configurações complexas e credenciais não são exportados automaticamente. URLs sensíveis e argumentos suspeitos são omitidos.
- Instalar MCP apenas registra seu comando, com confirmação individual: dependências (ex.: \`npx\`, \`uvx\`) e autenticação devem existir no destino.
- Skills existentes no destino não são sobrescritas. O publish preserva skills de outros PCs que já estejam no repositório.
- Não apaga skills ou MCPs removidos da máquina de origem.
- O repositório é **privado**; não o torne público sem auditoria.
- O script não agenda tarefas nem executa sincronização em segundo plano. Rode publish após instalar algo e install no outro PC.
- Execute apenas scripts e skills de origem confiável, pois podem conter código executável.

> Teste inicial sugerido: crie uma skill sem dados sensíveis, publique, instale no segundo computador e confira o resultado.
