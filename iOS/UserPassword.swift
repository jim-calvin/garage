/*******************************************************

 UserPassword.swift
  part of Garage

  Created by Jim Calvin on 3/30/17.

*******************************************************/

import UIKit
import Foundation

protocol UserPasswordDelegate {
    func UserPasswordComplete(sender: UserPassword, newUserName: String, newPassword: String)
    func UserPasswordCanceled(sender: UserPassword)
}

class UserPassword : UIViewController, UITextFieldDelegate {
    
    var delegate : UserPasswordDelegate?
    var theName : String?
    var thePassword : String?

    @IBOutlet var userNameTxt: UITextField!
    @IBOutlet var passwordTxt: UITextField!
    
// MARK: overridden UIViewController functions

    override func viewDidLoad() {
        userNameTxt.text = theName
        passwordTxt.text = thePassword
        userNameTxt.delegate = self
        passwordTxt.delegate = self
        userNameTxt.becomeFirstResponder()
    }

// MARK: UITextField delegate methods

    func textFieldDidEndEditing(theText: UITextField) {
        theText.resignFirstResponder()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

// MARK openURL utility method iOS10 vs older systems

    func openURL(_ url: URL) {
        if #available(iOS 10.0, *) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            UIApplication.shared.openURL(url)
        }
    }

// MARK: UIButton handlers
    
    @IBAction func okButtonPressed(_ sender: UIButton) {
        theName = userNameTxt.text
        thePassword = passwordTxt.text
        delegate?.UserPasswordComplete(sender: self, newUserName: theName!, newPassword: thePassword!)
    }
    
    @IBAction func cancelButtonPressed(_ sender: UIButton) {
        delegate?.UserPasswordCanceled(sender: self)
    }
    
    @IBAction func visitAdafruit(_ sender: UIButton) {
        openURL(URL(string: "https://learn.adafruit.com/adabox003")!)
    }

    @IBAction func visitGitHub(_ sender: UIButton) {
        openURL(URL(string: "http://www.github.com/jim-calvin/garage")!)
    }

    @IBAction func visitProjectWebPage(_ sender: UIButton) {
        openURL(URL(string: "http://www.swaystairs.com/Garage")!)
    }
}

/* Edit history

[28 Jun 17] Leave alarm vestiges in place - text field is hidden in storyboard
[ 6 Jul 17] Alarm vestiges removed; added buttons & code to link to web pages
[14 Jul 17] Change name of parameters in delegate function

*/
