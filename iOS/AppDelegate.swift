/***************************************************************************
    minimal appDelegate used to deal with entering/leaving background mode
 
    /jc, June 2017
 
****************************************************************************/
 
import UIKit

@UIApplicationMain

class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?                       // so we can use a storyboard

    var backgroundTOD = Date()                  // time we moved to background mode

    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundTOD = Date()
        NotificationCenter.default.post(Notification.init(name: Notification.Name(rawValue: "enteringBackground")))
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        let now = Date()
        let aaa = backgroundTOD.addingTimeInterval(30.0)
        if aaa <= now {
            NotificationCenter.default.post(Notification.init(name: Notification.Name(rawValue: "restartConnection")))
        }
        NotificationCenter.default.post(Notification.init(name: Notification.Name(rawValue: "enteringForeground")))
    }
}

/* Edit history
 
[   Jun 17] added code to notify main code on returning from background (used to force reconnection to MQTT broker)

*/
