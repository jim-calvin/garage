/*******************************************************
 Modification history
  ViewController.swift
  Example

  Created by CrazyWisdom on 15/12/14.
  Copyright © 2015年 emqtt.io. All rights reserved.

  All that's left from the example is the MQTT framework code. And some of that was modified a bit
  All code relating to the garage door opener was added by Jim Calvin in June of 2017
  Also created a fresh project & workspace no longer based on Example
  Added the "UserPassword.swift" file for configuration etc.
 
********************************************************/

import UIKit
import CocoaMQTT
import MessageUI

let unknownString = "Unknown"

class GarageDoor: UIViewController, UserPasswordDelegate, MFMailComposeViewControllerDelegate {
    var mqtt: CocoaMQTT?
    var userName: String?
    var password: String?
//    var alarmPeriod = 30;

    @IBOutlet var leftState: UILabel!
    @IBOutlet var rightState: UILabel!
    @IBOutlet var connectionStatus: UILabel!
    @IBOutlet var leftOpenCloseButton: UIButton!
    @IBOutlet var rightOpenCloseButton: UIButton!
    @IBOutlet var versionLabel: UILabel!
    @IBOutlet var receiveCount: UILabel!
    @IBOutlet var doorsView: UIView!

    @IBOutlet var logOnOff: UIButton!
    @IBOutlet var debugLog: UITextView!
    
    @IBOutlet var dataAcquisitionTimerLabel: UILabel!
    var dataAcquisitionTimer : Timer?
    var dataAcquisitionCounter = 10

    var logOnOffDownTime = Date()

    var logOnOffState = false

    var connectTimer : Timer? = nil
    var subscribeTimer : Timer? = nil

    var totalReceivedCount = 0;
    var lastConnectTime = Date(timeIntervalSince1970: 0)

    var loggingString = ""
    let myFormatter = DateFormatter()

    let timeBetweenConnectAttempts = 10
    let maxLogFileLength = 15000

    var subscribedCount = 0

    let kLeftReedFeed = "left-reed"
    let kRightReedFeed = "right-reed"

    var leftOpenCloseTime = Date()
    var rightOpenCloseTime = Date()

    let kLeftOpenCloseFeed = "left-open-close"
    let kRightOpenCloseFeed = "right-open-close"
    
// MARK: Utility functions

    func feedName(_ fromFeedName: String) -> String {
        return "\(userName!)/feeds/\(fromFeedName)"
    }

    func myLog(_ logThis: String) {
        myFormatter.dateFormat = "hh:mm:ss"
        let now = myFormatter.string(from: Date())
        loggingString = "\(now) \(logThis)\n\(loggingString)"
        debugLog.text = loggingString
        debugLog.scrollRangeToVisible(NSMakeRange(0, 0))
        debugLog.setNeedsDisplay()
    }

// MARK: overridden UIViewController functions

    override func viewDidLoad() {
        debugLog.backgroundColor = UIColor.lightGray
        
        super.viewDidLoad()
        let vers = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String;
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String;
        versionLabel.text = "\(vers)(\(build))";
        userName = UserDefaults.standard.string(forKey: "UserName")
        password = UserDefaults.standard.string(forKey: "Password")
        loggingString = UserDefaults.standard.string(forKey: "loggingString") ?? ""
        if ((UserDefaults.standard.object(forKey: "logOnOffState")) != nil) {
            logOnOffState = UserDefaults.standard.bool(forKey: "logOnOffState")
            debugLog.isHidden = !logOnOffState;          // set to true to hide & not log to
        }
        if (loggingString.lengthOfBytes(using: .utf8) > maxLogFileLength) {
            let index = loggingString.index(loggingString.startIndex, offsetBy: 1999)
            loggingString = loggingString.substring(to: index)
        }
        debugLog.text = loggingString
        debugLog.setNeedsDisplay()

        myLog("viewDidLoad")               // log here as earlier could get lost

        connectionStatus.text = "Not connected"
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(fromBackground),
                                               name: NSNotification.Name(rawValue: "restartConnection"),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enteringBackground),
                                               name: NSNotification.Name(rawValue: "enteringBackground"),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(enteringForeground),
                                               name: NSNotification.Name(rawValue: "enteringForeground"),
                                               object: nil)
        
        if (userName == nil) || (password == nil) {
            return
        }
        leftOpenCloseButton.isEnabled = false
        rightOpenCloseButton.isEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        myLog("viewDidAppear")
        super.viewDidAppear(animated)
        if ((userName == nil) || (password == nil) || (userName == "") || (password == "")) {
            performSegue(withIdentifier: "getPassword", sender: self)
        } else {
            if mqtt?.connState == .connected {  // already connected?
                return
            }
            myLog("viewDidAppear, connection state: \(String(describing: mqtt?.connState))")
            leftOpenCloseButton.isEnabled = false
            rightOpenCloseButton.isEnabled = false
            tryToReconnect()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let up  = segue.destination as! UserPassword
        up.delegate = self
        up.theName = userName
        up.thePassword = password
    }
    
