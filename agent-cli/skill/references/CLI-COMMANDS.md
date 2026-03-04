# IOSAgentDriver CLI - Complete Command Reference

This document provides comprehensive reference for all `agent-cli` commands with syntax, parameters, and examples.

---

## Table of Contents

- [Session Management (5 commands)](#session-management)
- [Simulator Management (9 commands)](#simulator-management)
- [API Commands (18 commands)](#api-commands)
  - [App Lifecycle](#app-lifecycle)
  - [UI Interaction](#ui-interaction)
  - [UI Query](#ui-query)
  - [Configuration](#configuration)

---

## Session Management

Sessions represent active IOSAgentDriver instances running on iOS simulators. Each session has a unique ID, dedicated simulator, and port.

### session create

**Description**: Create a new testing session with a dedicated simulator and IOSAgentDriver instance.

**Syntax**:
```bash
agent-cli session create --device <device> --ios <version> [OPTIONS]
```

**Required Parameters**:
- `--device <device>` or `-d <device>` - Device model (e.g., "iPhone 15", "iPhone 15 Pro")
- `--ios <version>` or `-i <version>` - iOS version (e.g., "18.6", "17.5")

**Optional Parameters**:
- `--port <port>` or `-p <port>` - Custom port number (default: auto-assigned from 8080+)
- `--app <bundle-id>` or `-a <bundle-id>` - App bundle ID to install after creation
- `--simulator <udid>` - Use existing simulator UDID (skips creation)
- `--force-reinstall` - Force reinstall IOSAgentDriver even if present
- `--json` - Output in JSON format

**Examples**:
```bash
# Create session with iPhone 15, iOS 18.6
agent-cli session create --device "iPhone 15" --ios "18.6"

# Create with custom port
agent-cli session create -d "iPhone 15" -i "18.6" --port 9090

# Create with JSON output
agent-cli session create -d "iPhone 15" -i "18.6" --json

# Create using existing simulator
agent-cli session create --simulator ABC-123-DEF

# Create and install app
agent-cli session create -d "iPhone 15" -i "18.6" --app com.example.myapp
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "sessionId": "550e8400-e29b-41d4-a716-446655440000",
    "simulatorUDID": "6D97F8F5-F14A-4555-8C07-34B0B3EDEDA3",
    "port": 8080,
    "device": "iPhone 15",
    "iOSVersion": "18.6",
    "status": "ready",
    "ownsSimulator": true,
    "createdAt": "2026-03-02T14:30:00Z",
    "lastAccessedAt": "2026-03-02T14:30:00Z"
  }
}
```

---

### session list

**Description**: List all active sessions.

**Syntax**:
```bash
agent-cli session list [OPTIONS]
```

**Optional Parameters**:
- `--verbose` or `-v` - Show detailed information including timestamps
- `--json` - Output in JSON format

**Examples**:
```bash
# List sessions (simple view)
agent-cli session list

# List with timestamps
agent-cli session list --verbose

# List as JSON
agent-cli session list --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "total": 2,
    "sessions": [
      {
        "id": "abc-123",
        "device": "iPhone 15",
        "iOSVersion": "18.6",
        "port": 8080,
        "status": "ready",
        "simulatorUDID": "6D97F8F5-F14A-4555-8C07-34B0B3EDEDA3"
      }
    ]
  }
}
```

---

### session get

**Description**: Get detailed information about a specific session.

**Syntax**:
```bash
agent-cli session get <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID to retrieve

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Get session details
agent-cli session get abc-123

# Get as JSON
agent-cli session get abc-123 --json
```

**JSON Response**: Same format as `session create` response.

---

### session delete

**Description**: Delete a session, stopping IOSAgentDriver and cleaning up resources.

**Syntax**:
```bash
agent-cli session delete <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID to delete

**Optional Parameters**:
- `--force` or `-f` - Delete without confirmation prompt
- `--json` - Output in JSON format

**Examples**:
```bash
# Delete with confirmation
agent-cli session delete abc-123

# Force delete
agent-cli session delete abc-123 --force

# Delete with JSON output
agent-cli session delete abc-123 -f --json
```

**Behavior**:
- If session owns simulator (`ownsSimulator: true`): Simulator is deleted
- If session reused simulator (`ownsSimulator: false`): Simulator is kept

---

### session delete-all

**Description**: Delete all sessions.

**Syntax**:
```bash
agent-cli session delete-all [OPTIONS]
```

**Optional Parameters**:
- `--force` or `-f` - Delete without confirmation
- `--json` - Output in JSON format

**Examples**:
```bash
# Delete all with confirmation
agent-cli session delete-all

# Force delete all
agent-cli session delete-all --force

# Delete all as JSON
agent-cli session delete-all -f --json
```

---

## Simulator Management

Commands for controlling iOS simulators directly (without sessions).

### simulator list

**Description**: List all iOS simulators.

**Syntax**:
```bash
agent-cli simulator list [OPTIONS]
```

**Optional Parameters**:
- `--booted` - Show only booted simulators
- `--ios <version>` - Filter by iOS version (e.g., "18", "17.5")
- `--json` - Output in JSON format

**Examples**:
```bash
# List all simulators
agent-cli simulator list

# List only booted
agent-cli simulator list --booted

# List iOS 18.x simulators
agent-cli simulator list --ios 18

# List as JSON
agent-cli simulator list --json
```

---

### simulator create

**Description**: Create a new simulator.

**Syntax**:
```bash
agent-cli simulator create <name> [OPTIONS]
```

**Required Parameters**:
- `<name>` - Simulator name

**Optional Parameters**:
- `--device <device>` - Device type (default: "iPhone 15")
- `--runtime <runtime>` - Runtime ID (e.g., "iOS-18-6")
- `--json` - Output in JSON format

**Examples**:
```bash
# Create with defaults
agent-cli simulator create "Test iPhone"

# Create with specific device
agent-cli simulator create "Test iPhone" --device "iPhone 15 Pro"

# Create with JSON output
agent-cli simulator create "Test iPhone" --json
```

---

### simulator delete

**Description**: Delete a simulator.

**Syntax**:
```bash
agent-cli simulator delete <udid> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Delete simulator
agent-cli simulator delete ABC-123-DEF

# Delete with JSON output
agent-cli simulator delete ABC-123-DEF --json
```

---

### simulator boot

**Description**: Boot a simulator.

**Syntax**:
```bash
agent-cli simulator boot <udid> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Boot simulator
agent-cli simulator boot ABC-123-DEF

# Boot with JSON output
agent-cli simulator boot ABC-123-DEF --json
```

---

### simulator shutdown

**Description**: Shutdown a running simulator.

**Syntax**:
```bash
agent-cli simulator shutdown <udid> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Shutdown simulator
agent-cli simulator shutdown ABC-123-DEF

# Shutdown with JSON
agent-cli simulator shutdown ABC-123-DEF --json
```

---

### simulator info

**Description**: Get detailed simulator information.

**Syntax**:
```bash
agent-cli simulator info <udid> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Get simulator info
agent-cli simulator info ABC-123-DEF

# Get as JSON
agent-cli simulator info ABC-123-DEF --json
```

---

### simulator list-apps

**Description**: List apps installed on a simulator.

**Syntax**:
```bash
agent-cli simulator list-apps <udid> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID

**Optional Parameters**:
- `--user-only` - Show only user-installed apps (exclude system apps)
- `--json` - Output raw PropertyList JSON

**Examples**:
```bash
# List all apps
agent-cli simulator list-apps ABC-123-DEF

# List only user apps
agent-cli simulator list-apps ABC-123-DEF --user-only

# Get raw JSON
agent-cli simulator list-apps ABC-123-DEF --json
```

---

### simulator snapshot

**Description**: Create a snapshot of simulator state.

**Syntax**:
```bash
agent-cli simulator snapshot <udid> <name> [OPTIONS]
```

**Required Parameters**:
- `<udid>` - Simulator UDID
- `<name>` - Snapshot name

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Create snapshot
agent-cli simulator snapshot ABC-123-DEF "clean-state"

# Create with JSON output
agent-cli simulator snapshot ABC-123-DEF "clean-state" --json
```

---

### simulator cleanup

**Description**: Delete all IOSAgentDriver-managed simulators.

**Syntax**:
```bash
agent-cli simulator cleanup [OPTIONS]
```

**Optional Parameters**:
- `--force` or `-f` - Skip confirmation
- `--json` - Output in JSON format

**Examples**:
```bash
# Cleanup with confirmation
agent-cli simulator cleanup

# Force cleanup
agent-cli simulator cleanup --force

# Cleanup as JSON
agent-cli simulator cleanup -f --json
```

---

## API Commands

Commands that interact with IOSAgentDriver's HTTP API for UI testing.

### App Lifecycle

#### api launch-app

**Description**: Launch an app on the simulator.

**Syntax**:
```bash
agent-cli api launch-app <session-id> <bundle-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<bundle-id>` - App bundle identifier (e.g., "com.apple.mobilesafari")

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Launch Safari
agent-cli api launch-app abc-123 com.apple.mobilesafari

# Launch with JSON output
agent-cli api launch-app abc-123 com.example.myapp --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "bundleId": "com.apple.mobilesafari",
    "launched": true
  },
  "executionTime": 1.23
}
```

---

#### api terminate-app

**Description**: Terminate a running app.

**Syntax**:
```bash
agent-cli api terminate-app <session-id> [bundle-id] [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `<bundle-id>` - App bundle ID (if omitted, terminates current app)
- `--json` - Output in JSON format

**Examples**:
```bash
# Terminate current app
agent-cli api terminate-app abc-123

# Terminate specific app
agent-cli api terminate-app abc-123 com.example.myapp

# Terminate with JSON
agent-cli api terminate-app abc-123 --json
```

---

#### api app-state

**Description**: Get the current application state.

**Syntax**:
```bash
agent-cli api app-state <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Get app state
agent-cli api app-state abc-123

# Get as JSON
agent-cli api app-state abc-123 --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "bundleId": "com.apple.mobilesafari",
    "processId": 12345,
    "state": "runningForeground"
  }
}
```

---

#### api install-app

**Description**: Install an app bundle (.app) on the simulator.

**Syntax**:
```bash
agent-cli api install-app <session-id> <app-path> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<app-path>` - Path to .app bundle

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Install app from path
agent-cli api install-app abc-123 /path/to/MyApp.app

# Install with JSON output
agent-cli api install-app abc-123 ~/DerivedData/MyApp.app --json
```

---

#### api health

**Description**: Check IOSAgentDriver health status.

**Syntax**:
```bash
agent-cli api health <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Check health
agent-cli api health abc-123

# Check health with JSON
agent-cli api health abc-123 --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "status": "OK",
    "timestamp": "2026-03-04T06:24:00Z"
  }
}
```

---

---

### UI Interaction

#### api tap

**Description**: Tap a UI element using identifier, label, or predicate.

**Syntax**:
```bash
agent-cli api tap <session-id> <selector> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<selector>` - Element selector (identifier, label, or predicate)

**Optional Parameters**:
- `--selector-type <type>` - Selector type: id, label, or predicate (default: auto-detect)
- `--timeout <seconds>` - Timeout in seconds
- `--json` - Output in JSON format

**Examples**:
```bash
# Tap by identifier (auto-detected)
agent-cli api tap abc-123 "loginButton"

# Tap by label explicitly
agent-cli api tap abc-123 "Login" --selector-type label

# Tap by predicate (auto-detected if contains operators)
agent-cli api tap abc-123 "label == 'Submit'"

# Tap with custom timeout
agent-cli api tap abc-123 "submitBtn" --timeout 10

# Tap with JSON output
agent-cli api tap abc-123 "button" --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "tapped": true,
    "predicate": "identifier == 'loginButton'"
  },
  "executionTime": 0.45
}
```

---

#### api type-text

**Description**: Type text into an element.

**Syntax**:
```bash
agent-cli api type-text <session-id> <selector> <text> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<selector>` - Element selector (identifier, label, or predicate)
- `<text>` - Text to type

**Optional Parameters**:
- `--clear` - Clear field before typing
- `--selector-type <type>` - Selector type: id, label, or predicate (default: auto-detect)
- `--json` - Output in JSON format

**Examples**:
```bash
# Type into username field
agent-cli api type-text abc-123 "usernameField" "testuser@example.com"

# Type password with selector type
agent-cli api type-text abc-123 "Password" "MyP@ssw0rd" --selector-type label

# Clear and type new email
agent-cli api type-text abc-123 "emailField" "new@email.com" --clear

# Type with JSON
agent-cli api type-text abc-123 "identifier == 'searchField'" "test query" --json
```

---

#### api swipe

**Description**: Perform swipe gesture on a specific element.

**Syntax**:
```bash
agent-cli api swipe <session-id> <selector> <direction> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<selector>` - Element selector (identifier, label, or predicate)
- `<direction>` - Direction: "up", "down", "left", or "right"

**Optional Parameters**:
- `--selector-type <type>` - Selector type: id, label, or predicate (default: auto-detect)
- `--json` - Output in JSON format

**Examples**:
```bash
# Swipe up on scroll view by identifier
agent-cli api swipe abc-123 "scrollView" up

# Swipe down on table view
agent-cli api swipe abc-123 "tableView" down

# Swipe left by label
agent-cli api swipe abc-123 "Main Content" left --selector-type label

# Swipe with JSON output
agent-cli api swipe abc-123 "scrollView" up --json
```

---

### UI Query

#### api get-ui-tree

**Description**: Get the complete UI hierarchy.

**Syntax**:
```bash
agent-cli api get-ui-tree <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--max-depth <depth>` - Maximum tree depth (default: unlimited)
- `--json` - Output in JSON format

**Examples**:
```bash
# Get full UI tree
agent-cli api get-ui-tree abc-123

# Get tree with max depth 3
agent-cli api get-ui-tree abc-123 --max-depth 3

# Get as JSON
agent-cli api get-ui-tree abc-123 --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "tree": {
      "type": "XCUIElementTypeApplication",
      "identifier": "com.example.myapp",
      "label": "MyApp",
      "frame": {"x": 0, "y": 0, "width": 390, "height": 844},
      "children": [...]
    },
    "timestamp": "2026-03-02T14:30:00Z",
    "depth": 12
  },
  "executionTime": 0.89
}
```

---

#### api find-element

**Description**: Find the first element matching a predicate.

**Syntax**:
```bash
agent-cli api find-element <session-id> <predicate> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<predicate>` - Element predicate string

**Optional Parameters**:
- `--timeout <seconds>` - Timeout in seconds (default: 5.0)
- `--json` - Output in JSON format

**Examples**:
```bash
# Find first button
agent-cli api find-element abc-123 "identifier == 'loginButton'"

# Find with custom timeout
agent-cli api find-element abc-123 "label == 'Submit'" --timeout 10

# Find with JSON output
agent-cli api find-element abc-123 "type == 'XCUIElementTypeButton'" --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "type": "XCUIElementTypeButton",
    "identifier": "loginButton",
    "label": "Login",
    "frame": {"x": 100, "y": 200, "width": 200, "height": 44}
  }
}
```

---

#### api find-elements

**Description**: Find all elements matching a predicate.

**Syntax**:
```bash
agent-cli api find-elements <session-id> <predicate> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<predicate>` - Element predicate

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Find all buttons
agent-cli api find-elements abc-123 "elementType == 'XCUIElementTypeButton'"

# Find elements with specific label
agent-cli api find-elements abc-123 "label BEGINSWITH 'Submit'"

# Find with JSON
agent-cli api find-elements abc-123 "identifier CONTAINS 'button'" --json
```

---

#### api get-element

**Description**: Get a specific element's properties.

**Syntax**:
```bash
agent-cli api get-element <session-id> <predicate> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<predicate>` - Element predicate

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Get element details
agent-cli api get-element abc-123 "identifier == 'loginButton'"

# Get with JSON
agent-cli api get-element abc-123 "identifier == 'statusLabel'" --json
```

---

#### api wait-for-element

**Description**: Wait for an element with specific conditions.

**Syntax**:
```bash
agent-cli api wait-for-element <session-id> <identifier> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<identifier>` - Element accessibility identifier or predicate

**Optional Parameters**:
- `--condition <condition>` - Wait condition: exists, isEnabled, isHittable, etc. (default: exists)
- `--value <value>` - Expected value for text/value conditions
- `--timeout <seconds>` - Timeout in seconds (default: 10.0)
- `--soft-validation` - Don't throw exception on failure
- `--json` - Output in JSON format

**Examples**:
```bash
# Wait for element to exist (default condition)
agent-cli api wait-for-element abc-123 "identifier == 'welcomeMessage'" --timeout 10

# Wait for element to be enabled
agent-cli api wait-for-element abc-123 "loginButton" --condition isEnabled

# Wait with soft validation (no exception)
agent-cli api wait-for-element abc-123 "errorLabel" --soft-validation --json
```

---

#### api screenshot

**Description**: Capture screenshot of current screen.

**Syntax**:
```bash
agent-cli api screenshot <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--output <path>` - Save screenshot to file path
- `--json` - Output in JSON format (returns base64 image)

**Examples**:
```bash
# Take screenshot (auto-saved)
agent-cli api screenshot abc-123

# Save to specific path
agent-cli api screenshot abc-123 --output ~/Desktop/test.png

# Get screenshot as base64 JSON
agent-cli api screenshot abc-123 --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "image": "iVBORw0KGgoAAAANSUhEUgAA...",
    "width": 390,
    "height": 844,
    "timestamp": "2026-03-04T06:24:00Z"
  }
}
```

---

#### api detect-alert

**Description**: Detect if a system alert is present.

**Syntax**:
```bash
agent-cli api detect-alert <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Detect alert
agent-cli api detect-alert abc-123

# Detect with JSON
agent-cli api detect-alert abc-123 --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "alertPresent": true,
    "alertTitle": "Allow Location Access?",
    "buttons": ["Don't Allow", "Allow"]
  }
}
```

---

#### api dismiss-alert

**Description**: Dismiss a system alert by tapping a button.

**Syntax**:
```bash
agent-cli api dismiss-alert <session-id> <button-label> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<button-label>` - Button label to tap (e.g., "Allow", "OK")

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Dismiss alert by tapping "Allow"
agent-cli api dismiss-alert abc-123 "Allow"

# Dismiss with "OK" button
agent-cli api dismiss-alert abc-123 "OK"

# Dismiss with JSON output
agent-cli api dismiss-alert abc-123 "Don't Allow" --json
```

**JSON Response**:
```json
{
  "success": true,
  "data": {
    "dismissed": true,
    "buttonTapped": "Allow"
  }
}
```

---

### Configuration

#### api get-config

**Description**: Get current IOSAgentDriver configuration.

**Syntax**:
```bash
agent-cli api get-config <session-id> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Get configuration
agent-cli api get-config abc-123

# Get as JSON
agent-cli api get-config abc-123 --json
```

---

#### api set-timeout

**Description**: Set default timeout for element operations.

**Syntax**:
```bash
agent-cli api set-timeout <session-id> <seconds> [OPTIONS]
```

**Required Parameters**:
- `<session-id>` - Session ID
- `<seconds>` - Timeout in seconds

**Optional Parameters**:
- `--json` - Output in JSON format

**Examples**:
```bash
# Set 5 second timeout
agent-cli api set-timeout abc-123 5

# Set 10 second timeout with JSON
agent-cli api set-timeout abc-123 10 --json
```

---

## Command Summary

### By Category

**Session Management (5)**:
- session create
- session list
- session get
- session delete
- session delete-all

**Simulator Management (9)**:
- simulator list
- simulator create
- simulator delete
- simulator boot
- simulator shutdown
- simulator info
- simulator list-apps
- simulator snapshot
- simulator cleanup

**API Commands (18)**:
- api health
- api launch-app
- api terminate-app
- api app-state
- api install-app
- api tap
- api type-text
- api swipe
- api get-ui-tree
- api find-element
- api find-elements
- api get-element
- api wait-for-element
- api screenshot
- api detect-alert
- api dismiss-alert
- api get-config
- api set-timeout
- api set-timeout

**Total**: 32 commands

---

## Common Patterns

### Testing Flow Pattern
```bash
# 1. Create session
SESSION_ID=$(agent-cli session create -d "iPhone 15" -i "18.6" --json | jq -r '.data.sessionId')

# 2. Launch app
agent-cli api launch-app $SESSION_ID com.example.myapp --json

# 3. Interact and verify
agent-cli api tap $SESSION_ID "identifier == 'button'" --json
agent-cli api wait-for-element $SESSION_ID "identifier == 'result'" --timeout 5 --json

# 4. Capture evidence
agent-cli api screenshot $SESSION_ID --json | jq -r '.data.base64' | base64 -d > result.png

# 5. Cleanup
agent-cli session delete $SESSION_ID --force
```

### Error Handling Pattern
```bash
# Execute command and check success
RESULT=$(agent-cli api tap $SESSION_ID "identifier == 'button'" --json)
SUCCESS=$(echo $RESULT | jq -r '.success')

if [ "$SUCCESS" != "true" ]; then
  echo "ERROR: Command failed"
  echo $RESULT | jq '.error'
  exit 1
fi
```

### Element Search Pattern
```bash
# Get UI tree
agent-cli api get-ui-tree $SESSION_ID --json > ui_tree.json

# Search for elements
jq '.data.tree' ui_tree.json | grep -i "login"

# Find element and interact
agent-cli api tap $SESSION_ID "identifier == 'loginButton'" --json
```

---

## Predicate Syntax

Element predicates use NSPredicate format:

### Comparison Operators
- `==` - Equals
- `!=` - Not equals
- `>`, `<`, `>=`, `<=` - Numeric comparison

### String Operators
- `BEGINSWITH` - String starts with
- `ENDSWITH` - String ends with
- `CONTAINS` - String contains
- `LIKE` - Pattern matching (* and ? wildcards)
- `MATCHES` - Regular expression

### Logical Operators
- `AND` - Both conditions true
- `OR` - Either condition true
- `NOT` - Negate condition

### Common Properties
- `identifier` - Accessibility identifier
- `label` - Accessibility label
- `elementType` - UI element type
- `isEnabled` - Element is enabled
- `isSelected` - Element is selected
- `value` - Element value

### Examples
```bash
# By identifier
"identifier == 'loginButton'"

# By label
"label == 'Submit'"

# By type
"elementType == 'XCUIElementTypeButton'"

# Compound
"elementType == 'XCUIElementTypeButton' AND label CONTAINS 'Login'"

# Pattern matching
"label LIKE '*Submit*'"

# Multiple conditions
"(identifier == 'btn1' OR identifier == 'btn2') AND isEnabled == YES"
```

---

## Tips & Best Practices

1. **Always use `--json` for automation** - Easier to parse and more reliable
2. **Check command success** - Parse JSON response and verify `success: true`
3. **Use identifiers over labels** - More stable across localization
4. **Wait for elements** - Use `wait-for-element` before interacting
5. **Take screenshots** - Capture evidence at key points
6. **Clean up sessions** - Always delete sessions when done
7. **Handle errors** - Check JSON responses and handle failures
8. **Use timeouts** - Set appropriate timeouts for slow operations

---

**For more examples and guidance, see the main skill documentation.**
