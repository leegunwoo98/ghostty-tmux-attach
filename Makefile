# ghostty-tmux-attach development tasks
.PHONY: help test test-unit test-integration test-race test-e2e lint ci-local clean

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: ## Run all bats tests
	@tests/run.sh all

test-unit: ## Run unit tests only
	@tests/run.sh unit

test-integration: ## Run integration tests only
	@tests/run.sh integration

test-race: ## Run race/concurrency tests only
	@tests/run.sh race

test-e2e: ## Run end-to-end tests only
	@tests/run.sh e2e

lint: ## shellcheck all .sh files
	@shellcheck -x -e SC1091 \
		install.sh \
		lib/*.sh \
		libexec/ghostty-tmux-attach-launch \
		libexec/ghostty-tmux-attach-shell \
		bin/ghostty-tmux-attach \
		tests/helpers/*.bash \
		tests/run.sh

ci-local: lint test ## Run everything CI runs

clean: ## Remove test scratch
	@find . -name '*.bak' -delete
	@rm -rf /tmp/ghostty-tmux-attach-test-*
