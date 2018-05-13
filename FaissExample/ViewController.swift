//
//  ViewController.swift
//  FaissExample
//
//  Created by Oleg Poyaganov on 10/05/2018.
//

import UIKit
import CoreImage
import Photos
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, AlbumPickerViewControllerDelegate {
    
    private let indexer = Indexer(
        pcaPath: Bundle.main.path(forResource: "pca", ofType: "faiss")!
    )
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    private weak var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()
        updateStatusLabel()
        loadIndex()
        
        setupCaptureSession()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        cameraPreviewContainer.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        
        // bluryness indicator - border
        cameraPreviewContainer.layer.borderWidth = 4
        cameraPreviewContainer.layer.borderColor = UIColor.clear.cgColor
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let _ = checkPhotoAuth()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        previewLayer.frame = cameraPreviewContainer.bounds
        session.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stopRunning()
    }
    
    // MARK: - Photo Library
    
    private let imageManager = PHCachingImageManager()
    
    private func checkPhotoAuth() -> Bool {
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { [weak self] (status) in
                if status != .authorized {
                    DispatchQueue.main.async {
                        self?.showNeedsPhotoAuthAlert()
                    }
                }
            }
            return false
        }
        return true
    }
    
    private func showNeedsPhotoAuthAlert() {
        let alert = UIAlertController(
            title: "Auth is needed",
            message: "Please grant access to your photo library. We'll use it responsibly.",
            preferredStyle: .alert
        )
        
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
            if let appSettings = URL(string: UIApplicationOpenSettingsURLString) {
                UIApplication.shared.open(appSettings)
            }
        }
        alert.addAction(settingsAction)
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    // MARK: - UI
    
    @IBOutlet weak var cameraPreviewContainer: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var scanButton: UIButton!
    
    private var isScanning = false
    
    @IBAction func scanPhotoLibrary(_ sender: Any) {
        if !checkPhotoAuth() {
            return
        }
        
        let albumVC = AlbumPickerViewController()
        albumVC.delegate = self
        let navVC = UINavigationController(rootViewController: albumVC)
        present(navVC, animated: true, completion: nil)
    }
    
    private func updateStatusLabel() {
        statusLabel.text = "Photos in index: \(indexer.numberOfIndexedItems)"
    }
    
    private var searchResults: [SearchResultAsset] = []
    
    private func updateSearchResults(_ results: [SearchResultAsset]) {
        let width = collectionView.frame.width / 3
        imageManager.startCachingImages(
            for: results.map { $0.asset },
            targetSize: CGSize(width: width, height: width),
            contentMode: .aspectFill,
            options: nil
        )
        searchResults = results
        collectionView.reloadData()
    }
    
    // MARK: - AlbumPickerViewControllerDelegate
    
    func albumPickerDidCancel(_ vc: AlbumPickerViewController) {}
    func albumPicker(_ vc: AlbumPickerViewController, didSelectCollections collections: [PHCollection]) {
        isScanning = true
        scanButton.isHidden = true
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.indexer.clear()
            self?.index(collections: collections.compactMap { $0 as? PHAssetCollection })
            self?.indexer.save(toPath: getIndexURL().path)
            DispatchQueue.main.async {
                self?.updateStatusLabel()
                self?.isScanning = false
                self?.scanButton.isHidden = false
            }
        }
    }
    
    // MARK: - Collection view stuff
    
    @IBOutlet weak var collectionView: UICollectionView!
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    private func title(forAsset asset: PHAsset) -> String? {
        let fetchOptions = PHFetchOptions()
        if let userAlbum = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: fetchOptions).firstObject {
            return userAlbum.localizedTitle
        }
        if let moment = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .moment, options: fetchOptions).firstObject {
            return moment.localizedTitle
        }
        if let smartAlbum = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .smartAlbum, options: fetchOptions).firstObject {
            return smartAlbum.localizedTitle
        }
        
        return nil
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "imageCell", for: indexPath) as! ImageCell
        let searchResult = searchResults[indexPath.item]
        cell.representedIdentifier = searchResult.asset.localIdentifier
        cell.albumTitleLabel.text = nil
        DispatchQueue.global(qos: .background).async { [weak self] in
            let title = self?.title(forAsset: searchResult.asset)
            DispatchQueue.main.async {
                if cell.representedIdentifier == searchResult.asset.localIdentifier {
                    cell.albumTitleLabel.text = title
                }
            }
        }
        
        let width = collectionView.frame.width / 3
        imageManager.requestImage(
            for: searchResult.asset,
            targetSize: CGSize(width: width, height: width),
            contentMode: .aspectFill,
            options: nil) { (image, _) in
                if cell.representedIdentifier == searchResult.asset.localIdentifier {
                    cell.imageView.image = image
                }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.frame.width / 3
        return CGSize(width: width, height: width)
    }
    
    // MARK: - Index
    
    private let featurizer = mobilenetv2()
    
    private func index(image: UIImage, identifier: String) {
        guard let pixelBuffer = image.pixelBuffer() else {
            print("Can't create pixel buffer from image")
            return
        }
        guard let predictionResult = try? featurizer.prediction(image: pixelBuffer) else {
            print("Can't extract features from pixel buffer")
            return
        }
        
        indexer.addFeatures(predictionResult.features, forId: identifier)
    }
    
    private func loadIndex() {
        isScanning = true
        statusLabel.text = "Loading index"
        scanButton.isHidden = true
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            let indexURL = getIndexURL()
            if FileManager.default.fileExists(atPath: indexURL.path) {
                self?.indexer.load(fromPath: indexURL.path)
            }
            
            DispatchQueue.main.async {
                self?.updateStatusLabel()
                self?.scanButton.isHidden = false
                self?.isScanning = false
            }
        }
    }
    
    private func index(collections: [PHAssetCollection]) {
        for collection in collections {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let fetchResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            let photosCount = fetchResult.count
            let imgSize = self.imageSize
            fetchResult.enumerateObjects { [weak self] (asset, index, _) in
                DispatchQueue.main.async {
                    self?.statusLabel.text = "Scanning \(collection.localizedTitle ?? "Unnamed") (\(index + 1) of \(photosCount))"
                }
                
                let requestOptions = PHImageRequestOptions()
                requestOptions.deliveryMode = .highQualityFormat
                requestOptions.resizeMode = .exact
                requestOptions.isSynchronous = true
                self?.imageManager.requestImage(
                    for: asset,
                    targetSize: imgSize,
                    contentMode: .aspectFill,
                    options: requestOptions) { (image, _) in
                        guard let img = image else {
                            print("Image can't be loaded")
                            return
                        }
                        self?.index(image: img, identifier: asset.localIdentifier)
                }
            }
        }
    }
    
    // MARK: - Search
    
    private let maxSearchResults = 9;
    
    private lazy var imageSize: CGSize = { [unowned self] in
        guard let (_, input) = self.featurizer.model.modelDescription.inputDescriptionsByName.first else {
            fatalError("Model has no input")
        }
        
        guard let constraint = input.imageConstraint else {
            fatalError("Model input has no image constraint")
        }
        
        return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
    }()
    
    private func performSearch(on pixelBuffer: CVPixelBuffer) {
        // extract features from pixel buffer
        guard let features = try? featurizer.prediction(image: pixelBuffer).features else {
            print("Can't extract features from pixel buffer")
            return
        }
        
        // search for similar items in index
        let results = indexer.search(byFeatures: features, maxResults: maxSearchResults)
        
        // fetch assets from photo library
        let localIds = results.map { $0.identifier }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIds, options: nil)
        
        var assetDict = [String:PHAsset]()
        fetchResult.enumerateObjects { (asset, index, _) in
            assetDict[asset.localIdentifier] = asset
        }
        
        let searchResults = results.compactMap { (r) -> SearchResultAsset? in
            guard let asset = assetDict[r.identifier] else {
                return nil
            }
            return SearchResultAsset(asset: asset, distance: r.distance)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateSearchResults(searchResults)
        }
    }
    
    // MARK: - Camera
    
    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(label: "faiss_example.sample.queue", attributes: [])
    private let searchQueue = DispatchQueue(label: "faiss_example.search.queue", attributes: [])
    private let sema = DispatchSemaphore(value: 1)
    
    private func setupCaptureSession() {
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            fatalError("No camera found")
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            fatalError("Cannot create input")
        }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        
        guard let connection = output.connection(with: .video) else {
            fatalError("No output connection")
        }
        connection.videoOrientation = .portrait
    }
    
    private var lastFrameTime = CACurrentMediaTime()
    private let blurDetector = BlurDetector()
    
    private let blurynessThreshold: Float = 400
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let preparedBuffer = centerCropAndScale(pixelBuffer: pixelBuffer)
        
        // check if image is too "blury"
        let bluryness = blurDetector.detectBluryness(on: preparedBuffer)
        if bluryness < blurynessThreshold {
            DispatchQueue.main.async { [weak self] in
                self?.cameraPreviewContainer.layer.borderColor = UIColor.red.cgColor
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.cameraPreviewContainer.layer.borderColor = UIColor.green.cgColor
        }
        
        if isScanning {
            return
        }
        
        if sema.wait(timeout: .now()) == .timedOut {
            return
        }
        
        searchQueue.async { [unowned self] in
            let currentTime = CACurrentMediaTime()
            if currentTime - self.lastFrameTime < 1.0 {
                self.sema.signal()
                return
            }
            self.lastFrameTime = currentTime
            self.performSearch(on: preparedBuffer)
            self.sema.signal()
        }
    }
    
    private let ciContext = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
    
    private func centerCropAndScale(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        // center crop (assume that we need squared images)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let width = image.extent.width
        let height = image.extent.height
        
        let cropped = image
            .cropped(to: CGRect(x: 0, y: (height - width) / 2, width: width, height: width))
            .transformed(by: CGAffineTransform(translationX: 0, y: -(height - width) / 2))
        
        scaleFilter.setValue(cropped, forKey: kCIInputImageKey)
        scaleFilter.setValue(CGFloat(imageSize.width) / width, forKey: kCIInputScaleKey)
        
        let croppedAndScaled = scaleFilter.outputImage!
        
        let bufferAttributes = [
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(imageSize.width), Int(imageSize.width),
            kCVPixelFormatType_32BGRA,
            bufferAttributes as CFDictionary,
            &buffer
        )
        
        guard let outputBuffer = buffer else {
            fatalError("Can't create pixel buffer")
        }
        
        ciContext.render(
            croppedAndScaled,
            to: outputBuffer,
            bounds: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.width),
            colorSpace: colorSpace
        )
        
        return outputBuffer
    }
}

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let documentsDirectory = paths[0]
    return documentsDirectory
}

func getIndexURL() -> URL {
    return getDocumentsDirectory().appendingPathComponent("index.faiss")
}

struct SearchResultAsset {
    let asset: PHAsset
    let distance: Float
}

class ImageCell: UICollectionViewCell {
    var representedIdentifier: String!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var albumTitleLabel: UILabel!
}
