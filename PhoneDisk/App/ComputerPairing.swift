import AVFoundation
import CryptoKit
import Foundation
import LocalAuthentication
import Network
import Security
import SwiftUI
import UIKit

struct PairInvitation {
    let id: String
    let host: String
    let port: UInt16
    let fingerprint: String
    let code: String
    let tailnet: String?

    init?(_ text: String) {
        guard text.utf8.count <= 512, let url = URLComponents(string: text),
              url.scheme == "phonedisk", url.host == "pair", url.path.isEmpty,
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              let query = url.queryItems, Set(query.map(\.name)).count == query.count,
              Set(query.map(\.name)).isSubset(of: ["v", "id", "host", "port", "pin", "code", "tailnet"])
        else { return nil }
        func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
        guard value("v") == "1", let id = value("id"), Self.validID(id), let host = value("host"),
              let port = value("port").flatMap({ UInt16($0) }),
              let route = DiskRoute.companion(id: id, host: host, port: port), route.isLocal,
              let fingerprint = value("pin"), Self.isHex(fingerprint, count: 64),
              let code = value("code"), Self.validToken(code)
        else { return nil }
        let tailnet = value("tailnet")
        if let tailnet, DiskRoute.companion(id: id, host: tailnet, port: port)?.isTailnet != true { return nil }
        self.id = id
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
        self.code = code
        self.tailnet = tailnet
    }

    static func validID(_ value: String) -> Bool { isHex(value, count: 32) }

    static func validToken(_ value: String) -> Bool {
        value.utf8.count == 43 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    private static func isHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct PairedComputer: Codable {
    var id: String
    var name: String
    var port: UInt16
    var host: String
    var tailnet: String?
    var fingerprint: String
    var credential: DiskDeviceKey

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ru.atma.phonedisk.computer",
        kSecAttrAccount as String: "paired"
    ]
    static var hasLegacyComputer: Bool {
        let defaults = UserDefaults.standard
        return Transfers.base.host == "127.0.0.1" ||
            defaults.string(forKey: "phone-disk-server-identity") != nil || DiskDeviceKey.load() != nil
    }

    static func load() -> Self? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func store() throws {
        let data = try JSONEncoder().encode(self)
        let status = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecSuccess {
            guard status == errSecItemNotFound else { throw DiskFailure.rejected }
            var item = Self.query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw DiskFailure.rejected }
        }
    }

    static func clear() { SecItemDelete(query as CFDictionary) }

    var logicalOrigin: URL {
        URL(string: "https://\(id).phonedisk.local:\(port)/")!
    }

    var preferredLocal: DiskRoute? { DiskRoute.companion(id: id, host: host, port: port) }
    var fallback: DiskRoute? { tailnet.flatMap { DiskRoute.companion(id: id, host: $0, port: port) } }
}

enum ComputerTrust {
    static func verify(_ challenge: URLAuthenticationChallenge, route: DiskRoute,
                       fingerprint: String) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.previousFailureCount == 0,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == route.address,
              challenge.protectionSpace.port == Int(route.port),
              let id = route.companionID, let trust = challenge.protectionSpace.serverTrust,
              let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map({ String(format: "%02x", $0) }).joined() == fingerprint,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, "\(id).phonedisk.local" as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil)
        else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

private enum PairingFailure: LocalizedError {
    case invalid, expired, network

    var errorDescription: String? {
        switch self {
        case .invalid: return "Наведите камеру на QR-код из окна «Подключить телефон»."
        case .expired: return "На компьютере нажмите «Новый код» и отсканируйте его."
        case .network: return "Подключите iPhone к домашней сети ПК и разрешите «Локальную сеть» в настройках iPhone."
        }
    }
}

private final class PairingConnection: NSObject, URLSessionTaskDelegate {
    let route: DiskRoute
    let fingerprint: String

    init(route: DiskRoute, fingerprint: String) {
        self.route = route
        self.fingerprint = fingerprint
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (action, credential) = ComputerTrust.verify(challenge, route: route, fingerprint: fingerprint)
        completionHandler(action, credential)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func exchange(code: String, device: String, name: String) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = false
        configuration.proxyConfigurations = []
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 7
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let url = route.webOrigin?.appendingPathComponent("api/companion/pair") else { throw PairingFailure.invalid }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code, "deviceId": device, "name": name])
        let (data, response) = try await session.data(for: request)
        guard let reply = response as? HTTPURLResponse, route.acceptsBackgroundURL(reply.url) else { throw PairingFailure.invalid }
        return (data, reply)
    }
}

@MainActor
final class Computers: ObservableObject {
    @Published private(set) var computer = PairedComputer.load()
    @Published private(set) var legacy = PairedComputer.load() == nil && PairedComputer.hasLegacyComputer
    @Published private(set) var notice: String?
    var connected: Bool { computer != nil || legacy }

