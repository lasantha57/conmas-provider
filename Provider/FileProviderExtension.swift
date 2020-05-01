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

import FileProvider

class FileProviderExtension: NSFileProviderExtension {
  private lazy var fileManager = FileManager()
  
  override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
    guard let reference = MediaItemReference(itemIdentifier: identifier) else {
      throw NSError.fileProviderErrorForNonExistentItem(withIdentifier: identifier)
    }
    return FileProviderItem(reference: reference)
  }
  
  override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
    guard let item = try? item(for: identifier) else {
      return nil
    }
    
    return NSFileProviderManager.default.documentStorageURL
      .appendingPathComponent(identifier.rawValue, isDirectory: true)
      .appendingPathComponent(item.filename)
  }
  
  override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
    let identifier = url.deletingLastPathComponent().lastPathComponent
    return NSFileProviderItemIdentifier(identifier)
  }
  
  private func providePlaceholder(at url: URL) throws {
    guard
      let identifier = persistentIdentifierForItem(at: url),
      let reference = MediaItemReference(itemIdentifier: identifier)
      else {
        throw FileProviderError.unableToFindMetadataForPlaceholder
    }
    
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    
    let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
    let item = FileProviderItem(reference: reference)
    
    try NSFileProviderManager.writePlaceholder(
      at: placeholderURL,
      withMetadata: item
    )
  }

  override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
    do {
      try providePlaceholder(at: url)
      completionHandler(nil)
    } catch {
      completionHandler(error)
    }
  }
  
  // MARK: - Enumeration
  
  override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
    if containerItemIdentifier == .rootContainer {
      return FileProviderEnumerator(path: "/")
    }

    guard
      let ref = MediaItemReference(itemIdentifier: containerItemIdentifier),
      ref.isDirectory
      else {
        throw FileProviderError.notAContainer
    }

    return FileProviderEnumerator(path: ref.path)
  }

  // MARK: - Thumbnails

  override func fetchThumbnails(
    for itemIdentifiers: [NSFileProviderItemIdentifier],
    requestedSize size: CGSize,
    perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void,
    completionHandler: @escaping (Error?) -> Void)
      -> Progress {
    let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))

    for itemIdentifier in itemIdentifiers {
      let itemCompletion: (Data?, Error?) -> Void = { data, error in
        perThumbnailCompletionHandler(itemIdentifier, data, error)

        if progress.isFinished {
          DispatchQueue.main.async {
            completionHandler(nil)
          }
        }
      }

      guard
        let reference = MediaItemReference(itemIdentifier: itemIdentifier),
        !reference.isDirectory
        else {
          progress.completedUnitCount += 1
          let error = NSError.fileProviderErrorForNonExistentItem(withIdentifier: itemIdentifier)
          itemCompletion(nil, error)
          continue
      }

      let name = reference.filename
      let path = reference.containingDirectory

      let task = NetworkClient.shared.downloadMediaItem(named: name, at: path) { url, error in

        guard
          let url = url,
          let data = try? Data(contentsOf: url, options: .alwaysMapped)
          else {
            itemCompletion(nil, error)
            return
        }
        itemCompletion(data, nil)
      }

      progress.addChild(task.progress, withPendingUnitCount: 1)
    }

    return progress
  }

  // MARK: - Providing Items

  override func startProvidingItem(at url: URL, completionHandler: @escaping ((_ error: Error?) -> Void)) {
    guard !fileManager.fileExists(atPath: url.path) else {
      completionHandler(nil)
      return
    }

    guard
      let identifier = persistentIdentifierForItem(at: url),
      let reference = MediaItemReference(itemIdentifier: identifier)
      else {
        completionHandler(FileProviderError.unableToFindMetadataForItem)
        return
    }

    let name = reference.filename
    let path = reference.containingDirectory
    NetworkClient.shared.downloadMediaItem(named: name, at: path, isPreview: false) { fileURL, error in
      guard let fileURL = fileURL else {
        completionHandler(error)
        return
      }

      do {
        try self.fileManager.moveItem(at: fileURL, to: url)
        completionHandler(nil)
      } catch {
        completionHandler(error)
      }
    }
  }

  override func stopProvidingItem(at url: URL) {
    try? fileManager.removeItem(at: url)
    try? providePlaceholder(at: url)
  }
}
