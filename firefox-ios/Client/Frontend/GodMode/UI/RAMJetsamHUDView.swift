// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit

@MainActor
public final class RAMJetsamHUDView: UIView {
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        view.layer.cornerRadius = 14
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.clipsToBounds = false
        return view
    }()

    private let statusDot: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGreen
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let metricsLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.text = "RAM: -- MB | Free: -- MB"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detoxButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("⚡", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.tintColor = .systemYellow
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let presetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("🛡️", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.tintColor = .systemCyan
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let pipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📺", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.tintColor = .systemGreen
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let speedButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("⏩", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        button.tintColor = .systemOrange
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    public weak var bvc: BrowserViewController?
    private var panGesture: UIPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupGestures()
        setupNotifications()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(statusDot)
        containerView.addSubview(metricsLabel)
        containerView.addSubview(detoxButton)
        containerView.addSubview(presetButton)
        containerView.addSubview(pipButton)
        containerView.addSubview(speedButton)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusDot.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            statusDot.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            metricsLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 6),
            metricsLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            detoxButton.leadingAnchor.constraint(equalTo: metricsLabel.trailingAnchor, constant: 8),
            detoxButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            detoxButton.widthAnchor.constraint(equalToConstant: 24),
            detoxButton.heightAnchor.constraint(equalToConstant: 24),

            presetButton.leadingAnchor.constraint(equalTo: detoxButton.trailingAnchor, constant: 2),
            presetButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            presetButton.widthAnchor.constraint(equalToConstant: 24),
            presetButton.heightAnchor.constraint(equalToConstant: 24),

            pipButton.leadingAnchor.constraint(equalTo: presetButton.trailingAnchor, constant: 2),
            pipButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            pipButton.widthAnchor.constraint(equalToConstant: 24),
            pipButton.heightAnchor.constraint(equalToConstant: 24),

            speedButton.leadingAnchor.constraint(equalTo: pipButton.trailingAnchor, constant: 2),
            speedButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            speedButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            speedButton.widthAnchor.constraint(equalToConstant: 24),
            speedButton.heightAnchor.constraint(equalToConstant: 24),

            containerView.heightAnchor.constraint(equalToConstant: 28)
        ])

        detoxButton.addTarget(self, action: #selector(didTapDetox), for: .touchUpInside)
        presetButton.addTarget(self, action: #selector(didTapPreset), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(didTapPiP), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(didTapSpeed), for: .touchUpInside)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        self.panGesture = pan

        metricsLabel.isUserInteractionEnabled = true
        let tapMetrics = UITapGestureRecognizer(target: self, action: #selector(didTapMetrics))
        metricsLabel.addGestureRecognizer(tapMetrics)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        presetButton.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began, let bvc = bvc {
            GodMode.presentSettings(from: bvc)
        }
    }

    @objc private func didTapMetrics() {
        guard let bvc = bvc else { return }
        GodMode.presentDevTools(from: bvc)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryUpdate(_:)),
            name: RAMJetsamMonitor.didUpdateMemoryNotification,
            object: nil
        )
    }

    @objc private func handleMemoryUpdate(_ notification: Notification) {
        guard let snapshot = notification.userInfo?["snapshot"] as? MemorySnapshot else { return }

        let ramMB = Int(snapshot.footprintMB)
        let freeMB = Int(snapshot.availableMB)
        metricsLabel.text = "\(ramMB)MB | Free:\(freeMB)MB"

        if snapshot.isCritical {
            statusDot.backgroundColor = .systemRed
        } else if snapshot.isWarning {
            statusDot.backgroundColor = .systemOrange
        } else {
            statusDot.backgroundColor = .systemGreen
        }
    }

    @objc private func didTapDetox() {
        guard let bvc = bvc, let currentTab = bvc.tabManager.selectedTab else { return }

        metricsLabel.text = "Detoxing RAM..."
        ProcessDetoxManager.shared.detoxTab(currentTab, in: bvc)

        UIView.animate(withDuration: 0.2, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.containerView.transform = .identity
            }
        }
    }

    @objc private func didTapPreset() {
        let current = GodModeConfig.shared.state.preset
        let next: GodModePreset
        switch current {
        case .balanced: next = .coexistence
        case .coexistence: next = .ultraSurvival
        case .ultraSurvival: next = .balanced
        case .custom: next = .coexistence
        }

        GodModeConfig.shared.applyPreset(next)
        metricsLabel.text = next.title
    }

    @objc private func didTapPiP() {
        guard let bvc = bvc, let currentTab = bvc.tabManager.selectedTab else { return }
        MediaPlaybackPiPEngine.shared.triggerPiP(in: currentTab.webView) { [weak self] success in
            if success {
                self?.metricsLabel.text = "PiP Active"
            }
        }
    }

    @objc private func didTapSpeed() {
        guard let bvc = bvc, let currentTab = bvc.tabManager.selectedTab else { return }
        let current = JSTimeWarpEngine.shared.currentSpeed
        let next: Double
        if current >= 10.0 {
            next = 0.5
        } else if current >= 5.0 {
            next = 10.0
        } else if current >= 2.0 {
            next = 5.0
        } else if current >= 1.0 {
            next = 2.0
        } else {
            next = 1.0
        }
        JSTimeWarpEngine.shared.setSpeed(next, in: currentTab.webView)
        metricsLabel.text = "\(next)x Speed"
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)

        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)

        if gesture.state == .ended {
            let safeArea = superview.safeAreaInsets
            let minX = frame.width / 2 + safeArea.left + 8
            let maxX = superview.bounds.width - frame.width / 2 - safeArea.right - 8
            let minY = frame.height / 2 + safeArea.top + 8
            let maxY = superview.bounds.height - frame.height / 2 - safeArea.bottom - 8

            let clampedX = min(max(center.x, minX), maxX)
            let clampedY = min(max(center.y, minY), maxY)

            UIView.animate(withDuration: 0.2) {
                self.center = CGPoint(x: clampedX, y: clampedY)
            }

            GodModeConfig.shared.update { state in
                state.hudPositionX = Double(self.frame.origin.x)
                state.hudPositionY = Double(self.frame.origin.y)
            }
        }
    }
}
