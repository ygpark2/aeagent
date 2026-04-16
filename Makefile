# Load environment variables from .env file if it exists
-include .env

# Default variables
export PORT ?= 4000
export MIX_ENV ?= dev
export ELIXIR_VERSION ?= 1.18.0
export DATABASE_PATH ?= priv/repo/aos_dev.db
export SECRET_KEY_BASE ?= ZnfvXfq91z5om0lWqBxlTce32/0vJqReJ8vngKJAtx8hyPIJpKhcZfDt//34oSAw
export ENCRYPTION_KEYS ?= HOqyElOsSB50sZcjhqqkXRxWfLQSB4bGtglXvhqfakQ=
export DOT_ENV_FILE ?= .env-none
export AGENT_BASE_URL ?= http://localhost:8317/v1beta
export AGENT_API_KEY ?= my-factory-api-key
export AGENT_MODEL ?= models/gemini-3-pro-preview
export AGENT_PROFILE ?= jobdori
export CLIPROXYAPI ?= false

# Colors for output
BLUE   := \033[1;34m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[1;31m
NC     := \033[0m

.PHONY: help start stop restart reset setup build clean

help:
	@echo "$(BLUE)Usage: make [target]$(NC)"
	@echo ""
	@echo "$(YELLOW)Targets:$(NC)"
	@echo "  start      - Start the containers (usage: make start [build=true] [no_auto_start=true] [setup=true])"
	@echo "  stop       - Stop the containers"
	@echo "  restart    - Stop and start the containers"
	@echo "  reset      - Reset environment variables and restart"
	@echo "  setup      - Start with setup (mix ecto.setup)"
	@echo "  build      - Build and start the containers"
	@echo "  clean      - Remove unused docker resources"
	@echo ""
	@echo "$(YELLOW)Local Targets (without Docker):$(NC)"
	@echo "  local-setup  - Install dependencies and setup database locally"
	@echo "  local-server - Start the Phoenix server locally"
	@echo "  local-stop   - Stop the local Phoenix server and IEx sessions"
	@echo "  local-iex    - Start the Phoenix server with IEx locally"

	.PHONY: help start stop restart reset setup build clean local-setup local-server local-stop local-iex

STACK_NAME := aos-stack
COMPOSE_FILE := deploy/docker-stack.dev.yml

# Build the docker image locally
build-image:
	@echo "$(BLUE)Building docker image...$(NC)"
	@docker build -t aos-api-elixir:dev -f Dockerfile-dev .

# Start logic using docker stack
start:
	@if [ "$(build)" = "true" ]; then \
		$(MAKE) build-image; \
	fi
	@if [ "$(no_auto_start)" = "true" ]; then \
		export NO_AUTO_START=true; \
	fi
	@if [ "$(setup)" = "true" ]; then \
		export MIX_SETUP=true; \
	fi
	@# Check if swarm is initialized
	@docker info | grep -q "Swarm: active" || docker swarm init
	@echo "$(BLUE)Deploying stack: $(STACK_NAME)$(NC)"
	@docker stack deploy -c $(COMPOSE_FILE) $(STACK_NAME)
	@if [ -z "$$NO_AUTO_START" ]; then \
		$(MAKE) check-status; \
	else \
		echo "$(GREEN)The stack is deployed.$(NC)"; \
	fi

stop:
	@echo "$(RED)Removing stack: $(STACK_NAME)$(NC)"
	@docker stack rm $(STACK_NAME)

# Local execution targets
local-setup:
	@echo "$(BLUE)Setting up local environment...$(NC)"
	mix deps.get
	mix ecto.setup

local-server:
	@echo "$(BLUE)Starting local server...$(NC)"
	mix phx.server

local-stop:
	@echo "$(RED)Stopping local server and IEx sessions...$(NC)"
	@pkill -f "mix phx.server" || true
	@pkill -f "iex" || true

local-iex:
	@echo "$(BLUE)Starting local server with IEx...$(NC)"
	iex -S mix phx.server

restart: stop start

reset:
	@echo "$(GREEN)* Environment variables reset (using defaults or .env).$(NC)"
	@$(MAKE) start

setup:
	@$(MAKE) start setup=true

build:
	@$(MAKE) start build=true

clean:
	@docker system prune --force

# Health check logic
check-status:
	@echo "$(YELLOW)* Checking if the server is Up at localhost:$(PORT)$(NC) ..."
	@iterator=0; \
	while [ $$iterator -lt 35 ]; do \
		status_code=$$(curl --write-out %{http_code} --silent --output /dev/null localhost:$(PORT)/healthcheck); \
		if [ "$$status_code" -eq 200 ]; then \
			echo "$(GREEN)The server is Up at localhost:$(PORT)$(NC)"; \
			if command -v open > /dev/null; then open http://localhost:$(PORT)/; \
			elif command -v xdg-open > /dev/null; then xdg-open http://localhost:$(PORT)/; \
			fi; \
			exit 0; \
		fi; \
		sleep 1; \
		iterator=$$((iterator + 1)); \
	done; \
	echo "$(YELLOW)Did not work. Perhaps the server is taking a long time to start?$(NC)"
