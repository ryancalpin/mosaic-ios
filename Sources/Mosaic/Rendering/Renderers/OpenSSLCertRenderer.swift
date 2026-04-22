import SwiftUI

@MainActor
public final class OpenSSLCertRenderer: OutputRenderer {
    public let id          = "infra.openssl"
    public let displayName = "SSL Certificate"
    public let badgeLabel  = "CERT"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let isOpenSSL = cmd.contains("openssl") || cmd.contains("x509") || cmd.contains("s_client")
        let looksCert = output.contains("Subject:") && (output.contains("Issuer:") || output.contains("Not After"))
        return isOpenSSL && looksCert
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        var subject    = ""
        var issuer     = ""
        var notBefore  = ""
        var notAfter   = ""
        var san        = ""
        var serialNo   = ""
        var sigAlg     = ""
        var keySize    = ""

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Subject:") {
                subject = extractValue(from: trimmed, prefix: "Subject:")
            } else if trimmed.hasPrefix("Issuer:") {
                issuer = extractValue(from: trimmed, prefix: "Issuer:")
            } else if trimmed.hasPrefix("Not Before:") {
                notBefore = extractValue(from: trimmed, prefix: "Not Before:")
            } else if trimmed.hasPrefix("Not After") {
                notAfter = extractValue(from: trimmed, prefix: "Not After :")
                if notAfter.isEmpty { notAfter = extractValue(from: trimmed, prefix: "Not After:") }
            } else if trimmed.hasPrefix("DNS:") || trimmed.contains("Subject Alternative Name") {
                san = trimmed
            } else if trimmed.hasPrefix("Serial Number:") {
                serialNo = extractValue(from: trimmed, prefix: "Serial Number:")
            } else if trimmed.hasPrefix("Signature Algorithm:") {
                sigAlg = extractValue(from: trimmed, prefix: "Signature Algorithm:")
            } else if trimmed.contains("Public-Key:") {
                keySize = trimmed
            }
        }

        guard !subject.isEmpty else { return nil }

        let isExpired: Bool
        let isExpiringSoon: Bool
        if let date = parseDate(notAfter) {
            let now = Date()
            isExpired = date < now
            isExpiringSoon = !isExpired && date.timeIntervalSince(now) < 30 * 24 * 3600
        } else {
            isExpired = false
            isExpiringSoon = false
        }

        return CertData(
            subject:      subject,
            issuer:       issuer,
            notBefore:    notBefore,
            notAfter:     notAfter,
            san:          san.isEmpty ? nil : san,
            serialNumber: serialNo.isEmpty ? nil : serialNo,
            signatureAlg: sigAlg.isEmpty ? nil : sigAlg,
            keySize:      keySize.isEmpty ? nil : keySize,
            isExpired:    isExpired,
            isExpiringSoon: isExpiringSoon
        )
    }

    private func extractValue(from line: String, prefix: String) -> String {
        guard let range = line.range(of: prefix) else { return "" }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func parseDate(_ s: String) -> Date? {
        let formats = [
            "MMM d HH:mm:ss yyyy z",
            "MMM dd HH:mm:ss yyyy z",
            "yyyy-MM-dd HH:mm:ss z"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: s) { return date }
        }
        return nil
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? CertData else { return AnyView(EmptyView()) }
        return AnyView(CertView(data: data))
    }
}

public struct CertData: RendererData {
    public let subject:       String
    public let issuer:        String
    public let notBefore:     String
    public let notAfter:      String
    public let san:           String?
    public let serialNumber:  String?
    public let signatureAlg:  String?
    public let keySize:       String?
    public let isExpired:     Bool
    public let isExpiringSoon: Bool

    public var statusColor: Color {
        if isExpired      { return Color(hex: "#FF4D6A") }
        if isExpiringSoon { return Color(hex: "#FFB020") }
        return Color(hex: "#3DFF8F")
    }
    public var statusLabel: String {
        if isExpired      { return "EXPIRED" }
        if isExpiringSoon { return "EXPIRING SOON" }
        return "VALID"
    }
    public var commonName: String {
        // Extract CN= from subject
        if let range = subject.range(of: "CN=") {
            let after = String(subject[range.upperBound...])
            return String(after.prefix(while: { $0 != "," && $0 != "/" }))
        }
        return subject
    }
}

struct CertView: View {
    let data: CertData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: data.isExpired ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(data.statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.commonName)
                        .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                    Text(data.statusLabel)
                        .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                        .foregroundColor(data.statusColor)
                        .kerning(0.4)
                }
                Spacer()
                Text("CERT")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color(hex: "#1E1E26"))

            VStack(alignment: .leading, spacing: 0) {
                certRow(label: "Subject",  value: data.subject)
                certRow(label: "Issuer",   value: data.issuer)
                certRow(label: "Valid From", value: data.notBefore)
                certRow(label: "Expires",  value: data.notAfter, color: data.statusColor)
                if let san = data.san { certRow(label: "SAN", value: san) }
                if let alg = data.signatureAlg { certRow(label: "Algorithm", value: alg) }
                if let key = data.keySize { certRow(label: "Key", value: key) }
                if let ser = data.serialNumber { certRow(label: "Serial", value: ser) }
            }
            .padding(.vertical, 4)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(data.statusColor.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func certRow(label: String, value: String, color: Color = Color(hex: "#D8E4F0")) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(Color(hex: "#3A4A58"))
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
