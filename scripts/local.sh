#!/bin/sh
# Sobe um serviço da Solaria na máquina local a partir da imagem do Docker Hub.
# Chamado pelo fragmento local.mk (docs-warehouse/templates/make). Uso:
#   SERVICE=api-core sh local.sh up|down|logs|docker-build|docker-push|compose
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CMD=${1:-help}

SERVICE=${SERVICE:-}
ENV=${ENV:-qa}
DB=${DB:-remote}
OBS=${OBS:-0}
BUILD=${BUILD:-0}
ALL=${ALL:-0}
TAG=${TAG:-dev-$(id -un 2>/dev/null || echo local)}
STATE=${LOCAL_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/solierrr-local}
INFISICAL_PROJECT=${INFISICAL_PROJECT:-2296d19c-5f3b-41e1-afa3-fcde39966a71}
HELP_URL=${LOCAL_HELP_URL:-https://github.com/Solierrr/docs-warehouse/blob/main/helps/TRY-LOCAL.md}
NETWORK=local

die() {
  printf 'erro: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

infisical_help() {
  cat >&2 <<EOF

Não foi possível obter os segredos do Infisical.
  - Verifique se sua conta Infisical está logada: infisical login
  - Verifique se o Infisical CLI está atualizado: infisical --version
Saiba mais em $HELP_URL
EOF
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' não foi encontrado no PATH. Saiba mais em $HELP_URL"
}

need_service() {
  [ -n "$SERVICE" ] || die "informe SERVICE (por exemplo SERVICE=api-core)"
}

container_port() {
  if [ -n "${CONTAINER_PORT:-}" ]; then
    printf '%s' "$CONTAINER_PORT"
    return
  fi
  case "$SERVICE" in
    api-recommendation | ai-* | mcp-* | google-registry) printf '8000' ;;
    *) printf '8080' ;;
  esac
}

host_port() {
  printf '%s' "${HOST_PORT:-$(container_port)}"
}

ensure_network() {
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
}

sync_repo() {
  # sync_repo <nome> <destino>: clona (ou atualiza) um repositório público da organização
  name=$1
  dest=$2
  if [ -d "$dest/.git" ]; then
    if git -C "$dest" fetch --quiet --depth 1 origin HEAD 2>/dev/null; then
      git -C "$dest" checkout --quiet --force FETCH_HEAD
    else
      info "não foi possível atualizar $name; usando a cópia local"
    fi
  else
    mkdir -p "$(dirname "$dest")"
    git clone --quiet --depth 1 "https://github.com/Solierrr/$name.git" "$dest"
  fi
}

obs_dir() {
  if [ -n "${OBS_DIR:-}" ]; then
    printf '%s' "$OBS_DIR"
    return
  fi
  sync_repo infra-otel-collector "$STATE/infra-otel-collector" >&2
  printf '%s' "$STATE/infra-otel-collector"
}

fetch_secrets() {
  out=$1
  if [ -n "${ENV_FILE:-}" ]; then
    [ -f "$ENV_FILE" ] || die "ENV_FILE não existe: $ENV_FILE"
    cp "$ENV_FILE" "$out"
    return
  fi
  need infisical
  if ! infisical export --projectId="$INFISICAL_PROJECT" --env="$ENV" --path=/ --format=dotenv >"$out" 2>"$out.err"; then
    sed 's/^/    /' "$out.err" >&2 || true
    rm -f "$out.err"
    infisical_help
  fi
  rm -f "$out.err"
  [ -s "$out" ] || infisical_help
}

write_overrides() {
  out=$1
  : >"$out"
  if [ "$OBS" = "1" ]; then
    {
      printf 'OTEL_SDK_DISABLED=false\n'
      printf 'OTEL_SERVICE_NAME=%s\n' "$SERVICE"
      printf 'OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318\n'
      printf 'OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf\n'
      printf 'OTEL_RESOURCE_ATTRIBUTES=service.namespace=solaria,deployment.environment=local\n'
      printf 'DEPLOYMENT_ENVIRONMENT=local\n'
      printf 'OTEL_TRACES_SAMPLING_PROBABILITY=1.0\n'
      printf 'OTEL_PYTHON_LOG_CORRELATION=true\n'
    } >>"$out"
  else
    printf 'OTEL_SDK_DISABLED=true\n' >>"$out"
  fi
  if [ "$DB" = "local" ]; then
    {
      printf 'DB_POSTGRES_HOST=local-postgres\n'
      printf 'DB_POSTGRES_PORT=5432\n'
      printf 'DB_POSTGRES_CORE=coredb\n'
      printf 'DB_POSTGRES_USER=solier\n'
      printf 'DB_POSTGRES_PASSWORD=solier\n'
      printf 'DB_POSTGRES_SSLMODE=disable\n'
      printf 'DB_NEO4J_URI=bolt://local-neo4j:7687\n'
      printf 'DB_NEO4J_USER=neo4j\n'
      printf 'DB_NEO4J_PASSWORD=local-neo4j-password\n'
      printf 'DB_NEO4J_FEED=feeddb\n'
    } >>"$out"
  fi
}

