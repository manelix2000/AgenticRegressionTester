# IOSAgentDriver Usage Examples

This directory contains examples of integrating IOSAgentDriver with various programming languages.

## Available Examples

- **Python** ([python_example.py](./python_example.py)) - Using `requests` library
- **JavaScript/TypeScript** ([javascript_example.js](./javascript_example.js)) - Using `axios` or `fetch`

## Prerequisites

### 1. Install Tuist

Tuist is required to generate and manage the Xcode project.

```bash
# Install using Homebrew
brew install tuist

# Or using mise (recommended)
mise install tuist

# Verify installation
tuist version
```

### 2. Generate Xcode Project

```bash
cd ios-driver
tuist generate
```

### 3. Start IOSAgentDriver

Using the interactive script (recommended):
```bash
./scripts/test_server_interactive.sh
```

Or manually with Tuist:
```bash
# Default device and port (8080)
tuist test IOSAgentDriverUITests

# Specific device
tuist test IOSAgentDriverUITests --device "iPhone 15"

# Custom port via test plan
# Edit IOSAgentDriverUITests.xctestplan and set RUNNER_PORT environment variable
```

### 4. Configure Test Plan (Optional)

The `IOSAgentDriverUITests.xctestplan` file controls environment variables:

```json
{
  "configurations": [{
    "options": {
      "environmentVariableEntries": [
        {
          "key": "RUNNER_PORT",
          "value": "8080"
        },
        {
          "key": "INSTALLED_APPLICATIONS",
          "value": "com.example.MyApp,com.example.AnotherApp"
        }
      ]
    }
  }]
}
```

**Environment Variables:**
- `RUNNER_PORT`: HTTP server port (default: 8080)
- `INSTALLED_APPLICATIONS`: Comma-separated list of bundle IDs for /app/list endpoint

The interactive script (`test_server_interactive.sh`) automatically generates this file with your configuration.

### 5. Wait for Server to Start

Look for this message in the output:
```
✅ IOSAgentDriver started on port 8080
```

Then verify:
```bash
curl http://localhost:8080/health
```

## Common Patterns

### 1. Basic Test Flow
```
1. Launch app
2. Wait for element
3. Tap element
4. Type text
5. Assert state
6. Take screenshot
```

### 2. Error Handling
All endpoints return error responses with:
- `error`: Error category
- `message`: Human-readable message
- `suggestion`: Recommended fix (when available)

Configure error verbosity:
```bash
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"errorVerbosity": "verbose"}'
```

### 3. Timeout Configuration
Set global timeout:
```bash
curl -X POST http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"defaultTimeout": 10.0}'
```

Or use per-request timeout:
```json
{
  "identifier": "slowElement",
  "timeout": 20.0
}
```

### 4. Element Finding Strategies
- **By identifier**: `{"identifier": "loginButton"}`
- **By label**: `{"label": "Login"}`
- **By predicate**: `{"predicate": "type == 'XCUIElementTypeButton' AND label CONTAINS 'Submit'"}`

### 5. Validation vs Assertion
- **Soft validation** (`/ui/validate`): Returns pass/fail results without stopping
- **Hard assertion** (`/ui/assert`): Fails immediately if assertion doesn't pass

## Interactive Testing Script

The `test_server_interactive.sh` script provides a menu-driven interface for testing IOSAgentDriver:

### Features
- **Automatic Setup**: Generates test plan with your configuration
- **Device Selection**: Choose simulator from available devices
- **Port Configuration**: Set custom port for multiple instances
- **App Management**: Configure installed applications list
- **23 Test Options**: Interactive menu for all API endpoints
- **Color-Coded Output**: Easy-to-read responses

### Usage
```bash
./scripts/test_server_interactive.sh
```

The script will:
1. Show available simulators
2. Prompt for device selection
3. Ask for port configuration
4. Generate test plan automatically
5. Start IOSAgentDriver
6. Display interactive menu with 23 options

### Example Session
```
Available simulators:
1) iPhone 15 (iOS 17.5)
2) iPhone 16 (iOS 18.0)
Select simulator: 1

Enter port (default 8080): 8080

Starting IOSAgentDriver on iPhone 15...
✅ Server started on port 8080

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IOSAgentDriver Interactive Test Menu
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1.  Health Check
2.  Launch App
3.  Terminate App
...
23. Exit

Select option: 1
✓ Server is healthy
```

## Tips

1. **Use explicit waits** before assertions to avoid race conditions
2. **Configure timeouts** appropriately for your environment
3. **Take screenshots** on failures for debugging
4. **Check for alerts** before interacting with elements
5. **Use interactive script** for manual testing and exploration
6. **Reset configuration** between test runs for consistency

## API Documentation

For complete API documentation, see:
- **[OpenAPI Specification](../openapi.yaml)** - Complete API reference with schemas
- **[Troubleshooting Guide](../TROUBLESHOOTING.md)** - Common issues and solutions
- **[Swagger UI](../swagger/README.md)** - Interactive API explorer

## Example: Running Tests

### Python
```bash
# Install dependencies
pip install requests pytest

# Run example
python3 docs/examples/python_example.py

# Or run as pytest tests
pytest docs/examples/python_example.py -v
```

### JavaScript
```bash
# Install dependencies
npm install axios

# Run example
node docs/examples/javascript_example.js

# Or with Jest
npm test
```

## Support

For more help:
- Check [README.md](../../README.md) for complete documentation
- Use interactive script for hands-on exploration
- Review [Troubleshooting Guide](../TROUBLESHOOTING.md) for common issues
- Explore API with [Swagger UI](../swagger/README.md)

