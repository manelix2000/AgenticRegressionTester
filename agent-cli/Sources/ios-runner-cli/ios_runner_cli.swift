@preconcurrency import ArgumentParser
import Foundation

/// IOSAgentDriver CLI - Multi-session iOS simulator testing tool for LLM agents
///
/// This CLI wraps the IOSAgentDriver HTTP API to enable automated testing
/// across multiple iOS simulators with session management.
@main
struct IOSAgentDriverCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-cli",
        abstract: "Multi-session iOS simulator testing for LLM agents",
        discussion: """
            IOSAgentDriver CLI manages multiple concurrent iOS simulator sessions,
            each running an isolated IOSAgentDriver instance. Sessions persist across
            CLI invocations, enabling long-running automated testing workflows.
            
            \(ColorPrint.info("Use 'agent-cli <command> --help' to see available commands in each group."))
            \(ColorPrint.info("You can use either '--help' or 'help <command>' syntax."))
            """,
        version: "1.0.0",
        subcommands: [
            // Session Management
            Session.self,
            
            // Simulator Management
            Simulator.self,
            
            // API Commands
            APICommands.self,
            
            // Skill Management
            Skill.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: false)]
    )
}