deps_up() {
  info "subindo os bancos locais"
  console="$STATE/database-console"
  sync_repo database-console "$console"
  ref=${LOCAL_DB_CONSOLE_REF:-main}
  if git -C "$console" fetch --quiet --depth 1 origin "$ref" 2>/dev/null; then
    git -C "$console" checkout --quiet --force FETCH_HEAD
  else
    info "aviso: a ref $ref não existe; usando o schema da main do database-console"
  fi
  initdb="$STATE/initdb"
  rm -rf "$initdb"
  mkdir -p "$initdb"
  core="$console/db/core"
  n=0
  stage() {
    n=$((n + 1))
    cp "$1" "$initdb/$(printf '%02d' "$n")_$(basename "$1")"
  }
  stage "$core/enums.sql"
  stage "$core/schema.sql"
  for f in $(find "$core/migrations" -name 'V*.sql' 2>/dev/null | sort -V); do
    case "$(basename "$f")" in
      V[1-9]__*) ;;
      *) stage "$f" ;;
    esac
  done
  stage "$core/indexes.sql"
  stage "$core/seed.sql"
  deps="postgres"
  [ "$SERVICE" = "api-recommendation" ] && deps="postgres neo4j"
  # shellcheck disable=SC2086
  LOCAL_INITDB_DIR="$initdb" docker compose -p local-deps -f "$ROOT/compose/deps.yaml" up -d --wait $deps
  if [ "$SERVICE" = "api-recommendation" ]; then
    info "populando o grafo com o database-bootstrap"
    if ! docker run --rm --network "$NETWORK" \
      -e DB_POSTGRES_HOST=local-postgres -e DB_POSTGRES_PORT=5432 -e DB_POSTGRES_CORE=coredb \
      -e DB_POSTGRES_USER=solier -e DB_POSTGRES_PASSWORD=solier -e DB_POSTGRES_SSLMODE=disable \
      -e DB_NEO4J_URI=bolt://local-neo4j:7687 -e DB_NEO4J_USER=neo4j \
      -e DB_NEO4J_PASSWORD=local-neo4j-password -e DB_NEO4J_FEED=feeddb \
      solarianetwork/database-bootstrap:latest; then
      info "aviso: o bootstrap do grafo falhou; o serviço usará o fallback em SQL"
    fi
  fi
}

compose_service() {
  export SERVICE
  export SERVICE_IMAGE="$IMAGE"
  export SECRETS_FILE="$SECRETS"
  export OVERRIDES_FILE="$OVERRIDES"
  export HOST_PORT
  export CONTAINER_PORT
  HOST_PORT=$(host_port)
  CONTAINER_PORT=$(container_port)
  docker compose -p "local-$SERVICE" -f "$ROOT/compose/service.yaml" "$@"
}

cmd_up() {
  need_service
  need docker
  ensure_network
  mkdir -p "$STATE"
  chmod 700 "$STATE" 2>/dev/null || true

  SECRETS=$(mktemp "$STATE/secrets.XXXXXX")
  OVERRIDES=$(mktemp "$STATE/overrides.XXXXXX")
  trap 'rm -f "$SECRETS" "$OVERRIDES" "$SECRETS.err"' EXIT INT TERM
  chmod 600 "$SECRETS" "$OVERRIDES"

  info "lendo os segredos de $ENV"
  fetch_secrets "$SECRETS"

  if [ "$BUILD" = "1" ]; then
    [ -f Dockerfile ] || die "BUILD=1 exige um Dockerfile na pasta atual"
    info "construindo a imagem local $SERVICE:local"
    docker build -t "$SERVICE:local" .
    IMAGE="$SERVICE:local"
  else
    IMAGE="solarianetwork/$SERVICE:latest"
    info "baixando $IMAGE"
    docker pull --quiet "$IMAGE" >/dev/null
  fi

  if [ "$OBS" = "1" ]; then
    dir=$(obs_dir)
    info "subindo o Grafana local e o Collector"
    docker compose -f "$dir/local/compose.yaml" up -d --wait
  fi

  [ "$DB" = "local" ] && deps_up

  write_overrides "$OVERRIDES"
  info "subindo $SERVICE"
  compose_service up -d --force-recreate --wait
  info "$SERVICE em http://localhost:$(host_port)"
  [ "$OBS" = "1" ] && info "Grafana em http://localhost:3000 (admin / admin)"
  return 0
}

cmd_down() {
  need_service
  need docker
  SECRETS=/dev/null OVERRIDES=/dev/null IMAGE=unused compose_service down --remove-orphans
  if [ "$ALL" = "1" ]; then
    docker compose -p local-deps -f "$ROOT/compose/deps.yaml" down 2>/dev/null || true
    if dir=$(obs_dir 2>/dev/null) && [ -f "$dir/local/compose.yaml" ]; then
      docker compose -f "$dir/local/compose.yaml" down 2>/dev/null || true
    fi
  fi
}

cmd_logs() {
  need_service
  need docker
  docker logs -f --tail 200 "local-$SERVICE"
}

cmd_docker_build() {
  need_service
  need docker
  [ -f Dockerfile ] || die "este repositório não tem Dockerfile"
  docker build -t "$SERVICE:local" .
}

cmd_docker_push() {
  need_service
  need docker
  [ -f Dockerfile ] || die "este repositório não tem Dockerfile"
  case "$TAG" in
    latest | main | qa | v[0-9]* | [0-9]*.[0-9]*.[0-9]*)
      die "a tag '$TAG' é reservada ao CI. Use outra, por exemplo TAG=dev-$(id -un 2>/dev/null || echo local)"
      ;;
  esac
  docker build -t "solarianetwork/$SERVICE:$TAG" .
  docker push "solarianetwork/$SERVICE:$TAG"
}

cmd_compose() {
  need docker
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$f" ]; then
      docker compose -f "$f" up -d --build
      return
    fi
  done
  die "este repositório não tem arquivo de compose"
}

case "$CMD" in
  up) cmd_up ;;
  down) cmd_down ;;
  logs) cmd_logs ;;
  docker-build) cmd_docker_build ;;
  docker-push) cmd_docker_push ;;
  compose) cmd_compose ;;
  *)
    printf 'uso: SERVICE=<serviço> sh local.sh up|down|logs|docker-build|docker-push|compose\n' >&2
    exit 64
    ;;
esac
