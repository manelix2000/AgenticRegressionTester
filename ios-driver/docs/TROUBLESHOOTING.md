# IOSAgentDriver Troubleshooting Guide

This guide covers common issues, their causes, and solutions when working with IOSAgentDriver.

---

## Table of Contents

1. [Server Startup Issues](#server-startup-issues)
2. [Simulator Issues](#simulator-issues)
3. [Timeout Issues](#timeout-issues)
4. [Concurrency Issues](#concurrency-issues)
5. [XCTest Limitations](#xctest-limitations)
6. [Performance Issues](#performance-issues)
7. [Network Issues](#network-issues)
8. [Element Finding Issues](#element-finding-issues)

---

## Server Startup Issues

### Port Already in Use

**Symptom**: Server fails to start with "Address already in use" error.

**Cause**: Another process is using the configured port (default: 8080).

**Solutions**:
```bash
# 1. Find and kill process using the port
lsof -ti:8080 | xargs kill -9

# 2. Use a different port
RUNNER_PORT=8081 xcodebuild test \
  -scheme IOSAgentDriverUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# 3. Configure multiple runners on different ports
RUNNER_PORT=8080 xcodebuild test ... &  # Runner 1
RUNNER_PORT=8081 xcodebuild test ... &  # Runner 2
```

### Permission Denied

**Symptom**: "Permission denied" when binding to port.

**Cause**: Trying to bind to privileged port (<1024) without root access.

**Solution**:
```bash
# Use unprivileged ports (1024-65535)
RUNNER_PORT=8080 xcodebuild test ...
```

---

## Simulator Issues

### Simulator Not Found

**Symptom**: Test fails with "Unable to find simulator".

**Cause**: Specified simulator doesn't exist or isn't booted.

**Solutions**:
```bash
# 1. List available simulators
xcrun simctl list devices available

# 2. Boot simulator first
xcrun simctl boot "iPhone 15"

# 3. Use correct destination format
xcodebuild test \
  -scheme IOSAgentDriverUITests \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'
```

### Simulator Performance

**Symptom**: Slow element detection or timeouts.

**Cause**: Simulator running on resource-constrained machine.

**Solutions**:
```bash
# 1. Reduce graphics quality
defaults write com.apple.iphonesimulator GraphicsQualityOverride 10

# 2. Disable animations in app under test
# Add to app launch:
curl -X POST http://localhost:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.example.app", "arguments": ["-UIAnimationDragCoefficient", "100"]}'

# 3. Increase timeouts
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"defaultTimeout": 10.0}'
```

### Multiple Simulators

**Symptom**: Elements from wrong simulator being detected.

**Cause**: Multiple simulators booted simultaneously.

**Solution**:
```bash
# Shutdown all simulators first
xcrun simctl shutdown all

# Boot only the target simulator
xcrun simctl boot "iPhone 15"
```

---

## Timeout Issues

### Element Not Found Within Timeout

**Symptom**: `/ui/find` or `/ui/tap` returns timeout error.

**Cause**: Element doesn't exist, isn't visible, or takes longer to appear than timeout allows.

**Solutions**:
```bash
# 1. Increase global timeout
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"defaultTimeout": 15.0}'

# 2. Use per-request timeout
curl -X POST http://localhost:8080/ui/find \
  -H "Content-Type: application/json" \
  -d '{"identifier": "myButton", "timeout": 20.0}'

# 3. Use explicit wait before action
curl -X POST http://localhost:8080/ui/wait \
  -H "Content-Type: application/json" \
  -d '{"condition": "exists", "identifier": "myButton", "timeout": 30.0}'
```

### Scroll Timeouts

**Symptom**: Scroll operations timeout frequently.

**Cause**: Scroll operations take 2x default timeout (involves searching + scrolling).

**Solution**:
```bash
# Increase default timeout (scroll uses 2x multiplier)
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"defaultTimeout": 10.0}'  # Scroll will use 20s
```

---

## Concurrency Issues

### Race Conditions

**Symptom**: Intermittent failures, "element no longer valid" errors.

**Cause**: Multiple concurrent requests modifying UI state.

**Solution**:
```bash
# 1. Reduce concurrent requests
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"maxConcurrentRequests": 1}'

# 2. Add explicit waits between operations
curl -X POST http://localhost:8080/ui/wait \
  -H "Content-Type: application/json" \
  -d '{"condition": "exists", "identifier": "nextElement", "timeout": 5.0}'
```

### Thread Safety Issues

**Symptom**: Crashes or hangs under concurrent load.

**Cause**: XCUIElement is not thread-safe; all access must be on MainActor.

**Solution**: 
- IOSAgentDriver already handles this via `@MainActor` annotations
- If extending: ensure all XCUIElement access is `@MainActor`

---

## XCTest Limitations

### Cannot Access Private App Data

**Symptom**: Cannot read app's UserDefaults, keychain, or file system.

**Cause**: XCUITest runs in separate process with limited access.

**Solution**: 
- Use app launch arguments to configure app state
- Implement debug endpoints in app for test data setup

### Cannot Mock Network Calls

**Symptom**: Tests require real backend or fail.

**Cause**: XCUITest cannot intercept app's network calls.

**Solutions**:
```bash
# 1. Use launch arguments to point to mock server
curl -X POST http://localhost:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.example.app", "arguments": ["-API_BASE_URL", "http://localhost:3000"]}'

# 2. Use environment variables
curl -X POST http://localhost:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.example.app", "environment": {"MOCK_MODE": "true"}}'
```

### Keyboard Input Limitations

**Symptom**: Cannot type special characters or use hardware keyboard reliably.

**Cause**: XCUIElement keyboard input has edge cases.

**Solutions**:
```bash
# 1. Use software keyboard for special chars
curl -X POST http://localhost:8080/ui/type \
  -H "Content-Type: application/json" \
  -d '{"identifier": "textField", "text": "test@example.com", "useHardwareKeyboard": false}'

# 2. Use hardware keyboard for speed (ASCII only)
curl -X POST http://localhost:8080/ui/keyboard/type \
  -H "Content-Type: application/json" \
  -d '{"keys": ["test", "tab", "password", "enter"]}'
```

---

## Performance Issues

### Slow UI Tree Retrieval

**Symptom**: `/ui/tree` takes >5 seconds.

**Cause**: Deep UI hierarchy with many elements.

**Solutions**:
```bash
# 1. Query specific subtree instead of full tree
curl -X POST http://localhost:8080/ui/element/myContainer

# 2. Optimize app UI hierarchy (reduce nesting)

# 3. Use targeted queries instead of full tree
curl -X POST http://localhost:8080/ui/find \
  -H "Content-Type: application/json" \
  -d '{"predicate": "type == \"XCUIElementTypeButton\" AND label CONTAINS \"Submit\""}'
```

### Memory Issues

**Symptom**: Runner crashes or becomes unresponsive after many requests.

**Cause**: Memory accumulation in long-running test session.

**Solutions**:
```bash
# 1. Restart runner periodically in CI
# Run test suite → Kill runner → Start new runner

# 2. Terminate and relaunch app between test scenarios
curl -X POST http://localhost:8080/app/terminate \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.example.app"}'

curl -X POST http://localhost:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"bundleId": "com.example.app"}'
```

---

## Network Issues

### Connection Refused

**Symptom**: Client cannot connect to `http://localhost:8080`.

**Cause**: Server not started or wrong port/host.

**Solutions**:
```bash
# 1. Verify server is running
curl -X GET http://localhost:8080/health

# 2. Check server logs in xcodebuild output
# Look for: "✅ IOSAgentDriver started on port 8080"

# 3. Verify port configuration
# Server: RUNNER_PORT=8081
# Client: http://localhost:8081
```

### Request Timeout

**Symptom**: HTTP request times out before completion.

**Cause**: Operation takes longer than HTTP client timeout.

**Solution**:
```bash
# Increase client timeout (example: curl)
curl --max-time 30 -X POST http://localhost:8080/ui/wait \
  -H "Content-Type: application/json" \
  -d '{"condition": "exists", "identifier": "slowElement", "timeout": 25.0}'
```

---

## Element Finding Issues

### Element Exists But Not Found

**Symptom**: Visual confirmation element exists, but `/ui/find` fails.

**Cause**: Element lacks accessibility identifier or label.

**Solutions**:
```bash
# 1. Check element properties via UI tree
curl -X GET http://localhost:8080/ui/tree | jq '.'

# 2. Find by predicate instead
curl -X POST http://localhost:8080/ui/find \
  -H "Content-Type: application/json" \
  -d '{"predicate": "type == \"XCUIElementTypeButton\" AND label == \"Submit\""}'

# 3. Find by label
curl -X POST http://localhost:8080/ui/find \
  -H "Content-Type: application/json" \
  -d '{"label": "Submit"}'

# 4. Improve accessibility in app
# Add accessibilityIdentifier to UI elements
```

### Stale Element

**Symptom**: "Element is no longer valid" error.

**Cause**: Element reference becomes stale after UI update.

**Solution**:
```bash
# Don't cache element IDs across operations
# Always query fresh:
curl -X POST http://localhost:8080/ui/tap \
  -H "Content-Type: application/json" \
  -d '{"identifier": "myButton"}'
# Don't do: GET /ui/find → save elementId → POST /ui/tap with elementId
```

### Element Hidden By Other Element

**Symptom**: Element exists but tap fails.

**Cause**: Element is visible but not hittable (covered by another element).

**Solutions**:
```bash
# 1. Check isVisible property
curl -X POST http://localhost:8080/ui/validate \
  -H "Content-Type: application/json" \
  -d '{"identifier": "myButton", "properties": {"isVisible": true}}'

# 2. Scroll element into view first
curl -X POST http://localhost:8080/ui/scroll \
  -H "Content-Type: application/json" \
  -d '{"containerIdentifier": "scrollView", "direction": "down", "toVisible": {"identifier": "myButton"}}'

# 3. Dismiss overlays first
curl -X POST http://localhost:8080/ui/alert/dismiss \
  -H "Content-Type: application/json" \
  -d '{"buttonLabel": "OK"}'
```

---

## Advanced Debugging

### Enable Verbose Error Mode

Get detailed error information including stack traces:

```bash
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"errorVerbosity": "verbose"}'
```

### Capture Screenshot On Failure

```bash
# Take screenshot to debug visual state
curl -X POST http://localhost:8080/screenshot \
  -H "Content-Type: application/json" \
  -d '{"format": "png"}' \
  > debug_screenshot.png
```

### Inspect Alerts

```bash
# Check for unexpected alerts blocking interaction
curl -X GET http://localhost:8080/ui/alerts
```

### Monitor Configuration

```bash
# Verify current settings
curl -X GET http://localhost:8080/config
```

---

## Performance Tuning

### Optimal Configuration

For most use cases:

```json
{
  "defaultTimeout": 5.0,
  "errorVerbosity": "simple",
  "maxConcurrentRequests": 3
}
```

For slow environments (CI, low-spec machines):

```json
{
  "defaultTimeout": 10.0,
  "errorVerbosity": "simple",
  "maxConcurrentRequests": 1
}
```

For debugging:

```json
{
  "defaultTimeout": 30.0,
  "errorVerbosity": "verbose",
  "maxConcurrentRequests": 1
}
```

---

## Getting Help

If you encounter issues not covered here:

1. **Enable verbose errors**: See detailed error information
2. **Check server logs**: Look at xcodebuild test output
3. **Capture screenshots**: Visual debugging of current UI state
4. **Inspect UI tree**: Understand element hierarchy and properties
5. **Verify configuration**: Ensure timeouts and settings are appropriate
6. **Simplify**: Test with minimal setup to isolate issue

For feature requests or bugs, open an issue on GitHub with:
- Error message (from verbose mode)
- Request/response examples
- Screenshot of UI state
- Configuration used
- iOS version and simulator model
