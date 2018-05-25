//
//  CoreDataModel.swift
//  BCD
//
//  Created by Liuliet.Lee on 13/7/2017.
//  Copyright © 2017 Liuliet.Lee. All rights reserved.
//

import UIKit
import Foundation
import CoreData

class CoreDataModel {
    
    static let shared = CoreDataModel()
    
    private let nudity = Nudity()
    private let context = CoreDataStorage.sharedInstance.mainQueueContext
    private let PermFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Permission")
    private let HistFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "History")
    private let OrigFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "OriginCover")
    private let SettFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Setting")
    
    private func saveContext() {
        CoreDataStorage.sharedInstance.saveContext(context)
    }
    
    // MARK: - History
    
    func refreshHistory() {
        if let limit = historyNum {
            checkHistoryNumLimit(limit)
        }
    }
    
    func fetchHistory() -> [History] {
        var items = [History]()
        
        let sort = NSSortDescriptor(key: #keyPath(History.date), ascending: false)
        HistFetchRequest.sortDescriptors = [sort]
        
        do {
            items = try context.fetch(HistFetchRequest) as! [History]
        } catch {
            print(error)
        }
        
        return items
    }
    
    @discardableResult
    func addNewHistory(av: String, image: Image, title: String, up: String, url: String) -> History {
        refreshHistory()
        
        let entity = NSEntityDescription.entity(forEntityName: "History", in: context)!
        let newItem = History(entity: entity, insertInto: context)
        
        let list = fetchHistory()
        if list.count != 0, list[0].up == up && list[0].av == av { return list[0] }
        
        let uiImage = image.uiImage
        let originCoverData: Data
        switch image {
        case .gif(_, data: let data):
            originCoverData = data
        case .normal:
            originCoverData = uiImage.toData()
        }
        let resizedCoverData = uiImage.resized().toData()
        
        newItem.av = av
        newItem.date = Date()
        newItem.image = resizedCoverData
        newItem.title = title
        newItem.up = up
        newItem.url = url
        newItem.isHidden = isNeedHid(uiImage)
        
        let origEntity = NSEntityDescription.entity(forEntityName: "OriginCover", in: context)!
        let newOrig = OriginCover(entity: origEntity, insertInto: context)
        newOrig.image = originCoverData
        
        newItem.origin = newOrig
        newOrig.history = newItem
        
        saveContext()
        
        return newItem
    }
    
    func isNeedHid(_ cover: UIImage) -> Bool {
        let size = CGSize(width: 224, height: 224)
        
        let resizedImages = cover.resizeTo(newSize: size)
        
        for image in resizedImages {
            guard let buffer = image?.pixelBuffer() else {
                fatalError("Converting to pixel buffer failed!")
            }
            
            guard let result = try? nudity.prediction(data: buffer) else {
                fatalError("Prediction failed!")
            }
            
            let confidence = result.prob["SFW"]! * 100.0
            let converted = String(format: "%.2f", confidence)
            
            print("SFW - \(converted) %")
            
            if confidence < 70.0 { return true }
        }
        
        return false
    }
    
    func isExistInHistory(cover: BilibiliCover) -> History? {
        let history = fetchHistory()
        
        for item in history {
            if item.av == cover.shortDescription {
                return item
            }
        }
        
        return nil
    }
    
    func changeOriginCover(of item: History, image: UIImage) {
        item.origin?.image = image.toData()
        saveContext()
    }
    
    func changeIsHiddenOf(_ item: History) {
        item.isHidden = !item.isHidden
        saveContext()
    }
    
    func deleteHistory(_ item: History) {
        context.delete(item)
        saveContext()
    }
    
    func clearHistory() {
        do {
            let items = try context.fetch(HistFetchRequest) as! [History]
            for item in items { deleteHistory(item) }
        } catch {
            print(error)
        }
    }
    
    private func checkHistoryNumLimit(_ limit: Int, history: [History]! = nil) {
        var list = history ?? fetchHistory()
        let count = list.count
        if count == 0 { return }
        let overflow = count - limit
        if overflow > 0 {
            for i in 0..<overflow {
                deleteHistory(list[count - 1 - i])
            }
        }
    }
    
    // MARK: - Setting
    
    private func initSetting() {
        let initHistoryNum: Int16 = 120
        let entity = NSEntityDescription.entity(forEntityName: "Setting", in: context)!
        let newItem = Setting(entity: entity, insertInto: context)
        newItem.historyNumber = initHistoryNum
        saveContext()
    }
    
    private var setting: Setting? {
        do {
            let searchResults = try context.fetch(SettFetchRequest)
            if searchResults.count == 0 {
                initSetting()
                return self.setting
            } else {
                return searchResults[0] as? Setting
            }
        } catch {
            print(error)
        }
        
        return nil
    }
    
    var historyNum: Int! {
        get {
            return Int(setting?.historyNumber ?? 0)
        }
        set {
            setting?.historyNumber = Int16(newValue)
            saveContext()
        }
    }
}

extension UIImage {
    func toData() -> Data {
        return UIImagePNGRepresentation(self)!
    }
    
    func resized(to size: CGSize = CGSize(width: 135, height: 84)) -> UIImage {
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        return resizedImage
    }
}

extension String {
    var isGIF: Bool {
        return hasSuffix("gif")
    }
}

extension History {
    var isGIF: Bool! {
        return url?.isGIF
    }
    var uiImage: UIImage? {
        if let originCoverData = origin?.image {
            if isGIF {
                return UIImage.gif(data: originCoverData)
            } else {
                return UIImage(data: originCoverData)
            }
        } else if let data = image {
            return UIImage(data: data)
        } else { return nil }
    }
}
