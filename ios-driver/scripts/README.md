# Scripts

This directory contains utility scripts for the iOS Runner project.

## start_driver.sh (IOSAgentDriver CLI Integration)

Starts IOSAgentDriver on a simulator with automatic build, installation, and health checking. This script is designed to be called by the agent-cli but can also be used standalone.

**Usage:**
```bash
./start_driver.sh <simulator-udid> <port> [bundle-id]
```

**Arguments:**
- `simulator-udid`: UUID of the target simulator (required)
- `port`: Port number for the IOSAgentDriver HTTP server (required)
- `bundle-id`: (Optional) App bundle ID to configure in INSTALLED_APPLICATIONS environment variable

**Environment Variables:**
- `IOS_AGENT_DRIVER__DIR`: **Required**. Path to the IOSAgentDriver project directory
  - Example: `/Users/user/Projects/AgenticRegressionTester/ios-driver`
  - Must contain: `IOSAgentDriverUITests/` directory and Tuist project files
  - Set this before running: `export IOS_AGENT_DRIVER_DIR="/path/to/ios-driver"`

**How It Works:**

1. **Validation Phase**
   - Validates `IOS_AGENT_DRIVER_DIR` is set and points to valid IOSAgentDriver directory
   - Checks required arguments (UDID and port)
   - Logs all configuration for debugging

2. **Installation Check**
   - Checks if IOSAgentDriver is already installed using: `xcrun simctl get_app_container $UDID dev.tuist.IOSAgentDriverUITests.xctrunner`
   - Bundle ID: `dev.tuist.IOSAgentDriverUITests.xctrunner` (Tuist-generated)
   - If installed: logs "already installed, will launch directly"
   - If not installed: logs "not installed, will build and install"

3. **Test Plan Generation**
   - Calls `generate_testplan.sh` to create `IOSAgentDriverUITests.xctestplan`
   - Sets environment variables in test plan:
     - `RUNNER_PORT=$PORT` - tells IOSAgentDriver which port to bind to
     - `INSTALLED_APPLICATIONS=$BUNDLE_ID` (if provided)

4. **Build & Start**
   - Runs single command: `tuist test IOSAgentDriverUITests --device "$SIMULATOR_NAME" &`
   - This command does everything:
     - Builds the project (if needed - first run)
     - Installs on simulator (if needed - first run)
     - Runs tests which starts the HTTP server
   - Runs in background (`&`) so server stays running
   - Runs on ALL subsequent calls (even if installed) to launch the server

5. **Health Check**
   - Polls `http://localhost:$PORT/health` endpoint
   - Exponential backoff: 1s, 2s, 4s, 8s, 16s between retries
   - Maximum 10 retries (~63 seconds total timeout)
   - Success: HTTP 200 + response contains `"status"`
   - Logs progress: "Attempt 1/10...", "Attempt 2/10...", etc.

**Features:**
- ✅ Smart installation detection - skips rebuild if already installed
- ✅ Unified build/install/launch - single `tuist test` call handles everything
- ✅ Test plan generation - configures port and apps automatically
- ✅ Robust health checking - exponential backoff with clear feedback
- ✅ Colorized output - green=success, red=error, yellow=warning, blue=info
- ✅ Timestamp logging - all messages include `[HH:MM:SS]` timestamp
- ✅ Detailed debugging - logs commands, paths, and status at each step
- ✅ Graceful error handling - clear error messages with exit codes

