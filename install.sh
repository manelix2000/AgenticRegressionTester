#!/bin/bash

# AgenticRegressionTester install script
# Builds and installs agent-cli, then generates a QA skill for your app.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { echo -e "${CYAN}ℹ️  $1${RESET}"; }
log_success() { echo -e "${GREEN}✅ $1${RESET}"; }
log_error()   { echo -e "${RED}❌ $1${RESET}"; }
log_section() { echo -e "\n${BOLD}${CYAN}$1${RESET}\n"; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ── Step 1: Build and install agent-cli ───────────────────────────────────────
log_section "Step 1/2 — Building and installing agent-cli"

cd "$SCRIPT_DIR/agent-cli"
./build.sh install

# ── Step 2: Generate QA skill ─────────────────────────────────────────────────
log_section "Step 2/2 — Generating QA skill"

log_info "A QA skill ties the agent to a specific app target."
log_info "Please provide the following details:\n"

echo -n "  Product name (e.g. MyApp): "
read -r PRODUCT_NAME

echo -n "  App bundle ID (e.g. com.example.myapp): "
read -r APP_ID

if [ -z "$PRODUCT_NAME" ] || [ -z "$APP_ID" ]; then
    log_error "Product name and bundle ID are required."
    exit 1
fi

echo ""
log_info "Generating skill for '${PRODUCT_NAME}' (${APP_ID})..."
agent-cli skill generate -p "$PRODUCT_NAME" -b "$APP_ID"

echo ""
log_success "Installation complete! Restart your terminal to apply all environment variables."
