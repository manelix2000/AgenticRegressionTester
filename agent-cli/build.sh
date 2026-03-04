#!/bin/bash

# Build script for agent-cli
# Supports debug and release builds with optional global installation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Emoji helpers
SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
LOADING="🔄"
ROCKET="🚀"

# Print helpers
log_info() {
    echo -e "${CYAN}${INFO}  $1${RESET}"
}

log_success() {
    echo -e "${GREEN}${SUCCESS} $1${RESET}"
}

log_error() {
    echo -e "${RED}${ERROR} $1${RESET}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${RESET}"
}

log_loading() {
    echo -e "${BLUE}${LOADING} $1${RESET}"
}

# Usage help
usage() {
    echo -e "${BOLD}${CYAN}IOSAgentDriver CLI Build Script${RESET}"
    echo ""
    echo "Usage: ./build.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  debug              Build debug configuration (default)"
    echo "  release            Build release configuration (optimized)"
    echo "  both               Build both debug and release"
    echo "  clean              Clean build artifacts"
    echo "  install            Build, setup environment, and install globally"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "The 'install' command will:"
    echo "  • Check and install Tuist if needed"
    echo "  • Detect and configure IOS_AGENT_DRIVER_DIR environment variable"
    echo "  • Add IOS_AGENT_DRIVER_DIR to your shell profile (.zshrc, .bashrc, etc.)"
    echo "  • Install skill templates to ~/.agent-cli/skill"
    echo "  • Build release configuration"
    echo "  • Install to /usr/local/bin (requires sudo)"
    echo ""
    echo "Examples:"
    echo "  ./build.sh                  # Build debug"
    echo "  ./build.sh release          # Build release"
    echo "  ./build.sh both             # Build both configurations"
    echo "  ./build.sh install          # Full setup and global installation"
    echo "  ./build.sh clean            # Clean build artifacts"
    echo ""
}

# Get script directory (handles symlinks)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Verify we're in the right directory
if [ ! -f "Package.swift" ]; then
    log_error "Package.swift not found. Are you in the agent-cli directory?"
    exit 1
fi

# Parse command
COMMAND="${1:-debug}"

