# Swagger UI for IOSAgentDriver

Interactive API documentation and testing interface for IOSAgentDriver.

## What is Swagger UI?

Swagger UI provides an interactive interface to explore and test the IOSAgentDriver API directly from your browser. It automatically generates documentation from the OpenAPI specification.

## Features

- 🌐 **Interactive Interface**: Test API endpoints directly from the browser
- 📖 **Auto-Generated Docs**: Always up-to-date with the OpenAPI spec
- 🧪 **Try It Out**: Execute requests and see responses in real-time
- 📋 **Request/Response Examples**: See example payloads for all endpoints
- 🔍 **Schema Validation**: Validates requests against the OpenAPI schema
- 💾 **Export**: Download API specification or generate client code

## Prerequisites

- **Node.js** 18+ (for running Swagger UI server)
- **IOSAgentDriver** must be running (default: `http://localhost:8080`)

## Quick Start

### Option 1: Using the Start Script (Easiest)

```bash
cd ios-driver/docs/swagger
./start_swagger.sh
```

The script will:
1. Check for Node.js installation
2. **Kill any existing process on port 3000** (automatic cleanup)
3. Install dependencies if needed
4. Start the Swagger UI server in background
5. Monitor for 'q' key to quit
6. Open documentation at `http://localhost:3000`

**Interactive Controls**:
- Press **'q'** (and Enter) to gracefully stop the server and quit
- Press **Ctrl+C** to force stop

**Optional: Use custom port**
```bash
./start_swagger.sh 3001  # Use port 3001 instead
```

### Option 2: Manual Setup

```bash
# Install dependencies
cd ios-driver/docs/swagger
npm install

# Start server
npm start
```

Then open `http://localhost:3000` in your browser.

### Option 3: Using Docker

```bash
# From the IOSAgentDriver directory
cd ios-driver

# Start Swagger UI container
docker run -p 8081:8080 \
  -e SWAGGER_JSON=/openapi.yaml \
  -v $(pwd)/docs/openapi.yaml:/openapi.yaml \
  swaggerapi/swagger-ui
```

Then open `http://localhost:8081`

## Usage

### 1. Start IOSAgentDriver

In a separate terminal:

```bash
cd ios-driver
./scripts/test_server_interactive.sh
```

Wait for: `✅ IOSAgentDriver started on port 8080`

### 2. Start Swagger UI

```bash
cd ios-driver/docs/swagger
./start_swagger.sh
```

### 3. Open Browser

Navigate to `http://localhost:3000`

You should see the interactive API documentation with all 23 endpoints.

### 4. Stop the Server

When finished testing:

**Option 1: Graceful quit (recommended)**
```bash
# In the terminal running start_swagger.sh
# Press 'q' and then Enter
q
```

**Option 2: Force stop**
```bash
# Press Ctrl+C in the terminal
```

The cleanup function automatically:
- Terminates the Node.js server process
- Frees the port for future use
- Performs graceful shutdown (or force if needed)

## Using Swagger UI

### Explore Endpoints

1. **Browse endpoints** organized by tags (Health, Configuration, App Management, etc.)
2. **Click on an endpoint** to see details
3. **View request/response schemas** with examples

### Test Endpoints

1. **Click "Try it out"** on any endpoint
2. **Fill in parameters** (or use example values)
3. **Click "Execute"** to send the request
4. **View the response** including status code, headers, and body

### Example: Test Health Check

1. Expand `Health` section
2. Click on `GET /health`
3. Click "Try it out"
4. Click "Execute"
5. See the response:
   ```json
   {
     "status": "ok",
     "timestamp": "2026-03-01T12:00:00Z"
   }
   ```

### Example: Launch App

1. Expand `App Management` section
2. Click on `POST /app/launch`
3. Click "Try it out"
4. Modify the request body:
   ```json
   {
     "bundleId": "com.example.MyApp",
     "arguments": ["-UIAnimationDragCoefficient", "100"],
     "environment": {"MOCK_MODE": "true"}
   }
   ```
5. Click "Execute"
6. View response

### Example: Tap Element

1. Expand `UI Interaction` section
2. Click on `POST /ui/tap`
3. Click "Try it out"
4. Enter request body:
   ```json
   {
     "identifier": "loginButton",
     "timeout": 5.0
   }
   ```
5. Click "Execute"

## Configuration

### Change IOSAgentDriver URL

If IOSAgentDriver is running on a different port:

Edit `server.js`:
```javascript
const swaggerOptions = {
  swaggerOptions: {
    url: '/api-docs',
    // Update the servers list in openapi.yaml or here:
    servers: [
      { url: 'http://localhost:8080' }  // Change port here
    ]
  }
};
```

Or update `docs/openapi.yaml`:
```yaml
servers:
  - url: http://localhost:8080  # Change here
    description: Local runner
```

### Enable CORS (If Needed)

CORS is enabled by default in `server.js`. If you need to restrict it:

