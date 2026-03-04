#!/bin/bash

# stop_driver.sh - Stop IOSAgentDriver on a simulator
# Usage: ./stop_driver.sh <simulator-udid> <port>

set -e

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Exit codes
EXIT_SUCCESS=0
EXIT_FAILED=1
EXIT_INVALID_ARGS=2

# Validate arguments
if [ $# -lt 2 ]; then
    log_error "Usage: $0 <simulator-udid> <port>"
    exit $EXIT_INVALID_ARGS
fi

SIMULATOR_UDID="$1"
PORT="$2"

log_info "Stopping IOSAgentDriver on simulator $SIMULATOR_UDID:$PORT"

# Check if simulator is booted
if ! xcrun simctl list | grep "$SIMULATOR_UDID" | grep -q "Booted"; then
    log_warning "Simulator $SIMULATOR_UDID is not booted"
    log_success "IOSAgentDriver not running (simulator not booted)"
    exit $EXIT_SUCCESS
fi

# Find IOSAgentDriver process listening on the specified port
log_info "Looking for IOSAgentDriver process on port $PORT..."

# Try to find the process by port
# Note: This is a simplified approach. In reality, we might need to track PIDs
# or use a more sophisticated process management approach.

# Attempt graceful shutdown via API
log_info "Attempting graceful shutdown..."
if curl -s -f -X POST "http://localhost:$PORT/shutdown" -m 5 > /dev/null 2>&1; then
    log_success "Sent shutdown request"
    sleep 2
fi

# Check if port is still in use
if lsof -i ":$PORT" > /dev/null 2>&1; then
    log_warning "Port $PORT still in use after graceful shutdown"
    
    # Get the PID
    PID=$(lsof -t -i ":$PORT" 2>/dev/null || echo "")
    
    if [ -n "$PID" ]; then
        log_info "Found process $PID, sending SIGTERM..."
        kill -TERM "$PID" 2>/dev/null || true
        
        # Wait up to 5 seconds
        WAIT_COUNT=0
        while [ $WAIT_COUNT -lt 5 ]; do
            if ! lsof -i ":$PORT" > /dev/null 2>&1; then
                log_success "Process stopped"
                exit $EXIT_SUCCESS
            fi
            sleep 1
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        # Force kill if still running
        log_warning "Process did not stop gracefully, forcing..."
        kill -9 "$PID" 2>/dev/null || true
        sleep 1
        
        if ! lsof -i ":$PORT" > /dev/null 2>&1; then
            log_success "Process force killed"
            exit $EXIT_SUCCESS
        else
            log_error "Failed to stop process"
            exit $EXIT_FAILED
        fi
    else
        log_warning "Could not find process PID for port $PORT"
    fi
else
    log_success "IOSAgentDriver not running on port $PORT"
fi

# Alternative: Kill all IOSAgentDriver processes on the simulator
# This is a more aggressive approach
RUNNER_BUNDLE_ID="dev.tuist.IOSAgentDriverUITests"

log_info "Checking for IOSAgentDriver processes on simulator..."

# Get all processes on simulator and look for our bundle ID
# Note: This requires the simulator to be booted
if xcrun simctl spawn "$SIMULATOR_UDID" launchctl list 2>/dev/null | grep -q "$RUNNER_BUNDLE_ID"; then
    log_info "Found IOSAgentDriver process on simulator, stopping..."
    
    # Terminate the app
    xcrun simctl terminate "$SIMULATOR_UDID" "$RUNNER_BUNDLE_ID" 2>/dev/null || true
    
    sleep 1
    
    # Verify it stopped
    if xcrun simctl spawn "$SIMULATOR_UDID" launchctl list 2>/dev/null | grep -q "$RUNNER_BUNDLE_ID"; then
        log_warning "IOSAgentDriver still running after terminate"
    else
        log_success "IOSAgentDriver stopped on simulator"
    fi
fi

log_success "Stop operation completed"
exit $EXIT_SUCCESS
