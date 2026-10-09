# infra-scripts

Ferramentas de terminal compartilhadas pelos repositórios Solierrr. Este
repositório não é uma aplicação e não produz imagem Docker: os scripts são
instalados uma vez por máquina e chamados pelos Makefiles de cada projeto.

## Instalação

O `Makefile` de cada projeto já resolve isso sozinho: `make extract-env`
encadeia `make vault-config`, que clona este repositório (ele é público) em
`ORG_SCRIPTS_DIR` na primeira execução e faz `git pull --ff-only` nas
seguintes. Não é preciso clonar manualmente.

Instalação/atualização manual continuam possíveis quando preciso:

```powershell
git clone https://github.com/Solierrr/infra-scripts.git "$env:USERPROFILE/.local/share/solierrr-infra-scripts"
git -C "$env:USERPROFILE/.local/share/solierrr-infra-scripts" pull --ff-only
```

Cada projeto declara o caminho em `ORG_SCRIPTS_DIR` e disponibiliza os atalhos
adequados no seu próprio `Makefile`. Consulte
`docs-warehouse/templates/make/README.md` para o contrato de integração
(`vault-config` / `vault-auth` / `extract-env`).

Sem parâmetros, `make extract-env` mostra menus numerados para escolher o serviço e o ambiente. Também é possível informar um ou ambos diretamente:

```powershell
make extract-env SERVICE=database-console ENV=qa
make extract-env SERVICE=api-core
```

A opção “Todos os serviços” exporta todas as pastas mapeadas e deve ser escolhida explicitamente. Se uma pasta não retornar nenhuma variável, o script informa o ambiente e o caminho e mantém o `.env` existente intacto.
No Windows, o script prioriza `infisical.exe` para evitar shims npm inválidos no PowerShell. Se o CLI só conseguir responder com segredos do cache após uma falha de conexão, a extração é interrompida sem substituir o arquivo local.

## Scripts

### `extract-env.ps1`

Extrai os segredos do Infisical para um arquivo dotenv a partir das pastas de
que cada serviço depende. Requer Infisical CLI instalado e sessão autenticada
(`infisical login`).

```powershell
./scripts/extract-env.ps1
./scripts/extract-env.ps1 -Service api-core -Environment local -OutputPath .env
```

Sem argumentos, o script pergunta o serviço e o ambiente em menus numerados. O script mantém o mapa de serviço → pastas neste repositório, portanto toda
mudança de dependência de segredo é revisável e chega igualmente aos projetos
que atualizarem a ferramenta.

Scripts que operam um recurso específico — Terraform, GKE, ArgoCD ou state —
continuam no repositório proprietário desse recurso.

## Rodar um serviço localmente

`scripts/local.sh` sobe um serviço da Solaria na sua máquina a partir da imagem do Docker Hub. Quem chama é o fragmento `local.mk` (`docs-warehouse/templates/make/`), com `make up`, `make down` e `make logs`. O guia para quem só quer usar está em `docs-warehouse/helps/TRY-LOCAL.md`.

```bash
make up                 # imagem do Docker Hub, segredos de qa, bancos remotos
make up DB=local        # PostgreSQL (e Neo4j no api-recommendation) em containers
make up OBS=1           # Grafana local e Collector, com a telemetria do serviço ligada
make up BUILD=1         # constrói a imagem do Dockerfile do repositório
make down ALL=1         # para o serviço, os bancos e o Grafana
```

Como funciona:

- Os segredos vêm de `infisical export` com a sua conta (`infisical login`), gravados num arquivo temporário com permissão restrita e apagados ao final. Não há credencial de máquina. `ENV_FILE=caminho` usa um arquivo no lugar do Infisical.
- `compose/service.yaml` roda o serviço, e `compose/deps.yaml` traz o PostgreSQL e o Neo4j locais. Tudo usa a rede externa `local`, criada pelo script.
- Em `DB=local`, o schema vem do `database-console` (`LOCAL_DB_CONSOLE_REF`, por padrão `main`) e o Neo4j é populado pelo `database-bootstrap`.
- Em `OBS=1`, o script clona o `infra-otel-collector` e sobe o `local/compose.yaml` dele. `OBS_DIR` aponta para uma cópia local.
- `docker-push` publica só tags de desenvolvimento e recusa `latest`, `main`, `qa` e tags de versão.
- Quando o Infisical falha, o script explica o que verificar e aponta para o `TRY-LOCAL.md`.

Variáveis: `SERVICE`, `ENV` (padrão `qa`), `DB` (`remote` ou `local`), `OBS`, `BUILD`, `ALL`, `TAG`, `HOST_PORT`, `CONTAINER_PORT`, `ENV_FILE`, `OBS_DIR`, `LOCAL_STATE_DIR`, `LOCAL_DB_CONSOLE_REF`.

## Vários serviços e cluster local

- `scripts/local.sh stack` sobe um perfil de serviços (`PROFILE=core|rec|ai|all`), chamando o `up` de cada um com a porta do host e a do container, e `unstack` para.
- `scripts/cluster.sh` cria e gerencia um cluster k3d chamado `local` com o Argo CD (`up`, `down`, `status`, `apps`, `secrets`, `password`, `ui`). O k3d roda em um container (`ghcr.io/k3d-io/k3d`), então não precisa ser instalado. Todo `kubectl` usa o kubeconfig `kubeconfig-local` do diretório de estado e o contexto `k3d-local`; o contexto padrão da máquina nunca é usado.
- O Argo CD é instalado na versão do `infra-platform` (`ARGOCD_VERSION`, padrão `v3.5.2`). As `Application` vêm da `main` do `infra-gitops` (`INFRA_GITOPS_DIR` aponta para uma cópia local).
- Os comandos `make` equivalentes estão no fragmento `stack.mk` do `docs-warehouse`.
