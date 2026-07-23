# VitePress wiki container image
IMAGE      ?= archinit-wiki
TAG        ?= latest
FULL_IMAGE := $(IMAGE):$(TAG)
PORT       ?= 8080
CONTAINER  ?= archinit-wiki

DOCKER     ?= docker
DOCKERFILE ?= Dockerfile
CONTEXT    ?= .

.PHONY: help build rebuild run stop logs shell clean print-image

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

print-image: ## Print the image name:tag
	@echo $(FULL_IMAGE)

build: ## Build the production image
	$(DOCKER) build -f $(DOCKERFILE) -t $(FULL_IMAGE) $(CONTEXT)

rebuild: ## Build without cache
	$(DOCKER) build --no-cache -f $(DOCKERFILE) -t $(FULL_IMAGE) $(CONTEXT)

run: ## Run the container (http://127.0.0.1:$(PORT))
	$(DOCKER) run --rm -d \
		--name $(CONTAINER) \
		-p $(PORT):80 \
		$(FULL_IMAGE)
	@echo "Wiki: http://127.0.0.1:$(PORT)"

stop: ## Stop the running container
	-$(DOCKER) stop $(CONTAINER)

logs: ## Follow container logs
	$(DOCKER) logs -f $(CONTAINER)

shell: ## Open a shell in a fresh container
	$(DOCKER) run --rm -it --entrypoint sh $(FULL_IMAGE)

clean: stop ## Remove local image
	-$(DOCKER) rmi $(FULL_IMAGE)
