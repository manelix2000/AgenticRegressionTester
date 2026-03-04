#!/bin/bash

# Start Swagger UI for IOSAgentDriver
# Usage: ./start_swagger.sh [port]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${1:-3000}"  # Default to 3000 if no argument provided
SERVER_PID=""

# Cleanup function to kill server on exit
cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 $SERVER_PID 2>/dev/null; then
        echo ""
        echo "🛑 Stopping Swagger UI server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null
        
        # Wait for graceful shutdown
        for i in {1..3}; do
            sleep 0.5
            if ! kill -0 $SERVER_PID 2>/dev/null; then
                echo "✓ Server stopped successfully"
                return
            fi
        done
        
        # Force kill if still running
        kill -9 $SERVER_PID 2>/dev/null
        echo "✓ Server force-stopped"
    fi
}

# Set trap to cleanup on script exit
trap cleanup EXIT INT TERM

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Starting Swagger UI for IOSAgentDriver"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed"
    echo ""
    echo "Install Node.js:"
    echo "  - Using Homebrew: brew install node"
    echo "  - Download from: https://nodejs.org/"
    exit 1
fi

echo "✓ Node.js found: $(node --version)"

# Check if port is already in use and kill the process
echo ""
echo "🔍 Checking if port $PORT is in use..."
PORT_PID=$(lsof -ti:$PORT 2>/dev/null)

if [ -n "$PORT_PID" ]; then
    echo "⚠️  Port $PORT is already in use by process $PORT_PID"
    echo "   Killing existing process..."
    
    kill $PORT_PID 2>/dev/null
    
    # Wait up to 3 seconds for process to die
    for i in {1..3}; do
        sleep 1
        if ! kill -0 $PORT_PID 2>/dev/null; then
            echo "✓ Process killed successfully"
            break
        fi
        
        if [ $i -eq 3 ]; then
            echo "⚠️  Process didn't stop gracefully, forcing..."
            kill -9 $PORT_PID 2>/dev/null
            sleep 1
            echo "✓ Process force-killed"
        fi
    done
else
    echo "✓ Port $PORT is available"
fi

# Check if dependencies are installed
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo ""
    echo "📦 Installing dependencies..."
    cd "$SCRIPT_DIR" || exit 1
    npm install --silent
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install dependencies"
        exit 1
    fi
    
    echo "✓ Dependencies installed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting server..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  Make sure IOSAgentDriver is running on port 8080"
echo "   Run in another terminal:"
echo "   cd ../../ && ./scripts/test_server_interactive.sh"
echo ""

cd "$SCRIPT_DIR" || exit 1

# Start server in background
if [ "$PORT" != "3000" ]; then
    PORT=$PORT node server.js &
else
    node server.js &
fi

SERVER_PID=$!

# Wait for server to start
sleep 2

# Check if server is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "❌ Failed to start server"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Swagger UI is running!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Open browser: http://localhost:$PORT"
echo "🔄 Server PID: $SERVER_PID"
echo ""
echo "Press 'q' and Enter to quit, or Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Read input in a loop
while true; do
    read -r -t 1 -n 1 input 2>/dev/null
    
    # Check if user pressed 'q' or 'Q'
    if [[ "$input" == "q" ]] || [[ "$input" == "Q" ]]; then
        echo ""
        echo "👋 Quitting..."
        exit 0
    fi
    
    # Check if server is still running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo ""
        echo "❌ Server stopped unexpectedly"
        exit 1
    fi
done