// MARK: functions to handle messages from AppDelegate
 
    func fromBackground(note : Notification) {
        myLog("fromBackground")
        if (userName == nil) || (password == nil) {
            return
        }
        if (Date(timeIntervalSinceNow: 0) > Date(timeInterval: TimeInterval(timeBetweenConnectAttempts), since: lastConnectTime)) {
            mqtt?.disconnect()      // force disconnect, likely broken pipe by now
            leftOpenCloseButton.isEnabled = false
            rightOpenCloseButton.isEnabled = false
            perform(#selector(connectToServer), with: self, afterDelay: 0.5)
        }
    }

    func enteringBackground(note : Notification) {
        myLog("app is entering background mode")
        UserDefaults.standard.set("\n\(loggingString)", forKey: "loggingString")
        UserDefaults.standard.synchronize()
    }
    
    func enteringForeground(note: Notification) {
        loggingString = UserDefaults.standard.string(forKey: "loggingString") ?? ""
        if (loggingString.lengthOfBytes(using: .utf8) > maxLogFileLength) {
            let index = loggingString.index(loggingString.startIndex, offsetBy: 1999)
            loggingString = loggingString.substring(to: index)
        }
        myLog("app is entering foreground mode")        // do it here or it gets lost
        debugLog.text = loggingString
        debugLog.setNeedsDisplay()
    }

// MARK: functions to handle counting down timer waiting for data to arrive from garage door Huzzah
//       we display a count down timer to let the user know the max time they may have to wait for status

    func startDataAcquisitionTimer() {
        myLog("starting data acquisition timer")
        if (dataAcquisitionTimer != nil) {
            dataAcquisitionTimer?.invalidate()
        }
        dataAcquisitionTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                                    selector: #selector(dataAcqTimerTick), userInfo: nil, repeats: true)
        dataAcquisitionCounter = 10
        dataAcquisitionTimerLabel.text = "\(dataAcquisitionCounter)"
        dataAcquisitionTimerLabel.isHidden = false
    }

    func terminateDataAcqTimer () {
        if dataAcquisitionTimer == nil {
            return
        }
        dataAcquisitionTimer?.invalidate()
        dataAcquisitionTimer = nil
        dataAcquisitionTimerLabel.isHidden = true
    }

    func dataAcqTimerTick(theTimer: Timer) {
        dataAcquisitionCounter = dataAcquisitionCounter - 1
        if (dataAcquisitionCounter < 0) {
            terminateDataAcqTimer()
        }
        dataAcquisitionTimerLabel.text = "\(dataAcquisitionCounter)"
        dataAcquisitionTimerLabel.setNeedsDisplay()
    }

// MARK: functions to deal with connecting to MQTT broker

    func connectToServer() {
        myLog("connectToServer")
        if (connectTimer != nil) {
            connectTimer?.invalidate()
            connectTimer = nil
        }
        mqtt!.connect()
        connectTimer = Timer.scheduledTimer(timeInterval: 60*2, target: self, selector: #selector(connectTimeOut),
                                            userInfo: nil, repeats: false)
    }
    
    func connectTimeOut(theTimer: Timer) {
        myLog("Connection timed out")
        connectTimer = nil
        connectionStatus.text = "Connect timed out"
        mqtt?.disconnect()
    }
    
    func terminateConnectionTimer () {
        connectTimer?.invalidate()
        connectTimer = nil
    }
    
    func tryToReconnect() {
        myLog("tryToReconnect")
        if (Date(timeIntervalSinceNow: 0) > Date(timeInterval: TimeInterval(timeBetweenConnectAttempts), since: lastConnectTime)) {
            myLog("tryToReconnect, actually trying recoonect")
            simpleSSLSetting()
            connectionStatus.text = "Connecting to \(mqtt?.host ?? unknownString):\(mqtt?.port ?? 0)"
            connectToServer()
        }
    }
    
// MARK: handle "Log" button to hide/show/email/reset the log

    @IBAction func logOnOffReleased(_ sender: UIButton) {
        let alert = UIAlertController(title: "Log Options", message: "Please choose an option", preferredStyle: .actionSheet)
        var hideShow = "Hide Log"
        if self.debugLog.isHidden {
            hideShow = "Show Log"
        }
        alert.addAction(UIAlertAction(title: hideShow, style: .default, handler: { (action) in
            self.logOnOffState = !self.logOnOffState
            UserDefaults.standard.set(self.logOnOffState, forKey: "logOnOffState")
            UserDefaults.standard.synchronize()
            self.debugLog.isHidden = !self.logOnOffState
        }))
        alert.addAction(UIAlertAction(title: "EMail Log", style: .default, handler: { (action) in
            self.myLog("starting to send log as EMail")
            let mailComposeViewController = self.configuredMailComposeViewController()
            if MFMailComposeViewController.canSendMail() {
                self.present(mailComposeViewController, animated: true, completion: nil)
            } else {
                self.showSendMailErrorAlert()
            }
        }))
        alert.addAction(UIAlertAction(title: "Clear Log", style: .default, handler: { (action) in
            self.loggingString = ""
            self.debugLog.text = self.loggingString
            self.debugLog.setNeedsDisplay()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
        }))
        if (alert.popoverPresentationController != nil) {
            alert.popoverPresentationController?.sourceView = self.logOnOff
        }
        self.present(alert, animated: true, completion: nil)
    }


    func configuredMailComposeViewController() -> MFMailComposeViewController {
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self // Extremely important to set the --mailComposeDelegate-- property, NOT the --delegate-- property
        
//        mailComposerVC.setToRecipients([""])
        mailComposerVC.setSubject("Garage door log")
        let theName = userName ?? "<No user name set>"
        let bodyStr = "User Name: '\(theName)'\n\n\(loggingString)"
        mailComposerVC.setMessageBody(bodyStr, isHTML: false)
        return mailComposerVC
    }
    
    func showSendMailErrorAlert() {
        let sendMailErrorAlert = UIAlertView(title: "Could Not Send Email", message: "Your device could not send e-mail.  Please check e-mail configuration and try again.", delegate: self, cancelButtonTitle: "OK")
        sendMailErrorAlert.show()
    }
    
// MARK: MFMailComposeViewControllerDelegate Method

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
        var emailResult = "Log sent as EMail"
        if (result == MFMailComposeResult.failed) {
            emailResult = "Failed to send Log as EMail"
        } else if (result == MFMailComposeResult.cancelled) {
            emailResult = "Sending Log as EMail cancelled"
        }
        myLog(emailResult)
    }

