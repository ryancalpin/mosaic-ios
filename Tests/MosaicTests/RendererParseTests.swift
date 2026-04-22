import Testing
@testable import Mosaic

// MARK: - DockerPs

@Suite("DockerPsRenderer")
@MainActor
struct DockerPsTests {
    let r = DockerPsRenderer()

    @Test func parsesTwoContainers() throws {
        let data = r.parse(command: "docker ps", output: dockerPsOutput) as? DockerPsData
        #expect(data?.containers.count == 2)
    }

    @Test func firstContainerIsRunning() throws {
        let data = r.parse(command: "docker ps", output: dockerPsOutput) as? DockerPsData
        #expect(data?.containers.first?.isRunning == true)
    }

    @Test func stoppedContainerIsNotRunning() throws {
        let output = """
CONTAINER ID   IMAGE     COMMAND   CREATED      STATUS                  PORTS   NAMES
abc123def456   nginx     "nginx"   1 day ago    Exited (0) 10 min ago           stopped_web
"""
        let data = r.parse(command: "docker ps -a", output: output) as? DockerPsData
        #expect(data?.containers.first?.isRunning == false)
    }

    @Test func returnsNilForEmptyOutput() {
        #expect(r.parse(command: "docker ps", output: "") == nil)
    }

    @Test func returnsNilForNonDockerOutput() {
        #expect(r.parse(command: "docker ps", output: "hello world\nno containers here") == nil)
    }

