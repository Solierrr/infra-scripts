#!/bin/sh
# Cluster Kubernetes local (k3d) com Argo CD para validar o infra-gitops.
# Chamado pelo fragmento local.mk (docs-warehouse/templates/make). Uso:
#   sh cluster.sh up|down|status|apps <nome...>|secrets <serviço...>|password|ui
#
# Todo kubectl usa um kubeconfig próprio e o contexto k3d-local. O contexto padrão
# da máquina (por exemplo o do GKE) nunca é tocado.
set -eu

MSYS_NO_PATHCONV=1
export MSYS_NO_PATHCONV

CMD=${1:-help}
[ "$#" -gt 0 ] && shift

CLUSTER=${CLUSTER_NAME:-local}
CONTEXT="k3d-$CLUSTER"
API_PORT=${CLUSTER_API_PORT:-6550}
K3D_IMAGE=${K3D_IMAGE:-ghcr.io/k3d-io/k3d:5.8.3}
ARGOCD_VERSION=${ARGOCD_VERSION:-v3.5.2}
STATE=${LOCAL_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/solierrr-local}
KUBECONFIG_FILE="$STATE/kubeconfig-$CLUSTER"
GITOPS_RAW=${INFRA_GITOPS_RAW:-https://raw.githubusercontent.com/Solierrr/infra-gitops/main}
ENV=${ENV:-qa}
INFISICAL_PROJECT=${INFISICAL_PROJECT:-2296d19c-5f3b-41e1-afa3-fcde39966a71}
HELP_URL=${LOCAL_HELP_URL:-https://github.com/Solierrr/docs-warehouse/blob/main/helps/TRY-LOCAL.md}

die() {
  printf 'erro: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' não foi encontrado no PATH. Saiba mais em $HELP_URL"
}

native() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

k3d() {
  MSYS_NO_PATHCONV=1 docker run --rm --network host \
    -v //var/run/docker.sock:/var/run/docker.sock \
    "$K3D_IMAGE" "$@"
}

kc() {
  [ -f "$KUBECONFIG_FILE" ] || die "o cluster local não existe. Rode 'make cluster-up' primeiro."
  kubectl --kubeconfig "$(native "$KUBECONFIG_FILE")" --context "$CONTEXT" "$@"
}

cluster_exists() {
  k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER"
}

write_kubeconfig() {
  mkdir -p "$STATE"
  k3d kubeconfig get "$CLUSTER" | sed 's#https://0\.0\.0\.0:#https://127.0.0.1:#' >"$KUBECONFIG_FILE"
  chmod 600 "$KUBECONFIG_FILE" 2>/dev/null || true
}

cmd_up() {
  need docker
  need kubectl
  if cluster_exists; then
    info "o cluster $CLUSTER já existe"
    k3d cluster start "$CLUSTER" >/dev/null 2>&1 || true
  else
    info "criando o cluster $CLUSTER (k3d)"
    k3d cluster create "$CLUSTER" --api-port "127.0.0.1:$API_PORT" --servers 1 --agents 0 \
      --k3s-arg "--disable=traefik@server:0" --wait
  fi
  write_kubeconfig

  if ! kc get namespace argocd >/dev/null 2>&1; then
    info "instalando o Argo CD $ARGOCD_VERSION"
    kc create namespace argocd >/dev/null
    kc apply -n argocd --server-side --force-conflicts \
      -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" >/dev/null
  fi
  info "esperando o Argo CD ficar pronto"
  kc -n argocd rollout status deployment/argocd-server --timeout=300s
  kc -n argocd rollout status deployment/argocd-repo-server --timeout=300s
  kc -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
  info "pronto. Senha do admin: make cluster-password. Interface: make cluster-ui"
}

cmd_down() {
  need docker
  if cluster_exists; then
    k3d cluster delete "$CLUSTER"
  else
    info "o cluster $CLUSTER não existe"
  fi
  rm -f "$KUBECONFIG_FILE"
}

cmd_status() {
  need docker
  if ! cluster_exists; then
    info "o cluster $CLUSTER não existe"
    return 0
  fi
  write_kubeconfig
  kc get applications.argoproj.io -n argocd 2>/dev/null || kc get pods -A
}

fetch_manifest() {
  # fetch_manifest <caminho no infra-gitops>
  if [ -n "${INFRA_GITOPS_DIR:-}" ]; then
    cat "$INFRA_GITOPS_DIR/$1"
  else
    need curl
    curl -fsSL "$GITOPS_RAW/$1"
  fi
}

cmd_apps() {
  [ "$#" -gt 0 ] || die "informe os apps, por exemplo: make cluster-apps APPS='api-core api-auth' (ou APPS=root para todos)"
  for name in "$@"; do
    if [ "$name" = "root" ]; then
      path="bootstrap/root-app.yaml"
    else
      path="apps/$name.yaml"
    fi
    info "aplicando a Application $name"
    fetch_manifest "$path" | kc apply -n argocd -f -
  done
}

cmd_secrets() {
  [ "$#" -gt 0 ] || die "informe os serviços, por exemplo: make cluster-secrets SERVICES='api-core'"
  need infisical
  for name in "$@"; do
    tmp=$(mktemp "$STATE/secrets.XXXXXX")
    if ! infisical export --projectId="$INFISICAL_PROJECT" --env="$ENV" --path=/ --format=dotenv >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
      rm -f "$tmp"
      printf '\nNão foi possível obter os segredos do Infisical.\n  - Verifique se sua conta Infisical está logada: infisical login\n  - Verifique se o Infisical CLI está atualizado: infisical --version\nSaiba mais em %s\n' "$HELP_URL" >&2
      exit 1
    fi
    info "criando o secret ${name}-secrets no namespace default"
    kc -n default create secret generic "${name}-secrets" --from-env-file="$(native "$tmp")" \
      --dry-run=client -o yaml | kc apply -f -
    rm -f "$tmp"
  done
}

cmd_password() {
  kc -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  printf '\n'
}

cmd_ui() {
  info "Argo CD em https://localhost:8085 (usuário admin; senha: make cluster-password). Ctrl+C para sair."
  kc -n argocd port-forward svc/argocd-server 8085:443
}

case "$CMD" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  apps) cmd_apps "$@" ;;
  secrets) cmd_secrets "$@" ;;
  password) cmd_password ;;
  ui) cmd_ui ;;
  *)
    printf 'uso: sh cluster.sh up|down|status|apps <nome...>|secrets <serviço...>|password|ui\n' >&2
    exit 64
    ;;
esac