// MARK: other UIButton handlers

    @IBAction func configureButton(_ sender: UIButton) {
        performSegue(withIdentifier: "getPassword", sender: self)
    }
    
    func configureOpenCloseButton(theButton: UIButton, theStatus: String) {
        var buttonLabel = "--"
        if theStatus == "Open" {
            buttonLabel = "Close door"
        } else if theStatus == "Closed" {
            buttonLabel = "Open door"
        }
        theButton.setTitle(buttonLabel, for: UIControlState.normal)
    }

    @IBAction func leftOpenClosedPressed(_ sender: UIButton) {
        let left = feedName(kLeftOpenCloseFeed)
        mqtt?.publish(left, withString: "1")
        leftOpenCloseTime = Date()
    }

    @IBAction func leftOpenClosedReleased(_ sender: UIButton) {
        let howLong = leftOpenCloseTime.timeIntervalSinceNow
        if (howLong < -2) {
            return;
        }
        let left = feedName(kLeftOpenCloseFeed)
        mqtt?.publish(left, withString: "0")
    }

    @IBAction func rightOpenClosePressed(_ sender: UIButton) {
        let right = feedName(kRightOpenCloseFeed)
        mqtt?.publish(right, withString: "1")
        rightOpenCloseTime = Date()
    }

    @IBAction func rightOpenCloseReleased(_ sender: UIButton) {
        let howLong = rightOpenCloseTime.timeIntervalSinceNow
        if (howLong < -2) {
            return;
        }
        let right = feedName(kRightOpenCloseFeed)
        mqtt?.publish(right, withString: "0")
    }