**Exit Codes:**
- `0`: Success - IOSAgentDriver ready and health check passed
- `1`: IOS_AGENT_DRIVER_DIR not set or invalid directory
- `2`: Build/test failed (tuist command failed)
- `3`: Installation verification failed (simctl check failed)  
- `4`: Health check timeout (server didn't respond in ~63s)
- `5`: Invalid arguments (missing UDID or port)

**Key Implementation Details:**

**Bundle ID Discovery:**
- Tuist generates bundle IDs in format: `dev.tuist.<TargetName>.xctrunner`
- For IOSAgentDriverUITests target: `dev.tuist.IOSAgentDriverUITests.xctrunner`
- This ID is used for installation checks with `simctl get_app_container`

**Why Single tuist test Call:**
- Previously called `tuist test` twice (once for build, once for run) - redundant!
- Now calls once: `tuist test` both builds AND runs tests
- Works for both scenarios:
  - **First run**: Builds, installs, starts server
  - **Subsequent runs**: Skips build/install (cached), starts server
- Running in background (`&`) keeps server alive after launch

**Simulator Name Resolution:**
- Script extracts simulator name from UDID using `xcrun simctl list devices`
- Example: `A4FBE4AD-B8FD-4B11-82DF-FC133F535983` → `"iPhone 15"`
- Tuist requires simulator name, not UDID: `--device "iPhone 15"`

**Example Usage:**

```bash
# Set environment variable (required)
export IOS_AGENT_DRIVER_DIR="/Users/manuel/Projects/AgenticRegressionTester/ios-driver"

# Basic usage - start on simulator with port
./start_driver.sh A4FBE4AD-B8FD-4B11-82DF-FC133F535983 8080

# With bundle ID configuration
./start_driver.sh A4FBE4AD-B8FD-4B11-82DF-FC133F535983 8080 com.example.MyApp

# Output example (first run):
[19:23:45] ℹ️  Starting IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:23:45] ✅ IOS_AGENT_DRIVER_DIR validated: /Users/manuel/Projects/AgenticRegressionTester/ios-driver
[19:23:45] ℹ️  Checking if IOSAgentDriver is already installed on simulator...
[19:23:45] ℹ️  IOSAgentDriver not installed, will build and install
[19:23:45] 🔄 Building IOSAgentDriver with Tuist...
Generating project for testing...
[19:24:15] ✅ Build completed successfully
[19:24:15] ✅ IOSAgentDriver installation verified
[19:24:15] 🏥 Checking server health at http://localhost:8080/health
[19:24:16] ✅ Attempt 1/10: Server responded with status 200
[19:24:16] ✅ IOSAgentDriver is ready on port 8080

# Output example (already installed):
[19:25:30] ℹ️  Starting IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:25:30] ✅ IOS_AGENT_DRIVER_DIR validated: /Users/manuel/Projects/AgenticRegressionTester/ios-driver
[19:25:30] ℹ️  Checking if IOSAgentDriver is already installed on simulator...
[19:25:30] ✅ IOSAgentDriver is already installed
[19:25:30] 🔄 Starting IOSAgentDriver...
[19:25:32] ✅ IOSAgentDriver installation verified
[19:25:32] 🏥 Checking server health at http://localhost:8080/health
[19:25:33] ✅ Attempt 1/10: Server responded with status 200
[19:25:33] ✅ IOSAgentDriver is ready on port 8080
```

**Troubleshooting:**

**Problem: "IOS_AGENT_DRIVER_DIR is not set"**
```bash
[19:20:00] ❌ IOS_AGENT_DRIVER_DIR is not set
```
**Solution:** Set the environment variable:
```bash
export IOS_AGENT_DRIVER_DIR="/path/to/AgenticRegressionTester/ios-driver"
```

**Problem: "IOSAgentDriver installation verification failed"**
```bash
[19:20:15] ❌ IOSAgentDriver installation verification failed
```
**Solution:** Check Tuist build logs for errors. Common causes:
- Xcode not installed or wrong version
- iOS SDK missing for target version
- Tuist not installed: `brew install tuist`

**Problem: "Health check timeout"**
```bash
[19:21:00] ❌ Health check timed out after 10 retries
```
**Solution:** 
- Check simulator is booted: `xcrun simctl list devices | grep Booted`
- Check port not in use: `lsof -ti:8080`
- Check Xcode console for IOSAgentDriver errors
- Increase timeout by modifying `MAX_HEALTH_RETRIES` in script

**Problem: Wrong bundle ID detected**
```bash
[19:20:45] ❌ IOSAgentDriver installation verification failed
```
**Solution:** Script uses `dev.tuist.IOSAgentDriverUITests.xctrunner` - if you've customized bundle IDs in Tuist project, update `RUNNER_BUNDLE_ID` in script

**Integration with agent-cli:**

The CLI's `session create` command calls this script:
```bash
agent-cli session create --device "iPhone 15" --ios 17.5 --port 8080
# Internally calls: start_driver.sh <udid> 8080
```

**Related Scripts:**
- `generate_testplan.sh` - Creates test plan with environment variables (called by this script)
- `start_driver.sh` - Starts IOSAgentDriver instance
- `stop_driver.sh` - Stops running IOSAgentDriver instance
- `test_server.sh` - Quick health check script for testing

---

## stop_driver.sh (IOSAgentDriver CLI Integration)

Stops IOSAgentDriver running on a simulator using a three-tier graceful shutdown approach. This script is designed to be called by the agent-cli but can also be used standalone.

**Usage:**
```bash
./stop_driver.sh <simulator-udid> <port>
```

**Arguments:**
- `simulator-udid`: UUID of the target simulator (required)
- `port`: Port number the IOSAgentDriver is using (required)

**How It Works:**

The script uses a **three-tier shutdown strategy** to ensure clean termination:

**Tier 1: Graceful API Shutdown** (preferred)
- Sends `POST http://localhost:$PORT/shutdown` request
- Allows IOSAgentDriver to clean up resources, close connections, save state
- Waits 5 seconds for graceful shutdown
- If successful: exits immediately with success

**Tier 2: SIGTERM Signal** (fallback)
- Sends SIGTERM to process listening on port
- Uses `lsof -ti:$PORT` to find process ID
- Allows process to catch signal and shutdown gracefully
- Waits 5 seconds for process to exit
- If successful: exits with success

**Tier 3: SIGKILL Force Kill** (last resort)
- Sends SIGKILL to force-terminate process
- Cannot be caught or ignored by process
- Immediately terminates IOSAgentDriver
- Always succeeds (unless process doesn't exist)

**Features:**
- ✅ Three-tier graceful shutdown - API → SIGTERM → SIGKILL
- ✅ Works with any state - server running, crashed, or not started
- ✅ Works even if simulator is shutdown
- ✅ Safe - always returns success if runner stops
- ✅ Colorized output - green=success, red=error, blue=info
- ✅ Timestamp logging - all messages include `[HH:MM:SS]` timestamp
- ✅ Clear feedback - shows which tier succeeded
- ✅ No zombie processes - ensures complete cleanup

**Exit Codes:**
- `0`: Success - IOSAgentDriver stopped (or wasn't running)
- `1`: Failed to stop - process still running after all tiers (rare)
- `2`: Invalid arguments - missing UDID or port

**Implementation Details:**

**Process Discovery:**
- Uses `lsof -ti:$PORT` to find process ID listening on port
- Works regardless of process name (tuist, xctest, IOSAgentDriver, etc.)
- Returns empty if no process on port (not running)

**Shutdown API:**
- Endpoint: `POST http://localhost:$PORT/shutdown`
- Response: `{"status":"shutting_down"}`
- IOSAgentDriver performs cleanup:
  - Closes all XCUIElement references
  - Disconnects accessibility connections
  - Saves any pending logs
  - Terminates gracefully

**Signal Handling:**
- SIGTERM (15): Polite request to terminate - can be caught
- SIGKILL (9): Force kill - cannot be caught or ignored
- 5-second wait between tiers allows time for cleanup

**Works with Shutdown Simulator:**
- When simulator is shutdown, IOSAgentDriver process may still exist
- Script kills process using PID, not simulator state
- Ensures complete cleanup even with shutdown simulator

**Example Usage:**

```bash
# Stop IOSAgentDriver on specific simulator and port
./stop_driver.sh A4FBE4AD-B8FD-4B11-82DF-FC133F535983 8080

# Output example (graceful shutdown):
[19:30:00] 🛑 Stopping IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:30:00] 📡 Attempting graceful shutdown via API...
[19:30:00] ✅ Graceful shutdown successful
[19:30:00] ✅ IOSAgentDriver stopped successfully

# Output example (SIGTERM fallback):
[19:31:00] 🛑 Stopping IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:31:00] 📡 Attempting graceful shutdown via API...
[19:31:00] ⚠️  API shutdown failed (server not responding)
[19:31:00] 🔄 Sending SIGTERM to process (PID: 12345)...
[19:31:05] ✅ Process terminated successfully
[19:31:05] ✅ IOSAgentDriver stopped successfully

# Output example (SIGKILL last resort):
[19:32:00] 🛑 Stopping IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:32:00] 📡 Attempting graceful shutdown via API...
[19:32:00] ⚠️  API shutdown failed (server not responding)
[19:32:00] 🔄 Sending SIGTERM to process (PID: 12345)...
[19:32:05] ⚠️  SIGTERM did not stop process, forcing with SIGKILL...
[19:32:05] 🔄 Sending SIGKILL to process (PID: 12345)...
[19:32:05] ✅ Process killed successfully
[19:32:05] ✅ IOSAgentDriver stopped successfully

# Output example (not running):
[19:33:00] 🛑 Stopping IOSAgentDriver on simulator A4FBE4AD-B8FD-4B11-82DF-FC133F535983:8080
[19:33:00] ℹ️  No process found on port 8080
[19:33:00] ✅ IOSAgentDriver already stopped
```

**When Each Tier is Used:**

**Tier 1 succeeds when:**
- Server is running normally and healthy
- HTTP API is responsive
- Network is working
- Most common scenario

**Tier 2 needed when:**
- Server crashed but process still exists
- HTTP API is unresponsive
- Server is in deadlock state
- Port is blocked/unavailable

**Tier 3 needed when:**
- Process ignores SIGTERM (rare)
- Process is in uninterruptible state
- Kernel-level issues
- Very rare - last resort only

**Troubleshooting:**

**Problem: "Failed to stop process"**
```bash
[19:35:00] ❌ Failed to stop IOSAgentDriver (all tiers failed)
```
**Solution:** Very rare - check system state:
```bash
# Check if process still exists
lsof -ti:8080

# Check process state (if PID known)
ps aux | grep 12345

# Force kill with sudo (last resort)
sudo kill -9 $(lsof -ti:8080)
```

**Problem: Multiple processes on same port**
```bash
[19:36:00] ⚠️  Multiple processes on port 8080
```
**Solution:** Script kills all processes, but investigate why:
```bash
# List all processes on port
lsof -i:8080

# Check for zombie processes
ps aux | grep IOSAgentDriver | grep defunct
```

**Problem: "Port still in use after stop"**
```bash
# After stop, curl still works
curl http://localhost:8080/health
```
**Solution:** Wait a few seconds for OS to release port:
```bash
# Wait and retry
sleep 2 && lsof -ti:8080

# If still in use, check for other listeners
lsof -i:8080 -n -P
```

**Integration with agent-cli:**

The CLI's `session delete` command calls this script:
```bash
agent-cli session delete <session-id>
# Internally calls: stop_driver.sh <udid> <port>
```

Also used for cleanup:
```bash
agent-cli session delete-all
# Calls stop_driver.sh for each active session
```

**Best Practices:**

1. **Always use this script to stop** - don't manually kill processes
   - Ensures proper cleanup
   - Prevents zombie processes
   - Releases port correctly

2. **Wait between start/stop cycles** - allow time for cleanup
   ```bash
   ./stop_driver.sh $UDID $PORT
   sleep 2  # Let port release
   ./start_driver.sh $UDID $PORT
   ```

3. **Check status before starting** - avoid port conflicts
   ```bash
   # Check if port is free
   lsof -ti:8080 || echo "Port available"
   ```

4. **Monitor logs for issues** - if SIGKILL is frequently needed
   ```bash
   # Check for patterns in logs
   grep "SIGKILL" /tmp/ios-agent-driver-*.log
   ```

**Related Scripts:**
- `start_driver.sh` - Starts IOSAgentDriver instance
- `stop_driver.sh` - Stops IOSAgentDriver instance
- `test_server.sh` - Quick server test with auto-cleanup
- `test_server_interactive.sh` - Interactive API testing (includes cleanup on exit)

---

## test_server_interactive.sh

**Interactive menu-driven test interface** for comprehensive API testing of IOSAgentDriver.

### Features

- 🎯 **23 Interactive Test Options** - Complete coverage of all API endpoints
- 📱 **Automatic Setup** - Generates test plan with your configuration
- 🚀 **One-Command Start** - Handles device selection, port config, and server startup
- 🎨 **Color-Coded Output** - Green success, red errors, blue sections
- 💾 **Screenshot Support** - Save screenshots directly to files
- ⚙️ **Configuration Management** - Test runtime configuration changes
- 🔄 **Session Persistence** - Server stays running between tests
- 🧹 **Auto Cleanup** - Graceful shutdown on exit

### Quick Start

```bash
# From scripts directory
./test_server_interactive.sh

# From project root  
./scripts/test_server_interactive.sh
```

The script will guide you through:
1. **Device Selection** - Choose from available iOS simulators
2. **Port Configuration** - Set custom port (default: 8080)
3. **App Configuration** - Optionally configure installed applications list
4. **Test Plan Generation** - Automatically creates `IOSAgentDriverUITests.xctestplan`
5. **Server Startup** - Starts IOSAgentDriver with your configuration
6. **Interactive Menu** - Select from 23 test options

### Usage Flow

#### Step 1: Device Selection
```
Available simulators:
1) iPhone 15 (iOS 17.5)
2) iPhone 16 (iOS 18.0)
3) iPad Pro 12.9-inch (iOS 17.5)

Select simulator [1-3]: 1
```

#### Step 2: Port Configuration
```
Enter port number (default 8080): 8080
```

#### Step 3: Application Configuration (Optional)
```
Configure installed applications? (y/n): y
Enter comma-separated bundle IDs: com.apple.mobilesafari,com.example.MyApp
```

#### Step 4: Server Starts
```
Generating test plan...
✅ IOSAgentDriverUITests.xctestplan created

Starting IOSAgentDriver on iPhone 15 (port 8080)...
✅ Server started successfully
📡 Ready to accept requests at http://localhost:8080
```

#### Step 5: Interactive Menu
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IOSAgentDriver Interactive Test Menu
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Server: http://localhost:8080
Device: iPhone 15 (iOS 17.5)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Health & Configuration:
  1.  Health Check                 GET /health
  2.  Get Configuration             GET /config
  3.  Update Configuration          POST /config
  4.  Reset Configuration           POST /config/reset

App Management:
  5.  List Installed Apps           GET /app/list
  6.  Launch App                    POST /app/launch
  7.  Terminate App                 POST /app/terminate

UI Query:
  8.  Get UI Tree                   GET /ui/tree
  9.  Find Elements                 POST /ui/find
  10. Get Element Details           GET /ui/element/:id

UI Interaction:
  11. Tap Element                   POST /ui/tap
  12. Type Text                     POST /ui/type
  13. Swipe                         POST /ui/swipe
  14. Scroll to Element             POST /ui/scroll
  15. Hardware Keyboard Input       POST /ui/keyboard/type

Screenshots:
  16. Take Full Screenshot          GET /screenshot
  17. Take Element Screenshot       POST /screenshot/element

Validation:
  18. Soft Validation               POST /ui/validate
  19. Hard Assertion                POST /ui/assert

Alerts:
  20. List Alerts                   GET /ui/alerts
  21. Dismiss Alert                 POST /ui/alert/dismiss

Wait Conditions:
  22. Explicit Wait                 POST /ui/wait

  23. Exit

Select option [1-23]:
```

### Menu Options Explained

#### Health & Configuration (1-4)

**1. Health Check** - Test server connectivity
```
✓ Status: 200 OK
Response: {"status":"ok","timestamp":"2026-03-01T12:00:00Z"}
```

**2. Get Configuration** - View current configuration
```
Response: {"defaultTimeout":5.0,"errorVerbosity":"simple"}
```

**3. Update Configuration** - Change timeouts and error verbosity
```
Default timeout (seconds, current: 5.0): 10.0
Error verbosity [simple/verbose]: verbose
✓ Configuration updated
```

**4. Reset Configuration** - Restore default settings

#### App Management (5-7)

**5. List Installed Apps** - Show configured applications
```
Response: {"apps":["com.apple.mobilesafari","com.example.MyApp"]}
```

**6. Launch App** - Start an application
```
Enter bundle ID: com.apple.mobilesafari
Launch arguments (optional): -UIAnimationDragCoefficient,100
Environment variables (optional): MOCK_MODE=true
✓ App launched successfully
```

**7. Terminate App** - Stop a running application

#### UI Query (8-10)

**8. Get UI Tree** - Retrieve accessibility hierarchy
```
Max depth (default: 10): 5
Response: Full UI tree with elements, frames, labels
```

**9. Find Elements** - Search by predicate
```
Enter NSPredicate: type == 'XCUIElementTypeButton' AND label CONTAINS 'Login'
Response: Array of matching elements
```

**10. Get Element Details** - Get specific element info

#### UI Interaction (11-15)

**11. Tap Element** - Tap by ID, label, or predicate
```
Search by:
  1) Accessibility ID
  2) Label
  3) NSPredicate
