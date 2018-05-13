//
//  AlbumPickerViewController.swift
//  FaissExample
//
//  Created by Oleg Poyaganov on 13/05/2018.
//

import UIKit
import Photos

protocol AlbumPickerViewControllerDelegate: class {
    func albumPickerDidCancel(_ vc: AlbumPickerViewController)
    func albumPicker(_ vc: AlbumPickerViewController, didSelectCollections collections: [PHCollection])
}

class AlbumPickerViewController: UITableViewController {
    typealias Album = (name: String, photosCount: Int)
    
    weak var delegate: AlbumPickerViewControllerDelegate?
    weak var doneButtonItem: UIBarButtonItem!
    
    var smartAlbums: PHFetchResult<PHAssetCollection>!
    var userCollections: PHFetchResult<PHCollection>!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Select Albums"
        tableView.allowsMultipleSelection = true
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelPicking)
        )
        
        let doneBtn = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(finishPicking)
        )
        doneBtn.isEnabled = false
        self.navigationItem.rightBarButtonItem = doneBtn
        doneButtonItem = doneBtn
        
        smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .albumRegular, options: nil)
        userCollections = PHCollectionList.fetchTopLevelUserCollections(with: nil)
    }
    
    // MARK: - Actions
    @objc func cancelPicking() {
        dismiss(animated: true, completion: nil)
        delegate?.albumPickerDidCancel(self)
    }
    
    @objc func finishPicking() {
        guard let selected = tableView.indexPathsForSelectedRows,
            selected.count > 0 else {
            return
        }
        
        dismiss(animated: true, completion: nil)
        let selectedCollections = selected.map { (indexPath) -> PHCollection in
            switch indexPath.section {
            case 0:
                return userCollections.object(at: indexPath.row)
            case 1:
                return smartAlbums.object(at: indexPath.row)
            default:
                fatalError()
            }
        }
        
        delegate?.albumPicker(self, didSelectCollections: selectedCollections)
    }

    // MARK: - Table view data source
    
    private func album(forIndexPath indexPath: IndexPath) -> Album {
        switch indexPath.section {
        case 0:
            let collection = userCollections.object(at: indexPath.row)
            if let assetCollection = collection as? PHAssetCollection {
                return (assetCollection.localizedTitle ?? "Unnamed", assetCollection.estimatedAssetCount)
            } else {
                return (collection.localizedTitle ?? "Unnamed", NSNotFound)
            }
        case 1:
            let collection = smartAlbums.object(at: indexPath.row)
            return (collection.localizedTitle ?? "Unnamed", collection.estimatedAssetCount)
        default:
            fatalError()
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return userCollections.count
        case 1:
            return smartAlbums.count
        default:
            fatalError()
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "albumCell") else {
                return UITableViewCell(style: .subtitle, reuseIdentifier: "albumCell")
            }
            return cell
        }()
        
        let album = self.album(forIndexPath: indexPath)
        cell.textLabel?.text = album.name
        cell.detailTextLabel?.text = album.photosCount != NSNotFound ? "\(album.photosCount)" : ""

        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        checkSelection()
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        checkSelection()
    }
    
    private func checkSelection() {
        if let selected = tableView.indexPathsForSelectedRows,
            selected.count > 0 {
            doneButtonItem.isEnabled = true
        } else {
            doneButtonItem.isEnabled = false
        }
    }

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}

//extension PHAssetCollection {
//    var photosCount: Int {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
//        let result = PHAsset.fetchAssetsInAssetCollection(self, options: fetchOptions)
//        return result.count
//    }
//}