// MARK: delegate methods for configuration controller

    func UserPasswordComplete(sender: UserPassword, newUserName: String, newPassword: String) {
        myLog("UserPasswordComplete")
        if (newUserName != "") {
            if (userName != newUserName) {
                userName = newUserName
                UserDefaults.standard.set(userName, forKey: "UserName")
            }
        } else {
            userName = newUserName;
            UserDefaults.standard.removeObject(forKey: "UserName")
        }
        if (newPassword != "") {
            if (password != newPassword) {
                password = newPassword
                UserDefaults.standard.set(password, forKey: "Password")
            }
        } else {
            password = newPassword;
            UserDefaults.standard.removeObject(forKey: "Password")
        }
        
        weak var weakSelf = self
        dismiss(animated: true, completion: {
            if (self.userName == nil) || (self.password == nil) {
                weakSelf?.performSegue(withIdentifier: "getPassword", sender: weakSelf)
            } else if (weakSelf?.mqtt?.connState != CocoaMQTTConnState.connected) {
                weakSelf?.simpleSSLSetting()
                weakSelf?.connectionStatus.text = "Connecting to \(weakSelf?.mqtt?.host ?? unknownString):\(weakSelf?.mqtt?.port ?? 0)"
                weakSelf?.connectToServer()
            }
        })
    }
    
    func UserPasswordCanceled(sender: UserPassword) {
        dismiss(animated: true, completion: nil)
    }

    
// MARK: Setup MQTT connect parameters depending upon connection type
    func mqttSetting() {
        myLog("mqttSetting")
        let clientID = "CocoaMQTT-GarageDoor-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "io.adafruit.com", port: 1883)
        mqtt!.username = userName
        mqtt!.password = password
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 120
        mqtt!.delegate = self
    }
    
    func simpleSSLSetting() {
        myLog("simpleSSLSetting")
        let clientID = "CocoaMQTT-GarageDoor-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "io.adafruit.com", port: 8883)
        mqtt!.username = userName
        mqtt!.password = password
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 120
        mqtt!.delegate = self
        mqtt!.enableSSL = true
    }
    
    func selfSignedSSLSetting() {
        myLog("selfSignedSSLSetting")
        let clientID = "CocoaMQTT-GarageDoor-" + String(ProcessInfo().processIdentifier)
        mqtt = CocoaMQTT(clientID: clientID, host: "io.adafruit.com", port: 8883)
        mqtt!.username = userName
        mqtt!.password = password
        mqtt!.willMessage = CocoaMQTTWill(topic: "/will", message: "dieout")
        mqtt!.keepAlive = 120
        mqtt!.delegate = self
        mqtt!.enableSSL = true
        
        let clientCertArray = getClientCertFromP12File(certName: "client-keycert", certPassword: "MySecretPassword")
        
        var sslSettings: [String: NSObject] = [:]
        sslSettings[kCFStreamSSLCertificates as String] = clientCertArray
        
        mqtt!.sslSettings = sslSettings
    }
    
    func getClientCertFromP12File(certName: String, certPassword: String) -> CFArray? {
        // get p12 file path
        let resourcePath = Bundle.main.path(forResource: certName, ofType: "p12")
        
        guard let filePath = resourcePath, let p12Data = NSData(contentsOfFile: filePath) else {
            myLog("Failed to open the certificate file: \(certName).p12")
            return nil
        }
        
        // create key dictionary for reading p12 file
        let key = kSecImportExportPassphrase as String
        let options : NSDictionary = [key: certPassword]
        
        var items : CFArray?
        let securityError = SecPKCS12Import(p12Data, options, &items)
        
        guard securityError == errSecSuccess else {
            if securityError == errSecAuthFailed {
                myLog("ERROR: SecPKCS12Import returned errSecAuthFailed. Incorrect password?")
            } else {
                myLog("Failed to open the certificate file: \(certName).p12")
            }
            return nil
        }
        
        guard let theArray = items, CFArrayGetCount(theArray) > 0 else {
            return nil
        }
        
        let dictionary = (theArray as NSArray).object(at: 0)
        guard let identity = (dictionary as AnyObject).value(forKey: kSecImportItemIdentity as String) else {
            return nil
        }
        let certArray = [identity] as CFArray
        
        return certArray
    }

}

// MARK: MQTT delegate methods

extension GarageDoor: CocoaMQTTDelegate {

    func mqtt(_ mqtt: CocoaMQTT, didConnect host: String, port: Int) {
        myLog("didConnect: \(host)，port: \(port)")
        terminateConnectionTimer()
        connectionStatus.text = "\(host):\(port)"
        lastConnectTime = Date(timeIntervalSinceNow: 0)
    }
    
