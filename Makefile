# Eirdom — Docker stack orchestration   (place at ~/eirdom/docker/Makefile)
#
# Loads the shared root .env (~/eirdom/.env, i.e. ../../.env from a stack dir)
# AND each stack's own .env (only when it has one) for BOTH ${VAR}
# interpolation and container env.
#
# Why this is needed:
#   - bare `docker compose up` reads only the .env in the stack dir for
#     ${VAR} interpolation — NOT ../../.env
#   - `env_file: ../../.env` injects into the CONTAINER only, not interpolation
#   So without --env-file, ${DOCKER_DATA_PATH} / ${ROOT_DOMAIN} resolve blank.
#
#   make up SVC=traefik       make logs SVC=authentik
#   make down SVC=immich      make ps   SVC=arr-stack
#   make pull SVC=immich      make restart SVC=ntfy
#   make config SVC=traefik   # debug: print the fully-resolved compose
#   make up-all  /  make down-all

.RECIPEPREFIX = >

ROOT_ENV  := ../.env
# add --env-file .env only if the chosen stack actually has a local .env
local_env  = $(if $(wildcard $(SVC)/.env),--env-file .env,)
compose    = docker compose --env-file $(ROOT_ENV) $(local_env)

# eirdom-intelligence runs on the laptop — excluded.
STACKS := traefik authentik actual webserver jellyfin immich \
            mealie homeassistant homebox ntfy stirling-pdf paperless \
            uptime-kuma arr-stack radicale netbox cloudflared

.PHONY: up down restart recreate logs ps pull config validate up-all down-all _guard

_guard:
> @test -n "$(SVC)" || { echo "Usage: make <target> SVC=<stack>"; exit 1; }
> @test -d "$(SVC)" || { echo "No such stack: $(SVC)"; exit 1; }
> @test -f ../.env || { echo "Root .env missing at $$(cd .. && pwd)/.env"; exit 1; }

up: _guard
> cd $(SVC) && $(compose) up -d
down: _guard
> cd $(SVC) && $(compose) down
restart: _guard
> cd $(SVC) && $(compose) restart

recreate: _guard
> cd $(SVC) && $(compose) up -d --force-recreate
logs: _guard
> cd $(SVC) && $(compose) logs -f
ps: _guard
> cd $(SVC) && $(compose) ps
pull: _guard
> cd $(SVC) && $(compose) pull
config: _guard
> cd $(SVC) && $(compose) config

validate: _guard
> cd $(SVC) && $(compose) config --quiet

up-all:
> @for s in $(STACKS); do echo "==> up $$s"; \
>   ( cd $$s && docker compose --env-file ../.env $$([ -f .env ] && echo --env-file .env) up -d ) || exit 1; \
> done

down-all:
> @for s in $(STACKS); do echo "==> down $$s"; \
>   ( cd $$s && docker compose --env-file ../.env $$([ -f .env ] && echo --env-file .env) down ) || true; \
> done