```javascript
const cors = require('cors');

// Enable for specific origin
app.use(cors({
  origin: 'http://localhost:8080'
}));
```

## Troubleshooting

### Swagger UI Shows "Failed to Fetch"

**Cause**: IOSAgentDriver not running, wrong URL, or CORS issue

**Solution**:
1. ✅ **Check IOSAgentDriver is running**: 
   ```bash
   curl http://localhost:8080/health
   ```
   
2. ✅ **Verify CORS is enabled** (built-in since version 1.0):
   IOSAgentDriver automatically includes CORS headers in all responses:
   - `Access-Control-Allow-Origin: *`
   - `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
   - `Access-Control-Allow-Headers: Content-Type, Accept, Authorization`
   
3. ✅ **Check URL matches**: 
   Verify Swagger UI is pointing to the correct IOSAgentDriver URL (check `openapi.yaml` servers section)
   
4. ✅ **Test from terminal first**:
   ```bash
   # This should work
   curl http://localhost:8080/health
   
   # If this works but Swagger fails, it's a browser/CORS issue
   ```

5. ⚠️ **If still failing**: 
   - Check browser console for specific error messages
   - Try incognito/private mode to rule out browser extensions
   - Verify no firewall/security software blocking requests

### Cannot Load OpenAPI Spec

**Cause**: Incorrect path to `openapi.yaml`

**Solution**:
Check the path in `server.js` points to the correct location:
```javascript
app.get('/api-docs', (req, res) => {
  res.sendFile(path.join(__dirname, '../openapi.yaml'));
});
```

### Port 3000 Already in Use

**Solution 1: Let the script handle it (automatic)**
```bash
./start_swagger.sh  # Automatically kills existing process
```

**Solution 2: Use different port**
```bash
./start_swagger.sh 3001  # Start on port 3001 instead
```

**Solution 3: Manual cleanup**
```bash
# Find and kill process manually
lsof -ti:3000 | xargs kill
```

**Solution 4: Change default port in server.js**
```javascript
const PORT = process.env.PORT || 3001;  // Change default
```

### Node.js Not Found

**Cause**: Node.js not installed

**Solution**:
```bash
# Install using Homebrew
brew install node

# Verify installation
node --version
```

## Features by Endpoint Category

### Health (1 endpoint)
- Health check

### Configuration (3 endpoints)
- Get configuration
- Update configuration
- Reset configuration

### App Management (3 endpoints)
- Launch app
- Terminate app
- List installed apps

### UI Query (3 endpoints)
- Get UI tree
- Find element
- Get element details

### UI Interaction (5 endpoints)
- Tap element
- Type text
- Swipe
- Scroll
- Hardware keyboard input

### Screenshots (2 endpoints)
- Full screenshot
- Element screenshot

### Validation (2 endpoints)
- Soft validation
- Hard assertion

### Alerts (2 endpoints)
- List alerts
- Dismiss alert

### Wait (1 endpoint)
- Explicit wait conditions

## Advanced Usage

### Generate API Client

Use Swagger Codegen to generate client libraries:

```bash
# Install Swagger Codegen
npm install -g @openapitools/openapi-generator-cli

# Generate Python client
openapi-generator-cli generate \
  -i ../openapi.yaml \
  -g python \
  -o ./clients/python

# Generate JavaScript client
openapi-generator-cli generate \
  -i ../openapi.yaml \
  -g javascript \
  -o ./clients/javascript
```

### Export OpenAPI Spec

From Swagger UI:
1. Click the `/api-docs` link at the top
2. Copy the JSON or download it
3. Use for client generation or documentation

### Validate Requests

Swagger UI automatically validates requests against the schema:
- Required fields are marked
- Type validation (string, number, boolean)
- Format validation (dates, UUIDs, etc.)
- Enum validation (for fixed value lists)

## Workflow: Testing a New Feature

1. **Start IOSAgentDriver** with interactive script
2. **Open Swagger UI** in browser
3. **Navigate to endpoint** you want to test
4. **Try example requests** with "Try it out"
5. **Modify parameters** as needed
6. **Execute and observe** responses
7. **Copy working request** to your test code
8. **Take screenshots** if needed for debugging

## Integration with Examples

Use Swagger UI to:
- **Verify request format** before writing Python/JavaScript code
- **Test error cases** (timeouts, not found, etc.)
- **Explore API** interactively before automation
- **Debug issues** with real-time feedback
- **Share API** with team members

## Resources

- [OpenAPI Specification](../openapi.yaml) - Source of truth for API
- [Swagger UI Documentation](https://swagger.io/tools/swagger-ui/) - Official Swagger UI docs
- [OpenAPI Generator](https://openapi-generator.tech/) - Client code generation
- [IOSAgentDriver README](../../README.md) - Complete IOSAgentDriver documentation
- [Troubleshooting Guide](../TROUBLESHOOTING.md) - Common issues
