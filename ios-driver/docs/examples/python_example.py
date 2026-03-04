#!/usr/bin/env python3
"""
IOSAgentDriver Python Example
Demonstrates automated iOS testing using Python and the requests library.
"""

import requests
import base64
import time
from typing import Dict, Any, Optional

class IOSAgentDriver:
    """Client for IOSAgentDriver HTTP API"""
    
    def __init__(self, base_url: str = "http://localhost:8080", timeout: float = 30.0):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({"Content-Type": "application/json"})
        self.default_timeout = timeout
    
    def health_check(self) -> Dict[str, Any]:
        """Check if server is healthy"""
        response = self.session.get(f"{self.base_url}/health")
        response.raise_for_status()
        return response.json()
    
    def launch_app(self, bundle_id: str, arguments: Optional[list] = None, 
                   environment: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        """Launch an app"""
        payload = {"bundleId": bundle_id}
        if arguments:
            payload["arguments"] = arguments
        if environment:
            payload["environment"] = environment
        
        response = self.session.post(f"{self.base_url}/app/launch", json=payload)
        response.raise_for_status()
        return response.json()
    
    def terminate_app(self, bundle_id: str) -> Dict[str, Any]:
        """Terminate a running app"""
        response = self.session.post(
            f"{self.base_url}/app/terminate",
            json={"bundleId": bundle_id}
        )
        response.raise_for_status()
        return response.json()
    
    def get_ui_tree(self) -> Dict[str, Any]:
        """Get complete UI hierarchy"""
        response = self.session.get(f"{self.base_url}/ui/tree")
        response.raise_for_status()
        return response.json()
    
    def find_element(self, identifier: Optional[str] = None, 
                     label: Optional[str] = None,
                     predicate: Optional[str] = None,
                     timeout: Optional[float] = None) -> Dict[str, Any]:
        """Find an element by identifier, label, or predicate"""
        payload = {}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        elif predicate:
            payload["predicate"] = predicate
        else:
            raise ValueError("Must provide identifier, label, or predicate")
        
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/find", json=payload)
        response.raise_for_status()
        return response.json()
    
    def tap(self, identifier: Optional[str] = None,
            label: Optional[str] = None,
            predicate: Optional[str] = None,
            timeout: Optional[float] = None) -> Dict[str, Any]:
        """Tap an element"""
        payload = {}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        elif predicate:
            payload["predicate"] = predicate
        else:
            raise ValueError("Must provide identifier, label, or predicate")
        
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/tap", json=payload)
        response.raise_for_status()
        return response.json()
    
    def type_text(self, text: str, identifier: Optional[str] = None,
                  label: Optional[str] = None,
                  clear_first: bool = False,
                  use_hardware_keyboard: bool = True,
                  timeout: Optional[float] = None) -> Dict[str, Any]:
        """Type text into an element"""
        payload = {"text": text, "clearFirst": clear_first, "useHardwareKeyboard": use_hardware_keyboard}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        else:
            raise ValueError("Must provide identifier or label")
        
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/type", json=payload)
        response.raise_for_status()
        return response.json()
    
    def wait_for(self, condition: str, identifier: Optional[str] = None,
                 label: Optional[str] = None,
                 expected_text: Optional[str] = None,
                 expected_value: Optional[str] = None,
                 timeout: Optional[float] = None,
                 poll_interval: float = 0.5) -> Dict[str, Any]:
        """Wait for a condition to be met"""
        payload = {"condition": condition, "pollInterval": poll_interval}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        else:
            raise ValueError("Must provide identifier or label")
        
        if expected_text:
            payload["expectedText"] = expected_text
        if expected_value:
            payload["expectedValue"] = expected_value
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/wait", json=payload)
        response.raise_for_status()
        return response.json()
    
    def validate(self, properties: Dict[str, Any], identifier: Optional[str] = None,
                 label: Optional[str] = None,
                 timeout: Optional[float] = None) -> Dict[str, Any]:
        """Soft validation - returns pass/fail without failing"""
        payload = {"properties": properties}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        else:
            raise ValueError("Must provide identifier or label")
        
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/validate", json=payload)
        response.raise_for_status()
        return response.json()
    
    def assert_property(self, property: str, expected: Any,
                        identifier: Optional[str] = None,
                        label: Optional[str] = None,
                        timeout: Optional[float] = None) -> Dict[str, Any]:
        """Hard assertion - fails if assertion doesn't pass"""
        payload = {"property": property, "expected": expected}
        if identifier:
            payload["identifier"] = identifier
        elif label:
            payload["label"] = label
        else:
            raise ValueError("Must provide identifier or label")
        
        if timeout:
            payload["timeout"] = timeout
        
        response = self.session.post(f"{self.base_url}/ui/assert", json=payload)
        response.raise_for_status()
        return response.json()
    
    def screenshot(self, format: str = "png", quality: float = 0.8) -> bytes:
        """Take a screenshot and return image bytes"""
        payload = {"format": format}
        if format == "jpeg":
            payload["quality"] = quality
        
        response = self.session.post(f"{self.base_url}/screenshot", json=payload)
        response.raise_for_status()
        data = response.json()["data"]
        return base64.b64decode(data)
    
    def get_config(self) -> Dict[str, Any]:
        """Get current configuration"""
        response = self.session.get(f"{self.base_url}/config")
        response.raise_for_status()
        return response.json()
    
    def update_config(self, default_timeout: Optional[float] = None,
                      error_verbosity: Optional[str] = None,
                      max_concurrent_requests: Optional[int] = None) -> Dict[str, Any]:
        """Update configuration"""
        payload = {}
        if default_timeout is not None:
            payload["defaultTimeout"] = default_timeout
        if error_verbosity is not None:
            payload["errorVerbosity"] = error_verbosity
        if max_concurrent_requests is not None:
            payload["maxConcurrentRequests"] = max_concurrent_requests
        
        response = self.session.post(f"{self.base_url}/config", json=payload)
        response.raise_for_status()
        return response.json()


# Example Test
def test_login_flow():
    """Example: Test app login flow"""
    runner = IOSAgentDriver()
    
    # Configure for debugging
    runner.update_config(error_verbosity="verbose", default_timeout=10.0)
    
    # Check server health
    health = runner.health_check()
    assert health["status"] == "ok", "Server not healthy"
    print("✓ Server healthy")
    
    # Launch app
    result = runner.launch_app(
        bundle_id="com.example.MyApp",
        arguments=["-UIAnimationDragCoefficient", "100"],  # Speed up animations
        environment={"MOCK_MODE": "true"}
    )
    assert result["state"] == "running", "App failed to launch"
    print("✓ App launched")
    
    # Wait for login screen
    runner.wait_for(condition="exists", identifier="emailField", timeout=15.0)
    print("✓ Login screen appeared")
    
    # Enter email
    runner.type_text("user@example.com", identifier="emailField", clear_first=True)
    print("✓ Entered email")
    
    # Enter password
    runner.type_text("password123", identifier="passwordField", clear_first=True)
    print("✓ Entered password")
    
    # Tap login button
    runner.tap(label="Login")
    print("✓ Tapped login button")
    
    # Wait for home screen
    result = runner.wait_for(condition="exists", identifier="homeScreen", timeout=20.0)
    print(f"✓ Home screen appeared after {result['waitedTime']}s")
    
    # Validate we're on home screen
    validation = runner.validate(
        properties={"exists": True, "isVisible": True},
        identifier="homeScreen"
    )
    assert len(validation["failed"]) == 0, f"Validation failed: {validation['failed']}"
    print("✓ Home screen validated")
    
    # Take screenshot
    screenshot_bytes = runner.screenshot(format="png")
    with open("login_success.png", "wb") as f:
        f.write(screenshot_bytes)
    print("✓ Screenshot saved")
    
    print("\n🎉 Login test passed!")


def test_with_error_handling():
    """Example: Test with proper error handling"""
    runner = IOSAgentDriver()
    
    try:
        runner.launch_app("com.example.MyApp")
        
        # Try to find element
        try:
            element = runner.find_element(identifier="nonExistentButton", timeout=2.0)
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                print("Element not found (expected)")
                # Take screenshot for debugging
                screenshot = runner.screenshot()
                with open("element_not_found.png", "wb") as f:
                    f.write(screenshot)
            else:
                raise
        
        # Continue with test...
        
    except requests.HTTPError as e:
        print(f"HTTP Error: {e}")
        print(f"Response: {e.response.text}")
        raise
    except Exception as e:
        print(f"Unexpected error: {e}")
        raise


def test_wait_conditions():
    """Example: Using explicit wait conditions"""
    runner = IOSAgentDriver()
    runner.launch_app("com.example.MyApp")
    
    # Wait for element to exist
    runner.wait_for(condition="exists", identifier="loadingSpinner", timeout=5.0)
    print("✓ Loading spinner appeared")
    
    # Wait for element to disappear
    runner.wait_for(condition="notExists", identifier="loadingSpinner", timeout=30.0)
    print("✓ Loading spinner disappeared")
    
    # Wait for text to appear
    runner.wait_for(
        condition="textContains",
        label="statusLabel",
        expected_text="Success",
        timeout=10.0
    )
    print("✓ Success message appeared")
    
    # Wait for element to be enabled
    runner.wait_for(condition="isEnabled", identifier="submitButton", timeout=5.0)
    print("✓ Submit button enabled")


if __name__ == "__main__":
    # Run example tests
    print("Running IOSAgentDriver Python Examples\n")
    print("="*50)
    print("Test 1: Login Flow")
    print("="*50)
    test_login_flow()
    
    print("\n" + "="*50)
    print("Test 2: Wait Conditions")
    print("="*50)
    test_wait_conditions()
    
    print("\n✅ All examples completed!")
