/**
 * IOSAgentDriver JavaScript/TypeScript Example
 * Demonstrates automated iOS testing using Node.js and axios
 * 
 * Install dependencies: npm install axios
 */

const axios = require('axios');
const fs = require('fs');

class IOSAgentDriver {
    constructor(baseURL = 'http://localhost:8080', timeout = 30000) {
        this.client = axios.create({
            baseURL,
            timeout,
            headers: { 'Content-Type': 'application/json' }
        });
    }

    async healthCheck() {
        const { data } = await this.client.get('/health');
        return data;
    }

    async launchApp(bundleId, options = {}) {
        const { arguments: args, environment } = options;
        const payload = { bundleId };
        if (args) payload.arguments = args;
        if (environment) payload.environment = environment;

        const { data } = await this.client.post('/app/launch', payload);
        return data;
    }

    async terminateApp(bundleId) {
        const { data } = await this.client.post('/app/terminate', { bundleId });
        return data;
    }

    async getUITree() {
        const { data } = await this.client.get('/ui/tree');
        return data;
    }

    async findElement(query) {
        const { data } = await this.client.post('/ui/find', query);
        return data;
    }

    async tap(query) {
        const { data } = await this.client.post('/ui/tap', query);
        return data;
    }

    async typeText(text, query, options = {}) {
        const { clearFirst = false, useHardwareKeyboard = true, timeout } = options;
        const payload = { 
            text, 
            clearFirst, 
            useHardwareKeyboard,
            ...query 
        };
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/type', payload);
        return data;
    }

    async waitFor(condition, query, options = {}) {
        const { expectedText, expectedValue, timeout, pollInterval = 0.5 } = options;
        const payload = { 
            condition, 
            pollInterval,
            ...query 
        };
        if (expectedText) payload.expectedText = expectedText;
        if (expectedValue) payload.expectedValue = expectedValue;
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/wait', payload);
        return data;
    }

    async validate(properties, query, timeout) {
        const payload = { properties, ...query };
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/validate', payload);
        return data;
    }

    async assertProperty(property, expected, query, timeout) {
        const payload = { property, expected, ...query };
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/assert', payload);
        return data;
    }

    async screenshot(format = 'png', quality = 0.8) {
        const payload = { format };
        if (format === 'jpeg') payload.quality = quality;

        const { data } = await this.client.post('/screenshot', payload);
        return Buffer.from(data.data, 'base64');
    }

    async getConfig() {
        const { data } = await this.client.get('/config');
        return data;
    }

    async updateConfig(config) {
        const { data } = await this.client.post('/config', config);
        return data;
    }

    async swipe(direction, query, options = {}) {
        const { velocity = 'default', timeout } = options;
        const payload = { direction, velocity, ...query };
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/swipe', payload);
        return data;
    }

    async scroll(containerIdentifier, direction, toVisible, timeout) {
        const payload = { containerIdentifier, direction };
        if (toVisible) payload.toVisible = toVisible;
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/scroll', payload);
        return data;
    }

    async getAlerts() {
        const { data } = await this.client.get('/ui/alerts');
        return data;
    }

    async dismissAlert(buttonLabel, timeout) {
        const payload = { buttonLabel };
        if (timeout) payload.timeout = timeout;

        const { data } = await this.client.post('/ui/alert/dismiss', payload);
        return data;
    }
}

// Example Test using Jest
async function testLoginFlow() {
    const runner = new IOSAgentDriver();

    try {
        // Configure runner
        await runner.updateConfig({ 
            errorVerbosity: 'verbose', 
            defaultTimeout: 10.0 
        });
        console.log('✓ Runner configured');

        // Check health
        const health = await runner.healthCheck();
        console.assert(health.status === 'ok', 'Server not healthy');
        console.log('✓ Server healthy');

        // Launch app
        await runner.launchApp('com.example.MyApp', {
            arguments: ['-UIAnimationDragCoefficient', '100'],
            environment: { MOCK_MODE: 'true' }
        });
        console.log('✓ App launched');

        // Wait for login screen
        await runner.waitFor('exists', { identifier: 'emailField' }, { timeout: 15.0 });
        console.log('✓ Login screen appeared');

        // Fill in form
        await runner.typeText('user@example.com', 
            { identifier: 'emailField' }, 
            { clearFirst: true }
        );
        await runner.typeText('password123', 
            { identifier: 'passwordField' }, 
            { clearFirst: true }
        );
        console.log('✓ Form filled');

        // Submit
        await runner.tap({ label: 'Login' });
        console.log('✓ Login tapped');

        // Wait for home screen
        const result = await runner.waitFor('exists', 
            { identifier: 'homeScreen' }, 
            { timeout: 20.0 }
        );
        console.log(`✓ Home screen appeared after ${result.waitedTime}s`);

        // Validate
        const validation = await runner.validate(
            { exists: true, isVisible: true },
            { identifier: 'homeScreen' }
        );
        console.assert(validation.failed.length === 0, 
            `Validation failed: ${JSON.stringify(validation.failed)}`);
        console.log('✓ Validation passed');

        // Screenshot
        const screenshot = await runner.screenshot('png');
        fs.writeFileSync('login_success.png', screenshot);
        console.log('✓ Screenshot saved');

        console.log('\n🎉 Login test passed!');
    } catch (error) {
        console.error('Test failed:', error.response?.data || error.message);
        
        // Take failure screenshot
        try {
            const screenshot = await runner.screenshot('png');
            fs.writeFileSync('test_failure.png', screenshot);
            console.log('📸 Failure screenshot saved');
        } catch (e) {
            console.error('Could not capture failure screenshot:', e.message);
        }
        
        throw error;
    }
}

