import UserNotifications

// MARK: - NotificationManager

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private static let categoryProcessAlert = "PROCESS_ALERT"
    private static let categoryLogKeyword   = "LOG_KEYWORD"
    private static let categoryCertExpiry   = "CERT_EXPIRY"
    private static let actionViewSession    = "VIEW_SESSION"
    private static let actionDismiss        = "DISMISS"

    private override init() {
        super.init()
    }

    // MARK: - Permission + Category Registration

    func requestPermission() {
        registerCategories()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
    }

    private func registerCategories() {
        let viewAction = UNNotificationAction(
            identifier: Self.actionViewSession,
            title: "View Session",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: Self.actionDismiss,
            title: "Dismiss",
            options: [.destructive]
        )

        let categories: [UNNotificationCategory] = [
            UNNotificationCategory(identifier: Self.categoryProcessAlert,
                                   actions: [viewAction, dismissAction],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryLogKeyword,
                                   actions: [viewAction, dismissAction],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryCertExpiry,
                                   actions: [viewAction, dismissAction],
                                   intentIdentifiers: [], options: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    // MARK: - Command Complete (existing)

    func notifyCommandComplete(command: String, duration: TimeInterval) {
        guard duration >= 5 else { return }
        fire(title: "Command finished",
             body: "$ \(command) (\(Int(duration))s)",
             identifier: UUID().uuidString)
    }

    // MARK: - Process CPU Alert

    func scheduleProcessAlert(sessionName: String, process: String, cpuPercent: Double) {
        fire(title: "High CPU — \(sessionName)",
             body: String(format: "%@ is using %.0f%% CPU", process, cpuPercent),
             identifier: "process-alert-\(sessionName)-\(process)",
             category: Self.categoryProcessAlert,
             userInfo: ["sessionName": sessionName, "process": process])
    }

    // MARK: - Log Keyword Alert

    func scheduleLogKeywordAlert(sessionName: String, keyword: String, line: String) {
        let body = line.count > 100 ? String(line.prefix(97)) + "…" : line
        fire(title: "[\(keyword)] — \(sessionName)",
             body: body,
             identifier: "log-keyword-\(sessionName)-\(UUID().uuidString)",
             category: Self.categoryLogKeyword,
             userInfo: ["sessionName": sessionName, "keyword": keyword])
    }

    // MARK: - Certificate Expiry Alert

    func scheduleCertExpiryAlert(hostname: String, daysLeft: Int) {
        let body = daysLeft == 1
            ? "\(hostname): certificate expires tomorrow!"
            : "\(hostname): certificate expires in \(daysLeft) days."
        fire(title: "Certificate Expiring Soon",
             body: body,
             identifier: "cert-expiry-\(hostname)",
             category: Self.categoryCertExpiry,
             sound: daysLeft <= 7 ? .defaultCritical : .default,
             userInfo: ["hostname": hostname, "daysLeft": daysLeft])
    }

    // MARK: - Private fire helper

    private func fire(
        title: String,
        body: String,
        identifier: String,
        category: String? = nil,
        sound: UNNotificationSound = .default,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = sound
            if let category { content.categoryIdentifier = category }
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.actionViewSession,
           let sessionName = response.notification.request.content.userInfo["sessionName"] as? String {
            Task { @MainActor in
                if let session = SessionManager.shared.sessions.first(where: {
                    $0.connection.connectionInfo.hostname == sessionName
                }) {
                    SessionManager.shared.activate(session)
                }
            }
        }
        completionHandler()
    }
}
