#!/bin/bash

# Script to generate a dynamic test plan with environment variables
# Usage: generate_testplan.sh <port> [installed_apps_csv]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR%/scripts}"

PORT="${1:-8080}"
INSTALLED_APPS="${2:-}"

TESTPLAN_PATH="$PROJECT_DIR/IOSAgentDriverUITests.xctestplan"

# Generate test plan JSON
cat > "$TESTPLAN_PATH" << EOF
{
  "configurations" : [
    {
      "id" : "B8E7F0A6-8C3D-4F2E-9E1B-5D6A7C8B9D0E",
      "name" : "Configuration 1",
      "options" : {
        "environmentVariableEntries" : [
          {
            "key" : "RUNNER_PORT",
            "value" : "$PORT"
          },
          {
            "key" : "INSTALLED_APPLICATIONS",
            "value" : "$INSTALLED_APPS"
          }
        ]
      }
    }
  ],
  "defaultOptions" : {
    "targetForVariableExpansion" : {
      "containerPath" : "container:IOSAgentDriver.xcodeproj",
      "identifier" : "IOSAgentDriverUITests",
      "name" : "IOSAgentDriverUITests"
    }
  },
  "testTargets" : [
    {
      "skippedTests" : [],
      "target" : {
        "containerPath" : "container:IOSAgentDriver.xcodeproj",
        "identifier" : "IOSAgentDriverUITests",
        "name" : "IOSAgentDriverUITests"
      }
    }
  ],
  "version" : 1
}
EOF

echo "$TESTPLAN_PATH"
