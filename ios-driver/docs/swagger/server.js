const express = require('express');
const swaggerUi = require('swagger-ui-express');
const YAML = require('yamljs');
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Enable CORS for all routes (allows Swagger UI to call IOSAgentDriver)
app.use(cors());

// Load OpenAPI specification
const swaggerDocument = YAML.load(path.join(__dirname, '../openapi.yaml'));

// Serve the OpenAPI spec as JSON
app.get('/api-docs', (req, res) => {
  res.json(swaggerDocument);
});

// Swagger UI options
const swaggerOptions = {
  customCss: '.swagger-ui .topbar { display: none }',
  customSiteTitle: 'IOSAgentDriver API Documentation',
  swaggerOptions: {
    url: '/api-docs',
    docExpansion: 'list',  // 'list', 'full', or 'none'
    defaultModelsExpandDepth: 3,
    defaultModelExpandDepth: 3,
    displayRequestDuration: true,
    filter: true,
    showExtensions: true,
    showCommonExtensions: true,
    tryItOutEnabled: true
  }
};

// Serve Swagger UI
app.use('/', swaggerUi.serve, swaggerUi.setup(swaggerDocument, swaggerOptions));

// Health check for Swagger UI server itself
app.get('/swagger-health', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: 'Swagger UI server is running',
    iosAgentDriverUrl: swaggerDocument.servers[0].url
  });
});

app.listen(PORT, () => {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🚀 Swagger UI for IOSAgentDriver');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`\n📖 Documentation: http://localhost:${PORT}`);
  console.log(`\n⚙️  IOSAgentDriver: ${swaggerDocument.servers[0].url}`);
  console.log('\n✅ Make sure IOSAgentDriver is running before testing endpoints');
  console.log('\n💡 Tip: Use "Try it out" to test endpoints interactively');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
});
