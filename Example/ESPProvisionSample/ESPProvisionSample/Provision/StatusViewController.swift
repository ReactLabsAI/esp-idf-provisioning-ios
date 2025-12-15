// Copyright 2020 Espressif Systems
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//  StatusViewController.swift
//  ESPProvisionSample
//

import ESPProvision
import Foundation
import UIKit

// Class that applies Wi-Fi credentials to device and show provisioning status.
class StatusViewController: UIViewController {
    var ssid: String!
    var passphrase: String!
    var threadOpetationalDataset: Data!
    var step1Failed = false
    var espDevice: ESPDevice!
    var message = ""

    @IBOutlet var step1Image: UIImageView!
    @IBOutlet var step2Image: UIImageView!
    @IBOutlet weak var sendingCredsLabel: UILabel!
    @IBOutlet weak var confirmNetworkConnectionLabel: UILabel!
    @IBOutlet var step1Indicator: UIActivityIndicatorView!
    @IBOutlet var step2Indicator: UIActivityIndicatorView!
    @IBOutlet var step1ErrorLabel: UILabel!
    @IBOutlet var step2ErrorLabel: UILabel!
    @IBOutlet var finalStatusLabel: UILabel!
    @IBOutlet var okayButton: UIButton!
    
    var errorMessage: String?