Select [1-3]: 2
Enter label: Login
✓ Element tapped successfully
```

**12. Type Text** - Enter text in field
```
Element identifier: usernameField
Text to type: testuser@example.com
Clear before typing? (y/n): y
✓ Text entered successfully
```

**13. Swipe** - Swipe in direction
```
Direction [up/down/left/right]: up
Velocity [slow/fast]: fast
✓ Swipe executed
```

**14. Scroll to Element** - Scroll until element visible
**15. Hardware Keyboard Input** - Fast keyboard typing with special keys

#### Screenshots (16-17)

**16. Take Full Screenshot** - Capture entire screen
```
Save to file (y/n)? y
Filename: home_screen.png
✓ Screenshot saved to: home_screen.png
```

**17. Take Element Screenshot** - Capture specific element
```
Element identifier: loginButton
Filename: button.png
✓ Element screenshot saved
```

#### Validation (18-19)

**18. Soft Validation** - Check multiple conditions without failing
```
Validations to run:
  1) Exists
  2) IsEnabled
  3) IsVisible
Response: {"validations":[{"property":"exists","passed":true},...]}
```

**19. Hard Assertion** - Assert single condition (fails on error)

#### Alerts (20-21)

**20. List Alerts** - Detect system/app alerts
```
Response: {"alerts":[{"type":"alert","label":"Allow Location?"}]}
```

**21. Dismiss Alert** - Dismiss alert by button label
```
Button label: Allow
✓ Alert dismissed
```

#### Wait Conditions (22)

**22. Explicit Wait** - Wait for UI state
```
Condition types:
  1) exists
  2) notExists
  3) isEnabled
  4) isHittable
  5) textContains
  ...
