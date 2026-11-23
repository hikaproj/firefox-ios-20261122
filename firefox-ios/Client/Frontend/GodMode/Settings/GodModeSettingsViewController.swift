// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit

@MainActor
public final class GodModeSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    weak var bvc: BrowserViewController?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Section: Int, CaseIterable {
        case masterSwitch
        case presets
        case memoryAndProcess
        case renderingAndThermal
        case blockingAndPrivacy
        case networkAndCheats
        case aiAndTools
        case advancedLaunchers
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "GodMode Settings"
        view.backgroundColor = UIColor(white: 0.12, alpha: 1.0)

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(didTapDone))

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func didTapDone() {
        dismiss(animated: true)
    }

    // MARK: - UITableViewDataSource & Delegate

    public func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .masterSwitch: return 2 // Enable, HUD
        case .presets: return 1 // Segmented control
        case .memoryAndProcess: return 5 // Single Pool, Hibernation, Max tabs, Background diet, Auto purge
        case .renderingAndThermal: return 7 // Fonts, Images, CSS anim, GPU CSS, Autoplay, DOM pruning, Retina scale
        case .blockingAndPrivacy: return 5 // Adblock, Userscript, Canvas noise, Referrer cut, Tracking params
        case .networkAndCheats: return 5 // MITM, TimeWarp, Anti-Debug, Anti-Adblock, Smart Dark Mode
        case .aiAndTools: return 3 // Local HTTP Server, Floating D-Pad, AI Provider & Key
        case .advancedLaunchers: return 4 // Open DevTools, Open Filer, Knowledge Search, Macro Manager
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .masterSwitch: return "Master Control"
        case .presets: return "Optimization Preset"
        case .memoryAndProcess: return "RAM & WebContent Process"
        case .renderingAndThermal: return "Extreme Lite Rendering & Thermal"
        case .blockingAndPrivacy: return "Content Blocker & Privacy Shield"
        case .networkAndCheats: return "Network Interception & Runtime Cheats"
        case .aiAndTools: return "Local Services & AI"
        case .advancedLaunchers: return "Power User Tools"
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = UIColor(white: 0.18, alpha: 1.0)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = .lightGray

        let state = GodModeConfig.shared.state
        guard let s = Section(rawValue: indexPath.section) else { return cell }

        switch s {
        case .masterSwitch:
            if indexPath.row == 0 {
                cell.textLabel?.text = "GodMode Engine Active"
                let sw = createSwitch(isOn: state.isEnabled) { val in
                    GodModeConfig.shared.update { $0.isEnabled = val }
                }
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "Live RAM & Jetsam HUD"
                let sw = createSwitch(isOn: state.isHUDVisible) { val in
                    GodModeConfig.shared.update { $0.isHUDVisible = val }
                }
                cell.accessoryView = sw
            }

        case .presets:
            let seg = UISegmentedControl(items: ["Balanced", "Coexist", "Ultra", "Custom"])
            switch state.preset {
            case .balanced: seg.selectedSegmentIndex = 0
            case .coexistence: seg.selectedSegmentIndex = 1
            case .ultraSurvival: seg.selectedSegmentIndex = 2
            case .custom: seg.selectedSegmentIndex = 3
            }
            seg.addTarget(self, action: #selector(presetSegmentChanged(_:)), for: .valueChanged)
            cell.accessoryView = seg

        case .memoryAndProcess:
            let rows: [(String, Bool, (inout GodModeState, Bool) -> Void)] = [
                ("Single WKProcessPool", state.singleProcessPoolEnabled, { $0.singleProcessPoolEnabled = $1 }),
                ("Background Diet (URLCache limit)", state.backgroundDietEnabled, { $0.backgroundDietEnabled = $1 }),
                ("Auto-Purge on Memory Pressure", state.autoPurgeOnMemoryPressure, { $0.autoPurgeOnMemoryPressure = $1 }),
                ("Crash Guard (Self-Repair)", state.isCrashGuardEnabled, { $0.isCrashGuardEnabled = $1 }),
                ("Sideload Container Resilience", state.isSideloadResilienceEnabled, { $0.isSideloadResilienceEnabled = $1 })
            ]
            let item = rows[indexPath.row]
            cell.textLabel?.text = item.0
            cell.accessoryView = createSwitch(isOn: item.1) { val in
                GodModeConfig.shared.update { item.2(&$0, val) }
            }

        case .renderingAndThermal:
            let rows: [(String, Bool, (inout GodModeState, Bool) -> Void)] = [
                ("Block Web Fonts (@font-face)", state.blockWebFonts, { $0.blockWebFonts = $1 }),
                ("Block All Images", state.blockImages, { $0.blockImages = $1 }),
                ("Disable CSS Animations", state.disableCSSAnimations, { $0.disableCSSAnimations = $1 }),
                ("Strip Heavy GPU CSS (Blur/Shadow)", state.stripHeavyGPUCSS, { $0.stripHeavyGPUCSS = $1 }),
                ("Strip Video Autoplay", state.stripAutoplayVideo, { $0.stripAutoplayVideo = $1 }),
                ("Infinite Scroll DOM Pruning", state.domPruningEnabled, { $0.domPruningEnabled = $1 }),
                ("Thermal Throttling (30/15 FPS)", state.thermalThrottlingEnabled, { $0.thermalThrottlingEnabled = $1 })
            ]
            let item = rows[indexPath.row]
            cell.textLabel?.text = item.0
            cell.accessoryView = createSwitch(isOn: item.1) { val in
                GodModeConfig.shared.update { item.2(&$0, val) }
            }

        case .blockingAndPrivacy:
            let rows: [(String, Bool, (inout GodModeState, Bool) -> Void)] = [
                ("Native Ad & Tracker Blocker", state.isAdBlockerEnabled, { $0.isAdBlockerEnabled = $1 }),
                ("Userscript (.user.js) Engine", state.isUserscriptEngineEnabled, { $0.isUserscriptEngineEnabled = $1 }),
                ("Canvas & Audio Noise Injection", state.isCanvasAudioNoiseEnabled, { $0.isCanvasAudioNoiseEnabled = $1 }),
                ("Cross-Origin Referrer Stripping", state.isReferrerStrippingEnabled, { $0.isReferrerStrippingEnabled = $1 }),
                ("Strip Tracking Parameters (utm, fbclid)", state.isTrackingParameterStrippingEnabled, { $0.isTrackingParameterStrippingEnabled = $1 })
            ]
            let item = rows[indexPath.row]
            cell.textLabel?.text = item.0
            cell.accessoryView = createSwitch(isOn: item.1) { val in
                GodModeConfig.shared.update { item.2(&$0, val) }
            }

        case .networkAndCheats:
            let rows: [(String, Bool, (inout GodModeState, Bool) -> Void)] = [
                ("Network MITM Interception", state.isNetworkMITMEnabled, { $0.isNetworkMITMEnabled = $1 }),
                ("Anti-Anti-Debug & Copy Unlock", state.isAntiAntiDebugEnabled, { $0.isAntiAntiDebugEnabled = $1 }),
                ("Anti-Adblock Defusal", state.isAntiAdblockDefusalEnabled, { $0.isAntiAdblockDefusalEnabled = $1 }),
                ("Smart Forced Dark Mode", state.isSmartDarkModeEnabled, { $0.isSmartDarkModeEnabled = $1 }),
                ("Background Media Playback & PiP", state.isBackgroundMediaPlaybackEnabled, { $0.isBackgroundMediaPlaybackEnabled = $1 })
            ]
            let item = rows[indexPath.row]
            cell.textLabel?.text = item.0
            cell.accessoryView = createSwitch(isOn: item.1) { val in
                GodModeConfig.shared.update { item.2(&$0, val) }
            }

        case .aiAndTools:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Local HTTP Server"
                let isRunning = LocalHTTPServerEngine.shared.isRunning
                cell.detailTextLabel?.text = isRunning ? "Port \(LocalHTTPServerEngine.shared.port)" : "Off"
                cell.accessoryView = createSwitch(isOn: isRunning) { val in
                    if val {
                        try? LocalHTTPServerEngine.shared.start()
                    } else {
                        LocalHTTPServerEngine.shared.stop()
                    }
                }
            } else if indexPath.row == 1 {
                cell.textLabel?.text = "Floating Shortcut D-Pad"
                cell.accessoryView = createSwitch(isOn: state.isFloatingDPadVisible) { val in
                    GodModeConfig.shared.update { $0.isFloatingDPadVisible = val }
                }
            } else {
                cell.textLabel?.text = "AI API Settings"
                cell.detailTextLabel?.text = "\(state.aiProvider.capitalized) Key"
                cell.accessoryType = .disclosureIndicator
            }

        case .advancedLaunchers:
            let titles = ["Open DevTools & Sniffer", "Open Local Filer", "Search Offline Knowledge DB", "Manage Macro Scripts"]
            cell.textLabel?.text = titles[indexPath.row]
            cell.accessoryType = .disclosureIndicator
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let s = Section(rawValue: indexPath.section) else { return }

        if s == .aiAndTools && indexPath.row == 2 {
            showAISettingsAlert()
        } else if s == .advancedLaunchers {
            switch indexPath.row {
            case 0:
                dismiss(animated: true) { [weak self] in
                    guard let bvc = self?.bvc else { return }
                    GodMode.presentDevTools(from: bvc)
                }
            case 1:
                let filer = LocalFilerViewController()
                filer.onSelectFileToOpen = { [weak self] url in
                    self?.bvc?.tabManager.selectedTab?.loadRequest(URLRequest(url: url))
                }
                navigationController?.pushViewController(filer, animated: true)
            case 2:
                showKnowledgeSearchAlert()
            case 3:
                showMacroList()
            default:
                break
            }
        }
    }

    private func createSwitch(isOn: Bool, onChange: @escaping (Bool) -> Void) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = isOn
        sw.onTintColor = .systemCyan
        sw.addAction(UIAction { action in
            if let sender = action.sender as? UISwitch {
                onChange(sender.isOn)
            }
        }, for: .valueChanged)
        return sw
    }

    @objc private func presetSegmentChanged(_ sender: UISegmentedControl) {
        let preset: GodModePreset
        switch sender.selectedSegmentIndex {
        case 0: preset = .balanced
        case 1: preset = .coexistence
        case 2: preset = .ultraSurvival
        default: preset = .custom
        }
        GodModeConfig.shared.applyPreset(preset)
        tableView.reloadData()
    }

    private func showAISettingsAlert() {
        let state = GodModeConfig.shared.state
        let alert = UIAlertController(title: "AI API Configuration", message: "Enter API Key for OpenAI or Gemini", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "API Key"
            field.text = state.aiAPIKey
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Save (Gemini)", style: .default, handler: { [weak alert] _ in
            let key = alert?.textFields?.first?.text ?? ""
            GodModeConfig.shared.update {
                $0.aiProvider = "gemini"
                $0.aiAPIKey = key
            }
        }))
        alert.addAction(UIAlertAction(title: "Save (OpenAI)", style: .default, handler: { [weak alert] _ in
            let key = alert?.textFields?.first?.text ?? ""
            GodModeConfig.shared.update {
                $0.aiProvider = "openAI"
                $0.aiAPIKey = key
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showKnowledgeSearchAlert() {
        let alert = UIAlertController(title: "Search Knowledge DB", message: "Offline Full-Text Search across browsed pages", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Search keyword..."
        }
        alert.addAction(UIAlertAction(title: "Search", style: .default, handler: { [weak self, weak alert] _ in
            guard let q = alert?.textFields?.first?.text, !q.isEmpty else { return }
            let results = OfflineKnowledgeDBEngine.shared.search(query: q)
            let resultText = results.map { "• \($0.title)\n  \($0.url)\n  \($0.snippet.replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: ""))" }.joined(separator: "\n\n")

            let resAlert = UIAlertController(title: "Results (\(results.count))", message: resultText.isEmpty ? "No matches found" : String(resultText.prefix(2500)), preferredStyle: .alert)
            resAlert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(resAlert, animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showMacroList() {
        let scripts = MacroEngine.shared.getAllScripts()
        let alert = UIAlertController(title: "Macro Scripts", message: "Select script to run or create sample", preferredStyle: .actionSheet)

        for script in scripts {
            alert.addAction(UIAlertAction(title: "\(script.name) (\(script.steps.count) steps)", style: .default, handler: { [weak self] _ in
                if let wv = self?.bvc?.tabManager.selectedTab?.webView {
                    MacroEngine.shared.execute(script: script, in: wv)
                }
            }))
        }

        alert.addAction(UIAlertAction(title: "+ Create Sample Auto-Scroll Macro", style: .default, handler: { [weak self] _ in
            let sample = MacroScript(
                name: "Auto-Scroll & Wait",
                steps: [
                    MacroStep(type: .scroll, coordinateX: 0, coordinateY: 400),
                    MacroStep(type: .wait, waitSeconds: 1.5),
                    MacroStep(type: .scroll, coordinateX: 0, coordinateY: 400),
                    MacroStep(type: .wait, waitSeconds: 1.5)
                ],
                loopCount: 5
            )
            MacroEngine.shared.saveScript(sample)
            self?.showMacroList()
        }))

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
