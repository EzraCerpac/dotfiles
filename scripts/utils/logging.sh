#!/usr/bin/env bash

# Logging utilities for dotfiles scripts
# Source this file to use logging functions

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Gum detection
if command -v gum >/dev/null 2>&1; then
    readonly HAVE_GUM=1
else
    readonly HAVE_GUM=0
fi

# Minimal color palette (xterm-256)
readonly COLOR_ACCENT=213   # magenta-ish
readonly COLOR_INFO=245     # faint gray
readonly COLOR_SUCCESS=82   # green
readonly COLOR_WARN=178     # yellow
readonly COLOR_ERROR=203    # red

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

function log_debug() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]]; then
        if [[ $HAVE_GUM -eq 1 ]]; then
            gum style --foreground ${COLOR_INFO} "• $*" 2>/dev/null || echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
        else
            echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
        fi
    fi
}

function log_info() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        if [[ $HAVE_GUM -eq 1 ]]; then
            gum style --foreground ${COLOR_INFO} "$*" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $*"
        else
            echo -e "${BLUE}[INFO]${NC} $*"
        fi
    fi
}

function log_success() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        if [[ $HAVE_GUM -eq 1 ]]; then
            gum style --foreground ${COLOR_SUCCESS} "✓ $*" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $*"
        else
            echo -e "${GREEN}[SUCCESS]${NC} $*"
        fi
    fi
}

function log_warning() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_WARNING ]]; then
        if [[ $HAVE_GUM -eq 1 ]]; then
            gum style --foreground ${COLOR_WARN} "! $*" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $*" >&2
        else
            echo -e "${YELLOW}[WARNING]${NC} $*" >&2
        fi
    fi
}

function log_error() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]]; then
        if [[ $HAVE_GUM -eq 1 ]]; then
            gum style --foreground ${COLOR_ERROR} "✗ $*" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $*" >&2
        else
            echo -e "${RED}[ERROR]${NC} $*" >&2
        fi
    fi
}

function log_fatal() {
    if [[ $HAVE_GUM -eq 1 ]]; then
        gum style --foreground ${COLOR_ERROR} --bold "✗ $*" 2>/dev/null || echo -e "${RED}${BOLD}[FATAL]${NC} $*" >&2
    else
        echo -e "${RED}${BOLD}[FATAL]${NC} $*" >&2
    fi
    exit 1
}

function log_step() {
    if [[ $HAVE_GUM -eq 1 ]]; then
        gum style --foreground ${COLOR_ACCENT} --bold "➜ $*" || echo -e "\n${CYAN}${BOLD}==> $*${NC}"
    else
        echo -e "\n${CYAN}${BOLD}==> $*${NC}"
    fi
}

function log_substep() {
    if [[ $HAVE_GUM -eq 1 ]]; then
        gum style --foreground ${COLOR_INFO} "  • $*" || echo -e "  ${WHITE}-> $*${NC}"
    else
        echo -e "  ${WHITE}-> $*${NC}"
    fi
}

# Progress indicators
function spinner() {
    # Fallback text spinner (kept for compatibility)
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Run a command with a spinner title (uses gum if available)
function run_with_spinner() {
    local title=$1
    shift
    if [[ $HAVE_GUM -eq 1 ]]; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        "$@"
    fi
}

function progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $remaining | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# Utility functions
function confirm() {
    local message=${1:-"Do you want to continue?"}
    local default=${2:-"n"}
    if [[ $HAVE_GUM -eq 1 ]]; then
        local args=()
        [[ $default == "y" ]] && args+=(--default)
        if gum confirm "${message}" "${args[@]}"; then
            return 0
        else
            return 1
        fi
    fi

    # Fallback TTY confirm
    local prompt
    if [[ $default == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    while true; do
        read -rp "$message $prompt " choice
        case $choice in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            "" ) [[ $default == "y" ]] && return 0 || return 1 ;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

function check_command() {
    local cmd=$1
    local install_msg=${2:-"Please install $cmd"}
    
    if ! command -v "$cmd" &>/dev/null; then
        log_error "$cmd is not installed. $install_msg"
        return 1
    fi
    return 0
}

function check_file() {
    local file=$1
    local error_msg=${2:-"File $file does not exist"}
    
    if [[ ! -f $file ]]; then
        log_error "$error_msg"
        return 1
    fi
    return 0
}

function check_directory() {
    local dir=$1
    local error_msg=${2:-"Directory $dir does not exist"}
    
    if [[ ! -d $dir ]]; then
        log_error "$error_msg"
        return 1
    fi
    return 0
}