Select condition: 1
Identifier: loginButton
Timeout (seconds): 10.0
✓ Condition met
```

### Example Test Session

**Scenario**: Test Safari login flow

```bash
./test_server_interactive.sh

# Setup: Select device, configure port
# Menu appears

# 1. Check server health
Select option: 1
✓ Server is healthy

# 2. Launch Safari
Select option: 6
Bundle ID: com.apple.mobilesafari
✓ Safari launched

# 3. Get UI tree to find elements
Select option: 8
Max depth: 5
✓ UI tree retrieved

# 4. Tap address bar
Select option: 11
Search by: 2 (Label)
Label: Address
✓ Address bar tapped

# 5. Type URL
Select option: 12
Identifier: URL
Text: https://example.com
✓ URL entered

# 6. Take screenshot
Select option: 16
Save to file: y
Filename: safari_loaded.png
✓ Screenshot saved

# 7. Validate page loaded
Select option: 18
✓ All validations passed

# 8. Exit
Select option: 23
```

### Advanced Features

#### Custom Port for Multiple Instances

Run multiple instances on different simulators:

```bash
# Terminal 1: iPhone 15 on port 8080
./test_server_interactive.sh
# Select iPhone 15, port 8080

# Terminal 2: iPad on port 9090
./test_server_interactive.sh
# Select iPad, port 9090
```

#### Test Plan Customization

The script generates `IOSAgentDriverUITests.xctestplan` automatically:

```json
{
  "configurations": [{
    "options": {
      "environmentVariableEntries": [
        {"key": "RUNNER_PORT", "value": "8080"},
        {"key": "INSTALLED_APPLICATIONS", "value": "com.apple.mobilesafari"}
      ]
    }
  }]
}
```

You can edit this file manually before starting for advanced configuration.

#### Screenshot Workflow

```bash
# Test visual changes
1. Take baseline screenshot (option 16)
2. Perform UI action (option 11-15)
3. Take comparison screenshot (option 16)
4. Compare files externally
```

### Tips & Best Practices

#### 1. Start with Health Check
Always run option 1 first to verify server is responding.

#### 2. Get UI Tree Before Interacting
Use option 8 to explore available elements before trying to tap/type.

#### 3. Use Soft Validation for Multiple Checks
Option 18 lets you check multiple conditions without stopping on failure.

#### 4. Save Screenshots for Debugging
When tests fail, take screenshots (option 16) to see actual UI state.

#### 5. Configure Timeouts Early
If your app is slow, use option 3 to increase default timeout.

#### 6. Check for Alerts First
Before interacting, use option 20 to detect unexpected alerts.

### Troubleshooting

#### Problem: "No simulators found"
```
❌ No iOS simulators found
```
**Solution**: Install simulators via Xcode → Preferences → Platforms

#### Problem: "Port already in use"
```
⚠️ Port 8080 is already in use
```
**Solution**: Script automatically cleans up. If persists, use different port.

#### Problem: "Server not responding"
```
❌ Failed to connect to server
```
**Solution**: 
1. Check server started successfully
2. Verify port matches configuration
3. Check Xcode console for errors

#### Problem: "Element not found"
```
❌ Element not found: loginButton
```
**Solution**:
1. Use option 8 to get UI tree
2. Verify element identifier is correct
3. Increase timeout with option 3

### Color Legend

The script uses color coding for clarity:
- 🟢 **Green**: Success messages, passed tests
- 🔴 **Red**: Errors, failed tests
- 🔵 **Blue**: Section headers, separators
- 🟡 **Yellow**: Warnings, highlights
- ⚪ **White**: Normal output, prompts

### Exit and Cleanup

**Exit the menu**:
- Select option **23** to exit gracefully
- Press **Ctrl+C** to force stop

**On exit, the script**:
- Attempts graceful shutdown of IOSAgentDriver
- Force-kills if needed after 5 seconds
- Frees the port
- Displays cleanup confirmation

### Requirements

- macOS 13.0+
- Xcode 15.0+
- iOS Simulator installed
- Tuist 4.0+ installed
- `curl`, `lsof`, `xcrun` available

### Files Generated

**IOSAgentDriverUITests.xctestplan** - Test plan with environment variables
```
Location: ios-driver/IOSAgentDriverUITests.xctestplan
Purpose: Configure RUNNER_PORT and INSTALLED_APPLICATIONS
Auto-generated: Yes
```

### Comparison with Other Scripts

| Feature | test_server.sh | test_server_interactive.sh |
|---------|----------------|----------------------------|
| Server startup | ✅ Automatic | ✅ Automatic |
| Health check | ✅ Automatic | ✅ Manual option |
| API testing | ❌ No | ✅ 23 endpoints |
| Interactive menu | ❌ No | ✅ Yes |
| Screenshot support | ❌ No | ✅ Yes |
| Configuration testing | ❌ No | ✅ Yes |
| Validation testing | ❌ No | ✅ Yes |
| Use case | Quick health check | Comprehensive API testing |

### Integration with Documentation

This script complements the main documentation:
- **[Main README](../README.md)** - Complete API documentation
- **[OpenAPI Spec](../docs/openapi.yaml)** - Machine-readable API reference
- **[Swagger UI](../docs/swagger/)** - Browser-based API explorer
- **[Examples](../docs/examples/)** - Python/JavaScript integration

**When to use each**:
- **test_server_interactive.sh**: Manual testing, exploration, debugging
- **Swagger UI**: API documentation, visual testing, sharing with team
- **Python/JavaScript examples**: Automated testing, CI/CD integration

### Real-World Workflows

#### Workflow 1: Debug Element Finding
```
1. Launch app (option 6)
2. Get UI tree (option 8) → Find correct identifier
3. Tap element (option 11) → Test interaction
4. Take screenshot (option 16) → Verify result
```

#### Workflow 2: Test Configuration Impact
```
1. Get config (option 2) → Check defaults
2. Update config (option 3) → Set high timeout
3. Perform slow operation (option 11-15)
4. Reset config (option 4) → Restore defaults
```

#### Workflow 3: Alert Handling
```
1. List alerts (option 20) → Detect alert
2. Dismiss alert (option 21) → Clear it
3. Continue testing → Normal flow
```

#### Workflow 4: Validation Suite
```
1. Navigate to screen
2. Soft validation (option 18) → Check all elements
3. Take screenshot (option 16) → Document state
4. Repeat for each screen
```

### Summary

`test_server_interactive.sh` is your **comprehensive testing companion** for IOSAgentDriver:
- ✅ Complete API coverage (23 endpoints)
- ✅ User-friendly interactive interface
- ✅ Automatic setup and configuration
- ✅ Screenshot support for debugging
- ✅ Session persistence for multiple tests
- ✅ Color-coded, clear output

Perfect for manual testing, API exploration, and debugging UI automation workflows!

---

## test_server.sh

**Automated** test script for the iOS Runner HTTP server.

### Features

- 🚀 **Automatic server startup** - Starts the server automatically with Tuist
- 📱 **Interactive device selection** - Shows list of available simulators
- ⏳ **Smart waiting** - Polls health endpoint with 60s timeout
- ✅ **Health validation** - Automatically tests server response
- 🎨 **Colored output** - Clear visual feedback
- 🧹 **Auto cleanup** - Kills server on exit (CTRL+C)
- 📝 **Logging** - Saves output to /tmp/ios-agent-driver-{port}.log

### Usage

The script can be run from **any directory** - it automatically finds the project root:

```bash
# From scripts directory
./scripts/test_server.sh

