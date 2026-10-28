# Handoff técnico — Codex MCP & Skill Transfer

**Data:** 28/10/2026  
**Repositório:** https://github.com/pjz3650/codex-mcp-skill-transfer  
**Destino:** agente Codex que vai auditar, corrigir, testar e completar o projeto.

## 1. Proposta original

Criar um mecanismo para inventariar e transferir **skills e servidores MCP configurados no Codex entre computadores Windows**, usando um repositório GitHub privado como fonte compartilhada.

Fluxo pretendido:

1. Em qualquer computador com Codex instalado, executar um comando de **scan** que liste no próprio PowerShell todas as skills e MCPs descobertos.
2. Executar **publish** para atualizar o GitHub com dados suficientes para reconstruir a instalação na outra máquina.
3. Executar **install** em outro computador para baixar o inventário e instalar só os componentes ausentes.
4. Não publicar credenciais, tokens, variáveis de ambiente, arquivos de autenticação nem outros dados sensíveis.
5. Evitar copiar pastas completas das skills. **A decisão mais recente foi publicar apenas informações/comandos de instalação**, com suas fontes confiáveis, e preservar MCPs apenas quando sua definição for segura.
6. Em evolução futura, detectar mudanças e manter o repositório atualizado automaticamente, com distribuição entre PCs, evitando conflitos e solicitações repetitivas.

O projeto **não é um repositório central de todas as skills**. O repositório `codex-mcp-skill-transfer` serve somente para os scripts e manifestos. Cada skill pode ter origem em um repositório diferente.

## 2. Diretórios a inspecionar

- `$HOME\.agents\skills`
- `$env:CODEX_HOME\skills` (se `CODEX_HOME` existir), senão `$HOME\.codex\skills`
- MCPs configurados no `config.toml` do Codex (não publicar o arquivo original)

Opcional futuro: skills locais por projeto, sob raízes explicitamente escolhidas pelo usuário. **Não varrer indiscriminadamente todo o disco**.

O `scan` precisa apresentar os nomes, caminhos lógicos, status e totais **direto no terminal**; não abrir o Bloco de Notas nem depender de um relatório externo.

## 3. Mudanças já feitas (histórico)

1. Criado `sync-codex.ps1`, com modos `scan`, `publish` e `install`, além de README e regras de Git.
2. Incluída a detecção de `~/.agents/skills` e `~/.codex/skills`.
3. Melhorado o relatório do `scan` com listagem, status de MCP e comandos para publicar/instalar.
4. O primeiro desenho copiava arquivos das skills. Isso gerou bloqueios em `LICENSE`, em documentação com termos parecidos com credenciais (`impeccable/reference/polish.md`) e em scripts executáveis sem extensão (`impeccable/scripts/impeccable`).
5. Por decisão posterior, **foi removida a cópia de conteúdo das skills**. Foi introduzido `package/skills.json` para guardar nome, localização lógica e origem de instalação; `package/mcps.json` contém MCPs exportáveis.
6. Adicionado modo `register`, com `skill-sources.local.json` para cadastro manual de fonte, e tentativas automáticas de achar origem pelo remote Git de uma skill ou por campos explícitos de frontmatter de `SKILL.md`.
7. Corrigida a apresentação dos comandos para usar caminho absoluto do script e bloqueado o próprio repositório de sincronização como fonte de uma skill.
8. Os commits publicados durante essa evolução incluem `f62462f` (autodescoberta), `d883ae6` (correção de origem circular), entre outros. **Não tomar a existência de commits como prova de funcionamento**.

## 4. Estado atual confirmado e limitações

Foi consultado o conteúdo atual de `sync-codex.ps1` no GitHub. O script implementa os modos `scan`, `publish`, `install` e `register`, mas **a execução completa em Windows ainda não foi validada**.

Pontos de atenção:

- Não é possível inferir a origem verdadeira de toda skill a partir do diretório de instalação. Sem metadados ou histórico confiável, marcar **origem desconhecida**, não inventar um URL.
- O comando genérico `npx --yes skills add <url> --skill <nome> --global --yes` pode não reproduzir exatamente o método, a versão e a localização da instalação original. Confirmar a sintaxe real e a compatibilidade antes de executar.
- Alguns MCPs têm configurações remotas (HTTP/SSE), comandos locais, dependências, caminhos específicos ou parâmetros que precisam de autenticação; a exportação atual cobre apenas um subconjunto simples.
- Não afirmar que nenhum dado sensível pode vazar apenas por existir um filtro de regex. Tratar conteúdo e argumentos como potencialmente sensíveis, reduzir o que é armazenado, permitir revisão antes do push e nunca imprimir segredos.
- Registro no `skills.json` não garante que a skill esteja disponível ou que o pacote seja íntegro. Validar a fonte e a identidade da skill.
- O script não faz sincronização automática bidirecional: a versão atual depende de comandos manuais.
- Se em alguma versão anterior houve envio de arquivos sensíveis, retirá-los do HEAD não basta; avaliar histórico Git e rotação das credenciais.
- O arquivo `sync-codex.ps1` no repositório parece excepcionalmente grande para essa função (aprox. 52 KB ao ser lido nesta data). **Auditar estrutura, duplicações e sintaxe antes de adicionar funcionalidades.**

