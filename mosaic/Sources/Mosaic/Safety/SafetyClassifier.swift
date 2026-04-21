import Foundation

// MARK: - SafetyClassifier
//
// Runs on every command BEFORE it's sent to the shell.
// Returns a SafetyTier — the UI uses this to either:
//   .safe    → send immediately
//   .tier3   → show yellow warning banner, auto-proceed after 1.5s
//   .tier2   → show approval card, require one tap to confirm
//   .tier1   → show approval card with hold-to-confirm (2s hold)

public final class SafetyClassifier {
    public static let shared = SafetyClassifier()
    private init() {}

    public func classify(_ command: String) -> SafetyTier {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Tier 1 — catastrophic, hold-to-confirm
        for pattern in Self.tier1Patterns {
            if cmd.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .tier1(reason: "This command can cause irreversible system damage.")
            }
        }

        // Tier 2 — destructive, tap-to-confirm
        for pattern in Self.tier2Patterns {
            if cmd.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .tier2(reason: Self.tier2Reason(for: cmd))
            }
        }

        // Tier 3 — risky, auto-dismiss warning
        for pattern in Self.tier3Patterns {
            if cmd.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .tier3(reason: Self.tier3Reason(for: cmd))
            }
        }

        return .safe
    }

    // MARK: - Pattern Lists

    /// Tier 1 — always block, require hold-to-confirm
    private static let tier1Patterns: [String] = [
        #"sudo\s+rm\s+-[a-zA-Z]*r[a-zA-Z]*f?\s+/"#,       // sudo rm -rf /
        #"sudo\s+rm\s+-[a-zA-Z]*f?[a-zA-Z]*r\s+/"#,       // sudo rm -fr /
        #"\bmkfs\b"#,                                        // format filesystem
        #"\bdd\b.+of=/dev/[a-z]"#,                         // raw disk write
        #"\bshred\b"#,                                       // shred files
        #"\bwipefs\b"#,                                      // wipe filesystem signatures
        #"terraform\s+destroy"#,                            // terraform destroy
        #"DROP\s+DATABASE\b"#,                              // SQL drop database
        #"kubectl\s+delete\s+namespace\b"#,                 // delete k8s namespace
    ]

    /// Tier 2 — intercept, show approval card, tap to confirm
    private static let tier2Patterns: [String] = [
        #"\brm\s+-[a-zA-Z]*r"#,                            // rm -r / rm -rf
        #"kubectl\s+delete\b"#,                             // kubectl delete anything
        #"docker\s+rm\s+-f\b"#,                            // docker rm -f
        #"docker\s+system\s+prune\b"#,                     // docker system prune
        #"docker\s+volume\s+prune\b"#,                     // docker volume prune
        #"git\s+push\s+--force\b"#,                        // git push --force
        #"git\s+push\s+-f\b"#,                             // git push -f
        #"git\s+reset\s+--hard\b"#,                        // git reset --hard
        #"git\s+clean\s+-[a-zA-Z]*f"#,                    // git clean -fd
        #"\btruncate\b"#,                                   // truncate file/table
        #"\bpkill\b"#,                                      // kill by name
        #"\bkill\s+-9\b"#,                                  // SIGKILL
        #"\bkillall\b"#,                                    // killall
        #"systemctl\s+stop\b"#,                            // stop service
        #"systemctl\s+disable\b"#,                         // disable service
        #"npm\s+uninstall\b"#,                             // npm uninstall
        #"pip\s+uninstall\b"#,                             // pip uninstall
        #"DROP\s+TABLE\b"#,                                 // SQL drop table
        #"DELETE\s+FROM\b"#,                               // SQL delete (any)
        #"ALTER\s+TABLE\b.+DROP\b"#,                       // SQL alter drop column
    ]

    /// Tier 3 — warn, auto-proceed after 1.5s
    private static let tier3Patterns: [String] = [
        #"\bsudo\b"#,                                       // any sudo (not caught by T1/T2)
        #"chmod\s+777\b"#,                                  // world-writable
        #"chown\s+-R\s+root\b"#,                           // chown -R root
        #"git\s+stash\s+drop\b"#,                          // stash drop
        #"git\s+stash\s+clear\b"#,                         // stash clear
    ]

    private static func tier2Reason(for command: String) -> String {
        if command.contains("rm")           { return "This will permanently delete files." }
        if command.contains("git push")     { return "Force pushing rewrites remote history." }
        if command.contains("git reset")    { return "Hard reset discards uncommitted changes." }
        if command.contains("docker")       { return "This will remove Docker resources." }
        if command.contains("kubectl")      { return "This will delete Kubernetes resources." }
        if command.contains("DROP TABLE")   { return "This will permanently delete a database table." }
        if command.contains("DELETE FROM")  { return "This will permanently delete database rows." }
        if command.contains("kill")         { return "This will forcefully terminate a process." }
        return "This command makes irreversible changes."
    }

    private static func tier3Reason(for command: String) -> String {
        if command.contains("sudo")     { return "Running with elevated privileges." }
        if command.contains("chmod")    { return "World-writable permissions are a security risk." }
        if command.contains("stash")    { return "Stash changes cannot be recovered after this." }
        return "Proceed with caution."
    }
}

// MARK: - SafetyTier

public enum SafetyTier: Equatable {
    case safe
    case tier3(reason: String)
    case tier2(reason: String)
    case tier1(reason: String)

    public var requiresConfirmation: Bool {
        switch self {
        case .safe, .tier3: return false
        case .tier2, .tier1: return true
        }
    }

    public var isImmediate: Bool {
        if case .safe = self { return true }
        return false
    }
}