case "$COMMAND" in
    debug)
        log_info "Building agent-cli (debug configuration)..."
        echo ""
        
        # Build
        if swift build; then
            log_success "Debug build completed successfully"
            echo ""
            log_info "Binary location:"
            echo -e "   ${CYAN}.build/debug/agent-cli${RESET}"
            echo ""
            log_info "Run with:"
            echo -e "   ${CYAN}.build/debug/agent-cli --help${RESET}"
        else
            log_error "Build failed"
            exit 1
        fi
        ;;
        
    release)
        log_info "Building agent-cli (release configuration)..."
        log_warning "This may take a while (optimizations enabled)"
        echo ""
        
        # Build
        if swift build -c release; then
            log_success "Release build completed successfully"
            echo ""
            log_info "Binary location:"
            echo -e "   ${CYAN}.build/release/agent-cli${RESET}"
            echo ""
            log_info "Binary size:"
            ls -lh .build/release/agent-cli | awk '{print "   " $5}'
            echo ""
            log_info "Run with:"
            echo -e "   ${CYAN}.build/release/agent-cli --help${RESET}"
            echo ""
            log_info "Install globally with:"
            echo -e "   ${CYAN}./build.sh install${RESET}"
        else
            log_error "Build failed"
            exit 1
        fi
        ;;
        
    both)
        log_info "Building both debug and release configurations..."
        echo ""
        
        # Build debug
        log_loading "Building debug..."
        if swift build; then
            log_success "Debug build completed"
        else
            log_error "Debug build failed"
            exit 1
        fi
        
        echo ""
        
        # Build release
        log_loading "Building release..."
        if swift build -c release; then
            log_success "Release build completed"
        else
            log_error "Release build failed"
            exit 1
        fi
        
        echo ""
        log_success "Both builds completed successfully"
        echo ""
        log_info "Binary locations:"
        echo -e "   Debug:   ${CYAN}.build/debug/agent-cli${RESET}"
        echo -e "   Release: ${CYAN}.build/release/agent-cli${RESET}"
        echo ""
        log_info "Binary sizes:"
        DEBUG_SIZE=$(ls -lh .build/debug/agent-cli | awk '{print $5}')
        RELEASE_SIZE=$(ls -lh .build/release/agent-cli | awk '{print $5}')
        echo "   Debug:   $DEBUG_SIZE"
        echo "   Release: $RELEASE_SIZE"
        ;;
        
    clean)
        log_info "Cleaning build artifacts..."
        echo ""
        
        if [ -d ".build" ]; then
            BUILD_SIZE=$(du -sh .build 2>/dev/null | awk '{print $1}')
            log_info "Removing .build directory ($BUILD_SIZE)..."
            rm -rf .build
            log_success "Build artifacts cleaned"
        else
            log_info "No build artifacts to clean"
        fi
        
        if [ -d ".swiftpm" ]; then
            log_info "Removing .swiftpm directory..."
            rm -rf .swiftpm
        fi
        
        echo ""
        log_success "Clean complete"
        ;;
        
    install)
        log_info "Building release and installing globally..."
        echo ""
        
        # Check for Tuist
        log_loading "Checking dependencies..."
        if ! command -v tuist >/dev/null 2>&1; then
            log_warning "Tuist is not installed"
            log_info "Tuist is required to build the IOSAgentDriver XCTest target"
            echo ""
            echo "Install Tuist with one of these methods:"
            echo ""
            echo -e "  ${CYAN}# Homebrew (recommended)${RESET}"
            echo -e "  ${BOLD}brew install tuist${RESET}"
            echo ""
            echo -e "  ${CYAN}# Official installer${RESET}"
            echo -e "  ${BOLD}curl -Ls https://install.tuist.io | bash${RESET}"
            echo ""
            echo -e "  ${CYAN}# mise (formerly rtx)${RESET}"
            echo -e "  ${BOLD}mise install tuist${RESET}"
            echo ""
            echo -n "Would you like to install Tuist via Homebrew now? [y/N]: "
            read -r INSTALL_TUIST
            if [[ "$INSTALL_TUIST" =~ ^[Yy]$ ]]; then
                echo ""
                log_loading "Installing Tuist via Homebrew..."
                if brew install tuist; then
                    log_success "Tuist installed successfully"
                    echo ""
                else
                    log_error "Failed to install Tuist via Homebrew"
                    log_info "Please install manually and try again"
                    exit 1
                fi
            else
                log_info "Please install Tuist manually and run this script again"
                exit 1
            fi
        else
            TUIST_VERSION=$(tuist version 2>/dev/null || echo "unknown")
            log_success "Tuist is installed (version: $TUIST_VERSION)"
        fi
        echo ""
        
        # Detect shell for profile file (used later for instructions)
        SHELL_NAME=$(basename "$SHELL")
        case "$SHELL_NAME" in
            bash)
                PROFILE_FILE="$HOME/.bashrc"
                if [ -f "$HOME/.bash_profile" ]; then
                    PROFILE_FILE="$HOME/.bash_profile"
                fi
                ;;
            zsh)
                PROFILE_FILE="$HOME/.zshrc"
                ;;
            fish)
                PROFILE_FILE="$HOME/.config/fish/config.fish"
                ;;
            *)
                PROFILE_FILE="$HOME/.profile"
                ;;
        esac
        
        # Check for IOS_AGENT_DRIVER_DIR
        log_loading "Checking IOS_AGENT_DRIVER_DIR environment variable..."
        if [ -z "${IOS_AGENT_DRIVER_DIR:-}" ]; then
            log_warning "IOS_AGENT_DRIVER_DIR is not set"
            echo ""
            log_info "IOS_AGENT_DRIVER_DIR should point to the IOSAgentDriver project directory"
            
            # Try to detect IOSAgentDriver location
            DETECTED_DIR=""
            if [ -d "../ios-driver" ]; then
                DETECTED_DIR="$(cd ../ios-driver && pwd)"
            elif [ -d "$(dirname "$SCRIPT_DIR")/ios-driver" ]; then
                DETECTED_DIR="$(cd "$(dirname "$SCRIPT_DIR")/ios-driver" && pwd)"
            fi
            
            if [ -n "$DETECTED_DIR" ]; then
                log_info "Detected IOSAgentDriver at: ${CYAN}$DETECTED_DIR${RESET}"
                echo ""
                echo -n "Use this path for IOS_AGENT_DRIVER_DIR? [Y/n]: "
                read -r USE_DETECTED
                if [[ ! "$USE_DETECTED" =~ ^[Nn]$ ]]; then
                    IOS_AGENT_DRIVER_DIR="$DETECTED_DIR"
                else
                    echo ""
                    echo -n "Enter IOSAgentDriver directory path: "
                    read -r IOS_AGENT_DRIVER_DIR
                fi
            else
                echo ""
                echo -n "Enter IOSAgentDriver directory path (e.g., /path/to/ios-driver): "
                read -r IOS_AGENT_DRIVER_DIR
            fi
            
            # Validate path
            if [ ! -d "$IOS_AGENT_DRIVER_DIR" ]; then
                log_error "Directory not found: $IOS_AGENT_DRIVER_DIR"
                exit 1
            fi
            
            if [ ! -f "$IOS_AGENT_DRIVER_DIR/Project.swift" ]; then
                log_error "Not a valid IOSAgentDriver directory (Project.swift not found)"
                exit 1
            fi
            
            echo ""
            log_success "IOSAgentDriver directory validated: $IOS_AGENT_DRIVER_DIR"
            echo ""
            
            log_info "Detected shell: ${CYAN}$SHELL_NAME${RESET}"
            log_info "Profile file: ${CYAN}$PROFILE_FILE${RESET}"
            echo ""
            echo -n "Add IOS_AGENT_DRIVER_DIR to $PROFILE_FILE? [Y/n]: "
            read -r ADD_TO_PROFILE
            
            if [[ ! "$ADD_TO_PROFILE" =~ ^[Nn]$ ]]; then
                echo "" >> "$PROFILE_FILE"
                echo "# IOSAgentDriver CLI - Added by install script on $(date)" >> "$PROFILE_FILE"
                echo "export IOS_AGENT_DRIVER_DIR=\"$IOS_AGENT_DRIVER_DIR\"" >> "$PROFILE_FILE"
                log_success "Added IOS_AGENT_DRIVER_DIR to $PROFILE_FILE"
                echo ""
                log_info "Run this to apply in current session:"
                echo -e "   ${CYAN}export IOS_AGENT_DRIVER_DIR=\"$IOS_AGENT_DRIVER_DIR\"${RESET}"
                echo ""
                # Set for current session
                export IOS_AGENT_DRIVER_DIR="$IOS_AGENT_DRIVER_DIR"
            else
                log_warning "IOS_AGENT_DRIVER_DIR not added to profile"
                log_info "You'll need to set it manually:"
                echo -e "   ${CYAN}export IOS_AGENT_DRIVER_DIR=\"$IOS_AGENT_DRIVER_DIR\"${RESET}"
                echo ""
                # Set for current session
                export IOS_AGENT_DRIVER_DIR="$IOS_AGENT_DRIVER_DIR"
            fi
        else
            log_success "IOS_AGENT_DRIVER_DIR is set: ${CYAN}$IOS_AGENT_DRIVER_DIR${RESET}"
            
            # Validate existing path
            if [ ! -d "$IOS_AGENT_DRIVER_DIR" ]; then
                log_error "IOS_AGENT_DRIVER_DIR points to non-existent directory: $IOS_AGENT_DRIVER_DIR"
                exit 1
            fi
            
            if [ ! -f "$IOS_AGENT_DRIVER_DIR/Project.swift" ]; then
                log_error "IOS_AGENT_DRIVER_DIR is not a valid IOSAgentDriver directory (Project.swift not found)"
                exit 1
            fi
        fi
        echo ""
        
        # Build release
        log_loading "Building release configuration..."
        if ! swift build -c release; then
            log_error "Build failed"
            exit 1
        fi
        
        log_success "Build completed"
        echo ""
        
        # Check if binary exists
        BINARY=".build/release/agent-cli"
        if [ ! -f "$BINARY" ]; then
            log_error "Binary not found at $BINARY"
            exit 1
        fi
        
        # Copy skill templates
        log_loading "Installing skill templates..."
        SKILL_INSTALL_DIR="$HOME/.agent-cli/skill"
        
        if [ -d "skill" ]; then
            mkdir -p "$SKILL_INSTALL_DIR"
            
            # Copy skill template files
            cp -r skill/* "$SKILL_INSTALL_DIR/"
            
            log_success "Skill templates installed to ${CYAN}$SKILL_INSTALL_DIR${RESET}"
            
            # Show what was installed
            log_info "Installed files:"
            echo "   • SKILL.md (template)"
            echo "   • SCENARIOS_TEMPLATE.md"
            echo "   • references/CLI-COMMANDS.md"
            echo "   • README.md"
        else
            log_warning "skill directory not found - skill generation may not work"
        fi
        echo ""
        
        # Install
        INSTALL_PATH="/usr/local/bin/agent-cli"
        
        log_info "Installing to ${CYAN}$INSTALL_PATH${RESET}..."
        echo ""
        
        # Check if already installed
        if [ -f "$INSTALL_PATH" ]; then
            CURRENT_SIZE=$(ls -lh "$INSTALL_PATH" 2>/dev/null | awk '{print $5}')
            log_warning "agent-cli is already installed ($CURRENT_SIZE)"
            echo -n "   Overwrite? [y/N]: "
            read -r RESPONSE
            if [[ ! "$RESPONSE" =~ ^[Yy]$ ]]; then
                log_info "Installation cancelled"
                exit 0
            fi
            echo ""
        fi
        
        # Copy binary (may require sudo)
        if sudo cp "$BINARY" "$INSTALL_PATH"; then
            sudo chmod +x "$INSTALL_PATH"
            log_success "Installed successfully to $INSTALL_PATH"
            echo ""
            
            # Show version
            log_info "Verifying installation..."
            if command -v agent-cli >/dev/null 2>&1; then
                log_success "agent-cli is now available globally"
                echo ""
                log_info "Test with:"
                echo -e "   ${CYAN}agent-cli --help${RESET}"
                echo -e "   ${CYAN}agent-cli --version${RESET}"
                echo ""
                log_success "${ROCKET} Installation complete!"
                echo ""
                log_info "Next steps:"
                echo "  1. Restart your terminal (or run: source $PROFILE_FILE)"
                echo -e "  2. Generate a QA skill: ${CYAN}agent-cli skill generate${RESET}"
                echo -e "  3. Create a session: ${CYAN}agent-cli session create --device \"iPhone 15\" --ios 17.5${RESET}"
                echo -e "  4. Start testing: ${CYAN}agent-cli api launch-app <session-id> com.apple.mobilesafari${RESET}"
            else
                log_warning "Installation succeeded but agent-cli not found in PATH"
                log_info "You may need to restart your terminal or check your PATH"
            fi
        else
            log_error "Installation failed (sudo required)"
            exit 1
        fi
        ;;
        
    --help|-h|help)
        usage
        exit 0
        ;;
        
    *)
        log_error "Unknown command: $COMMAND"
        echo ""
        usage
        exit 1
        ;;
esac

echo ""
