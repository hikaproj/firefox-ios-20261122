// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import WebKit

@MainActor
public final class FloatingDPadView: UIView {
    public weak var bvc: BrowserViewController?

    private let mainContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let toggleButton = UIButton(type: .system)
    private let topButton = UIButton(type: .system)
    private let bottomButton = UIButton(type: .system)
    private let detoxButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let closeTabButton = UIButton(type: .system)
    private let devToolsButton = UIButton(type: .system)

    private var isExpanded: Bool = false
    private var panGesture: UIPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear
        layer.zPosition = 9999

        mainContainer.layer.cornerRadius = 24
        mainContainer.layer.masksToBounds = true
        mainContainer.layer.borderColor = UIColor(white: 0.3, alpha: 0.8).cgColor
        mainContainer.layer.borderWidth = 1.0

        toggleButton.setTitle("🕹️", for: .normal)
        toggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
        toggleButton.addTarget(self, action: #selector(didTapToggle), for: .touchUpInside)

        topButton.setTitle("⬆️", for: .normal)
        topButton.addTarget(self, action: #selector(didTapTop), for: .touchUpInside)

        bottomButton.setTitle("⬇️", for: .normal)
        bottomButton.addTarget(self, action: #selector(didTapBottom), for: .touchUpInside)

        detoxButton.setTitle("⚡", for: .normal)
        detoxButton.addTarget(self, action: #selector(didTapDetox), for: .touchUpInside)

        pipButton.setTitle("📺", for: .normal)
        pipButton.addTarget(self, action: #selector(didTapPiP), for: .touchUpInside)

        closeTabButton.setTitle("✕", for: .normal)
        closeTabButton.tintColor = .systemRed
        closeTabButton.addTarget(self, action: #selector(didTapCloseTab), for: .touchUpInside)

        devToolsButton.setTitle("🛠️", for: .normal)
        devToolsButton.addTarget(self, action: #selector(didTapDevTools), for: .touchUpInside)

        addSubview(mainContainer)
        mainContainer.contentView.addSubview(toggleButton)
        mainContainer.contentView.addSubview(topButton)
        mainContainer.contentView.addSubview(bottomButton)
        mainContainer.contentView.addSubview(detoxButton)
        mainContainer.contentView.addSubview(pipButton)
        mainContainer.contentView.addSubview(closeTabButton)
        mainContainer.contentView.addSubview(devToolsButton)

        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        topButton.translatesAutoresizingMaskIntoConstraints = false
        bottomButton.translatesAutoresizingMaskIntoConstraints = false
        detoxButton.translatesAutoresizingMaskIntoConstraints = false
        pipButton.translatesAutoresizingMaskIntoConstraints = false
        closeTabButton.translatesAutoresizingMaskIntoConstraints = false
        devToolsButton.translatesAutoresizingMaskIntoConstraints = false

        updateExpandedState(animated: false)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        self.panGesture = pan
    }

    @objc private func didTapToggle() {
        isExpanded.toggle()
        updateExpandedState(animated: true)
    }

    private func updateExpandedState(animated: Bool) {
        let targetSize: CGSize = isExpanded ? CGSize(width: 140, height: 140) : CGSize(width: 48, height: 48)

        let updates = {
            self.frame = CGRect(origin: self.frame.origin, size: targetSize)
            self.mainContainer.frame = CGRect(origin: .zero, size: targetSize)
            self.mainContainer.layer.cornerRadius = targetSize.width / 2.0

            if self.isExpanded {
                self.toggleButton.frame = CGRect(x: 46, y: 46, width: 48, height: 48)
                self.topButton.frame = CGRect(x: 46, y: 4, width: 48, height: 36)
                self.bottomButton.frame = CGRect(x: 46, y: 100, width: 48, height: 36)
                self.detoxButton.frame = CGRect(x: 4, y: 46, width: 36, height: 48)
                self.pipButton.frame = CGRect(x: 100, y: 46, width: 36, height: 48)
                self.closeTabButton.frame = CGRect(x: 8, y: 8, width: 32, height: 32)
                self.devToolsButton.frame = CGRect(x: 100, y: 8, width: 32, height: 32)

                self.topButton.alpha = 1.0
                self.bottomButton.alpha = 1.0
                self.detoxButton.alpha = 1.0
                self.pipButton.alpha = 1.0
                self.closeTabButton.alpha = 1.0
                self.devToolsButton.alpha = 1.0
            } else {
                self.toggleButton.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
                self.topButton.alpha = 0.0
                self.bottomButton.alpha = 0.0
                self.detoxButton.alpha = 0.0
                self.pipButton.alpha = 0.0
                self.closeTabButton.alpha = 0.0
                self.devToolsButton.alpha = 0.0
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: updates)
        } else {
            updates()
        }
    }

    @objc private func didTapTop() {
        bvc?.tabManager.selectedTab?.webView?.evaluateJavaScript("window.scrollTo({ top: 0, behavior: 'smooth' });")
    }

    @objc private func didTapBottom() {
        bvc?.tabManager.selectedTab?.webView?.evaluateJavaScript("window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' });")
    }

    @objc private func didTapDetox() {
        guard let bvc = bvc, let currentTab = bvc.tabManager.selectedTab else { return }
        ProcessDetoxManager.shared.detox(tab: currentTab, in: bvc)
    }

    @objc private func didTapPiP() {
        guard let currentTab = bvc?.tabManager.selectedTab else { return }
        MediaPlaybackPiPEngine.shared.triggerPiP(in: currentTab.webView)
    }

    @objc private func didTapCloseTab() {
        guard let bvc = bvc, let currentTab = bvc.tabManager.selectedTab else { return }
        bvc.tabManager.closeTab(currentTab)
    }

    @objc private func didTapDevTools() {
        guard let bvc = bvc else { return }
        GodMode.presentDevTools(from: bvc)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended {
            let safeArea = superview.safeAreaInsets
            let minX = frame.width / 2 + safeArea.left + 4
            let maxX = superview.bounds.width - frame.width / 2 - safeArea.right - 4
            let minY = frame.height / 2 + safeArea.top + 4
            let maxY = superview.bounds.height - frame.height / 2 - safeArea.bottom - 4

            let clampedX = min(max(center.x, minX), maxX)
            let clampedY = min(max(center.y, minY), maxY)

            UIView.animate(withDuration: 0.2) {
                self.center = CGPoint(x: clampedX, y: clampedY)
            }
        }
    }
}
