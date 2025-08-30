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

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARNING=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

function log_debug() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_DEBUG ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

function log_info() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

function log_success() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $*"
    fi
}

function log_warning() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_WARNING ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $*" >&2
    fi
}

function log_error() {
    if [[ $LOG_LEVEL -le $LOG_LEVEL_ERROR ]]; then
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

function log_fatal() {
    echo -e "${RED}${BOLD}[FATAL]${NC} $*" >&2
    exit 1
}

function log_step() {
    echo -e "\n${CYAN}${BOLD}==> $*${NC}"
}

function log_substep() {
    echo -e "  ${WHITE}-> $*${NC}"
}

# Progress indicators
function spinner() {
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
    
    if [[ $default == "y" ]]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi
    
    while true; do
        read -rp "$message $prompt " choice
        case $choice in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            "" ) 
                if [[ $default == "y" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
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