    func pair(_ text: String) async throws {
        guard let invitation = PairInvitation(text) else { throw PairingFailure.invalid }
        let defaults = UserDefaults.standard
        let device = defaults.string(forKey: "phone-disk-companion-device") ??
            UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(device, forKey: "phone-disk-companion-device")
        struct PairReply: Decodable {
            var token: String
            var expires: TimeInterval
            var serverId: String
            var name: String
        }
        let routes = await DiskRoutes.shared.routesForPairing(invitation)
        for route in routes {
            try Task.checkCancellation()
            let client = PairingConnection(route: route, fingerprint: invitation.fingerprint)
            guard let (data, response) = try? await client.exchange(code: invitation.code, device: device, name: UIDevice.current.name)
            else { continue }
            if response.statusCode == 410 { throw PairingFailure.expired }
            guard response.statusCode == 200, let response = try? JSONDecoder().decode(PairReply.self, from: data),
                  response.serverId == invitation.id, PairInvitation.validToken(response.token),
                  response.expires > Date().timeIntervalSince1970, let host = route.address
            else { throw PairingFailure.invalid }
            let profile = PairedComputer(id: invitation.id, name: response.name, port: route.port, host: host,
                                         tailnet: invitation.tailnet, fingerprint: invitation.fingerprint,
                                         credential: DiskDeviceKey(token: response.token, expires: response.expires))
            try Task.checkCancellation()
            try profile.store()
            notice = nil
            computer = profile
            legacy = false
            DiskRoutes.shared.connectionChanged()
            return
        }
        throw PairingFailure.network
    }

    func disconnect(revoke: Bool) async {
        guard let computer else { return }
        if revoke, let route = try? await DiskRoutes.shared.resolve(), route.companionID == computer.id {
            var request = URLRequest(url: Transfers.address("/api/v2/device"), timeoutInterval: 4)
            request.httpMethod = "DELETE"
            request.setValue("Bearer " + computer.credential.token, forHTTPHeaderField: "Authorization")
            _ = try? await DiskRoutes.shared.data(request, route: route)
        }
        PairedComputer.clear()
        notice = revoke ? nil : "Доступ к компьютеру закрыт. Для повторного подключения отсканируйте новый код на ПК."
        legacy = PairedComputer.hasLegacyComputer
        self.computer = nil
        DiskRoutes.shared.connectionChanged()
        Transfers.shared.recover()
    }
}

@MainActor
final class FilesLock: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "phone-disk-files-lock")
    @Published private(set) var unlocked = false
    @Published private(set) var authenticating = false
    @Published var message = ""
    private var generation = 0
    private var context: LAContext?

    var needsUnlock: Bool { enabled && !unlocked }

    func background() {
        generation += 1
        unlocked = false
        context?.invalidate()
    }

    func unlock() async {
        guard needsUnlock, await authenticate() else { return }
        unlocked = true
    }

    func setEnabled(_ value: Bool) async {
        guard value != enabled, await authenticate() else { return }
        enabled = value
        unlocked = value
        UserDefaults.standard.set(value, forKey: "phone-disk-files-lock")
    }

    private func authenticate() async -> Bool {
        guard !authenticating else { return false }
        let context = LAContext()
        let revision = generation
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Настройте код-пароль iPhone в системных настройках."
            return false
        }
        authenticating = true
        self.context = context
        defer { self.context = nil; authenticating = false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Подтвердите доступ к файлам")
            return success && generation == revision
        } catch {
            if generation == revision, let failure = error as? LAError,
               ![.userCancel, .systemCancel, .appCancel].contains(failure.code) {
                message = "Не удалось подтвердить доступ. Повторите проверку."
            }
            return false
        }
    }
}

struct PairComputerScreen: View {
    @ObservedObject var computers: Computers
    @State private var scan = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "desktopcomputer").font(.system(size: 48, weight: .light)).foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Добавить компьютер").font(.title.bold())
            Text("На ПК откройте «Мой диск», выберите папку и нажмите «Подключить телефон».")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if loading {
                ProgressView("Подключаюсь к компьютеру…")
            } else {
                Button("Сканировать QR-код") { requestCamera() }.buttonStyle(.borderedProminent)
            }
            if let message = message ?? computers.notice {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if self.message != nil {
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(.subheadline)
                }
            }
            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $scan) {
            NavigationStack {
                QRScanner { code in
                    scan = false
                    loading = true
                    message = nil
                    Task {
                        defer { loading = false }
                        do { try await computers.pair(code) }
                        catch { message = error.localizedDescription }
                    }
                } failed: {
                    scan = false
                    message = "Камера недоступна. Проверьте разрешение в настройках iPhone."
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("QR-код с экрана ПК")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { scan = false } } }
            }
        }
    }

    private func requestCamera() {
        Task {
            if await AVCaptureDevice.requestAccess(for: .video) {
                scan = true
            } else {
                message = "Разрешите доступ к камере в настройках iPhone."
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    var didScan: (String) -> Void
    var failed: () -> Void

    func makeUIViewController(context: Context) -> Camera {
        Camera(didScan: didScan, failed: failed)
    }
    func updateUIViewController(_ controller: Camera, context: Context) {}

    final class Camera: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let capture = AVCaptureSession()
        private let worker = DispatchQueue(label: "PhoneDisk camera")
        private let didScan: (String) -> Void
        private let failed: () -> Void
        private var preview: AVCaptureVideoPreviewLayer?
        private var reported = false

        init(didScan: @escaping (String) -> Void, failed: @escaping () -> Void) {
            self.didScan = didScan
            self.failed = failed
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let output = AVCaptureMetadataOutput()
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                  capture.canAddInput(input), capture.canAddOutput(output)
            else {
                DispatchQueue.main.async { self.failed() }
                return
            }
            capture.addInput(input)
            capture.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            guard output.availableMetadataObjectTypes.contains(.qr) else {
                DispatchQueue.main.async { self.failed() }
                return
            }
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: capture)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
            worker.async { [capture] in capture.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            worker.async { [capture] in if capture.isRunning { capture.stopRunning() } }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !reported, let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            reported = true
            didScan(code)
        }
    }
}
