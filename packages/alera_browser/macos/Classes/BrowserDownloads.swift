import WebKit

final class BrowserDownload {
  let id = UUID().uuidString.lowercased()
  let download: WKDownload
  let pageID: String
  var progressObservation: NSKeyValueObservation?
  var suggestedFileName: String?
  var destinationPath: String?
  var accepted: Bool?
  var expectedBytes: Int64?

  init(download: WKDownload, pageID: String) {
    self.download = download
    self.pageID = pageID
  }
}

extension AleraBrowserPlugin: WKDownloadDelegate {
  func beginDownload(_ download: WKDownload, page: BrowserPage) {
    let key = ObjectIdentifier(download)
    let state = BrowserDownload(download: download, pageID: page.id)
    state.progressObservation = download.progress.observe(
      \.fractionCompleted,
      options: [.new]
    ) { [weak self, weak state] progress, _ in
      guard let self, let state else { return }
      let total =
        progress.totalUnitCount > 0
        ? progress.totalUnitCount
        : state.expectedBytes
      emitDownloadChanged(
        state,
        state: "inProgress",
        receivedBytes: max(0, progress.completedUnitCount),
        totalBytes: total
      )
    }
    downloads[key] = state
    download.delegate = self
  }

  public func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    let key = ObjectIdentifier(download)
    guard let state = downloads[key], let url = response.url else {
      completionHandler(nil)
      return
    }
    state.suggestedFileName = suggestedFilename
    state.expectedBytes =
      response.expectedContentLength >= 0
      ? response.expectedContentLength
      : nil
    let decision = addDecision(
      pageID: state.pageID,
      kind: .download { [weak state] destination in
        state?.accepted = destination != nil
        state?.destinationPath = destination?.path
        completionHandler(destination)
      }
    )
    var event: [String: Any] = [
      "type": "downloadRequest",
      "decisionId": decision.id,
      "pageId": state.pageID,
      "downloadId": state.id,
      "url": url.absoluteString,
      "suggestedFileName": suggestedFilename,
    ]
    if let mimeType = response.mimeType { event["mimeType"] = mimeType }
    if response.expectedContentLength >= 0 {
      event["totalBytes"] = response.expectedContentLength
    }
    emit(event)
  }

  public func downloadDidFinish(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    guard let state = downloads.removeValue(forKey: key) else { return }
    state.progressObservation = nil
    emitDownloadChanged(
      state,
      state: "completed",
      receivedBytes: max(0, state.download.progress.completedUnitCount),
      totalBytes: state.expectedBytes
    )
  }

  public func download(
    _ download: WKDownload,
    didFailWithError error: Error,
    resumeData: Data?
  ) {
    let key = ObjectIdentifier(download)
    guard let state = downloads.removeValue(forKey: key) else { return }
    state.progressObservation = nil
    let nativeError = error as NSError
    let cancelled = state.accepted == false || nativeError.code == NSURLErrorCancelled
    emitDownloadChanged(
      state,
      state: cancelled ? "cancelled" : "failed",
      receivedBytes: max(0, state.download.progress.completedUnitCount),
      totalBytes: state.expectedBytes,
      errorCode: cancelled ? nil : "\(nativeError.domain):\(nativeError.code)"
    )
  }

  func cancelDownloads(forPage pageID: String) {
    let matches = downloads.filter { $0.value.pageID == pageID }
    for (key, state) in matches {
      state.progressObservation = nil
      state.download.cancel(nil)
      downloads.removeValue(forKey: key)
      emitDownloadChanged(
        state,
        state: "cancelled",
        receivedBytes: max(0, state.download.progress.completedUnitCount),
        totalBytes: state.expectedBytes
      )
    }
  }

  private func emitDownloadChanged(
    _ download: BrowserDownload,
    state: String,
    receivedBytes: Int64,
    totalBytes: Int64?,
    errorCode: String? = nil
  ) {
    var event: [String: Any] = [
      "type": "downloadChanged",
      "pageId": download.pageID,
      "downloadId": download.id,
      "state": state,
      "receivedBytes": receivedBytes,
      "suggestedFileName": download.suggestedFileName.map { $0 as Any } ?? NSNull(),
      "destinationPath": download.destinationPath.map { $0 as Any } ?? NSNull(),
    ]
    if let totalBytes, totalBytes >= 0 { event["totalBytes"] = totalBytes }
    if let errorCode { event["errorCode"] = errorCode }
    emit(event)
  }
}