# From project root
./scripts/test_server.sh

# From anywhere with absolute path
/path/to/AgenticRegressionTester/ios-driver/scripts/test_server.sh

```

#### Interactive Mode (Recommended)

```bash
# Shows list of devices, lets you select one, then starts server
./scripts/test_server.sh

# Custom port + interactive device selection
./scripts/test_server.sh 8081
```

**Example output:**
```
📱 Available iOS Simulators:
==================================

1) iPhone 13
2) iPhone 14
3) iPhone 15
4) iPhone SE (3rd generation)
5) iPad iOS 17
6) iPhone 16

Select a device (1-6): 3

✅ Selected: iPhone 15

🧪 Testing iOS Runner Server
==================================
Port:   8080
Device: iPhone 15

🚀 Starting server...
Command: tuist test IOSAgentDriverUITests --device "iPhone 15" -- RUNNER_PORT=8080

✓ Server started (PID: 12345)

⏳ Waiting for server to start (timeout: 60s)...
..........✅ Server is ready! (took 20s)

🧪 Testing /health endpoint...
Response: {"status":"ok","version":"1.0.0"}

✅ Health check PASSED!
✅ Server is running successfully on port 8080

ℹ️  Server is running in background (PID: 12345)
ℹ️  Log file: /tmp/ios-agent-driver-8080.log

