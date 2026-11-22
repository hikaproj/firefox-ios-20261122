// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import QuickLook

@MainActor
public final class LocalFilerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource {
    public var onSelectFileToOpen: ((URL) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var currentDirectoryURL: URL
    private var items: [URL] = []
    private var previewURL: URL?

    public init(directoryURL: URL? = nil) {
        self.currentDirectoryURL = directoryURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDirectoryContents()
    }

    private func setupUI() {
        title = currentDirectoryURL.lastPathComponent
        view.backgroundColor = UIColor(white: 0.12, alpha: 1.0)

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(didTapAdd)),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(didTapDone))
        ]

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FileCell")

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func loadDirectoryContents() {
        let contents = (try? FileManager.default.contentsOfDirectory(at: currentDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [])) ?? []
        items = contents.sorted { (u1, u2) -> Bool in
            let isDir1 = (try? u1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let isDir2 = (try? u2.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir1 != isDir2 { return isDir1 }
            return u1.lastPathComponent.lowercased() < u2.lastPathComponent.lowercased()
        }
        tableView.reloadData()
    }

    @objc private func didTapDone() {
        dismiss(animated: true)
    }

    @objc private func didTapAdd() {
        let alert = UIAlertController(title: "New File", message: "Enter file name", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "index.html"
            field.text = "test.html"
        }
        alert.addAction(UIAlertAction(title: "Create", style: .default, handler: { [weak self, weak alert] _ in
            guard let self = self, let name = alert?.textFields?.first?.text, !name.isEmpty else { return }
            let fileURL = self.currentDirectoryURL.appendingPathComponent(name)
            let template = "<!DOCTYPE html>\n<html>\n<head><title>\(name)</title></head>\n<body>\n<h1>Hello from GodMode Filer</h1>\n</body>\n</html>"
            try? template.write(to: fileURL, atomically: true, encoding: .utf8)
            self.loadDirectoryContents()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource & Delegate

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath)
        cell.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        cell.textLabel?.textColor = .white

        let url = items[indexPath.row]
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let icon = isDir ? "📁 " : "📄 "
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeStr = isDir ? "" : " (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"

        cell.textLabel?.text = "\(icon)\(url.lastPathComponent)\(sizeStr)"
        cell.accessoryType = isDir ? .disclosureIndicator : .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = items[indexPath.row]
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if isDir {
            let subFiler = LocalFilerViewController(directoryURL: url)
            subFiler.onSelectFileToOpen = self.onSelectFileToOpen
            navigationController?.pushViewController(subFiler, animated: true)
        } else {
            showFileOptions(for: url)
        }
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let url = items[indexPath.row]
            try? FileManager.default.removeItem(at: url)
            items.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }

    private func showFileOptions(for url: URL) {
        let alert = UIAlertController(title: url.lastPathComponent, message: "Choose an action", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Open in Tab", style: .default, handler: { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onSelectFileToOpen?(url)
            }
        }))

        alert.addAction(UIAlertAction(title: "Edit as Text", style: .default, handler: { [weak self] _ in
            self?.openEditor(for: url)
        }))

        alert.addAction(UIAlertAction(title: "Quick Look Preview", style: .default, handler: { [weak self] _ in
            self?.previewURL = url
            let ql = QLPreviewController()
            ql.dataSource = self
            self?.present(ql, animated: true)
        }))

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func openEditor(for url: URL) {
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let editorVC = UIViewController()
        editorVC.title = url.lastPathComponent
        editorVC.view.backgroundColor = UIColor(white: 0.1, alpha: 1.0)

        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.text = content
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no

        editorVC.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: nil, action: nil)
        editorVC.navigationItem.rightBarButtonItem?.primaryAction = UIAction { [weak editorVC, weak self] _ in
            try? tv.text.write(to: url, atomically: true, encoding: .utf8)
            self?.loadDirectoryContents()
            editorVC?.dismiss(animated: true)
        }

        editorVC.view.addSubview(tv)
        tv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: editorVC.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tv.leadingAnchor.constraint(equalTo: editorVC.view.leadingAnchor, constant: 8),
            tv.trailingAnchor.constraint(equalTo: editorVC.view.trailingAnchor, constant: -8),
            tv.bottomAnchor.constraint(equalTo: editorVC.view.bottomAnchor, constant: -8)
        ])

        let nav = UINavigationController(rootViewController: editorVC)
        present(nav, animated: true)
    }

    // MARK: - QLPreviewControllerDataSource

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return previewURL != nil ? 1 : 0
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return previewURL! as NSURL
    }
}
