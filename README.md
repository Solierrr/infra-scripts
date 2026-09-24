# infra-scripts

Ferramentas de terminal compartilhadas pelos repositórios Solierrr. Este
repositório não é uma aplicação e não produz imagem Docker: os scripts são
instalados uma vez por máquina e chamados pelos Makefiles de cada projeto.

## Instalação

```powershell
git clone https://github.com/Solierrr/infra-scripts.git "$env:USERPROFILE/.local/share/solierrr-infra-scripts"
```

Para receber uma nova versão, atualize quando for conveniente:

```powershell
git -C "$env:USERPROFILE/.local/share/solierrr-infra-scripts" pull --ff-only
```

Cada projeto declara o caminho em `ORG_SCRIPTS_DIR` e disponibiliza os atalhos
adequados no seu próprio `Makefile`. Consulte
`docs-warehouse/templates/make/README.md` para o contrato de integração.

## Scripts

### `extract-env.ps1`

Extrai os segredos do Infisical para um arquivo dotenv a partir das pastas de
que cada serviço depende. Requer Infisical CLI instalado e sessão autenticada
(`infisical login`).

```powershell
./scripts/extract-env.ps1 -Service api-core -Environment local -OutputPath .env
```

O script mantém o mapa de serviço → pastas neste repositório, portanto toda
mudança de dependência de segredo é revisável e chega igualmente aos projetos
que atualizarem a ferramenta.

Scripts que operam um recurso específico — Terraform, GKE, ArgoCD ou state —
continuam no repositório proprietário desse recurso.
