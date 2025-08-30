# Simplified Makefile for dotfiles development
# Most operations should use chezmoi commands directly
# See README.md for usage instructions

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: help
help: ## Show available development commands
	@echo -e "$(BLUE)Dotfiles Development Commands$(NC)"
	@echo ""
	@echo -e "$(YELLOW)For daily usage, use chezmoi commands directly:$(NC)"
	@echo "  chezmoi status     # Check what needs to be applied"
	@echo "  chezmoi diff       # Show differences" 
	@echo "  chezmoi apply      # Apply configurations"
	@echo "  chezmoi update     # Update from repository"
	@echo ""
	@echo -e "$(YELLOW)Development targets:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf "  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##@ Development

.PHONY: doctor
doctor: ## Run chezmoi doctor to check for issues
	@echo -e "$(BLUE)Running chezmoi doctor...$(NC)"
	@chezmoi doctor

.PHONY: validate
validate: ## Run validation scripts if available
	@echo -e "$(BLUE)Validating dotfiles...$(NC)"
	@if [ -f scripts/validate.sh ]; then \
		./scripts/validate.sh; \
	else \
		echo -e "$(YELLOW)Running chezmoi verify...$(NC)"; \
		chezmoi verify; \
	fi

.PHONY: clean
clean: ## Clean up temporary files
	@echo -e "$(BLUE)Cleaning up temporary files...$(NC)"
	@find . -name "*.log" -delete 2>/dev/null || true
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find . -name "*~" -delete 2>/dev/null || true
	@find . -name ".DS_Store" -delete 2>/dev/null || true
	@echo -e "$(GREEN)Cleanup complete$(NC)"