Press CTRL+C to stop the server
```

#### Direct Device Specification

```bash
# Specify both port and device (no interaction needed)
./scripts/test_server.sh 8080 "iPhone 15"

# Default port (8080) with specific device
./scripts/test_server.sh 8080 "iPad (10th generation)"
```

### How It Works

1. **Path Resolution**: Uses `${BASH_SOURCE[0]}` to find script location (works even with symlinks)
2. **Project Root Discovery**: Navigates up one directory from script location
3. **Device Selection**: If no device is specified, script lists all available iOS simulators
4. **User Selection**: User picks a device by number (or skip if device specified)
5. **Server Start**: Automatically runs `tuist test IOSAgentDriverUITests --device "$DEVICE" -- RUNNER_PORT=$PORT` in background
6. **Health Check Loop**: Polls `http://localhost:$PORT/health` every 2 seconds (max 60s timeout)
7. **Validation**: Confirms response contains `"status":"ok"`
8. **Keep Alive**: Script stays running, keeping server alive until CTRL+C
9. **Cleanup**: On exit, kills server process and cleans up port

### Key Changes from Previous Version

**Before** (Manual):
- Showed instructions
- User had to start server manually in another terminal
- User had to press ENTER to test
- No timeout handling

**After** (Automated):
- ✅ Starts server automatically
- ✅ Waits intelligently with timeout
- ✅ Tests automatically when ready
- ✅ Keeps server running until stopped
- ✅ Cleanup on exit

