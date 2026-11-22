// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import WebKit

@MainActor
public final class DevToolsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    public weak var activeWebView: WKWebView?

    private let segmentedControl = UISegmentedControl(items: ["Network", "Console", "WebSocket", "DOM", "Storage", "Server"])
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let textView = UITextView()
    private let controlBar = UIStackView()
    private let actionButton = UIButton(type: .system)
    private let secondaryActionButton = UIButton(type: .system)
    private let filterField = UITextField()

    private var networkItems: [DevToolsNetworkEntry] = []
    private var consoleItems: [DevToolsConsoleEntry] = []
    private var webSocketItems: [WebSocketFrameEntry] = []
    private var selectedIndex: Int = 0

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
        reloadCurrentTab()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.1, alpha: 0.98)
        title = "GodMode DevTools"

        let closeButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(didTapDone))
        closeButton.tintColor = .systemCyan
        navigationItem.rightBarButtonItem = closeButton

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(didChangeSegment), for: .valueChanged)
        segmentedControl.tintColor = .systemCyan
        segmentedControl.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        let normalTextAttrs = [NSAttributedString.Key.foregroundColor: UIColor.lightGray]
        let selectedTextAttrs = [NSAttributedString.Key.foregroundColor: UIColor.white]
        segmentedControl.setTitleTextAttributes(normalTextAttrs, for: .normal)
        segmentedControl.setTitleTextAttributes(selectedTextAttrs, for: .selected)

        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 0.25, alpha: 1.0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        textView.backgroundColor = UIColor(white: 0.05, alpha: 1.0)
        textView.textColor = .systemGreen
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = false
        textView.isHidden = true

        filterField.placeholder = "Filter..."
        filterField.textColor = .white
        filterField.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        filterField.borderStyle = .roundedRect
        filterField.font = UIFont.systemFont(ofSize: 13)
        filterField.addTarget(self, action: #selector(filterDidChange), for: .editingChanged)

        actionButton.setTitle("Clear", for: .normal)
        actionButton.tintColor = .systemRed
        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        actionButton.addTarget(self, action: #selector(didTapAction), for: .touchUpInside)

        secondaryActionButton.setTitle("Inspect", for: .normal)
        secondaryActionButton.tintColor = .systemCyan
        secondaryActionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        secondaryActionButton.addTarget(self, action: #selector(didTapSecondaryAction), for: .touchUpInside)

        controlBar.axis = .horizontal
        controlBar.spacing = 8
        controlBar.distribution = .fillProportionally
        controlBar.addArrangedSubview(filterField)
        controlBar.addArrangedSubview(secondaryActionButton)
        controlBar.addArrangedSubview(actionButton)

        view.addSubview(segmentedControl)
        view.addSubview(controlBar)
        view.addSubview(tableView)
        view.addSubview(textView)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32),

            controlBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            controlBar.heightAnchor.constraint(equalToConstant: 34),

            tableView.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textView.topAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: DevToolsEngine.didUpdateNetworkNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: DevToolsEngine.didUpdateConsoleNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: WebSocketMonitorEngine.didUpdateFramesNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: LocalHTTPServerEngine.didChangeStateNotification,
            object: nil
        )
    }

    @objc private func handleUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.reloadCurrentTab()
        }
    }

    @objc private func didTapDone() {
        dismiss(animated: true)
    }

    @objc private func didChangeSegment() {
        selectedIndex = segmentedControl.selectedSegmentIndex
        filterField.text = ""
        reloadCurrentTab()
    }

    @objc private func filterDidChange() {
        reloadCurrentTab()
    }

    private func reloadCurrentTab() {
        let filter = filterField.text?.lowercased() ?? ""

        switch selectedIndex {
        case 0:
            tableView.isHidden = false
            textView.isHidden = true
            actionButton.setTitle("Clear", for: .normal)
            secondaryActionButton.isHidden = true
            let all = DevToolsEngine.shared.getNetworkEntries().reversed()
            if filter.isEmpty {
                networkItems = Array(all)
            } else {
                networkItems = all.filter { $0.url.lowercased().contains(filter) || $0.method.lowercased().contains(filter) }
            }
            tableView.reloadData()

        case 1:
            tableView.isHidden = false
            textView.isHidden = true
            actionButton.setTitle("Clear", for: .normal)
            secondaryActionButton.isHidden = true
            let all = DevToolsEngine.shared.getConsoleEntries().reversed()
            if filter.isEmpty {
                consoleItems = Array(all)
            } else {
                consoleItems = all.filter { $0.message.lowercased().contains(filter) || $0.level.rawValue.contains(filter) }
            }
            tableView.reloadData()

        case 2:
            tableView.isHidden = false
            textView.isHidden = true
            actionButton.setTitle("Clear", for: .normal)
            secondaryActionButton.setTitle("Inject", for: .normal)
            secondaryActionButton.isHidden = false
            let all = WebSocketMonitorEngine.shared.getFrames().reversed()
            if filter.isEmpty {
                webSocketItems = Array(all)
            } else {
                webSocketItems = all.filter { $0.payload.lowercased().contains(filter) || $0.url.lowercased().contains(filter) }
            }
            tableView.reloadData()

        case 3:
            tableView.isHidden = true
            textView.isHidden = false
            actionButton.setTitle("Copy", for: .normal)
            secondaryActionButton.setTitle("Refresh DOM", for: .normal)
            secondaryActionButton.isHidden = false
            if textView.text.isEmpty {
                inspectDOM()
            }

        case 4:
            tableView.isHidden = true
            textView.isHidden = false
            actionButton.setTitle("Copy", for: .normal)
            secondaryActionButton.setTitle("Refresh Storage", for: .normal)
            secondaryActionButton.isHidden = false
            if textView.text.isEmpty {
                inspectStorage()
            }

        case 5:
            tableView.isHidden = true
            textView.isHidden = false
            let isRunning = LocalHTTPServerEngine.shared.isRunning
            actionButton.setTitle(isRunning ? "Stop Server" : "Start Server", for: .normal)
            actionButton.tintColor = isRunning ? .systemRed : .systemGreen
            secondaryActionButton.setTitle("Refresh Status", for: .normal)
            secondaryActionButton.isHidden = false
            renderServerStatus()

        default:
            break
        }
    }

    @objc private func didTapAction() {
        switch selectedIndex {
        case 0, 1:
            DevToolsEngine.shared.clearAll()
            reloadCurrentTab()
        case 2:
            WebSocketMonitorEngine.shared.clearFrames()
            reloadCurrentTab()
        case 3, 4:
            UIPasteboard.general.string = textView.text
            let alert = UIAlertController(title: "Copied", message: "Content copied to clipboard", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        case 5:
            if LocalHTTPServerEngine.shared.isRunning {
                LocalHTTPServerEngine.shared.stop()
            } else {
                try? LocalHTTPServerEngine.shared.start()
            }
            renderServerStatus()
        default:
            break
        }
    }

    @objc private func didTapSecondaryAction() {
        switch selectedIndex {
        case 2:
            showWebSocketInjectionAlert()
        case 3:
            inspectDOM()
        case 4:
            inspectStorage()
        case 5:
            renderServerStatus()
        default:
            break
        }
    }

    private func inspectDOM() {
        guard let webView = activeWebView else {
            textView.text = "No active tab webView"
            return
        }
        textView.text = "Loading DOM..."
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let self = self else { return }
            if let html = result as? String {
                self.textView.text = html
            } else if let error = error {
                self.textView.text = "Error inspecting DOM: \(error.localizedDescription)"
            }
        }
    }

    private func inspectStorage() {
        guard let webView = activeWebView else {
            textView.text = "No active tab webView"
            return
        }
        textView.text = "Loading Storage..."
        webView.evaluateJavaScript("window.__godModeGetStorageData ? window.__godModeGetStorageData() : '{}'") { [weak self] result, error in
            guard let self = self else { return }
            if let str = result as? String {
                self.textView.text = str
            } else if let error = error {
                self.textView.text = "Error reading storage: \(error.localizedDescription)"
            }
        }
    }

    private func renderServerStatus() {
        let isRunning = LocalHTTPServerEngine.shared.isRunning
        let urlStr = LocalHTTPServerEngine.shared.serverURL?.absoluteString ?? "http://\(LocalHTTPServerEngine.shared.localIPAddress ?? "127.0.0.1"):\(LocalHTTPServerEngine.shared.port)"
        let root = LocalHTTPServerEngine.shared.rootDirectoryURL.path

        var status = "=== GodMode Local HTTP Server ===\n"
        status += "Status: \(isRunning ? "RUNNING 🟢" : "STOPPED 🔴")\n"
        status += "URL: \(urlStr)\n"
        status += "Port: \(LocalHTTPServerEngine.shared.port)\n"
        status += "Root Directory: \(root)\n\n"
        status += "Files in root directory:\n"

        if let files = try? FileManager.default.contentsOfDirectory(atPath: root) {
            for file in files {
                status += " - \(file)\n"
            }
        }

        textView.text = status
        actionButton.setTitle(isRunning ? "Stop Server" : "Start Server", for: .normal)
        actionButton.tintColor = isRunning ? .systemRed : .systemGreen
    }

    private func showWebSocketInjectionAlert() {
        let alert = UIAlertController(title: "Inject WebSocket Frame", message: "Enter Socket ID and payload", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Socket ID (e.g. ws_1_abcde)"
            if let first = self.webSocketItems.first {
                field.text = first.socketId
            }
        }
        alert.addTextField { field in
            field.placeholder = "Payload (JSON or text)"
            field.text = "{\"action\":\"ping\"}"
        }

        alert.addAction(UIAlertAction(title: "Send", style: .default, handler: { [weak self, weak alert] _ in
            guard let self = self,
                  let socketId = alert?.textFields?[0].text,
                  let payload = alert?.textFields?[1].text else { return }

            WebSocketMonitorEngine.shared.sendFrame(socketId: socketId, payload: payload, in: self.activeWebView) { success in
                let resAlert = UIAlertController(title: success ? "Sent" : "Failed", message: success ? "Frame sent to \(socketId)" : "Could not send frame", preferredStyle: .alert)
                resAlert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(resAlert, animated: true)
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource & Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch selectedIndex {
        case 0: return networkItems.count
        case 1: return consoleItems.count
        case 2: return webSocketItems.count
        default: return 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        switch selectedIndex {
        case 0:
            let item = networkItems[indexPath.row]
            let statusColor: UIColor = item.statusCode >= 400 ? .systemRed : (item.statusCode >= 300 ? .systemYellow : .systemGreen)
            cell.textLabel?.textColor = .white
            let attr = NSMutableAttributedString(
                string: "[\(item.method)] \(item.statusCode) ",
                attributes: [.foregroundColor: statusColor, .font: UIFont.boldSystemFont(ofSize: 12)]
            )
            attr.append(NSAttributedString(string: "\(item.url) (\(Int(item.durationMs))ms)", attributes: [.foregroundColor: UIColor.lightGray]))
            cell.textLabel?.attributedText = attr

        case 1:
            let item = consoleItems[indexPath.row]
            let color: UIColor
            switch item.level {
            case .error: color = .systemRed
            case .warn: color = .systemYellow
            case .info: color = .systemCyan
            case .log, .debug: color = .white
            }
            let attr = NSMutableAttributedString(
                string: "[\(item.level.rawValue.uppercased())] ",
                attributes: [.foregroundColor: color, .font: UIFont.boldSystemFont(ofSize: 12)]
            )
            attr.append(NSAttributedString(string: item.message, attributes: [.foregroundColor: UIColor.lightGray]))
            cell.textLabel?.attributedText = attr

        case 2:
            let item = webSocketItems[indexPath.row]
            let arrow: String
            let color: UIColor
            switch item.direction {
            case .outgoing:
                arrow = "⬆️ OUT"
                color = .systemCyan
            case .incoming:
                arrow = "⬇️ IN"
                color = .systemGreen
            case .open:
                arrow = "🟢 OPEN"
                color = .systemYellow
            case .close:
                arrow = "🔴 CLOSE"
                color = .systemRed
            case .error:
                arrow = "⚠️ ERR"
                color = .systemRed
            }
            let attr = NSMutableAttributedString(
                string: "[\(arrow)] ",
                attributes: [.foregroundColor: color, .font: UIFont.boldSystemFont(ofSize: 12)]
            )
            attr.append(NSAttributedString(string: "\(item.payload.prefix(120))", attributes: [.foregroundColor: UIColor.lightGray]))
            cell.textLabel?.attributedText = attr

        default:
            cell.textLabel?.text = nil
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if selectedIndex == 0 {
            let item = networkItems[indexPath.row]
            let alert = UIAlertController(title: "\(item.method) \(item.statusCode)", message: item.url, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Copy as cURL", style: .default, handler: { _ in
                UIPasteboard.general.string = item.curlCommand
            }))
            alert.addAction(UIAlertAction(title: "View Details", style: .default, handler: { [weak self] _ in
                var details = "URL: \(item.url)\nMethod: \(item.method)\nStatus: \(item.statusCode)\nDuration: \(item.durationMs)ms\n\n"
                details += "--- Request Headers ---\n"
                for (k, v) in item.requestHeaders { details += "\(k): \(v)\n" }
                if let body = item.requestBody { details += "\n--- Request Body ---\n\(body)\n" }
                details += "\n--- Response Headers ---\n"
                for (k, v) in item.responseHeaders { details += "\(k): \(v)\n" }
                if let body = item.responseBody { details += "\n--- Response Body ---\n\(body)\n" }

                let detAlert = UIAlertController(title: "Request Details", message: String(details.prefix(2000)), preferredStyle: .alert)
                detAlert.addAction(UIAlertAction(title: "Copy Details", style: .default, handler: { _ in
                    UIPasteboard.general.string = details
                }))
                detAlert.addAction(UIAlertAction(title: "Close", style: .cancel))
                self?.present(detAlert, animated: true)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        } else if selectedIndex == 1 {
            let item = consoleItems[indexPath.row]
            UIPasteboard.general.string = item.message
        } else if selectedIndex == 2 {
            let item = webSocketItems[indexPath.row]
            UIPasteboard.general.string = item.payload
        }
    }
}
