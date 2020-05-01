/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import Foundation

final class NetworkClient {
  static let shared = NetworkClient()
  
  private enum APIConfig {
    enum Path: String {
      case media, file, preview
    }
    enum Parameter: String {
      case id, path
    }
  }

  private let session: URLSession = .shared
  
  private func buildURL(with path: APIConfig.Path, queryItems: [URLQueryItem]) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "conmas-server.herokuapp.com"
    components.path = "/" + path.rawValue
    components.queryItems = queryItems
    return components.url!
  }

  @discardableResult
  func getMediaItems(atPath path: String = "/",
                     handler: @escaping ([MediaItem]?, Error?) -> Void) -> URLSessionTask {
    let url = buildURL(with: .media, queryItems: [
      URLQueryItem(name: APIConfig.Parameter.path.rawValue, value: path)
    ])

    let task = session.dataTask(with: url) { data, _, error in
      guard
        let data = data,
        let results = try? JSONDecoder().decode([MediaItem].self, from: data)
        else {
          return handler(nil, error)
      }
      handler(results, nil)
    }

    task.resume()
    return task
  }

  @discardableResult
  func downloadMediaItem(named name: String,
                         at path: String,
                         isPreview: Bool = true,
                         handler: @escaping (URL?, Error?) -> Void) -> URLSessionTask {
    let url = buildURL(with: isPreview ? .preview : .file, queryItems: [
      URLQueryItem(name: APIConfig.Parameter.id.rawValue, value: name),
      URLQueryItem(name: APIConfig.Parameter.path.rawValue, value: path)
    ])

    let task = session.downloadTask(with: url) { url, _, error in
      handler(url, error)
    }

    task.resume()
    return task
  }
}
