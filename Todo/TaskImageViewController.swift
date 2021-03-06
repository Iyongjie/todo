//
//  TaskImageViewController.swift
//  Todo
//
//  Created by Pasin Suriyentrakorn on 2/9/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

import UIKit
import CouchbaseLiteSwift

class TaskImageViewController: UIViewController, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
    @IBOutlet weak var imageView: UIImageView!
    
    var database: Database!
    var taskID: String!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
         NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: NSNotification.Name(rawValue:"sessionStart"), object: nil)

    }
    @objc func reloadData() {
        // Get database:
        let app = UIApplication.shared.delegate as! AppDelegate
        database = app.database
        
        let sessionId = UserDefaults.standard.string(forKey: "sessionId")
        if (sessionId != nil) {
            reload()
        }
    }
    // MARK: - Action
    
    @IBAction func editAction(_ sender: AnyObject) {
        Ui.showImageActionSheet(on: self, imagePickerDelegate: self, onDelete: {
            self.deleteImage()
        })
    }
    
    @IBAction func closeAction(_ sender: AnyObject) {
        dismissController()
    }
    
    func dismissController() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        updateImage(image: info["UIImagePickerControllerOriginalImage"] as! UIImage)
        picker.presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Database
    
    func reload() {
        let task = database.document(withID: taskID)!
        DispatchQueue.main.async {

            if let blob = task.blob(forKey: "image"), let content = blob.content {
                self.imageView.image = UIImage(data: content)
            } else {
                self.imageView.image = nil
            }
        }
        
    }
    
    func updateImage(image: UIImage) {
        guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
            Ui.showMessage(on: self, title: "Error", message: "Invalid image format")
            return
        }
        
        do {
            let task = database.document(withID: taskID)!.toMutable()
            task.setValue(Blob(contentType: "image/jpg", data: imageData), forKey: "image")
            try database.saveDocument(task)
            reload()
        } catch let error as NSError {
            Ui.showError(on: self, message: "Couldn't update image", error: error)
        }
    }
    
    func deleteImage() {
        do {
            let task = database.document(withID: taskID)!.toMutable()
            task.setValue(nil, forKey: "image")
            try database.saveDocument(task)
            reload()
        } catch let error as NSError {
            Ui.showError(on: self, message: "Couldn't delete image", error: error)
        }
    }
    deinit {
        /// 移除通知
        NotificationCenter.default.removeObserver(self)
    }

}