    // Optional ssl CocoaMQTTDelegate
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        myLog("mqtt didReceive")
        completionHandler(true)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        myLog("didConnectAck: \(ack)，rawValue: \(ack.rawValue)")
        subscribedCount = 0
        let left = feedName(kLeftReedFeed)
        let right = feedName(kRightReedFeed)
        if ack == .accept {
            if (subscribeTimer != nil) {
                subscribeTimer?.invalidate()
                subscribeTimer = nil
            }
            connectionStatus.text = "Subscribing"
            mqtt.subscribe(left, qos: CocoaMQTTQOS.qos1)
            mqtt.subscribe(right, qos: CocoaMQTTQOS.qos1)

            subscribeTimer = Timer.init(timeInterval: 60, target: self, selector: #selector(subscribeTimeOut),
                                        userInfo: nil, repeats: false)
            leftOpenCloseButton.isEnabled = true
            rightOpenCloseButton.isEnabled = true

        } else if ack == .notAuthorized || ack == .badUsernameOrPassword {
            connectionStatus.text = "Authorization failed"
        }
    }
    
    func subscribeTimeOut(theTimer: Timer) {
        myLog("subscribeTimeOut")
        subscribeTimer = nil
        connectionStatus.text = "Subscribe timed out"
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        myLog("didPublishMessage(\(id)) (\(message.topic)) with message: \(String(describing: message.string!))")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        myLog("didPublishAck with id: \(id)")
    }
    
    func updateState(whichState: UILabel, theMessage: String) {
        whichState.text = theMessage
        if (theMessage == "Closed") {
            whichState.textColor = UIColor.init(red: 0.0, green: 165.0/255.0, blue: 30.0/255.0, alpha: 1.0)
        } else if (theMessage == unknownString) {
            whichState.textColor = UIColor.white
        } else {
            whichState.textColor = UIColor.red
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16 ) {
        totalReceivedCount = totalReceivedCount + 1;
        receiveCount.text = "\(totalReceivedCount)"
        myLog("didReceivedMessage: \(String(describing: message.string!)), topic: \(String(describing: message.topic)) with id \(id)")
        if (message.topic.contains("left-reed")) {
            updateState(whichState: leftState, theMessage: message.string!)
            configureOpenCloseButton(theButton: leftOpenCloseButton, theStatus: message.string!)
        } else if message.topic.contains("right-reed") {
            updateState(whichState: rightState, theMessage: message.string!)
            configureOpenCloseButton(theButton: rightOpenCloseButton, theStatus: message.string!)
        }
        if ((leftState.text == "Closed") && (rightState.text == "Closed")) {
            doorsView.backgroundColor = view.backgroundColor
        }
        terminateDataAcqTimer()
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopic topic: String) {
        myLog("didSubscribeTopic to \(topic)")
        subscribeTimer?.invalidate()
        subscribeTimer = nil
        if (subscribedCount > 0) {
            connectionStatus.text = "\(mqtt.host):\(mqtt.port)"
        } else {
            connectionStatus.text = "\(topic) subscribed"
            startDataAcquisitionTimer()
        }
        subscribedCount = subscribedCount + 1;
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopic topic: String) {
        myLog("didUnsubscribeTopic to \(topic)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        myLog("didPing")
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        myLog("didReceivePong")
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        myLog("mqttDidDisconnect: \(String(describing: err))")
        updateState(whichState: leftState, theMessage: unknownString)
        updateState(whichState: rightState, theMessage: unknownString)
        connectionStatus.text = "Disconnected"
        perform(#selector(tryToReconnect), with: self, afterDelay: Double(timeBetweenConnectAttempts)/2.0)
    }
    
}

/* Edit History started 1 June 2017 by Jim Calvin

[ 1 Jun 17] Try to reconnect (once) when we receive a mqttDidDisconnect;
            moved connect code to a seperate function
[ 2 Jun 17] Put a time out so we don't constantly try to reconnect to the server
            Replaced "print" with "myLog" & added a view for that
[ 8 Jun 17] Tweaks to reconnect/squawk logic
[15 Jun 17] New version without squawk logic; no alarm timer
[17 Jun 17] Changes to not send relay OFF msg if button is held for a while
[18 Jun 17] Rearranged some code for better organization
[28 Jun 17] Comment out the alarm code
[ 6 Jul 17] Removed all of the alarm code; added comments
[14 Jul 17] Check for empty (as opposed to nil) userName & password in viewDidAppear
              also better checks for this in UserPassword delegate method

*/

