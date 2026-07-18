# Eirdom Docker stack orchestration
#
# Repository layout:
#
#   Eirdom-Docker/
#   ├── .env
#   ├── Makefile
#   ├── traefik/
#   │   ├── docker-compose.yml
#   │   └── .env
#   ├── authentik/
#   └── ...
#
# Examples:
#   make up SVC=traefik
#   make logs SVC=authentik
#   make down SVC=immich
#   make ps SVC=arr-stack
#   make pull SVC=immich
#   make restart SVC=ntfy
#   make config SVC=traefik
#   make validate SVC=paperless
#   make up-all
#   make down-all

.RECIPEPREFIX = >

# Absolute repository path based on this Makefile's location.
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT_ENV  := $(REPO_ROOT)/.env

# These must remain recursively expanded because SVC is supplied at runtime.
STACK_DIR = $(REPO_ROOT)/$(SVC)
LOCAL_ENV = $(if $(wildcard $(STACK_DIR)/.env),--env-file "$(STACK_DIR)/.env",)
COMPOSE   = docker compose --env-file "$(ROOT_ENV)" $(LOCAL_ENV)

# eirdom-intelligence runs on the laptop and is intentionally excluded.
STACKS := \
    traefik \
    authentik \
    actual \
    webserver \
    jellyfin \
    immich \
    mealie \
    homeassistant \
    homebox \
    ntfy \
    stirling-pdf \
    paperless \
    uptime-kuma \
    arr-stack \
    radicale \
    netbox \
    cloudflared \
    dockhand

.PHONY: \
    up down restart recreate logs ps pull config validate \
    up-all down-all _guard

_guard:
> @test -n "$(SVC)" || { \
>   echo "Usage: make <target> SVC=<stack>"; \
>   exit 1; \
> }
> @test -d "$(STACK_DIR)" || { \
>   echo "No such stack: $(SVC)"; \
>   exit 1; \
> }
> @test -f "$(ROOT_ENV)" || { \
>   echo "Root .env missing at $(ROOT_ENV)"; \
>   exit 1; \
> }
> @test -f "$(STACK_DIR)/docker-compose.yml" || { \
>   echo "Compose file missing at $(STACK_DIR)/docker-compose.yml"; \
>   exit 1; \
> }

up: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) up -d

down: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) down

restart: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) restart

recreate: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) up -d --force-recreate

logs: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) logs -f

ps: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) ps

pull: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) pull

config: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) config

validate: _guard
> cd "$(STACK_DIR)" && $(COMPOSE) config --quiet

up-all:
> @test -f "$(ROOT_ENV)" || { \
>   echo "Root .env missing at $(ROOT_ENV)"; \
>   exit 1; \
> }
> @for s in $(STACKS); do \
>   stack_dir="$(REPO_ROOT)/$$s"; \
>   echo "==> Starting $$s"; \
>   if [ ! -f "$$stack_dir/docker-compose.yml" ]; then \
>     echo "Compose file missing: $$stack_dir/docker-compose.yml"; \
>     exit 1; \
>   fi; \
>   local_env=""; \
>   if [ -f "$$stack_dir/.env" ]; then \
>     local_env="--env-file $$stack_dir/.env"; \
>   fi; \
>   ( \
>     cd "$$stack_dir" && \
>     docker compose \
>       --env-file "$(ROOT_ENV)" \
>       $$local_env \
>       up -d \
>   ) || exit 1; \
> done

down-all:
> @test -f "$(ROOT_ENV)" || { \
>   echo "Root .env missing at $(ROOT_ENV)"; \
>   exit 1; \
> }
> @for s in $(STACKS); do \
>   stack_dir="$(REPO_ROOT)/$$s"; \
>   echo "==> Stopping $$s"; \
>   if [ ! -f "$$stack_dir/docker-compose.yml" ]; then \
>     echo "Skipping $$s: no docker-compose.yml"; \
>     continue; \
>   fi; \
>   local_env=""; \
>   if [ -f "$$stack_dir/.env" ]; then \
>     local_env="--env-file $$stack_dir/.env"; \
>   fi; \
>   ( \
>     cd "$$stack_dir" && \
>     docker compose \
>       --env-file "$(ROOT_ENV)" \
>       $$local_env \
>       down \
>   ) || true; \
> done