    // MARK: - Overriden Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let _ = threadOpetationalDataset {
            self.sendingCredsLabel.text = "Sending Thread credentials."
            self.confirmNetworkConnectionLabel.text = "Confirming Thread connection."
        }
        if step1Failed {
            step1FailedWithMessage(message: message)
        } else {
            startProvisioning()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = true
    }

    // MARK: - IBActions
    
    @IBAction func goToFirstView(_: Any) {
        navigationController?.popToRootViewController(animated: true)
    }
    
    // MARK: - Provisioning
    
    func startProvisioning() {
        step1Image.isHidden = true
        step1Indicator.isHidden = false
        step1Indicator.startAnimating()

        espDevice.provision(ssid: self.ssid, passPhrase: self.passphrase, threadOperationalDataset: self.threadOpetationalDataset) { status in
            DispatchQueue.main.async {
                switch status {
                case .success:
                    self.step2Indicator.stopAnimating()
                    self.step2Image.image = UIImage(named: "checkbox_checked")
                    self.step2Image.isHidden = false
                    self.provisionFinsihedWithStatus(message: "Device has been successfully provisioned!")
                case let .failure(error):
                    // Send WiFi reset command on any provisioning failure
                    switch error {
                    case .configurationError:
                        self.step1FailedWithMessage(message: "Failed to apply network configuration to device", shouldDisconnectDevice: false)
                    case .sessionError:
                        self.step1FailedWithMessage(message: "Session is not established", shouldDisconnectDevice: false)
                    case .wifiStatusDisconnected:
                        self.step2FailedWithMessage(error: error, shouldDisconnectDevice: false)
                    default:
                        self.step2FailedWithMessage(error: error, shouldDisconnectDevice: false)
                    }
                    self.errorMessage = error.description
                    self.sendWifiResetCommand()
                case .configApplied:
                    self.step2applyConfigurations()
                }
            }
        }
    }

    func step2applyConfigurations() {
        DispatchQueue.main.async {
            self.step1Indicator.stopAnimating()
            self.step1Image.image = UIImage(named: "checkbox_checked")
            self.step1Image.isHidden = false
            self.step2Image.isHidden = true
            self.step2Indicator.isHidden = false
            self.step2Indicator.startAnimating()
        }
    }

    func step1FailedWithMessage(message: String, shouldDisconnectDevice: Bool = true) {
        DispatchQueue.main.async {
            self.step1Indicator.stopAnimating()
            self.step1Image.image = UIImage(named: "error_icon")
            self.step1Image.isHidden = false
            self.step1ErrorLabel.text = message
            self.step1ErrorLabel.isHidden = false
            self.provisionFinsihedWithStatus(message: "Reboot your board and try again.")
        }
    }

    func step2FailedWithMessage(error: ESPProvisionError, shouldDisconnectDevice: Bool = true) {
        DispatchQueue.main.async {
            self.step2Indicator.stopAnimating()
            self.step2Image.image = UIImage(named: "error_icon")
            self.step2Image.isHidden = false
            var errorMessage = ""
            switch error {
            case .wifiStatusUnknownError, .wifiStatusDisconnected, .wifiStatusNetworkNotFound, .wifiStatusAuthenticationError:
                errorMessage = error.description
            case .wifiStatusError:
                errorMessage = "Unable to fetch Wi-Fi state."
            default:
                errorMessage = "Unknown error."
            }
            self.step2ErrorLabel.text = errorMessage
            self.step2ErrorLabel.isHidden = false
            self.provisionFinsihedWithStatus(message: "Reset your board to factory defaults and retry.", shouldDisconnectDevice: shouldDisconnectDevice)
        }
    }

    func provisionFinsihedWithStatus(message: String, shouldDisconnectDevice: Bool = true) {
        if shouldDisconnectDevice {
            self.espDevice.disconnect()
        }
        okayButton.isEnabled = true
        okayButton.alpha = 1.0
        finalStatusLabel.text = message
        finalStatusLabel.isHidden = false
    }
    
    // MARK: - WiFi Reset
    
    /// Send WiFi reset command to device when provisioning fails
    /// Checks connection status and reconnects if needed before sending reset
    private func sendWifiResetCommand() {
        // Check if device is still connected
        if !espDevice.isSessionEstablished() {
            // Device disconnected - reconnect first
            espDevice.connect { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .connected:
                    // Reconnected successfully - now send reset command
                    self.sendResetCommandAfterConnection()
                default:
                    break
                }
            }
        } else {
            // Device is still connected - send reset command directly
            sendResetCommandAfterConnection()
        }
    }
    
    /// Send WiFi reset command (assumes device is connected)
    private func sendResetCommandAfterConnection() {
        self.espDevice.resetWifiStatus { [weak self] success, error in
            guard let self = self else {
                return
            }
            if success {
                self.showReenterPasswordAlert()
            } else {
                if let error = error {
                    // Log error but don't block UI - reset is best effort
                    self.showResetPasswordFailedAlert("Failed to send WiFi reset command: \(error.localizedDescription)")
                } else {
                    // Reset command sent but status is not success
                    self.showResetPasswordFailedAlert("Failed to send WiFi reset command.")
                }
            }
        }
    }
    
    /// Show alert dialog to re-enter WiFi password
    private func showReenterPasswordAlert() {
        DispatchQueue.main.async {
            let title = "Provisioning"
            var message = "WiFi has been reset. Please reselect the WiFi credentials."
            if let msg = self.errorMessage, msg.count > 0 {
                message = "\(msg). WiFi has been reset. Please re-enter the WiFi credentials."
            }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            // OK button
            let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.navigationController?.popViewController(animated: true)
                }
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
            alert.addAction(cancelAction)
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    /// Show alert dialog to re-enter WiFi password
    private func showResetPasswordFailedAlert(_ message: String) {
        DispatchQueue.main.async {
            let title = "Provisioning"
            let message = message
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            // OK button
            let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.navigationController?.popViewController(animated: true)
                }
            }
            
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    /// Reset UI state before retrying provisioning
    private func resetUIForRetry() {
        // Hide error messages
        step1ErrorLabel.isHidden = true
        step2ErrorLabel.isHidden = true
        finalStatusLabel.isHidden = true
        
        // Hide images
        step1Image.isHidden = true
        step2Image.isHidden = true
        
        // Stop any running indicators
        step1Indicator.stopAnimating()
        step2Indicator.stopAnimating()
        step1Indicator.isHidden = true
        step2Indicator.isHidden = true
        
        // Disable okay button
        okayButton.isEnabled = false
        okayButton.alpha = 0.5
    }
}