    @Test func canRenderDockerPs()      { #expect(r.canRender(command: "docker ps", output: "")) }
    @Test func canRenderDockerLs()      { #expect(r.canRender(command: "docker container ls", output: "")) }
    @Test func cannotRenderGitStatus()  { #expect(!r.canRender(command: "git status", output: "")) }
}

private let dockerPsOutput = """
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                    NAMES
a1b2c3d4e5f6   nginx:latest   "/docker-entrypoint.…"   2 hours ago     Up 2 hours     0.0.0.0:80->80/tcp       web
b2c3d4e5f6a1   postgres:15    "docker-entrypoint.s…"   3 hours ago     Up 3 hours     0.0.0.0:5432->5432/tcp   db
"""

// MARK: - GitStatus

@Suite("GitStatusRenderer")
@MainActor
struct GitStatusTests {
    let r = GitStatusRenderer()

    @Test func parsesBranchName() throws {
        let data = r.parse(command: "git status", output: gitStatusOutput) as? GitStatusData
        #expect(data?.branch == "main")
    }

    @Test func parsesModifiedFiles() throws {
        let data = r.parse(command: "git status", output: gitStatusOutput) as? GitStatusData
        #expect((data?.modified.count ?? 0) > 0)
    }

    @Test func parsesUntrackedFiles() throws {
        let data = r.parse(command: "git status", output: gitStatusOutput) as? GitStatusData
        #expect((data?.untracked.count ?? 0) > 0)
    }

    @Test func cleanWorkingTree() throws {
        let clean = "On branch main\nnothing to commit, working tree clean\n"
        let data = r.parse(command: "git status", output: clean) as? GitStatusData
        #expect(data != nil)
        #expect(data?.modified.isEmpty == true)
    }

    @Test func canRenderGitStatus() { #expect(r.canRender(command: "git status", output: "")) }
    @Test func cannotRenderDockerPs() { #expect(!r.canRender(command: "docker ps", output: "")) }
}

private let gitStatusOutput = """
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
	modified:   Sources/Mosaic/App/MosaicApp.swift

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	Tests/MosaicTests/

no changes added to commit but untracked files present (use "git add" to track)
"""

// MARK: - GitLog

@Suite("GitLogRenderer")
@MainActor
struct GitLogTests {
    let r = GitLogRenderer()

    @Test func parsesCommitHashes() throws {
        let data = r.parse(command: "git log", output: gitLogOutput) as? GitLogData
        #expect(data?.commits.count == 3)
    }

    @Test func hashTruncatedTo7() throws {
        let data = r.parse(command: "git log", output: gitLogOutput) as? GitLogData
        #expect(data?.commits.first?.hash.count == 7)
    }

    @Test func extractsAuthorWithoutEmail() throws {
        let data = r.parse(command: "git log", output: gitLogOutput) as? GitLogData
        let author = data?.commits.first?.author ?? ""
        #expect(!author.contains("<"))
        #expect(!author.contains(">"))
    }

    @Test func extractsCommitMessage() throws {
        let data = r.parse(command: "git log", output: gitLogOutput) as? GitLogData
        #expect(data?.commits.first?.message == "feat: add initial project setup")
    }

    @Test func returnsNilWithoutCommitMarker() {
        #expect(r.parse(command: "git log", output: "just some text\nno commits here") == nil)
    }

    @Test func canRenderGitLog() {
        #expect(r.canRender(command: "git log", output: gitLogOutput))
    }

    @Test func cannotRenderWithoutAuthor() {
        #expect(!r.canRender(command: "git log", output: "commit abc1234\nsome text"))
    }
}

private let gitLogOutput = """
commit abc1234567890abcdef1234567890abcdef123456
Author: Ryan Calpin <ryan@example.com>
Date:   Mon Jan 20 14:30:00 2025 -0800

    feat: add initial project setup

commit def4567890abcdef1234567890abcdef12345678
Author: Ryan Calpin <ryan@example.com>
Date:   Sun Jan 19 10:00:00 2025 -0800

    fix: resolve connection timeout

commit ghi7890abcdef1234567890abcdef1234567890ab
Author: Other Dev <other@example.com>
Date:   Sat Jan 18 09:00:00 2025 -0800

    chore: update dependencies
"""

// MARK: - Traceroute

@Suite("TracerouteRenderer")
@MainActor
struct TracerouteTests {
    let r = TracerouteRenderer()

    @Test func parsesHopCount() throws {
        let data = r.parse(command: "traceroute google.com", output: tracerouteOutput) as? TracerouteData
        #expect(data?.hops.count == 3)
    }

    @Test func parsesTimeout() throws {
        let data = r.parse(command: "traceroute google.com", output: tracerouteOutput) as? TracerouteData
        let timeoutHop = data?.hops.first { $0.isTimeout }
        #expect(timeoutHop != nil)
    }

    @Test func parsesLatency() throws {
        let data = r.parse(command: "traceroute google.com", output: tracerouteOutput) as? TracerouteData
        let hopsWithTime = data?.hops.filter { $0.avgMs != nil } ?? []
        #expect(!hopsWithTime.isEmpty)
    }

    @Test func latencyColorsCorrect() {
        let fast  = TracerouteHop(number: 1, host: "h", ip: nil, times: [5.0],   isTimeout: false)
        let med   = TracerouteHop(number: 2, host: "h", ip: nil, times: [50.0],  isTimeout: false)
        let slow  = TracerouteHop(number: 3, host: "h", ip: nil, times: [200.0], isTimeout: false)
        let timedOut = TracerouteHop(number: 4, host: "*", ip: nil, times: [], isTimeout: true)
        #expect(fast.latencyColor     == .init(hex: "#3DFF8F"))
        #expect(med.latencyColor      == .init(hex: "#FFD060"))
        #expect(slow.latencyColor     == .init(hex: "#FF4D6A"))
        #expect(timedOut.latencyColor == .init(hex: "#3A4A58"))
    }

    @Test func returnsNilWithoutHeader() {
        #expect(r.parse(command: "traceroute x", output: "1  192.168.1.1  1.2 ms") == nil)
    }

    @Test func canRenderTraceroute() { #expect(r.canRender(command: "traceroute google.com", output: "")) }
    @Test func canRenderTracert()    { #expect(r.canRender(command: "tracert 8.8.8.8", output: "")) }
    @Test func canRenderMtr()        { #expect(r.canRender(command: "mtr google.com", output: "")) }
}

private let tracerouteOutput = """
traceroute to google.com (142.250.80.14), 30 hops max, 52 byte packets
 1  192.168.1.1 (192.168.1.1)  1.234 ms  1.100 ms  0.987 ms
 2  * * *
 3  108.170.235.204 (108.170.235.204)  12.345 ms  11.200 ms  10.876 ms
"""

// MARK: - Whois

@Suite("WhoisRenderer")
@MainActor
struct WhoisTests {
    let r = WhoisRenderer()

    @Test func parsesRegistrar() throws {
        let data = r.parse(command: "whois google.com", output: whoisOutput) as? WhoisData
        let registrar = data?.fields.first { $0.label == "Registrar" }
        #expect(registrar != nil)
    }

    @Test func parsesCreationDate() throws {
        let data = r.parse(command: "whois google.com", output: whoisOutput) as? WhoisData
        let created = data?.fields.first { $0.label == "Created" }
        #expect(created != nil)
    }

    @Test func targetIsCommandArg() throws {
        let data = r.parse(command: "whois google.com", output: whoisOutput) as? WhoisData
        #expect(data?.target == "google.com")
    }

    @Test func deduplicatesFields() throws {
        let data = r.parse(command: "whois google.com", output: whoisOutput) as? WhoisData
        let registrarCount = data?.fields.filter { $0.label == "Registrar" }.count ?? 0
        #expect(registrarCount == 1)
    }

    @Test func returnsNilForShortOutput() {
        #expect(r.parse(command: "whois x", output: "Domain Name: x\n") == nil)
    }

    @Test func canRenderWhois() { #expect(r.canRender(command: "whois google.com", output: "")) }
}

private let whoisOutput = """
Domain Name: GOOGLE.COM
Registry Domain ID: 2138514_DOMAIN_COM-VRSN
Registrar WHOIS Server: whois.markmonitor.com
Registrar URL: http://www.markmonitor.com
Updated Date: 2019-09-09T15:39:04Z
Creation Date: 1997-09-15T04:00:00Z
Registry Expiry Date: 2028-09-14T04:00:00Z
Registrar: MarkMonitor Inc.
Registrar IANA ID: 292
Domain Status: clientDeleteProhibited
Name Server: NS1.GOOGLE.COM
Name Server: NS2.GOOGLE.COM
DNSSEC: unsigned
"""

// MARK: - Netstat

@Suite("NetstatRenderer")
@MainActor
struct NetstatTests {
    let r = NetstatRenderer()

    @Test func parsesListeningPorts() throws {
        let data = r.parse(command: "netstat -tlnp", output: netstatOutput) as? NetstatData
        #expect((data?.listening.count ?? 0) > 0)
    }

    @Test func parsesEstablished() throws {
        let data = r.parse(command: "netstat -tnp", output: netstatOutput) as? NetstatData
        #expect((data?.established.count ?? 0) > 0)
    }

    @Test func returnsNilWithoutHeader() {
        #expect(r.parse(command: "netstat", output: "tcp 0 0 0.0.0.0:22") == nil)
    }

    @Test func canRenderNetstat() { #expect(r.canRender(command: "netstat -tlnp", output: "")) }
    @Test func canRenderSS()      { #expect(r.canRender(command: "ss -tlnp", output: "")) }
}

private let netstatOutput = """
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State
tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN
tcp        0      0 127.0.0.1:5432          0.0.0.0:*               LISTEN
tcp        0    100 192.168.1.10:22         192.168.1.1:54321       ESTABLISHED
"""

// MARK: - Nmap

@Suite("NmapRenderer")
@MainActor
struct NmapTests {
    let r = NmapRenderer()

    @Test func parsesHost() throws {
        let data = r.parse(command: "nmap 192.168.1.1", output: nmapOutput) as? NmapData
        #expect(data?.hosts.count == 1)
        #expect(data?.hosts.first?.host == "192.168.1.1")
    }

    @Test func parsesOpenPorts() throws {
        let data = r.parse(command: "nmap 192.168.1.1", output: nmapOutput) as? NmapData
        let openPorts = data?.hosts.first?.ports.filter { $0.isOpen } ?? []
        #expect(openPorts.count == 2)
    }

    @Test func parsesServiceNames() throws {
        let data = r.parse(command: "nmap 192.168.1.1", output: nmapOutput) as? NmapData
        let services = data?.hosts.first?.ports.map(\.service) ?? []
        #expect(services.contains("ssh"))
        #expect(services.contains("http"))
    }

    @Test func returnsNilWithoutScanReport() {
        #expect(r.parse(command: "nmap x", output: "Starting Nmap 7.94") == nil)
    }

    @Test func canRenderNmap()       { #expect(r.canRender(command: "nmap 192.168.1.0/24", output: "")) }
    @Test func canRenderByOutput()   { #expect(r.canRender(command: "scan", output: "Nmap scan report for host")) }
}

private let nmapOutput = """
Starting Nmap 7.94 ( https://nmap.org ) at 2024-01-15 12:00 PST
Nmap scan report for 192.168.1.1
Host is up (0.0015s latency).
Not shown: 998 filtered tcp ports (no-response)
PORT   STATE SERVICE
22/tcp open  ssh
80/tcp open  http

Nmap done: 1 IP address (1 host up) scanned in 5.23 seconds
"""

// MARK: - SqlTable

@Suite("SqlTableRenderer")
@MainActor
struct SqlTableTests {
    let r = SqlTableRenderer()

    @Test func parsesPsqlOutput() throws {
        let data = r.parse(command: "psql", output: psqlOutput) as? SqlTableData
        #expect(data?.columns == ["id", "name", "email"])
        #expect(data?.rows.count == 2)
    }

    @Test func parsesSqlite3PipeOutput() throws {
        let data = r.parse(command: "sqlite3 db.sqlite3", output: sqlite3PipeOutput) as? SqlTableData
        #expect(data?.columns.count == 3)
        #expect((data?.rows.count ?? 0) >= 1)
    }

    // Regression test: sqlite3 canRender was returning false for bare-pipe format
    @Test func canRenderSqlite3PipeFormat() {
        #expect(r.canRender(command: "sqlite3 db.sqlite3", output: sqlite3PipeOutput))
    }

    @Test func canRenderPsql()  { #expect(r.canRender(command: "psql -U postgres mydb", output: psqlOutput)) }
    @Test func canRenderMysql() { #expect(r.canRender(command: "mysql -u root", output: psqlOutput)) }

    @Test func returnsNilForEmpty() {
        #expect(r.parse(command: "psql", output: "") == nil)
    }
}

private let psqlOutput = """
 id |   name   |        email
----+----------+---------------------
  1 | Alice    | alice@example.com
  2 | Bob      | bob@example.com
(2 rows)
"""

private let sqlite3PipeOutput = """
id|name|email
1|Alice|alice@example.com
2|Bob|bob@example.com
"""

// MARK: - TerraformPlan

@Suite("TerraformPlanRenderer")
@MainActor
struct TerraformTests {
    let r = TerraformPlanRenderer()

    @Test func parsesSummaryLine() throws {
        let data = r.parse(command: "terraform plan", output: tfPlanOutput) as? TFPlanData
        #expect(data?.summary?.toAdd == 2)
        #expect(data?.summary?.toChange == 1)
        #expect(data?.summary?.toDestroy == 0)
    }

    @Test func parsesResourceList() throws {
        let data = r.parse(command: "terraform plan", output: tfPlanOutput) as? TFPlanData
        #expect(data?.resources.count == 3)
    }

    @Test func resourceKindsCorrect() throws {
        let data = r.parse(command: "terraform plan", output: tfPlanOutput) as? TFPlanData
        let creates  = data?.resources.filter { $0.kind == .create  } ?? []
        let updates  = data?.resources.filter { $0.kind == .update  } ?? []
        #expect(creates.count == 2)
        #expect(updates.count == 1)
    }

    @Test func noChanges() throws {
        let noChangeOutput = "No changes. Your infrastructure matches the configuration.\n"
        let data = r.parse(command: "terraform plan", output: noChangeOutput) as? TFPlanData
        #expect(data?.summary?.noChanges == true)
    }

    @Test func canRenderTerraform() { #expect(r.canRender(command: "terraform plan", output: tfPlanOutput)) }
    @Test func canRenderTofu()      { #expect(r.canRender(command: "tofu plan", output: tfPlanOutput)) }
}

private let tfPlanOutput = """
Terraform used the selected providers to generate the following execution plan.

  # aws_instance.web will be created
  # aws_s3_bucket.assets will be created
  # aws_security_group.web will be updated in-place

Plan: 2 to add, 1 to change, 0 to destroy.
"""

// MARK: - OpenSSLCert

@Suite("OpenSSLCertRenderer")
@MainActor
struct OpenSSLCertTests {
    let r = OpenSSLCertRenderer()

    @Test func parsesCommonName() throws {
        let data = r.parse(command: "openssl x509 -in cert.pem -text", output: certOutput) as? CertData
        #expect(data?.commonName == "example.com")
    }

    @Test func parsesIssuer() throws {
        let data = r.parse(command: "openssl x509 -in cert.pem -text", output: certOutput) as? CertData
        #expect(!(data?.issuer.isEmpty ?? true))
    }

    @Test func validCertNotExpired() throws {
        let data = r.parse(command: "openssl x509 -in cert.pem -text", output: certOutput) as? CertData
        // cert has future expiry date → should not be expired
        #expect(data?.isExpired == false)
    }

    @Test func returnsNilWithoutSubject() {
        #expect(r.parse(command: "openssl x509 -in cert.pem -text", output: "Not a certificate\n") == nil)
    }

    @Test func canRenderOpenSSL() { #expect(r.canRender(command: "openssl x509 -in cert.pem -noout -text", output: certOutput)) }
}

private let certOutput = """
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 1234 (0x4d2)
    Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=US, O=Let's Encrypt, CN=R3
        Validity
            Not Before: Jan  1 00:00:00 2025 GMT
            Not After : Dec 31 23:59:59 2027 GMT
        Subject: CN=example.com, O=Example Corp, C=US
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                Public-Key: (2048 bit)
"""

// MARK: - DockerLogs

@Suite("DockerLogsRenderer")
@MainActor
struct DockerLogsTests {
    let r = DockerLogsRenderer()

    @Test func parsesContainerName() throws {
        let data = r.parse(command: "docker logs mycontainer", output: dockerLogsOutput) as? DockerLogsData
        #expect(data?.containerName == "mycontainer")
    }

    @Test func parsesEntryCount() throws {
        let data = r.parse(command: "docker logs mycontainer", output: dockerLogsOutput) as? DockerLogsData
        #expect((data?.entries.count ?? 0) >= 3)
    }

    @Test func detectsErrorLevel() throws {
        let data = r.parse(command: "docker logs mycontainer", output: dockerLogsOutput) as? DockerLogsData
        let hasError = data?.entries.contains { $0.level == .error } ?? false
        #expect(hasError)
    }

    @Test func detectsWarnLevel() throws {
        let data = r.parse(command: "docker logs mycontainer", output: dockerLogsOutput) as? DockerLogsData
        let hasWarn = data?.entries.contains { $0.level == .warn } ?? false
        #expect(hasWarn)
    }

    @Test func parsesTimestamps() throws {
        let data = r.parse(command: "docker logs --timestamps mycontainer", output: dockerLogsOutput) as? DockerLogsData
        let hasTimestamp = data?.entries.contains { $0.timestamp != nil } ?? false
        #expect(hasTimestamp)
    }

    @Test func canRenderDockerLogs()          { #expect(r.canRender(command: "docker logs mycontainer", output: "")) }
    @Test func canRenderDockerContainerLogs() { #expect(r.canRender(command: "docker container logs web", output: "")) }
}

private let dockerLogsOutput = """
2024-01-15T12:00:00.000000000Z Starting application
2024-01-15T12:00:01.100000000Z Listening on port 8080
2024-01-15T12:00:05.500000000Z WARNING: disk usage above 90%
2024-01-15T12:00:10.200000000Z ERROR: failed to connect to database
2024-01-15T12:00:11.300000000Z Retrying connection...
"""

// MARK: - DuRenderer

@Suite("DuRenderer")
@MainActor
struct DuTests {
    let r = DuRenderer()

    @Test func parsesEntries() throws {
        let data = r.parse(command: "du -sh *", output: duOutput) as? DuData
        #expect((data?.entries.count ?? 0) == 4)
    }

    @Test func sortedDescending() throws {
        let data = r.parse(command: "du -sh *", output: duOutput) as? DuData
        let sizes = data?.entries.map(\.bytes) ?? []
        let sorted = sizes.sorted(by: >)
        #expect(sizes == sorted)
    }

    @Test func humanReadableG() throws {
        let output = "1.5G\t./bigdir\n100M\t./smalldir\n"
        let data = r.parse(command: "du -sh *", output: output) as? DuData
        #expect((data?.entries.first?.bytes ?? 0) > 1_000_000_000)
    }

    @Test func humanReadableM() throws {
        let output = "100M\t./meddir\n512K\t./smalldir\n"
        let data = r.parse(command: "du -sh *", output: output) as? DuData
        let big   = data?.entries.first { $0.name == "meddir" }
        let small = data?.entries.first { $0.name == "smalldir" }
        #expect((big?.bytes ?? 0) > (small?.bytes ?? 0))
    }

    @Test func returnsNilForSingleLine() {
        #expect(r.parse(command: "du -sh *", output: "8K\t.\n") == nil)
    }

    @Test func canRenderDu() { #expect(r.canRender(command: "du -sh *", output: "")) }
}

private let duOutput = """
1.2G\t./build
512M\t./node_modules
100M\t./src
8.0K\t./README.md
"""

// MARK: - ManPageRenderer

@Suite("ManPageRenderer")
@MainActor
struct ManPageTests {
    let r = ManPageRenderer()

    @Test func parsesSections() throws {
        let data = r.parse(command: "man ls", output: manPageOutput) as? ManPageData
        let titles = data?.sections.map(\.title) ?? []
        #expect(titles.contains("NAME"))
        #expect(titles.contains("SYNOPSIS"))
        #expect(titles.contains("DESCRIPTION"))
    }

    @Test func commandNameExtracted() throws {
        let data = r.parse(command: "man ls", output: manPageOutput) as? ManPageData
        #expect(data?.commandName == "ls")
    }

    @Test func sectionBodyNotEmpty() throws {
        let data = r.parse(command: "man ls", output: manPageOutput) as? ManPageData
        let name = data?.sections.first { $0.title == "NAME" }
        #expect(!(name?.body.isEmpty ?? true))
    }

    @Test func returnsNilWithoutSections() {
        #expect(r.parse(command: "man ls", output: "just some text without sections") == nil)
    }

    @Test func canRenderMan() {
        #expect(r.canRender(command: "man ls", output: manPageOutput))
    }

    @Test func cannotRenderWithoutSynopsis() {
        #expect(!r.canRender(command: "man ls", output: "NAME\nls - list directory contents\n"))
    }
}

private let manPageOutput = """
LS(1)                     BSD General Commands Manual                    LS(1)

NAME
     ls -- list directory contents

SYNOPSIS
     ls [-ABCFGHIOPRSTUW@abcdefghiklmnopqrstuwx1%] [file ...]

DESCRIPTION
     For each operand that names a file of a type other than directory, ls
     displays its name as well as any requested, associated information.  For
     each operand that names a file of type directory, ls displays the names
     of files contained within that directory, as well as any requested,
     associated information.

SEE ALSO
     chflags(1), chmod(1), sort(1), xterm(1), compat(5), termcap(5),
     symlink(7)
"""

// MARK: - ConnectionModel

@Suite("Connection model")
struct ConnectionModelTests {
    @Test func defaultPort() {
        let c = Connection(name: "test", hostname: "host.example.com", username: "admin")
        #expect(c.port == 22)
    }

    @Test func defaultTransport() {
        let c = Connection(name: "test", hostname: "host.example.com", username: "admin")
        #expect(c.transportProtocol == .ssh)
    }

    @Test func customPort() {
        let c = Connection(name: "test", hostname: "host.example.com", port: 2222, username: "admin")
        #expect(c.port == 2222)
    }

    @Test func moshTransport() {
        let c = Connection(name: "test", hostname: "host.example.com", username: "admin", transport: .mosh)
        #expect(c.transportProtocol == .mosh)
    }

    @Test func connectionInfoHostname() {
        let c = Connection(name: "test", hostname: "prod.example.com", username: "ryan")
        #expect(c.connectionInfo.hostname == "prod.example.com")
        #expect(c.connectionInfo.username == "ryan")
        #expect(c.connectionInfo.port == 22)
    }

    @Test func connectionInfoCredentialIDMatchesID() {
        let c = Connection(name: "test", hostname: "host", username: "u")
        #expect(c.connectionInfo.credentialID == c.id)
    }

    @Test func defaultColorHex() {
        let c = Connection(name: "test", hostname: "host", username: "u")
        #expect(c.colorHex == "#00D4AA")
    }

    @Test func customColorHex() {
        let c = Connection(name: "test", hostname: "host", username: "u", colorHex: "#FF4D6A")
        #expect(c.colorHex == "#FF4D6A")
    }

    @Test func idIsUniquePerInstance() {
        let c1 = Connection(name: "a", hostname: "h", username: "u")
        let c2 = Connection(name: "b", hostname: "h", username: "u")
        #expect(c1.id != c2.id)
    }

    @Test func sortOrderDefaultZero() {
        let c = Connection(name: "test", hostname: "h", username: "u")
        #expect(c.sortOrder == 0)
    }
}
