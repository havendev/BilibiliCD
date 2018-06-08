//
//  NetworkingModel.swift
//  BCD
//
//  Created by Liuliet.Lee on 17/6/2017.
//  Copyright © 2017 Liuliet.Lee. All rights reserved.
//

import UIKit

protocol VideoCoverDelegate: class {
    func gotVideoInfo(_ info: Info)
    func gotImage(_ image: Image)
    func connectError()
    func cannotFindVideo()
}

protocol UpuserImgDelegate: class {
    func gotUpusers(_ ups: [Upuser])
    func connectError()
    func cannotGetUser()
}

struct Upuser: Decodable {
    var name: String
    var videoNum: String
    var fansNum: String
    var imgURL: String
    enum CodingKeys: String, CodingKey {
        case name
        case videoNum = "videonum"
        case fansNum = "fansnum"
        case imgURL = "imgurl"
    }
}

class NetworkingModel {
    
    weak var delegateForVideo: VideoCoverDelegate?
    weak var delegateForUpuser: UpuserImgDelegate?
    let session = URLSession.shared
    
    private let baseAPI = "http://www.bilibilicd.tk/api"
    
    private func updateServerRecord(type: CoverType, nid: UInt64, info: Info) {
        guard let url = generateAPI(byType: type, andNID: Int(nid), orInfo: info) else {
            fatalError("cannot generate api url")
        }
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) { data, response, error in
            if error != nil {
                print(error!)
            }
        }
        task.resume()
    }
    
    private func generateAPI(byType type: CoverType, andNID nid: Int? = nil, andInfo newInfo: Info? = nil) -> URL? {
        var api = baseAPI
        
        if type == .hotList {
            return URL(string: api + "/hot_list")
        } else {
            api += "/db"
            if newInfo != nil {
                api += "/update?type="
            } else {
                api += "/search?type="
            }
            
            switch type {
            case .video: api += "av"
            case .article: api += "cv"
            case .live: api += "lv"
            default: return nil
            }

            api += "&nid=\(nid!)"

            if let info = newInfo {
                api += "&url=\(info.imageURL)&title=\(info.title)&author=\(info.author)"
            }
        }
        
        return URL(string: api.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)
    }
    
    private func fetchCoverRecordFromServer(withType type: CoverType, andID nid: UInt64) {
        guard let url = generateAPI(byType: type, andNID: Int(nid)) else {
            fatalError("cannot generate api url")
        }
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) { data, response, error in
            guard error == nil,
                let content = data,
                let newInfo = try? JSONDecoder().decode(Info.self, from: content)
                else {
                    self.videoDelegate { $0.connectError() }
                    return
            }
            if newInfo.isValid {
                self.videoDelegate { $0.gotVideoInfo(newInfo) }
                self.getImage(fromUrlPath: newInfo.imageURL)
                self.updateServerRecord(type: type, nid: nid, info: newInfo)
            } else {
                self.videoDelegate { $0.cannotFindVideo() }
            }
        }
        task.resume()
    }
    
    open func getCoverInfo(byType type: CoverType, andNID nid: UInt64) {
        switch type {
        case .video:   getInfo(forAV: nid)
        case .article: getInfo(forCV: nid)
        case .live:    getInfo(forLV: nid)
        default: break
        }
    }
    
    private func getInfo(forAV: UInt64) {
        BKVideo(av: Int(forAV)).getInfo {
            guard let info = $0 else {
                self.fetchCoverRecordFromServer(withType: .video, andID: forAV)
                return
            }
            let url = info.coverImageURL.absoluteString
            let newInfo = Info(author: info.author, title: info.title, imageURL: url)
            self.videoDelegate { $0.gotVideoInfo(newInfo) }
            self.getImage(fromUrlPath: url)
            self.updateServerRecord(type: .video, nid: forAV, info: newInfo)
        }
    }
    
    private func getInfo(forCV: UInt64) {
        BKArticle(cv: Int(forCV)).getInfo {
            guard let info = $0 else {
                self.fetchCoverRecordFromServer(withType: .article, andID: forCV)
                return
            }
            let url = info.coverImageURL.absoluteString
            let newInfo = Info(author: info.author, title: info.title, imageURL: url)
            self.videoDelegate { $0.gotVideoInfo(newInfo) }
            self.getImage(fromUrlPath: url)
            self.updateServerRecord(type: .article, nid: forCV, info: newInfo)
        }
    }
    
    private func getInfo(forLV: UInt64) {
        BKLiveRoom(Int(forLV)).getInfo {
            guard let info = $0 else {
                self.fetchCoverRecordFromServer(withType: .live, andID: forLV)
                return
            }
            let url = info.coverImageURL.absoluteString
            let newInfo = Info(author: String(info.mid), title: info.title, imageURL: url)
            self.videoDelegate { $0.gotVideoInfo(newInfo) }
            self.getImage(fromUrlPath: url)
            self.updateServerRecord(type: .live, nid: forLV, info: newInfo)
        }
    }
    
    private func getImage(fromUrlPath path: String) {
        let url = URL(string: path)
        let request = URLRequest(url: url!)
        let task = session.dataTask(with: request) { data, response, error in
            if let content = data {
                if path.isGIF {
                    if let gif = UIImage.gif(data: content) {
                        self.videoDelegate { $0.gotImage(.gif(gif, data: content)) }
                    } else {
                        self.videoDelegate { $0.connectError() }
                    }
                } else {
                    if let img = UIImage(data: content) {
                        self.videoDelegate { $0.gotImage(.normal(img)) }
                    } else {
                        self.videoDelegate { $0.connectError() }
                    }
                }
            } else {
                print(error ?? "network error")
                self.videoDelegate { $0.connectError() }
            }
        }
        task.resume()
    }

    private func videoDelegate(_ perform: @escaping (VideoCoverDelegate) -> Void) {
        DispatchQueue.main.async {
            if let delegate = self.delegateForVideo {
                perform(delegate)
            }
        }
    }
}