### Requirements

- macOS with Xcode installed
- iOS Simulator(s) installed
- Tuist installed
- `xcrun`, `curl`, `lsof` commands available

### Error Handling

**No simulators found:**
```
❌ No iOS simulators found
Please install iOS simulators from Xcode settings
```

**Invalid selection:**
```
❌ Invalid selection
```

**Server timeout:**
```
❌ Timeout waiting for server to start after 60s

Last 20 lines of log:
[log output shown here]
```

**Health check failed:**
```
❌ Health check FAILED
Expected: {"status":"ok", "version":"1.0.0"}
```

### Log Files

Server output is saved to `/tmp/ios-agent-driver-{PORT}.log`

View logs:
```bash
# For port 8080
tail -f /tmp/ios-agent-driver-8080.log

# For port 8081
tail -f /tmp/ios-agent-driver-8081.log
```

### Examples

**Quick test with defaults:**
```bash
./scripts/test_server.sh
# Select device from menu
# Server starts automatically
# Wait for success message
# Press CTRL+C when done
```

**Test on specific device:**
```bash
./scripts/test_server.sh 8080 "iPhone SE (3rd generation)"
# No interaction needed
# Server starts automatically
# Press CTRL+C when done
```

**Test multiple instances (parallel):**
```bash
# Terminal 1
./scripts/test_server.sh 8080 "iPhone 15"

# Terminal 2
./scripts/test_server.sh 8081 "iPad"
```

### Cleanup

The script automatically cleans up on exit (CTRL+C, SIGTERM, or SIGINT):
- Kills the server process (tuist/xcodebuild)
- Frees the port using `lsof`
- Trap ensures cleanup even on unexpected exit

### Color Output

- 🔵 Blue: Section headers
- 🟢 Green: Success messages
- 🟡 Yellow: Highlights, commands
- 🔴 Red: Errors
- 🔷 Cyan: Progress, waiting messages
