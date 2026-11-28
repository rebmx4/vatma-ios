import UIKit

@MainActor
final class DownloadCard: UIVisualEffectView {
    static let translations: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "download-labels", withExtension: "json", subdirectory: "BrowserUI/assets"),
              let data = try? Data(contentsOf: url),
              let strings = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return strings
    }()
    private let title = UILabel()
    private let detail = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?
    private var presentationKey = ""

    init(material: UIBlurEffect.Style) {
        super.init(effect: UIBlurEffect(style: material))
        isHidden = true
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.borderWidth = 0.6
        layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
        title.font = .preferredFont(forTextStyle: .headline)
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.lineBreakMode = .byTruncatingMiddle
        primary.configuration = .tinted()
        primary.configuration?.cornerStyle = .capsule
        secondary.configuration = .plain()
        primary.addTarget(self, action: #selector(tapPrimary), for: .touchUpInside)
        secondary.addTarget(self, action: #selector(tapSecondary), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [secondary, primary])
        buttons.distribution = .fillProportionally
        buttons.spacing = 8
        let stack = UIStackView(arrangedSubviews: [title, detail, progress, buttons])
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    @objc private func tapPrimary() { primaryAction?() }
    @objc private func tapSecondary() { secondaryAction?() }

    func hide() {
        guard !isHidden else { return }
        presentationKey = ""
        isHidden = true
        progress.observedProgress = nil
        primaryAction = nil
        secondaryAction = nil
    }

    func show(key: String, title heading: String, detail subtitle: String,
              progress observed: Progress?, primary label: String, secondary other: String?,
              action: @escaping () -> Void, secondaryAction: @escaping () -> Void) {
        guard key != presentationKey else { return }
        presentationKey = key
        isHidden = false
        title.text = heading
        detail.text = subtitle
        detail.isHidden = subtitle.isEmpty
        progress.isHidden = observed == nil
        progress.observedProgress = observed
        primary.configuration?.title = label
        secondary.configuration?.title = other
        secondary.isHidden = other == nil
        primaryAction = action
        self.secondaryAction = secondaryAction
        UIAccessibility.post(notification: .announcement, argument: heading)
    }
}

extension BrowserController {
    var downloadLabels: [String: String] {
        DownloadCard.translations[downloadLanguage] ?? DownloadCard.translations["en"] ?? [:]
    }

    func updateDownloadCard() {
        let labels = downloadLabels
        let visible = downloads.tasks.filter { $0.tabID == model.activeTabId || panel == "files" }
        let running = downloads.tasks.filter { ["connecting","running","cancelling"].contains($0.status) }
        let notice = downloads.notice
        let task = visible.first { $0.status == "confirm" }
            ?? notice.flatMap { candidate in visible.contains { $0 === candidate } ? candidate : nil }
            ?? (panel == nil ? visible.first { $0.status == "running" } : nil)
        guard let task else { downloadCard.hide(); return }
        let key = [task.id, task.status, downloadLanguage, String(running.count)].joined(separator: "/")
        let id = task.id
        if task.status == "confirm" {
            let bytes = ByteCountFormatter.string(fromByteCount: max(0, task.total), countStyle: .file)
            let button = (labels["save"] ?? "Download") + (task.total >= 0 ? " (\(bytes))" : "")
            downloadCard.show(key: key, title: task.name,
                detail: [task.host, task.total < 0 ? labels["unknown"] : nil].compactMap { $0 }.joined(separator: " · "),
                progress: nil, primary: button, secondary: labels["cancel"],
                action: { [weak self] in self?.downloads.confirm(id) },
                secondaryAction: { [weak self] in self?.downloads.cancel(id) })
        } else {
            let finished = task.status == "done"
            let ongoing = task.status == "running"
            let heading = ongoing ? "\(labels["count"] ?? "Downloads") · \(running.count)" : labels[task.status] ?? task.status
            downloadCard.show(key: key, title: heading, detail: task.name,
                progress: ongoing && task.total > 0 ? task.download?.progress : nil,
                primary: labels[finished ? "show" : "downloads"] ?? "Downloads", secondary: ongoing ? labels["cancel"] : "×",
                action: { [weak self] in
                    guard let self else { return }
                    if !ongoing { self.downloads.dismissNotice() }
                    self.ui.callAsyncJavaScript("await window.atmaShowDownload(fileID)", arguments: ["fileID": task.fileID ?? ""],
                                                in: nil, in: .page, completionHandler: nil)
                }, secondaryAction: { [weak self] in
                    if ongoing { self?.downloads.cancel(id) } else { self?.downloads.dismissNotice() }
                })
        }
    }
}