// Example with async/await and error handling
async function testWithErrorHandling() {
    const runner = new IOSAgentDriver();

    try {
        await runner.launchApp('com.example.MyApp');

        // Try to find element with timeout
        try {
            await runner.findElement({ 
                identifier: 'nonExistentButton', 
                timeout: 2.0 
            });
        } catch (error) {
            if (error.response?.status === 404) {
                console.log('Element not found (expected)');
                // Continue test...
            } else {
                throw error;
            }
        }

        // Check for alerts before proceeding
        const { alerts } = await runner.getAlerts();
        if (alerts.length > 0) {
            console.log(`Found ${alerts.length} alert(s), dismissing...`);
            await runner.dismissAlert('OK', 5.0);
        }

    } catch (error) {
        console.error('Error:', error.response?.data || error.message);
        throw error;
    }
}

// Example using Promises
function testUsingPromises() {
    const runner = new IOSAgentDriver();

    return runner.launchApp('com.example.MyApp')
        .then(() => runner.tap({ identifier: 'startButton' }))
        .then(() => runner.waitFor('exists', { identifier: 'resultScreen' }))
        .then(() => runner.screenshot())
        .then(screenshot => {
            fs.writeFileSync('result.png', screenshot);
            console.log('✓ Test completed');
        })
        .catch(error => {
            console.error('Test failed:', error.message);
            return runner.screenshot()
                .then(screenshot => {
                    fs.writeFileSync('error.png', screenshot);
                    throw error;
                });
        });
}

// Example: Scrolling to find element
async function testScrolling() {
    const runner = new IOSAgentDriver();

    await runner.launchApp('com.example.MyApp');

    // Scroll down to find element
    await runner.scroll(
        'mainScrollView',
        'down',
        { identifier: 'bottomElement' },
        20.0
    );
    console.log('✓ Scrolled to element');

    // Tap the element
    await runner.tap({ identifier: 'bottomElement' });
    console.log('✓ Element tapped');
}

// Example: Alert handling
async function testAlerts() {
    const runner = new IOSAgentDriver();

    await runner.launchApp('com.example.MyApp');
    await runner.tap({ identifier: 'triggerAlertButton' });

    // Wait a bit for alert to appear
    await new Promise(resolve => setTimeout(resolve, 1000));

    // Check for alerts
    const { alerts } = await runner.getAlerts();
    console.log(`Found ${alerts.length} alert(s)`);

    if (alerts.length > 0) {
        const alert = alerts[0];
        console.log(`Alert: ${alert.title} - ${alert.message}`);
        console.log(`Buttons: ${alert.buttons.join(', ')}`);

        // Dismiss with specific button
        await runner.dismissAlert('OK', 5.0);
        console.log('✓ Alert dismissed');
    }
}

// Export for use in test frameworks
module.exports = {
    IOSAgentDriver,
    testLoginFlow,
    testWithErrorHandling,
    testUsingPromises,
    testScrolling,
    testAlerts
};

// Run if executed directly
if (require.main === module) {
    (async () => {
        console.log('Running IOSAgentDriver JavaScript Examples\n');
        console.log('='.repeat(50));
        console.log('Test 1: Login Flow');
        console.log('='.repeat(50));
        await testLoginFlow();

        console.log('\n' + '='.repeat(50));
        console.log('Test 2: Scrolling');
        console.log('='.repeat(50));
        await testScrolling();

        console.log('\n✅ All examples completed!');
    })().catch(error => {
        console.error('\n❌ Examples failed:', error);
        process.exit(1);
    });
}