## 5. Requisitos para o Codex concluir o trabalho

### Prioridade P0 — Correção e segurança

- Fazer auditoria completa do repositório e da branch `main`; verificar sintaxe PowerShell, fluxo Git, arquivos rastreados, `.gitignore`, e possíveis regressões/código duplicado.
- Confirmar se `publish` realmente **não publica** nenhuma pasta ou conteúdo das skills; somente manifestos mínimos. Remover do índice conteúdo legado que contrarie esse requisito, com cautela.
- Evitar declarar como origem de todas as skills o repositório central de transferência.
- Criar política explícita para detectar origem por evidências confiáveis e registrar a procedência. Diferenciar `detectado`, `cadastrado manualmente` e `desconhecido`.
- Evitar publicar dados pessoais, caminhos absolutos locais, endpoints internos, URLs com credenciais e parâmetros sensíveis.
- Não executar silenciosamente comandos de terceiros nem sobrescrever configurações existentes.

### Prioridade P1 — Experiência funcional

- `scan`: painel legível no PowerShell, com skills dos dois diretórios, origem por skill, MCPs exportáveis/pendentes, números totais e comandos prontos para copiar.
- `publish`: construir manifestos determinísticos, mostrar diff/resumo, solicitar confirmação, commit e push para o repo privado; não confundir falta de origem com sucesso de exportação.
- `install`: git pull, comparar com a máquina de destino e reinstalar somente itens ausentes, confirmar fontes e comandos e relatar êxito/falha por item.
- Manter nomes e origens individuais, evitar colisões, trabalhar com entradas ausentes ou JSON vazio.
- Suportar execução com `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "CAMINHO_COMPLETO\sync-codex.ps1" -Mode scan`, sem depender de associação do Windows para arquivos `.ps1`.
- Evitar alterar permanentemente ExecutionPolicy e documentar riscos de executar scripts não assinados.

### Prioridade P2 — Qualidade e evolução

- Testes automatizados de parser/validador de MCPs, geração de manifestos, fontes com nomes colidentes, arquivos ausentes, URLs maliciosas, credenciais e erros de git.
- Testes em PowerShell 5.1 e 7 quando possível; validação em Windows real.
- Registrar as dependências necessárias e as etapas de login do MCP sem exportar segredos.
- Considerar modo automático posterior, mas com mecanismo de conflitos, alterações em múltiplos PCs e publicação segura.

## 6. Critérios de aceite

1. `scan` lista todas as skills detectadas nos dois diretórios, mesmo quando não possuem origem identificada.
2. Cada skill com fonte confiável tem URL própria e comando de instalação correspondente; uma sem fonte confiável aparece como pendente.
3. `publish` não lê nem envia o conteúdo das pastas das skills; publica somente metadados mínimos e MCPs sanitizados.
4. `install` não sobrescreve componentes existentes, requer confirmação antes de executar instalações externas e informa pendências.
5. Nenhuma credencial conhecida ou dado secreto de teste aparece em commits gerados.
6. O repositório central nunca é usado automaticamente como fonte de instalação de skills.
7. Os comandos impressos em `scan` executam corretamente no PowerShell.
8. Há testes e evidências dos cenários de sucesso e erro.
9. README corresponde ao comportamento efetivamente implementado.

## 7. Instrução direta ao agente Codex

> Inspecione todo o repositório existente, principalmente `sync-codex.ps1` e os manifestos. **Não presuma que a implementação anterior está correta.** Faça uma auditoria, corrija defeitos, torne a descoberta de origem conservadora e verificável, implemente/teste o fluxo ponta a ponta e documente claramente o que é automatizado e o que permanece manual. Preserve a regra principal: **não subir os arquivos internos das skills; subir somente referências/comandos confiáveis de instalação e definições seguras dos MCPs**. Não invente fontes nem exponha segredos. Antes de concluir, execute testes, revise o diff e entregue um resumo das alterações, evidências de validação e limitações remanescentes.
