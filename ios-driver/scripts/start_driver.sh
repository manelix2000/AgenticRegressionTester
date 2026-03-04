#!/bin/bash

# start_driver.sh - Start IOSAgentDriver on a simulator
# Usage: ./start_driver.sh <simulator-udid> <port> [bundle-id]

set -e

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} ℹ️  $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} ✅ $1"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')]${NC} ❌ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} ⚠️  $1"
}

log_loading() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} 🔄 $1"
}

# Exit codes
EXIT_SUCCESS=0
EXIT_NO_IOS_AGENT_DRIVER_DIR=1
EXIT_BUILD_FAILED=2
EXIT_INSTALL_FAILED=3
EXIT_HEALTH_CHECK_FAILED=4
EXIT_INVALID_ARGS=5

# Validate arguments
if [ $# -lt 2 ]; then
    log_error "Usage: $0 <simulator-udid> <port> [bundle-id]"
    exit $EXIT_INVALID_ARGS
fi

SIMULATOR_UDID="$1"
PORT="$2"
BUNDLE_ID="${3:-}"

log_info "Starting IOSAgentDriver on simulator $SIMULATOR_UDID:$PORT"

# Step 1: Validate IOS_AGENT_DRIVER_DIR
if [ -z "$IOS_AGENT_DRIVER_DIR" ]; then
    log_error "IOS_AGENT_DRIVER_DIR environment variable is not set"
    echo ""
    echo "Please set it in your shell configuration:"
    echo "  export IOS_AGENT_DIR=\"/path/to/AgenticRegressionTester/ios-driver\""
    echo ""
    exit $EXIT_NO_IOS_AGENT_DRIVER_DIR
fi

if [ ! -d "$IOS_AGENT_DRIVER_DIR" ]; then
    log_error "IOS_AGENT_DRIVER_DIR does not exist: $IOS_AGENT_DRIVER_DIR"
    exit $EXIT_NO_IOS_AGENT_DRIVER56r4e_DIR
fi

if [ ! -f "$IOS_AGENT_DRIVER_DIR/Project.swift" ]; then
    log_error "IOS_AGENT_DIR does not contain Project.swift: $IOS_AGENT_DRIVER_DIR"
    exit $EXIT_NO_IOS_AGENT_DRIVER_DIR
fi

log_success "IOS_AGENT_DRIVER_DIR validated: $IOS_AGENT_DRIVER_DIR"

# Step 2: Check if IOSAgentDriver is already installed
RUNNER_BUNDLE_ID="dev.tuist.IOSAgentDriverUITests.xctrunne<r"
log_info "Checking if IOSAgentDriver is already installed on simulator..."

if xcrun simctl get_app_container "$SIMULATOR_UDID" "$RUNNER_BUNDLE_ID" &>/dev/null; then
    log_success "IOSAgentDriver is already installed, skipping build"
    SKIP_BUILD=true
else
    log_info "IOSAgentDriver not installed, will build and install"
    SKIP_BUILD=false
fi

# Step 3: Prepare environment
cd "$IOS_AGENT_DRIVER_DIR"

# Generate test plan with port configuration
"$IOS_AGENT_DRIVER_DIR/scripts/generate_testplan.sh" "$PORT" "$INSTALLED_APP" > /dev/null
log_info "Test plan configured for port $PORT"

# Get simulator name for tuist test command
SIMULATOR_NAME=$(xcrun simctl list devices | grep "$SIMULATOR_UDID" | sed 's/ (.*//;s/^[[:space:]]*//')

# Step 4: Start IOSAgentDriver with tuist test
# This command will:
# - Build and install if needed (first run)
# - Just run tests if already installed (subsequent runs)
# - The test itself starts the HTTP server on the configured port
if [ "$SKIP_BUILD" = false ]; then
    log_loading "Building and starting IOSAgentDriver..."
else
    log_loading "Starting IOSAgentDriver..."
fi

# Run tuist test in background (builds + installs + starts server)
tuist test IOSAgentDriverUITests --device "$SIMULATOR_NAME" > /tmp/ios-agent-driver-$PORT.log 2>&1 &
RUNNER_PID=$!

log_success "IOSAgentDriver started (PID: $RUNNER_PID)"

# Step 5: Health check with exponential backoff
log_loading "Waiting for IOSAgentDriver to be ready..."

HEALTH_URL="http://localhost:$PORT/health"
MAX_RETRIES=10
ATTEMPT=0
BASE_DELAY=1

while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    log_info "Health check attempt $((ATTEMPT + 1))/$MAX_RETRIES..."
    
    if curl -s -f -m 5 "$HEALTH_URL" > /dev/null 2>&1; then
        log_success "IOSAgentDriver is ready on port $PORT"
        echo ""
        echo "IOSAgentDriver ready on port $PORT"
        exit $EXIT_SUCCESS
    fi
    
    # Calculate exponential backoff delay (max 16 seconds)
    DELAY=$((BASE_DELAY * (2 ** ATTEMPT)))
    if [ $DELAY -gt 16 ]; then
        DELAY=16
    fi
    
    log_info "Not ready yet, retrying in ${DELAY}s..."
    sleep $DELAY
    
    ATTEMPT=$((ATTEMPT + 1))
done

# Health check failed
log_error "Health check failed after $MAX_RETRIES attempts"
log_error "IOSAgentDriver may not have started correctly on port $PORT"
echo ""
echo "Troubleshooting:"
echo "  1. Check if simulator is booted: xcrun simctl list | grep $SIMULATOR_UDID"
echo "  2. Check simulator console logs"
echo "  3. Verify port $PORT is not in use: lsof -i :$PORT"
echo ""

exit $EXIT_HEALTH_CHECK_FAILED
