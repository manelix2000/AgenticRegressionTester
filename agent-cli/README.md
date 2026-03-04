# IOSAgentDriver CLI

**Multi-session iOS simulator testing tool for LLM agents**

IOSAgentDriver CLI is a Swift command-line tool that manages multiple concurrent iOS simulator sessions, each running an isolated IOSAgentDriver instance. It enables LLM agents and automated testing tools to interact with iOS apps through a simple, persistent session interface.

---

## Agent Skill

**🤖 Transform LLM agents into professional QA testers!**

New `skill generate` command creates customized skill templates that turn LLM agents (Claude, GitHub Copilot) into experienced iOS QA engineers.

```bash
# Interactive mode
agent-cli skill generate

# Generate skill for your project
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp"

# Use with LLM agents
gh copilot "using myapp-qa-skill, test the login flow"
```

**What you get**:
- 📋 Professional QA agent persona with systematic testing workflow
- 📚 Complete CLI command reference (all 32 commands documented)
- 🎯 Project-specific test scenarios template
- 🔧 Ready to use with GitHub Copilot, Claude Desktop, or any LLM API

See [Skill Generation](#skill-generation) section for details.

### Quick reference

```bash
# Create a session (auto-installs IOSAgentDriver)
agent-cli session create --device "iPhone 15" --ios 17.5

# List active sessions
agent-cli session list

# Launch Safari
agent-cli api launch-app <session-id> com.apple.mobilesafari

# Get UI tree
agent-cli api get-ui-tree <session-id>

# Take screenshot
agent-cli api screenshot <session-id> --output screenshot.png

# Delete session (stops IOSAgentDriver, cleans up simulator)
agent-cli session delete <session-id>
```

See [API Commands](#api-commands) and [Phase 3 Implementation](#phase-3-api-commands-complete) for details.

---

## Main Features

- 🤖 **QA Testing Skills** - Generate LLM agent skills for automated QA testing
- ⚡️ **Simulator Pool** - Pre-create simulators for near-instant session startup (5-7s vs 20-30s) *(Future)*
- 🎯 **Multi-Session Management** - Run multiple isolated test sessions simultaneously
- 📱 **Simulator Control** - Create, boot, shutdown, and manage iOS simulators via `simctl`
- 🧹 **Smart Cleanup** - Automatically deletes session-owned simulators, preserves shared ones
- 💾 **Persistent Sessions** - Sessions survive CLI restarts with file-based storage
- 🔌 **Port Management** - Automatic port allocation for each IOSAgentDriver instance
- 🎨 **Colorized Output** - ANSI colors for better readability (auto-detected)
- 📖 **Comprehensive Help** - Built-in help for all commands and options
- 🔄 **Snapshot Support** - Save and restore simulator states
- 📊 **JSON Mode** - Machine-readable output for all commands

---

## Installation

### Automated Installation (Recommended)

The easiest way to install agent-cli is using the automated build script, which handles all dependencies and configuration:

```bash
cd agent-cli
./build.sh install
```

**This will automatically:**
1. ✅ Check if Tuist is installed (offers to install via Homebrew if not)
2. ✅ Detect IOSAgentDriver directory location
3. ✅ Configure `IOS_AGENT_DRIVER_DIR` environment variable
4. ✅ Add `IOS_AGENT_DRIVER_DIR` to your shell profile (.zshrc, .bashrc, etc.)
5. ✅ Install skill templates to `~/.agent-cli/skill`
6. ✅ Build release version
7. ✅ Install to `/usr/local/bin` (requires sudo)

**Interactive prompts guide you through:**
- Tuist installation (if needed)
- IOSAgentDriver directory path detection/configuration
- Shell profile updates
- Installation confirmation

After installation, restart your terminal or run:
```bash
source ~/.zshrc  # or ~/.bashrc, ~/.bash_profile depending on your shell
```

**Important for Skill Generation**: The `IOS_AGENT_DRIVER_DIR` environment variable is automatically included in generated skills, allowing LLM agents to know the IOSAgentDriver project location. Ensure `IOS_AGENT_DRIVER_DIR` is set before generating skills.

### Manual Installation

If you prefer manual installation or need more control:

#### Prerequisites

- **macOS** 13.0 or later
- **Xcode** 15.0 or later (for iOS Simulator and simctl)
- **Swift** 6.0 or later
- **Tuist** (for building IOSAgentDriver)
- **IOSAgentDriver project** cloned locally

#### 1. Install Tuist

Choose one method:

**Homebrew (recommended):**
```bash
brew install tuist
```

**Official installer:**
```bash
curl -Ls https://install.tuist.io | bash
```

**mise (formerly rtx):**
```bash
mise install tuist
```

#### 2. Set IOS_AGENT_DRIVER_DIR Environment Variable

The CLI needs to know where your IOSAgentDriver project is located. Add this to your shell profile:

**For zsh (default on macOS Catalina+):**
```bash
echo 'export IOS_AGENT_DRIVER_DIR="/path/to/ios-driver"' >> ~/.zshrc
source ~/.zshrc
```

**For bash:**
```bash
echo 'export IOS_AGENT_DRIVER_DIR="/path/to/ios-driver"' >> ~/.bash_profile
source ~/.bash_profile
```

**For fish:**
```bash
echo 'set -gx IOS_AGENT_DRIVER_DIR "/path/to/ios-driver"' >> ~/.config/fish/config.fish
```

**Verify:**
```bash
echo $IOS_AGENT_DRIVER_DIR
# Should print: /path/to/ios-driver
```

⚠️ **Important**: Replace `/path/to` with the actual path to your AgenticRegressionTester project. For example:
```bash
export IOS_AGENT_DRIVER_DIR="/Users/yourname/Projects/AgenticRegressionTester/ios-driver"
```

**Note for Skill Generation**: The `IOS_AGENT_DRIVER_DIR` value is automatically included in generated skills, allowing LLM agents to reference the IOSAgentDriver project location. Ensure this variable is set before generating skills with `agent-cli skill generate`.

#### 3. Install Skill Templates (Required for skill generate command)

The `skill generate` command requires template files to be installed. Copy them manually:

```bash
# From the agent-cli directory
mkdir -p ~/.agent-cli/skill
cp -r skill/* ~/.agent-cli/skill/
```

**Verify installation:**
```bash
ls ~/.agent-cli/skill/
# Should show: SKILL.md  SCENARIOS_TEMPLATE.md  references/  README.md
```

This step is **automatically handled** by `./build.sh install`, but must be done manually if you're not using the automated installer.

#### 4. Build from Source

**Using the build script:**
```bash
cd agent-cli

# Build release (optimized)
./build.sh release

# Build debug (faster compilation, includes debug symbols)
./build.sh debug

# Build both configurations
./build.sh both

# Clean build artifacts
./build.sh clean

# Show help
./build.sh --help
```

**Manual build:**
```bash
cd agent-cli
swift build -c release
```

The binary will be at `.build/release/agent-cli`

#### 5. Install Globally

**Using the build script (validates dependencies):**
```bash
cd agent-cli
./build.sh install
```

**Manual installation:**
```bash
sudo cp .build/release/agent-cli /usr/local/bin/agent-cli
sudo chmod +x /usr/local/bin/agent-cli
```

**Verify installation:**
```bash
agent-cli --version
agent-cli --help
```

---

## Quick Start

### 1. List Available Simulators

```bash
agent-cli simulator list
```

Filter by status or iOS version:
```bash
agent-cli simulator list --booted
agent-cli simulator list --ios 17
```

### 2. Create a Session

```bash
# Create session with specific device and iOS version
agent-cli session create --device "iPhone 15" --ios 18.6

# Output:
# 🔄 Creating new simulator...
# ✅ Created simulator: IOSAgentDriver-34D3F4C6
# ✅ Session created: 550e8400-e29b-41d4-a716-446655440000
# 📱 Device: iPhone 15 (iOS 18.6)
# 🔌 Port: 8080
# 📡 Status: ready
```

**Options:**

```bash
# Custom port
agent-cli session create --device "iPhone 15" --ios 18.6 --port 9090

# Use existing simulator
agent-cli session create --simulator <udid>

# With app bundle ID
agent-cli session create --device "iPhone 15" --ios 18.6 --app com.example.MyApp
```

### 3. List Active Sessions

```bash
agent-cli session list
agent-cli session list --verbose  # Show creation/access times
```

### 4. Get Session Details

```bash
agent-cli session get <session-id>
```

### 5. Delete a Session

Sessions automatically clean up their resources based on simulator ownership:

```bash
# Delete a session (cleans up owned simulator if any)
agent-cli session delete <session-id>

# Force delete without confirmation
agent-cli session delete <session-id> --force

# Delete all sessions (cleans up all owned simulators)
agent-cli session delete-all
```

**What gets deleted:**
- ✅ **Always**: Session record and IOSAgentDriver instance stopped
- ✅ **If session created simulator** (`ownsSimulator=true`): Simulator is deleted
- ✅ **If session reused existing simulator** (via `--simulator` flag): Simulator is kept

---

## Commands

### Session Management

Manage IOSAgentDriver sessions with persistent state.

| Command | Description |
|---------|-------------|
| `session create` | Create a new session with IOSAgentDriver |
| `session list [-v]` | List all sessions |
| `session get <id>` | Get session details |
| `session delete <id> [-f]` | Delete a session (stops runner, cleans up owned simulators) |
| `session delete-all [-f]` | Delete all sessions (cleans up owned simulators) |

#### Session Model

Each session tracks:
- **ID**: Unique session identifier (UUID)
- **Simulator UDID**: Associated simulator
- **Port**: IOSAgentDriver HTTP port
- **Device Model**: e.g., "iPhone 15"
- **iOS Version**: e.g., "17.0"
- **Status**: `initializing`, `ready`, `running`, `stopped`, `error`
- **Installed App**: Bundle ID of installed app (optional)
- **Owns Simulator**: Boolean flag - whether session created the simulator
- **Created/Last Accessed**: Timestamps for lifecycle tracking

#### Smart Simulator Cleanup

Sessions automatically track whether they own their simulator:

- **Created simulators** (`ownsSimulator = true`): Deleted when session is deleted
- **Reused simulators** (`ownsSimulator = false`, via --simulator): Kept when session is deleted

```bash
# This creates a new simulator (owned by session)
# Deleting the session will DELETE the simulator
agent-cli session create --device "iPhone 15" --ios 18.6

# This reuses an existing simulator (not owned, manually specified)
# Deleting the session will KEEP the simulator
agent-cli session create --simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983
```

**Confirmation messages show what will happen:**
```bash
$ agent-cli session delete abc123
Delete session abc123?
   ⚠️  This will stop IOSAgentDriver and DELETE the simulator (4324F701...)
   Type 'yes' to confirm:
```

**Or for reused simulators:**
```bash
$ agent-cli session delete xyz789
Delete session xyz789?
   This will stop IOSAgentDriver but KEEP the simulator (reused)
   Type 'yes' to confirm:
```

### Simulator Management

Direct access to `xcrun simctl` for simulator lifecycle operations.

| Command | Description |
|---------|-------------|
| `simulator list [-b] [--ios]` | List all simulators |
| `simulator list-apps <udid> [--user-only] [--json]` | List apps installed on a simulator |
| `simulator create <name> [-d] [-r]` | Create a new simulator |
| `simulator delete <udid> [-f]` | Delete a simulator |
| `simulator boot <udid>` | Boot a simulator |
| `simulator shutdown <udid>` | Shutdown a simulator |
| `simulator snapshot <udid> <name>` | Create a snapshot (clone) |
| `simulator info <udid>` | Get simulator information |
| `simulator cleanup [--force]` | Delete all IOSAgentDriver-related simulators |

#### Examples

```bash
# Create a new simulator
agent-cli simulator create "Test iPhone" --device "iPhone 15" --runtime "iOS 17.0"

# Boot a simulator
agent-cli simulator boot <udid>

# List all apps on a simulator
agent-cli simulator list-apps <udid>

# List only user-installed apps (exclude system apps)
agent-cli simulator list-apps <udid> --user-only

# Create a snapshot of current state
agent-cli simulator snapshot <udid> "clean-state"

# Cleanup all IOSAgentDriver simulators (interactive confirmation)
agent-cli simulator cleanup

# Force cleanup without confirmation
agent-cli simulator cleanup --force

# Delete a simulator
agent-cli simulator delete <udid> --force
```

---

## API Commands

Interact with IOSAgentDriver's HTTP API to control apps and query UI state. All commands are session-aware and automatically route requests to the correct IOSAgentDriver instance.

### Application Management

| Command | Description |
|---------|-------------|
| `api launch-app <session> <bundleId>` | Launch an application (supports --arguments) |
| `api terminate-app <session> [bundleId]` | Terminate the running application |
| `api app-state <session>` | Get current application state (bundle ID, PID, state) |
| `api install-app <session> <path>` | Install an app bundle (.app) on the simulator |

#### Examples

```bash
# Launch Safari
agent-cli api launch-app abc123 com.apple.mobilesafari

# Check app state
agent-cli api app-state abc123

# Terminate app
agent-cli api terminate-app abc123 com.apple.mobilesafari

# Install custom app
agent-cli api install-app abc123 /path/to/MyApp.app
```

### UI Discovery

| Command | Description |
|---------|-------------|
| `api get-ui-tree <session>` | Get complete accessibility tree |
| `api find-element <session> <predicate>` | Find first element matching predicate |
| `api find-elements <session> <predicate>` | Find all elements matching predicate |
| `api get-element <session> <identifier>` | Get element by accessibility identifier |

#### Examples

```bash
# Get full UI tree
agent-cli api get-ui-tree abc123

# Find first button
agent-cli api find-element abc123 'type == "Button"'

# Find all text fields
agent-cli api find-elements abc123 'type == "TextField"'

# Get element by identifier
agent-cli api get-element abc123 "loginButton"

# Complex predicate
agent-cli api find-element abc123 'label CONTAINS "Submit" AND isEnabled == true'
```

### UI Interactions

| Command | Description |
|---------|-------------|
| `api tap <session> <selector>` | Tap an element (by identifier, label, or predicate) |
| `api type-text <session> <selector> <text>` | Type text into an element. Use `--clear` to clear first |
| `api swipe <session> <selector> <direction>` | Swipe in direction (up/down/left/right) |
| `api wait-for-element <session> <identifier>` | Wait for element (supports --condition, --value, --timeout, --soft-validation) |

#### Examples

```bash
# Tap by identifier (default)
agent-cli api tap abc123 "loginButton"

# Tap by label
agent-cli api tap abc123 "Login" --selector-type label

# Tap by predicate (auto-detected)
agent-cli api tap abc123 "label == 'Login'"

# Type text by identifier
agent-cli api type-text abc123 "usernameField" "john@example.com"

# Type text by label
agent-cli api type-text abc123 "Username" "john@example.com" --selector-type label

# Clear field before typing
agent-cli api type-text abc123 "emailField" "new@email.com" --clear

# Swipe by identifier
agent-cli api swipe abc123 "tableView" up

# Swipe by label
agent-cli api swipe abc123 "Main Content" left --selector-type label

# Wait for element
agent-cli api wait-for-element abc123 'identifier == "welcomeMessage"' --timeout 10
```

### Validation & Testing

| Command | Description |
|---------|-------------|
| `api detect-alert <session>` | Check if system alert is present |
| `api dismiss-alert <session> <buttonLabel>` | Dismiss alert by tapping button |
| `api screenshot <session> [--output path]` | Capture screenshot |
| `api health <session>` | Check IOSAgentDriver health status |

#### Examples

```bash
# Check for alerts
agent-cli api detect-alert abc123

# Dismiss alert
agent-cli api dismiss-alert abc123 "Allow"

# Screenshot with auto filename
agent-cli api screenshot abc123

# Screenshot with custom path
agent-cli api screenshot abc123 --output ~/Desktop/test.png

# Health check
agent-cli api health abc123
```

### Configuration

| Command | Description |
|---------|-------------|
| `api get-config <session>` | Get IOSAgentDriver configuration |
| `api set-timeout <session> <seconds>` | Set default element timeout |

#### Examples

```bash
# Get current config
agent-cli api get-config abc123

# Set 15 second timeout
agent-cli api set-timeout abc123 15
```

### JSON Output

**All 37 CLI commands** support `--json` flag for machine-readable output, perfect for automation and LLM integration.

#### Session Commands (5)
```bash
# List sessions
agent-cli session list --json

# Create session
agent-cli session create --device "iPhone 15" --ios 18.6 --json

# Get session details
agent-cli session get <session-id> --json

# Delete session
agent-cli session delete <session-id> --json
```

**JSON Output Format:**
```json
{
  "success": true,
  "data": {
    "session": {
      "id": "abc123",
      "port": 8080,
      "device": "iPhone 15",
      "iOSVersion": "18.6",
      "status": "running"
    }
  }
}
```

#### Simulator Commands (9)
```bash
# List simulators
agent-cli simulator list --json

# Create simulator
agent-cli simulator create "TestSim" --device "iPhone 15" --json

# Boot/shutdown simulator
agent-cli simulator boot <udid> --json
agent-cli simulator shutdown <udid> --json

# Get simulator info
agent-cli simulator info <udid> --json

# Cleanup IOSAgentDriver simulators
agent-cli simulator cleanup --force --json
```

**JSON Output Format:**
```json
{
  "success": true,
  "data": {
    "name": "TestSim",
    "udid": "ABC-123",
    "device": "iPhone 15",
    "runtime": "iOS 18.6"
  }
}
```

#### API Commands (18)
```bash
# Get UI tree as JSON
agent-cli api get-ui-tree <session-id> --json

# Launch app and get JSON response
agent-cli api launch-app <session-id> com.apple.mobilesafari --json

# Take screenshot
agent-cli api screenshot <session-id> --json

# Tap element
agent-cli api tap <session-id> "identifier == 'button'" --json
```

**JSON Output Format:**
```json
{
  "success": true,
  "data": {
    "...": "command-specific data"
  },
  "error": null,
  "executionTime": 0.0
}
```

**Error Format:**
```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "SESSION_NOT_FOUND",
    "message": "Session not found: abc123"
  }
}
```

### Predicate Syntax

UI element predicates use NSPredicate format:

```bash
# Exact match
'identifier == "loginButton"'

# Contains
'label CONTAINS "Submit"'

# Multiple conditions
'type == "Button" AND isEnabled == true'

# Type-based search
'type == "TextField"'
'type == "Button"'
'type == "StaticText"'

# Visibility and state
'isVisible == true'
'isSelected == true'
'hasFocus == true'
```

**Element Types** (from XCUIElement.ElementType):
- `0` = Any
- `1` = Other
- `2` = Application
- `9` = Button
- `12` = TextField
- `48` = StaticText
- [Full list in Apple's documentation]

### Testing Status

| Status | Count | Notes |
|--------|-------|-------|
| ✅ Tested & Working | 15 | All tested commands work perfectly |
| ⚠️ Known Issues | 2 | Minor UX improvements needed |
| ❌ Server Crash | 1 | `find-elements` (workaround: use `find-element`) |
| ⏸️ Not Tested | 5 | To be tested with real use cases |

See [CLI Testing Summary](files/cli-command-testing-summary.md) for detailed test results.

---

## Skill Generation

Transform LLM agents (Claude, GitHub Copilot, etc.) into professional iOS QA engineers using the `skill generate` command.

### Overview

The skill generation feature creates a complete testing skill package that includes:
- **SKILL.md** - Professional QA agent persona with systematic testing workflow
- **SCENARIOS.md** - Project-specific test scenarios template (customizable)
- **references/CLI-COMMANDS.md** - Complete CLI command reference (32 commands)

### Quick Start

```bash
# Interactive mode (prompts for values)
agent-cli skill generate

# Non-interactive mode
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp"

# Custom output location
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp" \
  --output ./my-skills/myapp-qa

# JSON output
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp" \
  --json
```

### Usage with LLM Agents

#### GitHub Copilot CLI

Skills are automatically detected in `~/.copilot/skills/`:

```bash
# Generate skill
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp"

# Use with Copilot (skill auto-detected)
gh copilot "using myapp-qa-skill, test the login flow"
gh copilot "using myapp-qa-skill, check for regressions in checkout"
```

#### Claude Desktop (MCP)

Configure in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "myapp-qa": {
      "command": "agent-cli",
      "args": ["skill", "serve", "~/.copilot/skills/myapp-qa-skill"]
    }
  }
}
```

#### Any LLM API/SDK

Load SKILL.md as the system prompt:

```python
# Python example
with open("~/.copilot/skills/myapp-qa-skill/SKILL.md") as f:
    skill_prompt = f.read()

response = claude.messages.create(
    system=[{"type": "text", "text": skill_prompt}],
    messages=[{
        "role": "user",
        "content": "Test the login flow for regressions"
    }]
)
```

### Skill Structure

Generated skills have this structure:

```
~/.copilot/skills/myapp-qa-skill/
├── SKILL.md                      # Main agent prompt (customized)
│   ├── YAML frontmatter          #   - Skill metadata (name, version, tags)
│   └── Markdown content          #   - Agent instructions and examples
├── SCENARIOS.md                  # Test scenarios (customize this!)
└── references/
    └── CLI-COMMANDS.md           # Complete CLI reference
```

**SKILL.md includes**:
- ✅ YAML frontmatter with skill metadata (required by Copilot CLI)
  - `name` property matching directory name (e.g., `privalia-qa-skill`)
  - `skill` display name (e.g., `Privalia QA Testing`)
  - Version, description, author, and tags
- ✅ Professional QA engineer persona
- ✅ Systematic testing workflow
- ✅ Complete command examples
- ✅ Best practices and troubleshooting

**Name normalization**: Project names are automatically converted:
- "Privalia" → `privalia-qa-skill`
- "My App" → `my-app-qa-skill`
- Special characters removed, spaces to hyphens, lowercase

### Customizing Your Skill

1. **Edit SCENARIOS.md** to add your app-specific test cases:
   ```bash
   cd ~/.copilot/skills/myapp-qa-skill
   nano SCENARIOS.md
   ```

2. **Add navigation paths** - Document your app's screens and key elements
3. **Add user journeys** - Define common test flows with step-by-step commands
4. **Add test data** - Valid/invalid users, sample content
5. **Document known issues** - Flaky tests, workarounds

### Example Agent Interaction

**Prompt**: "Using myapp-qa-skill, test if there's any regression in the checkout flow"

**Agent Response**:
```markdown
I'll test the checkout flow systematically. Let me create a plan:

## Test Plan: Checkout Flow

1. Create session (iPhone 15, iOS 18.6)
2. Launch MyApp
3. Navigate to product catalog
4. Add item to cart
5. Proceed to checkout
6. Verify confirmation

Executing...

$ agent-cli session create --device "iPhone 15" --ios "18.6" --json
✅ Session created: abc-123

$ agent-cli api launch-app abc-123 com.example.myapp --json
✅ App launched

[... continues with detailed testing ...]
```

### Command Options

```bash
agent-cli skill generate [OPTIONS]

OPTIONS:
  -p, --project-name <name>   Project name (e.g., 'MyApp')
  -b, --bundle-id <id>        App bundle ID (e.g., 'com.example.myapp')
  -o, --output <path>         Output directory (default: ~/.copilot/skills/{project}-qa-skill)
  --json                      Output in JSON format
  -h, --help                  Show help information
```

**Note**: After generation, manually edit `SCENARIOS.md` to add your app-specific test scenarios.

### JSON Output Format

```json
{
  "success": true,
  "data": {
    "projectName": "MyApp",
    "bundleId": "com.example.myapp",
    "outputDirectory": "~/.copilot/skills/myapp-qa-skill",
    "files": [
      "~/.copilot/skills/myapp-qa-skill/SKILL.md",
      "~/.copilot/skills/myapp-qa-skill/SCENARIOS.md",
      "~/.copilot/skills/myapp-qa-skill/references/CLI-COMMANDS.md"
    ]
  }
}
```

### What Makes This Powerful

1. **Complete Command Reference** - Agent knows all 32 CLI commands with examples
2. **Systematic Approach** - Enforces professional QA workflow (plan → execute → report)
3. **Evidence-Based** - Agent captures screenshots, logs, and errors
4. **Project-Specific** - Customizable scenarios for your app's flows
5. **Error Handling** - Agent knows how to debug and recover from failures
6. **Best Practices** - Built-in guidance for element identification, waits, etc.
7. **Standards Compliant** - YAML frontmatter makes skills discoverable by Copilot CLI
8. **Environment Aware** - Includes IOSAgentDriver project location for context

### Environment Information in Skills

Generated skills include environment configuration to help agents understand the project structure:

**Included in every skill**:
- **IOSAgentDriver Location** (`IOS_AGENT_DRIVER_DIR`) - Path to IOSAgentDriver Xcode project
- **App Bundle ID** - Target application identifier
- **Project Name** - Application name for context

**Example in generated skill**:
```markdown
## Environment Configuration

### Project Paths
- **IOSAgentDriver Location**: `/Users/you/Projects/AgenticRegressionTester/ios-driver`

### Application Under Test
- **App Bundle ID**: `com.example.myapp`
```

This allows agents to understand the project structure without needing to discover it at runtime.

### Template Files

The skill templates are installed during the setup process:

**Installation location**: `~/.agent-cli/skill/`

**Source location**: `agent-cli/skill/` (in the repository)

**Files**:
- `SKILL.md` - Main agent prompt template
- `SCENARIOS_TEMPLATE.md` - Test scenarios template
- `references/CLI-COMMANDS.md` - CLI command reference
- `README.md` - Template usage documentation

**Installation**:
- ✅ Automatic: Templates are installed by `./build.sh install`
- 📋 Manual: Copy with `cp -r skill/* ~/.agent-cli/skill/`

The `skill generate` command reads templates from `~/.agent-cli/skill/` and creates customized skills in `~/.copilot/skills/{project}-qa-skill/`.

See [skill/README.md](skill/README.md) for detailed template documentation.

---

## Colorized Output

The CLI provides rich, colorized terminal output for better readability and user experience.

### Color Semantics

**Status Colors:**
- 🟢 **Green**: Success, ready states, active/booted simulators
- 🔴 **Red**: Errors, failures, critical issues
- 🟡 **Yellow**: Warnings, confirmations, pending operations
- 🔵 **Blue**: Loading operations, in-progress tasks
- ⚪️ **Gray**: Inactive/shutdown states, metadata (UUIDs, timestamps)
- 🔷 **Cyan**: Information messages, hints, tips

**Text Formatting:**
- **Bold**: Headers and section titles
- **Highlighted** (bright yellow): Important values, user inputs
- **Code** (cyan): Command examples, file paths, identifiers
- **Labels** (white): Field names before values
- **Values** (bright white): Field values, important data

### Output Examples

**List Output:**
```bash
$ agent-cli simulator list --booted

📱 Simulators (2):

  🟢 iPhone 16
     UDID: A4FBE4AD-B8FD-...
     State: Booted
     Device: iPhone 16
     iOS: 18.6

  🟢 iPad Pro
     UDID: E5F6G7H8-1234-...
     State: Booted
     Device: iPad Pro
     iOS: 18.6
```

**Creation with Next Steps:**
```bash
$ agent-cli simulator create "Test Phone" --device "iPhone 15" --runtime "iOS 18.6"

🔄 Creating simulator 'Test Phone'...
   Device: iPhone 15
   Runtime: iOS 18.6
✅ Created simulator: Test Phone
   UDID: 2F9DB506-5F57-...

ℹ️  💡 Use this UDID for session creation:
   agent-cli session create --simulator 2F9DB506-5F57-...
```

**Confirmation Prompts:**
```bash
$ agent-cli simulator delete 2F9DB506-5F57-...

⚠️  Delete simulator 'Test Phone' (2F9DB506-5F57-...)?
   Type 'yes' to confirm: yes
✅ Deleted simulator 2F9DB506-5F57-...
```

**Empty States:**
```bash
$ agent-cli session list

ℹ️  No sessions found
ℹ️  Create one with 'agent-cli session create'
```

### Auto-Detection

Colors are automatically disabled when:
- Output is piped to another command (`agent-cli list | grep pattern`)
- Output is redirected to a file (`agent-cli list > output.txt`)
- Running in non-TTY environments (CI/CD systems)
- `TERM` environment variable is set to `"dumb"`

This ensures scripts and automation tools receive clean, parseable output.

---

## Help System

The CLI has comprehensive built-in help at every level, with **colorized output and practical examples**.

### Two Ways to Get Help

ArgumentParser provides two equivalent ways to access help:

```bash
# Method 1: Using --help flag (recommended)
agent-cli --help
agent-cli session --help
agent-cli session create --help

# Method 2: Using help subcommand
agent-cli help
agent-cli help session
agent-cli help session create
```

Both methods produce identical output. Use whichever feels more natural!

### Help Features

Each help screen shows:
- **Command overview** and description
- **Practical examples** with copy-paste ready commands
- **Usage syntax** with required and optional parameters
- **All options** with short (-d) and long (--device) flag forms
- **Option descriptions** explaining what each flag does

### Help Hierarchy

**Level 1: Main Help**
```bash
agent-cli --help
```
Shows overview and lists available command groups (session, simulator).

**Level 2: Command Group Help**
```bash
agent-cli session --help
```
Shows common usage examples and all subcommands:

```
Examples:
  # List all sessions
  agent-cli session list
  
  # Create a new session
  agent-cli session create --device "iPhone 15" --ios 18.6
  
  # Get session details
  agent-cli session get <session-id>

SUBCOMMANDS:
  create                  Create a new session
  list                    List all sessions
  get                     Get session details
  delete                  Delete a session
  delete-all              Delete all sessions
```

**Level 3: Individual Command Help**
```bash
agent-cli session create --help
```
Shows detailed usage with multiple examples and all options:

```
Examples:
  # Create with defaults from config
  agent-cli session create
  
  # Specify device and iOS version
  agent-cli session create --device "iPhone 15" --ios 18.6
  
  # Custom port
  agent-cli session create --port 9090
  
  # With app installation
  agent-cli session create --app com.example.MyApp

OPTIONS:
  -d, --device <device>   Device model (e.g., 'iPhone 15')
  -i, --ios <ios>         iOS version (e.g., '17.0')
  -p, --port <port>       Port number for IOSAgentDriver
  -a, --app <app>         App bundle ID to install
```

### Copy-Paste Ready Examples

All examples in the help output are:
- ✅ Valid, runnable commands
- ✅ Properly formatted with comments
- ✅ Show both short and long flag forms where applicable
- ✅ Demonstrate common use cases
- ✅ Progress from simple to complex usage

### Color-Coded Help

The help system automatically shows color-coded output:
- **Examples section** with dimmed comment lines and cyan commands
- **Headers** (Available commands:) in bold cyan
- **Command names** in bright yellow
- **Info hints** (Use '...') in cyan with ℹ️ emoji
- Colors auto-disable for pipes, redirects, and non-TTY environments

---

## Configuration

Configuration is stored in `~/.agent-cli/config.json`:

```json
{
  "defaultDevice": "iPhone 15",
  "defaultiOSVersion": "18.6",
  "autoCleanupIdleMinutes": 30,
  "startPort": 8080
}
```

### Configuration Options

- **defaultDevice**: Default device model for sessions
- **defaultiOSVersion**: Default iOS version
- **autoCleanupIdleMinutes**: Auto-cleanup idle sessions after N minutes
- **startPort**: Starting port for IOSAgentDriver instances

---

## Storage

All CLI data is stored in `~/.agent-cli/`:

```
~/.agent-cli/
├── sessions.json     # Active sessions
└── config.json       # CLI configuration
```

### Session Storage Format

```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "simulatorUDID": "6D97F8F5-F14A-4555-8C07-34B0B3EDEDA3",
    "port": 8080,
    "deviceModel": "iPhone 15",
    "iOSVersion": "17.0",
    "status": "ready",
    "installedApp": "com.example.myapp",
    "ownsSimulator": true,
    "createdAt": "2026-03-01T18:00:00Z",
    "lastAccessedAt": "2026-03-01T18:10:00Z"
  }
]
```

**Field Descriptions:**
- **id**: Unique session identifier (UUID)
- **simulatorUDID**: iOS Simulator UDID this session uses
- **port**: HTTP port where IOSAgentDriver API is exposed
- **deviceModel**: iOS device model (e.g., "iPhone 15")
- **iOSVersion**: iOS version (e.g., "17.0")
- **status**: Session status (`initializing`, `ready`, `running`, `stopped`, `error`)
- **installedApp**: Optional app bundle ID installed in this session
- **ownsSimulator**: Boolean flag indicating if session created this simulator
- **createdAt**: ISO 8601 timestamp when session was created
- **lastAccessedAt**: ISO 8601 timestamp of last session access

### Simulator Ownership

Sessions track whether they own their simulator through the `ownsSimulator` field:

**When `ownsSimulator = true` (session created simulator):**
- Session created a new simulator using `--device` and `--ios` flags
- **Deleting the session will also delete the simulator**
- Use this when you want automatic cleanup

**When `ownsSimulator = false` (simulator was reused):**
- Session was created with `--simulator <udid>` flag
- **Deleting the session will keep the simulator**
- Use this for shared simulators across multiple sessions

**Examples:**

```bash
# Creates new simulator → ownsSimulator = true
# Deleting this session will DELETE the simulator
agent-cli session create --device "iPhone 15" --ios 17.0

# Reuses existing simulator → ownsSimulator = false
# Deleting this session will KEEP the simulator
agent-cli session create --simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983
```

This ownership model enables:
- ✅ **Automatic cleanup** - Sessions clean up their own resources
- ✅ **Shared simulators** - Multiple sessions can safely share simulators
- ✅ **Explicit control** - Users know exactly what gets deleted

---

## IOSAgentDriver Scripts

The CLI depends on shell scripts in the IOSAgentDriver project for lifecycle management. These scripts are called automatically by the CLI but can also be used standalone.

### start_driver.sh

Starts IOSAgentDriver on a simulator with intelligent build management.

**Location:** `$IOS_AGENT_DRIVER_DIR/scripts/start_driver.sh`

**Features:**
- Smart installation detection (skips rebuild if already installed)
- Single `tuist test` command handles build, install, and launch
- Exponential backoff health checks (1s → 2s → 4s → 8s → 16s)
- Test plan generation with port configuration
- Comprehensive error handling with exit codes

**Manual Usage:**
```bash
cd $IOS_AGENT_DRIVER_DIR/scripts
./start_driver.sh <simulator-udid> <port> [bundle-id]

# Example
./start_driver.sh A4FBE4AD-B8FD-4B11-82DF-FC133F535983 8080
```

**See:** Complete documentation in `ios-driver/scripts/README.md`

### stop_driver.sh

Stops IOSAgentDriver with three-tier graceful shutdown.

**Location:** `$IOS_AGENT_DRIVER_DIR/scripts/stop_driver.sh`

**Features:**
- Three-tier shutdown: API → SIGTERM → SIGKILL
- Graceful resource cleanup when possible
- Works even with shutdown simulators
- Always succeeds (exits 0) if runner stops

**Manual Usage:**
```bash
cd $IOS_AGENT_DRIVER_DIR/scripts
./stop_driver.sh <simulator-udid> <port>

# Example
./stop_driver.sh A4FBE4AD-B8FD-4B11-82DF-FC133F535983 8080
```

**See:** Complete documentation in `ios-driver/scripts/README.md`

### generate_testplan.sh

Creates Xcode test plan with environment variables (called internally by start_driver.sh).

**Purpose:** Configures `RUNNER_PORT` and `INSTALLED_APPLICATIONS` environment variables for IOSAgentDriver.

---

## Architecture

### Project Structure

```
agent-cli/
├── Package.swift              # Swift package manifest
├── Sources/
│   └── agent-cli/
│       ├── ios_runner_cli.swift         # Main CLI entry point
│       ├── Models/
│       │   └── Session.swift            # RunnerSession model
│       ├── Core/
│       │   ├── SessionManager.swift     # Session persistence
│       │   └── SimulatorManager.swift   # Simulator management
│       └── Commands/
│           ├── SessionCommands.swift    # Session CLI commands
│           └── SimulatorCommands.swift  # Simulator CLI commands
└── README.md
```

### Key Components

1. **SessionManager**: Thread-safe session persistence using file-based JSON storage
2. **SimulatorManager**: Wrapper around `xcrun simctl` for simulator operations
3. **RunnerManager**: Manages IOSAgentDriver lifecycle via shell scripts (start/stop/health)
4. **RunnerSession**: Model representing an active IOSAgentDriver session
5. **ArgumentParser**: CLI framework for command parsing and help generation
6. **ColorPrint**: ANSI color utility for terminal output

### Scripts Integration

The CLI relies on shell scripts in `ios-driver/scripts/`:

- **start_driver.sh**: Builds (if needed) and launches IOSAgentDriver on simulator
- **stop_driver.sh**: Three-tier graceful shutdown (API → SIGTERM → SIGKILL)
- **generate_testplan.sh**: Creates Xcode test plan with environment variables

These scripts are executed by `RunnerManager.swift` via Swift's `Process` API.

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CLI Framework | Swift ArgumentParser | Official Apple framework, type-safe, auto-help |
| Session Storage | File-based JSON | Simple, debuggable, persistent across restarts |
| Concurrency | `@unchecked Sendable` + NSLock | Swift 6 compliant, thread-safe |
| Simulator Control | `xcrun simctl` wrapper | Native tool, full feature access |

---

## Contributing

This is part of the AgenticRegressionTester project. See main project README for contribution guidelines.

---

## License

MIT License - Free to use

**Author**: manelix  
**GitHub**: [github.com/manelix2000](https://github.com/manelix2000)

Copyright (c) 2026 manelix

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## Related Projects

- **IOSAgentDriver** (`ios-driver/`) - The UI test runner that this CLI controls

---

## Support

For issues and questions:
1. Check this README and troubleshooting section
2. Review session logs in `~/.agent-cli/`
3. Check IOSAgentDriver documentation for API details

---

**Last Updated**: March 3, 2026
