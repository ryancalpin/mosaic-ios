import Testing
@testable import Mosaic

@Suite("SafetyClassifier")
struct SafetyClassifierTests {
    let classifier = SafetyClassifier.shared

    // MARK: - Safe commands

    @Test func safeListDir()       { #expect(classifier.classify("ls -la") == .safe) }
    @Test func safeGitStatus()     { #expect(classifier.classify("git status") == .safe) }
    @Test func safeDockerPs()      { #expect(classifier.classify("docker ps") == .safe) }
    @Test func safeCatFile()       { #expect(classifier.classify("cat README.md") == .safe) }
    @Test func safeEmptyString()   { #expect(classifier.classify("") == .safe) }
    @Test func safeEcho()          { #expect(classifier.classify("echo hello") == .safe) }
    @Test func safePwd()           { #expect(classifier.classify("pwd") == .safe) }

    // MARK: - Tier 3

    @Test func tier3SudoBasic() {
        let result = classifier.classify("sudo apt-get update")
        guard case .tier3 = result else { Issue.record("Expected tier3, got \(result)"); return }
    }

    @Test func tier3Chmod777() {
        let result = classifier.classify("chmod 777 /tmp/file")
        guard case .tier3 = result else { Issue.record("Expected tier3, got \(result)"); return }
    }

    @Test func tier3GitStashDrop() {
        let result = classifier.classify("git stash drop")
        guard case .tier3 = result else { Issue.record("Expected tier3, got \(result)"); return }
    }

    @Test func tier3GitStashClear() {
        let result = classifier.classify("git stash clear")
        guard case .tier3 = result else { Issue.record("Expected tier3, got \(result)"); return }
    }

    // MARK: - Tier 2

    @Test func tier2RmRecursive() {
        let result = classifier.classify("rm -rf /tmp/old")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2RmRecursiveFlagOrder() {
        let result = classifier.classify("rm -fr /tmp/old")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2GitPushForce() {
        let result = classifier.classify("git push --force origin main")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2GitPushForceLong() {
        let result = classifier.classify("git push -f origin main")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2GitResetHard() {
        let result = classifier.classify("git reset --hard HEAD~1")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2GitClean() {
        let result = classifier.classify("git clean -fd")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2Kill9() {
        let result = classifier.classify("kill -9 1234")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2DockerSystemPrune() {
        let result = classifier.classify("docker system prune")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2SystemctlStop() {
        let result = classifier.classify("systemctl stop nginx")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2SQLDropTable() {
        let result = classifier.classify("DROP TABLE users;")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    @Test func tier2SQLDeleteFrom() {
        let result = classifier.classify("DELETE FROM orders WHERE id=5;")
        guard case .tier2 = result else { Issue.record("Expected tier2, got \(result)"); return }
    }

    // MARK: - Tier 1

    @Test func tier1SudoRmRfSlash() {
        let result = classifier.classify("sudo rm -rf /")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1SudoRmFrSlash() {
        let result = classifier.classify("sudo rm -fr /")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1Mkfs() {
        let result = classifier.classify("mkfs.ext4 /dev/sdb1")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1DdToDisk() {
        let result = classifier.classify("dd if=/dev/zero of=/dev/sda bs=1M")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1TerraformDestroy() {
        let result = classifier.classify("terraform destroy --auto-approve")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1SQLDropDatabase() {
        let result = classifier.classify("DROP DATABASE production;")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    @Test func tier1KubectlDeleteNamespace() {
        let result = classifier.classify("kubectl delete namespace production")
        guard case .tier1 = result else { Issue.record("Expected tier1, got \(result)"); return }
    }

    // MARK: - requiresConfirmation / isImmediate

    @Test func requiresConfirmationTier1() { #expect(SafetyTier.tier1(reason: "x").requiresConfirmation) }
    @Test func requiresConfirmationTier2() { #expect(SafetyTier.tier2(reason: "x").requiresConfirmation) }
    @Test func noConfirmationTier3()       { #expect(!SafetyTier.tier3(reason: "x").requiresConfirmation) }
    @Test func noConfirmationSafe()        { #expect(!SafetyTier.safe.requiresConfirmation) }
    @Test func immediateForSafe()          { #expect(SafetyTier.safe.isImmediate) }
    @Test func immediateForTier3()         { #expect(SafetyTier.tier3(reason: "x").isImmediate) }
    @Test func notImmediateTier1()         { #expect(!SafetyTier.tier1(reason: "x").isImmediate) }
    @Test func notImmediateTier2()         { #expect(!SafetyTier.tier2(reason: "x").isImmediate) }

    // MARK: - Case-insensitivity

    @Test func caseInsensitiveTier1() {
        let result = classifier.classify("SUDO RM -RF /")
        guard case .tier1 = result else { Issue.record("Expected tier1 for uppercase, got \(result)"); return }
    }

    @Test func caseInsensitiveSQLDrop() {
        let result = classifier.classify("drop database mydb")
        guard case .tier1 = result else { Issue.record("Expected tier1 for lowercase DROP DATABASE, got \(result)"); return }
    }
}
