import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let tgOpenChat = Notification.Name("tgOpenChat")
}

enum LocalNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func show(_ message: Message) {
        let content = UNMutableNotificationContent()
        content.title = message.senderName.isEmpty ? "新消息" : message.senderName
        content.body = message.text.replacingOccurrences(of: "\n", with: " ")
        content.sound = .default
        content.userInfo = ["chatId": message.chatId]

        let request = UNNotificationRequest(
            identifier: "msg-\(message.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        LocalNotifications.requestPermission()
        return true
    }

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
        if let chatId = response.notification.request.content.userInfo["chatId"] as? String {
            NotificationCenter.default.post(name: .tgOpenChat, object: chatId)
        }
        completionHandler()
    }
}
