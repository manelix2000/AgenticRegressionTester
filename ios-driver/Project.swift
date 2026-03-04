import ProjectDescription

let project = Project(
    name: "IOSAgentDriver",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "SWIFT_OBJC_BRIDGING_HEADER": "$(SRCROOT)/IOSAgentDriver/Sources/IOSAgentDriver-Bridging-Header.h"
        ]
    ),
    targets: [
        // UI Tests target (hosts HTTP server) - includes all source code
        .target(
            name: "IOSAgentDriverUITests",
            destinations: .iOS,
            product: .uiTests,
            productName: "Agent",
            bundleId: "dev.tuist.IOSAgentDriverUITests",
            infoPlist: .default,
            sources: ["IOSAgentDriver/Sources/**"],
            dependencies: []
        )
    ],
    schemes: [
        .scheme(
            name: "IOSAgentDriverUITests",
            buildAction: .buildAction(targets: ["IOSAgentDriverUITests"]),
            testAction: .testPlans(["IOSAgentDriverUITests.xctestplan"])
        )
    ]
)
