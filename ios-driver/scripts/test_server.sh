#!/bin/bash

# Test script for iOS Agent Driver server
# Usage: ./test_server.sh [port] [device]
#        ./test_server.sh [port]         # Interactive device selection
#        ./test_server.sh                # Port 8080 + interactive device selection

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get port (default 8080)
PORT=${1:-8080}
DEVICE=""
SERVER_PID=""
TIMEOUT=60  # seconds to wait for server to start

# Cleanup function
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo ""
        echo -e "${YELLOW}🧹 Cleaning up...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        # Kill any remaining xcodebuild processes on this port
        lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Function to list and select device
select_device() {
    echo ""
    echo -e "${BLUE}📱 Available iOS Simulators:${NC}"
    echo "=================================="
    echo ""
    
    # Get list of available simulators (iPhone and iPad only, booted or shutdown)
    DEVICES=$(xcrun simctl list devices ios available 2>/dev/null | \
              grep -E "(iPhone|iPad)" | \
              grep -v "unavailable" | \
              sed 's/^[[:space:]]*//' | \
              sed 's/ ([A-F0-9-]*) .*//')
    
    if [ -z "$DEVICES" ]; then
        echo -e "${RED}❌ No iOS simulators found${NC}"
        echo "Please install iOS simulators from Xcode settings"
        exit 1
    fi
    
    # Convert to array
    IFS=$'\n' read -rd '' -a DEVICE_ARRAY <<<"$DEVICES" || true
    
    # Display numbered list
    INDEX=1
    for device in "${DEVICE_ARRAY[@]}"; do
        echo -e "${YELLOW}$INDEX)${NC} $device"
        ((INDEX++))
    done
    
    echo ""
    echo -n "Select a device (1-${#DEVICE_ARRAY[@]}): "
    read SELECTION
    
    # Validate selection
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#DEVICE_ARRAY[@]}" ]; then
        echo -e "${RED}❌ Invalid selection${NC}"
        exit 1
    fi
    
    # Get selected device (array is 0-indexed, but user sees 1-indexed)
    DEVICE="${DEVICE_ARRAY[$((SELECTION-1))]}"
    echo ""
    echo -e "${GREEN}✅ Selected: $DEVICE${NC}"
}

# Function to wait for server to be ready
wait_for_server() {
    local elapsed=0
    echo ""
    echo -e "${CYAN}⏳ Waiting for server to start (timeout: ${TIMEOUT}s)...${NC}"
    
    while [ $elapsed -lt $TIMEOUT ]; do
        # Try to connect to health endpoint
        if curl -s -f http://localhost:$PORT/health > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Server is ready! (took ${elapsed}s)${NC}"
            return 0
        fi
        
        # Show progress dots
        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    echo ""
    echo -e "${RED}❌ Timeout waiting for server to start after ${TIMEOUT}s${NC}"
    return 1
}

# If device not provided as argument, show selection menu
if [ -z "$2" ]; then
    select_device
else
    DEVICE="$2"
fi

echo ""
echo -e "${BLUE}🧪 Testing iOS Agent Driver Server${NC}"
echo "=================================="
echo -e "Port:   ${YELLOW}$PORT${NC}"
echo -e "Device: ${YELLOW}$DEVICE${NC}"
echo ""

# Get script directory and navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Validate project directory
echo ""
echo -e "${CYAN}📂 Project Directory:${NC} $PROJECT_DIR"

if [ ! -f "$PROJECT_DIR/Project.swift" ]; then
    echo -e "${RED}❌ Error: Not in IOSAgentDriver project directory${NC}"
    echo -e "${RED}   Expected to find Project.swift in: $PROJECT_DIR${NC}"
    exit 1
fi

if [ ! -d "$PROJECT_DIR/IOSAgentDriver" ]; then
    echo -e "${RED}❌ Error: IOSAgentDriver directory not found${NC}"
    echo -e "${RED}   Expected to find IOSAgentDriver/ in: $PROJECT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Directory validation passed"

cd "$PROJECT_DIR"

# Start the server in background
echo -e "${CYAN}🚀 Starting server...${NC}"

# Generate test plan with environment variables
echo -e "${YELLOW}Generating test plan...${NC}"
"$SCRIPT_DIR/generate_testplan.sh" "$PORT" "" > /dev/null

echo -e "${YELLOW}Test Plan: RUNNER_PORT=$PORT${NC}"
echo -e "${CYAN}Command: tuist test IOSAgentDriverUITests --device \"$DEVICE\"${NC}"
echo ""

cd "$PROJECT_DIR"
tuist test IOSAgentDriverUITests --device "$DEVICE" > /tmp/ios-agent-driver-$PORT.log 2>&1 &
SERVER_PID=$!

echo -e "${GREEN}✓${NC} Server started (PID: $SERVER_PID)"

# Wait for server to be ready
if ! wait_for_server; then
    echo ""
    echo -e "${RED}❌ Server failed to start${NC}"
    echo ""
    echo -e "${YELLOW}Last 20 lines of log:${NC}"
    tail -20 /tmp/ios-agent-driver-$PORT.log
    exit 1
fi

# Test health endpoint
echo ""
echo -e "${BLUE}🧪 Testing /health endpoint...${NC}"
RESPONSE=$(curl -s http://localhost:$PORT/health)

if [ -z "$RESPONSE" ]; then
    echo -e "${RED}❌ No response from server${NC}"
    exit 1
fi

echo -e "${CYAN}Response:${NC} $RESPONSE"
echo ""

# Check if response contains expected fields
if echo "$RESPONSE" | grep -q "\"status\"" && echo "$RESPONSE" | grep -q "\"ok\""; then
    echo -e "${GREEN}✅ Health check PASSED!${NC}"
    echo -e "${GREEN}✅ Server is running successfully on port $PORT${NC}"
    echo ""
    echo -e "${YELLOW}ℹ️  Server is running in background (PID: $SERVER_PID)${NC}"
    echo -e "${YELLOW}ℹ️  Log file: /tmp/ios-agent-driver-$PORT.log${NC}"
    echo ""
    echo -e "${CYAN}Press CTRL+C to stop the server${NC}"
    
    # Keep script running to maintain server
    wait $SERVER_PID
else
    echo -e "${RED}❌ Health check FAILED${NC}"
    echo -e "${RED}Expected: {\"status\":\"ok\", \"version\":\"1.0.0\"}${NC}"
    exit 1
fi

