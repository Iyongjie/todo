//
//  AppDelegate.swift
//  Todo
//
//  Created by Pasin Suriyentrakorn on 2/8/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

import UIKit
import UserNotifications
import CouchbaseLiteSwift
import Fabric
import Crashlytics
import Alamofire
  
// Configuration:
let kLoggingEnabled = true
let kLoginFlowEnabled = true
let kSyncEnabled = true
let kSyncEndpoint = "ws://152.136.37.146:4984/test"
let kSyncWithPushNotification = false

// Database Encryption:
// Note: changing this value requires to delete the app before rerun:
let kDatabaseEncryptionKey: String? = nil

// QE:
let kQEFeaturesEnabled = true

// Crashlytics:
let kCrashlyticsEnabled = true

// Constants:
let kActivities = ["Stopped", "Offline", "Connecting", "Idle", "Busy"]

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, LoginViewControllerDelegate {
    var window: UIWindow?
    
    var database: Database!
    var replicator: Replicator!
    var changeListener: ListenerToken?
    
    var localSessionId: String?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions
        launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        
        initCrashlytics()
          
        if kLoggingEnabled {
            Database.log.console.level = .verbose
        }
         
        localSessionId = UserDefaults.standard.string(forKey: "sessionId")
        
        checkLocalSessionId(sessionId: localSessionId)
        self.showApp()

            //        }
        return true
    }
    
    // MARK: - Session
    
    
    func beginSession() {
        do {
            try startSession(username: "user1", withPassword: "pass")
        } catch let error as NSError {
            print(error)
        }
    }
    func startSession(username:String, withPassword password:String) throws {
        try openDatabase(username: username)
        Session.username = username
        Session.password = password
        startReplication(withUsername: username, andPassword: password)
//        DispatchQueue.main.async {
//        }
        registerRemoteNotification()
    }
    
    func openDatabase(username:String) throws {
        let config = DatabaseConfiguration()
        if let password = kDatabaseEncryptionKey {
//            config.encryptionKey = EncryptionKey.password(password)
        }
        database = try Database(name: username, config: config)
        createDatabaseIndex()
    }

    func closeDatabase() throws {
        try database.close()
    }
    
    func createDatabaseIndex() {
        // For task list query:
        let type = ValueIndexItem.expression(Expression.property("type"))
        let name = ValueIndexItem.expression(Expression.property("name"))
        let taskListId = ValueIndexItem.expression(Expression.property("taskList.id"))
        let task = ValueIndexItem.expression(Expression.property("task"))
        
        do {
            let index = IndexBuilder.valueIndex(items: type, name)
            try database.createIndex(index, withName: "task-list")
        } catch let error as NSError {
            NSLog("Couldn't create index (type, name): %@", error);
        }
        
        // For tasks query:
        do {
            let index = IndexBuilder.valueIndex(items: type, taskListId, task)
            try database.createIndex(index, withName: "tasks")
        } catch let error as NSError {
            NSLog("Couldn't create index (type, taskList.id, task): %@", error);
        }
    }
    
    // MARK: - Login
    
    func login(username: String? = nil) {
        let storyboard =  window!.rootViewController!.storyboard
        let navigation = storyboard!.instantiateViewController(
            withIdentifier: "LoginNavigationController") as! UINavigationController
        let loginController = navigation.topViewController as! LoginViewController
        loginController.delegate = self
        loginController.username = username
        window!.rootViewController = navigation
    }
    
    func logout() {
        stopReplication()
        do {
            try closeDatabase()
        } catch let error as NSError {
            NSLog("Cannot close database: %@", error)
        }
        let oldUsername = Session.username
        Session.username = nil
        Session.password = nil
        login(username: oldUsername)
    }
    
    func showApp() {
        guard let root = self.window?.rootViewController, let storyboard = root.storyboard else {
            return
        }
        
        let controller = storyboard.instantiateInitialViewController()
        self.window!.rootViewController = controller
    }
    
    // MARK: - LoginViewControllerDelegate
    
    func login(controller: UIViewController, withUsername username: String,
               andPassword password: String) {
        processLogin(controller: controller, withUsername: username, withPassword: password)
    }
    
    func processLogin(controller: UIViewController, withUsername username: String,
                      withPassword password: String) {
        do {
            try startSession(username: username, withPassword: password)
        } catch let error as NSError {
            Ui.showMessage(on: controller,
                           title: "Error",
                           message: "Login has an error occurred, code = \(error.code).")
            NSLog("Cannot start a session: %@", error)
        }
    }
    
    func getSessionId() {
        requestSessionId()
    }
    func requestSessionId() {
        
        let header:HTTPHeaders = ["Accept": "application/json", "Content-Type": "application/json"]
        guard let url =  URL(string: "http://152.136.37.146:4985/test/_session") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.headers = header
        do {
            let jsonData =  try JSONSerialization.data(withJSONObject: ["name": "user1", "password": "pass"], options: JSONSerialization.WritingOptions.prettyPrinted)
            request.httpBody = jsonData

        } catch let error as NSError  {
            print(error)
        }
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let resultData = data else {
                return
            }
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: resultData, options: .mutableLeaves) as! [String: Any]
                let session_id = jsonObject["session_id"]
                if session_id != nil {
                    UserDefaults.standard.setValue(session_id, forKey: "sessionId")
                    self.localSessionId = session_id as? String
                    self.beginSession()
                } else {
                    UserDefaults.standard.setValue(nil, forKey: "sessionId")
                    self.localSessionId = nil
                }
            } catch {
                print("解析错误！")
            }
        }.resume()
         
    }
    func checkLocalSessionId(sessionId: String?) {
        self.checkSessionId(sessionId: sessionId)
    }
    func checkSessionId(sessionId: String?) {
        
        let header:HTTPHeaders = ["Accept": "application/json"]
        
        guard let url =  URL(string: "http://152.136.37.146:4985/test/_session/\(sessionId ?? "")") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.headers = header
         print("请求\(url)")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let resultData = data else {
                return
            }

            do {
                let jsonObject = try JSONSerialization.jsonObject(with: resultData, options: .mutableLeaves) as! [String: Any]
                let userJson = jsonObject["userCtx"] as! [String: Any]
                let result = userJson["name"]
                if result is NSNull {
                    self.requestSessionId()
                } else {
                    print("sessionid没变")
                    self.beginSession()
                }
            } catch {
                print("解析错误！")
            }
            
        }.resume()
    }

    // MARK: - Replication
    
    func startReplication(withUsername username:String, andPassword password:String? = "") {
        guard kSyncEnabled else {
            return
        }
     
        let target = URLEndpoint(url: URL(string: kSyncEndpoint)!)
        let config = ReplicatorConfiguration(database: database, target: target)
        config.authenticator = SessionAuthenticator(sessionID: localSessionId!)
        config.continuous = true
//        config.documentIDs = ["user1.7A1CF699-4756-44BD-B4D2-7198610BE568"]
        config.replicatorType = .pushAndPull
//        config.pullFilter = { (document, flags) in
//            print("flag = \(flags)")
//            if (flags.contains(.deleted) || flags.contains(.accessRemoved)) {
//                return false
//            }
//
//            return true
//        }
//        config.allowReplicatingInBackground = true
        
        replicator = Replicator(config: config)
        
//        let queue = DispatchQueue(label: "listen",qos: .utility, attributes:.concurrent)
//        changeListener = replicator.addChangeListener(withQueue: queue, { (change) in
//            let s = change.status
//            let activity = kActivities[Int(s.activity.rawValue)]
//            let e = change.status.error as NSError?
//            let error = e != nil ? ", error: \(e!.description)" : ""
//            NSLog("同步进度: \(activity), \(s.progress.completed)/\(s.progress.total)\(error)")
//            DispatchQueue.main.async {
//                UIApplication.shared.isNetworkActivityIndicatorVisible = (s.activity == .busy)
//            }
//
//            if let code = e?.code {
//                if code == 401 {
//                    Ui.showMessage(on: self.window!.rootViewController!,
//                                   title: "Authentication Error",
//                                   message: "Your username or password is not correct",
//                                   error: nil,
//                                   onClose: {
//                                    self.logout()
//                    })
//                }
//            }
//        })
        
        changeListener = replicator.addChangeListener({ (change) in
            let s = change.status
            let activity = kActivities[Int(s.activity.rawValue)]
            let e = change.status.error as NSError?
            let error = e != nil ? ", error: \(e!.description)" : ""
            NSLog("同步进度: \(activity), \(s.progress.completed)/\(s.progress.total)\(error)")
            if s.activity == .stopped {
                print("同步完成")
            }
            UIApplication.shared.isNetworkActivityIndicatorVisible = (s.activity == .busy)
            if let code = e?.code {
                if code == 401 {
                    Ui.showMessage(on: self.window!.rootViewController!,
                                   title: "Authentication Error",
                                   message: "Your username or password is not correct",
                                   error: nil,
                                   onClose: {
                                    self.logout()
                    })
                }
            }
        })
        replicator.start()
        
        NotificationCenter.default.post(name: NSNotification.Name(rawValue:"sessionStart"), object: nil)
    }
    
    func stopReplication() {
        guard kSyncEnabled else {
            return
        }
        
        replicator.stop()
        replicator.removeChangeListener(withToken: changeListener!)
        changeListener = nil
    }
    
    // MARK: Push Notification Sync
    
    func registerRemoteNotification() {
        guard kSyncWithPushNotification else {
            return
        }
        
        let center = UNUserNotificationCenter.current();
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                NSLog("WARNING: Remote Notification has not been authorized");
            }
            if let err = error {
                NSLog("Register Remote Notification Error: \(err)");
            }
        }
    }
    
    func startPushNotificationSync() {
        guard kSyncWithPushNotification else {
            return
        }
        
        let target = URLEndpoint(url: URL(string: kSyncEndpoint)!)
        let config = ReplicatorConfiguration(database: database, target: target)
        if kLoginFlowEnabled, let u = Session.username, let p = Session.password {
            config.authenticator = BasicAuthenticator(username: u, password: p)
        }
        
        let repl = Replicator(config: config)
        changeListener = repl.addChangeListener({ (change) in
            let s = change.status
            let activity = kActivities[Int(s.activity.rawValue)]
            let e = change.status.error as NSError?
            let error = e != nil ? ", error: \(e!.description)" : ""
            NSLog("[Todo] Push-Notification-Replicator: \(activity), \(s.progress.completed)/\(s.progress.total)\(error)")
            UIApplication.shared.isNetworkActivityIndicatorVisible = (s.activity == .busy)
            if let code = e?.code {
                if code == 401 {
                    NSLog("ERROR: Authentication Error, username or password is not correct");
                }
            }
        })
        repl.start()
    }
    
    // MARK: UNUserNotificationCenterDelegate
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Note: Normally the application will send the device token to
        // the backend server so that the backend server can use that to
        // send the push notification to the application. We are just printing
        // to the console here.
        let tokenStrs = deviceToken.map { data -> String in
            return String(format: "%02.2hhx", data)
        }
        let token = tokenStrs.joined()
        NSLog("Push Notification Device Token: \(token)")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("WARNING: Failed to register for the remote notification: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Start single shot replicator:
        self.startPushNotificationSync()
        
        completionHandler(.newData)
    }
    
    // MARK: Crashlytics
    
    func initCrashlytics() {
        if !kCrashlyticsEnabled {
            return
        }
        
        Fabric.with([Crashlytics.self])
        
        if let info = Bundle(for: Database.self).infoDictionary {
            if let version = info["CFBundleShortVersionString"] {
                Crashlytics.sharedInstance().setObjectValue(version, forKey: "Version")
            }
            
            if let build = info["CFBundleShortVersionString"] {
                Crashlytics.sharedInstance().setObjectValue(build, forKey: "Build")
            }
        }
    }
}
