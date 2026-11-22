// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import WebKit

@MainActor
public final class FloatingDualWebViewController: UIViewController, UITextFieldDelegate, WKNavigationDelegate {
    public enum LayoutMode {
        case floating
        case splitBottom
    }

    private let containerView = UIView()
    private let titleBar = UIView()
    private let urlField = UITextField()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let modeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var webView: WKWebView!

    private var currentLayoutMode: LayoutMode = .floating
    private var panGesture: UIPanGestureRecognizer?
    private var floatingFrame: CGRect = .zero

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupUI()
        setupGestures()
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        if GodModeConfig.shared.state.singleProcessPoolEnabled {
            configuration.processPool = GodModeProcessPool.shared.processPool
        }
        GodMode.configureConfiguration(configuration)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        RetinaLimiter.shared.applyScale(to: webView)
    }

    private func setupUI() {
        view.backgroundColor = .clear

        containerView.backgroundColor = UIColor(white: 0.15, alpha: 0.98)
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        containerView.layer.borderColor = UIColor(white: 0.3, alpha: 1.0).cgColor
        containerView.layer.borderWidth = 1.0

        titleBar.backgroundColor = UIColor(white: 0.1, alpha: 1.0)

        urlField.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        urlField.textColor = .white
        urlField.font = UIFont.systemFont(ofSize: 12)
        urlField.borderStyle = .roundedRect
        urlField.placeholder = "Enter URL..."
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.returnKeyType = .go
        urlField.delegate = self

        backButton.setTitle("◀", for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)

        forwardButton.setTitle("▶", for: .normal)
        forwardButton.tintColor = .white
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .touchUpInside)

        reloadButton.setTitle("🔄", for: .normal)
        reloadButton.tintColor = .white
        reloadButton.addTarget(self, action: #selector(didTapReload), for: .touchUpInside)

        modeButton.setTitle("🔲", for: .normal)
        modeButton.tintColor = .systemCyan
        modeButton.addTarget(self, action: #selector(didTapMode), for: .touchUpInside)

        closeButton.setTitle("✕", for: .normal)
        closeButton.tintColor = .systemRed
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [backButton, forwardButton, reloadButton, urlField, modeButton, closeButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 6
        buttonStack.distribution = .fillProportionally
        buttonStack.alignment = .center

        titleBar.addSubview(buttonStack)
        containerView.addSubview(titleBar)
        containerView.addSubview(webView)
        view.addSubview(containerView)

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: titleBar.topAnchor, constant: 4),
            buttonStack.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 8),
            buttonStack.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -8),
            buttonStack.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: -4),

            backButton.widthAnchor.constraint(equalToConstant: 24),
            forwardButton.widthAnchor.constraint(equalToConstant: 24),
            reloadButton.widthAnchor.constraint(equalToConstant: 24),
            modeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.widthAnchor.constraint(equalToConstant: 24),

            titleBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: 36),

            webView.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        applyLayoutMode(.floating, animated: false)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        titleBar.addGestureRecognizer(pan)
        self.panGesture = pan
    }

    public func load(url: URL) {
        urlField.text = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    public func applyLayoutMode(_ mode: LayoutMode, animated: Bool) {
        currentLayoutMode = mode
        let screen = UIScreen.main.bounds

        let targetFrame: CGRect
        switch mode {
        case .floating:
            let width = min(340.0, screen.width - 32)
            let height = min(280.0, screen.height / 2.5)
            targetFrame = CGRect(x: screen.width - width - 16, y: screen.height - height - 100, width: width, height: height)
            containerView.layer.cornerRadius = 12
        case .splitBottom:
            let height = screen.height / 2.0
            targetFrame = CGRect(x: 0, y: screen.height - height, width: screen.width, height: height)
            containerView.layer.cornerRadius = 0
        }

        if animated {
            UIView.animate(withDuration: 0.3) {
                self.containerView.frame = targetFrame
            }
        } else {
            containerView.frame = targetFrame
        }
        floatingFrame = containerView.frame
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard currentLayoutMode == .floating, let superview = containerView.superview else { return }
        let translation = gesture.translation(in: superview)

        containerView.center = CGPoint(
            x: containerView.center.x + translation.x,
            y: containerView.center.y + translation.y
        )
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended {
            let safe = superview.safeAreaInsets
            let minX = containerView.frame.width / 2 + safe.left
            let maxX = superview.bounds.width - containerView.frame.width / 2 - safe.right
            let minY = containerView.frame.height / 2 + safe.top
            let maxY = superview.bounds.height - containerView.frame.height / 2 - safe.bottom

            let clampedX = min(max(containerView.center.x, minX), maxX)
            let clampedY = min(max(containerView.center.y, minY), maxY)

            UIView.animate(withDuration: 0.2) {
                self.containerView.center = CGPoint(x: clampedX, y: clampedY)
            }
            self.floatingFrame = self.containerView.frame
        }
    }

    @objc private func didTapBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func didTapForward() {
        if webView.canGoForward { webView.goForward() }
    }

    @objc private func didTapReload() {
        webView.reload()
    }

    @objc private func didTapMode() {
        let next: LayoutMode = currentLayoutMode == .floating ? .splitBottom : .floating
        applyLayoutMode(next, animated: true)
    }

    @objc private func didTapClose() {
        webView.stopLoading()
        webView.removeFromSuperview()
        webView = nil
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return true
        }

        let urlString: String
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            urlString = text
        } else if text.contains(".") && !text.contains(" ") {
            urlString = "https://\(text)"
        } else {
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            urlString = "https://www.google.com/search?q=\(encoded)"
        }

        if let url = URL(string: urlString) {
            load(url: url)
        }
        return true
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        urlField.text = webView.url?.absoluteString
    }
}
