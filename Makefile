SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configuration
DOTFILES_REPO := https://github.com/EzraCerpac/dotfiles
BRANCH_NAME := main
DOCKER_IMAGE_NAME := ezra-dotfiles
DOCKER_ARCH := x86_64

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: help
help: ## Show this help message
	@echo -e "$(BLUE)Dotfiles Management Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Setup and Installation

.PHONY: install
install: ## Run the full dotfiles installation
	@echo -e "$(BLUE)Installing dotfiles...$(NC)"
	@./setup.sh

.PHONY: init
init: ## Initialize chezmoi with dotfiles repository
	@echo -e "$(BLUE)Initializing chezmoi...$(NC)"
	@chezmoi init --apply $(DOTFILES_REPO) --branch $(BRANCH_NAME)

.PHONY: setup-homebrew
setup-homebrew: ## Install Homebrew (macOS only)
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		echo -e "$(BLUE)Installing Homebrew...$(NC)"; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
	else \
		echo -e "$(YELLOW)Homebrew installation is only available on macOS$(NC)"; \
	fi

##@ Daily Operations

.PHONY: update
update: ## Update dotfiles from repository and apply changes
	@echo -e "$(BLUE)Updating dotfiles...$(NC)"
	@chezmoi update --verbose

.PHONY: apply
apply: ## Apply current dotfiles configuration
	@echo -e "$(BLUE)Applying dotfiles...$(NC)"
	@chezmoi apply --verbose

.PHONY: status
status: ## Show chezmoi status (what would be changed)
	@echo -e "$(BLUE)Checking dotfiles status...$(NC)"
	@chezmoi status

.PHONY: diff
diff: ## Show diff between current and target state
	@echo -e "$(BLUE)Showing dotfiles diff...$(NC)"
	@chezmoi diff

##@ Development and Maintenance

.PHONY: watch
watch: ## Watch for changes and auto-apply (requires watchexec)
	@echo -e "$(BLUE)Watching for changes...$(NC)"
	@if command -v watchexec >/dev/null 2>&1; then \
		DOTFILES_DEBUG=1 watchexec --exts toml,sh,fish,lua,json,yaml,yml -- chezmoi apply --verbose; \
	else \
		echo -e "$(RED)watchexec is required for watch mode$(NC)"; \
		echo -e "$(YELLOW)Install with: brew install watchexec$(NC)"; \
		exit 1; \
	fi

.PHONY: doctor
doctor: ## Run chezmoi doctor to check for issues
	@echo -e "$(BLUE)Running chezmoi doctor...$(NC)"
	@chezmoi doctor

.PHONY: edit
edit: ## Open chezmoi source directory in editor
	@echo -e "$(BLUE)Opening dotfiles in editor...$(NC)"
	@chezmoi edit

.PHONY: cd
cd: ## Change to chezmoi source directory
	@echo -e "$(BLUE)Changing to source directory:$(NC) $$(chezmoi source-path)"
	@cd $$(chezmoi source-path) && exec $$SHELL

##@ Validation and Health

.PHONY: validate
validate: ## Validate dotfiles configuration
	@echo -e "$(BLUE)Validating dotfiles...$(NC)"
	@if [ -f scripts/validate.sh ]; then \
		./scripts/validate.sh; \
	else \
		echo -e "$(YELLOW)Validation script not found, running basic checks...$(NC)"; \
		chezmoi verify; \
	fi

.PHONY: health
health: ## Run comprehensive health check
	@echo -e "$(BLUE)Running health check...$(NC)"
	@./scripts/health-check.sh 2>/dev/null || echo -e "$(YELLOW)Health check script not found$(NC)"

##@ Backup and Recovery

.PHONY: backup
backup: ## Create backup of current dotfiles
	@echo -e "$(BLUE)Creating backup...$(NC)"
	@if [ -f scripts/backup.sh ]; then \
		./scripts/backup.sh; \
	else \
		echo -e "$(YELLOW)Creating simple backup...$(NC)"; \
		tar -czf "dotfiles-backup-$$(date +%Y%m%d-%H%M%S).tar.gz" \
			--exclude='.git' --exclude='*.log' --exclude='*.tmp' \
			-C ~ .config .local/bin .zshrc .zshenv 2>/dev/null || true; \
		echo -e "$(GREEN)Backup created$(NC)"; \
	fi

.PHONY: restore
restore: ## Restore from backup (requires backup file)
	@echo -e "$(BLUE)Restore functionality...$(NC)"
	@if [ -f scripts/restore.sh ]; then \
		./scripts/restore.sh; \
	else \
		echo -e "$(YELLOW)Please specify backup file to restore from$(NC)"; \
		echo -e "$(YELLOW)Usage: tar -xzf dotfiles-backup-YYYYMMDD-HHMMSS.tar.gz -C ~/$(NC)"; \
	fi

##@ Git Operations

.PHONY: git-status
git-status: ## Show git status in chezmoi source directory
	@echo -e "$(BLUE)Git status in source directory...$(NC)"
	@chezmoi git status

.PHONY: git-add
git-add: ## Add all changes in chezmoi source directory
	@echo -e "$(BLUE)Adding changes...$(NC)"
	@chezmoi git add -A

.PHONY: git-commit
git-commit: ## Commit changes with message (use MSG="your message")
	@echo -e "$(BLUE)Committing changes...$(NC)"
	@if [ -z "$(MSG)" ]; then \
		echo -e "$(RED)Please provide a commit message: make git-commit MSG=\"your message\"$(NC)"; \
		exit 1; \
	fi
	@chezmoi git commit -m "$(MSG)"

.PHONY: git-push
git-push: ## Push changes to remote repository
	@echo -e "$(BLUE)Pushing changes...$(NC)"
	@chezmoi git push

##@ Docker Support

.PHONY: docker-build
docker-build: ## Build Docker image for testing dotfiles
	@echo -e "$(BLUE)Building Docker image...$(NC)"
	@docker build -t $(DOCKER_IMAGE_NAME) . --build-arg USERNAME="$$(whoami)"

.PHONY: docker-run
docker-run: ## Run Docker container for testing
	@echo -e "$(BLUE)Running Docker container...$(NC)"
	@if ! docker inspect $(DOCKER_IMAGE_NAME) &>/dev/null; then \
		$(MAKE) docker-build; \
	fi
	@docker run -it -v "$$(pwd):/home/$$(whoami)/.local/share/chezmoi" $(DOCKER_IMAGE_NAME) /bin/bash --login

.PHONY: docker-test
docker-test: ## Test dotfiles installation in Docker
	@echo -e "$(BLUE)Testing dotfiles in Docker...$(NC)"
	@$(MAKE) docker-build
	@docker run --rm -v "$$(pwd):/home/$$(whoami)/.local/share/chezmoi" $(DOCKER_IMAGE_NAME) /bin/bash -c "make install"

##@ Cleanup

.PHONY: clean
clean: ## Clean up temporary files and caches
	@echo -e "$(BLUE)Cleaning up...$(NC)"
	@find . -name "*.log" -delete 2>/dev/null || true
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find . -name "*~" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo -e "$(GREEN)Cleanup complete$(NC)"

.PHONY: reset
reset: ## Reset chezmoi state (use with caution)
	@echo -e "$(YELLOW)This will reset chezmoi state. Are you sure? [y/N]$(NC)"
	@read -r response && [ "$$response" = "y" ] || [ "$$response" = "Y" ] || exit 1
	@echo -e "$(BLUE)Resetting chezmoi state...$(NC)"
	@chezmoi state delete-bucket --bucket=scriptState

.PHONY: uninstall
uninstall: ## Remove dotfiles and chezmoi (use with extreme caution)
	@echo -e "$(RED)This will remove all dotfiles and chezmoi. Are you sure? [y/N]$(NC)"
	@read -r response && [ "$$response" = "y" ] || [ "$$response" = "Y" ] || exit 1
	@echo -e "$(BLUE)Uninstalling dotfiles...$(NC)"
	@chezmoi remove --all || true
	@rm -rf ~/.local/share/chezmoi || true
	@rm -f ~/.local/bin/chezmoi || true
	@echo -e "$(GREEN)Uninstall complete$(NC)"

##@ Information

.PHONY: info
info: ## Show dotfiles and system information
	@echo -e "$(BLUE)Dotfiles Information$(NC)"
	@echo "Repository: $(DOTFILES_REPO)"
	@echo "Branch: $(BRANCH_NAME)"
	@echo "OS: $$(uname -s) $$(uname -r)"
	@echo "Architecture: $$(uname -m)"
	@echo -e "\n$(BLUE)Chezmoi Information$(NC)"
	@chezmoi --version 2>/dev/null || echo "chezmoi not installed"
	@echo "Source: $$(chezmoi source-path 2>/dev/null || echo 'Not initialized')"
	@echo "Config: $$(chezmoi config-path 2>/dev/null || echo 'Not found')"

.PHONY: list-configs
list-configs: ## List all managed configuration files
	@echo -e "$(BLUE)Managed configuration files:$(NC)"
	@chezmoi list 2>/dev/null || echo "chezmoi not initialized"

##@ Quick Actions

.PHONY: quick-setup
quick-setup: setup-homebrew install ## Quick setup for new machines (macOS)

.PHONY: daily-update
daily-update: update validate ## Daily update routine

.PHONY: commit-and-push
commit-and-push: git-add ## Commit and push changes (use MSG="your message")
	@$(MAKE) git-commit MSG="$(MSG)"
	@$(MAKE) git-push