import Darwin
import CommonCrypto
import Security
import WebKit

extension BrowserPage: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }
    if navigationAction.targetFrame?.isMainFrame == true {
      if let value = navigationAction.request.url?.absoluteString,
        (try? validatedBrowserURL(value)) == nil
      {
        decisionHandler(.cancel)
        return
      }
      lastRequestedMainFrameURL = navigationAction.request.url
    }
    decisionHandler(.allow)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    let response = navigationResponse.response as? HTTPURLResponse
    let disposition = response?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased()
    if !navigationResponse.canShowMIMEType || disposition?.contains("attachment") == true {
      decisionHandler(.download)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    owner?.emit([
      "type": "navigationStarted",
      "pageId": id,
      "url": webView.url?.absoluteString ?? "about:blank",
    ])
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    owner?.emit([
      "type": "navigationCommitted",
      "pageId": id,
      "url": webView.url?.absoluteString ?? "about:blank",
    ])
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    var event: [String: Any] = [
      "type": "navigationFinished",
      "pageId": id,
      "url": webView.url?.absoluteString ?? "about:blank",
      "canGoBack": webView.canGoBack,
      "canGoForward": webView.canGoForward,
    ]
    if let title = webView.title {
      event["title"] = title
    }
    owner?.emit(event)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    emitLoadFailure(error)
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    emitLoadFailure(error)
  }

  private func emitLoadFailure(_ error: Error) {
    let nativeError = error as NSError
    guard nativeError.code != NSURLErrorCancelled else { return }
    owner?.emit([
      "type": "loadFailed",
      "pageId": id,
      "url": webView.url?.absoluteString ?? "",
      "description": error.localizedDescription,
    ])
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    owner?.emit([
      "type": "loadFailed",
      "pageId": id,
      "url": webView.url?.absoluteString ?? "",
      "description": "The WebKit content process terminated.",
    ])
  }

  func webView(
    _ webView: WKWebView,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping (
        URLSession.AuthChallengeDisposition,
        URLCredential?
      ) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    var trustError: CFError?
    if SecTrustEvaluateWithError(trust, &trustError) {
      completionHandler(.useCredential, URLCredential(trust: trust))
      return
    }
    guard isExactLocalChallenge(challenge.protectionSpace) else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    guard
      let details = localUntrustedCertificateDetails(
        trust: trust,
        host: challenge.protectionSpace.host
      )
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    owner?.requestTLSDecision(
      page: self,
      trust: trust,
      host: challenge.protectionSpace.host.lowercased(),
      fingerprintSHA256: details.fingerprintSHA256,
      subject: details.subject,
      validFrom: details.validFrom,
      validTo: details.validTo,
      description: (trustError as Error?)?.localizedDescription,
      completion: completionHandler
    )
  }

  func webView(
    _ webView: WKWebView,
    navigationAction: WKNavigationAction,
    didBecome download: WKDownload
  ) {
    owner?.beginDownload(download, page: self)
  }

  func webView(
    _ webView: WKWebView,
    navigationResponse: WKNavigationResponse,
    didBecome download: WKDownload
  ) {
    owner?.beginDownload(download, page: self)
  }

  private func isExactLocalChallenge(_ protectionSpace: URLProtectionSpace) -> Bool {
    guard
      let currentURL = lastRequestedMainFrameURL ?? webView.url,
      currentURL.scheme?.lowercased() == "https",
      currentURL.host?.lowercased() == protectionSpace.host.lowercased()
    else {
      return false
    }
    let expectedPort = currentURL.port ?? 443
    guard expectedPort == protectionSpace.port else { return false }
    return isTemporaryLocalCertificateHost(protectionSpace.host)
  }
}

private struct LocalCertificateDetails {
  let fingerprintSHA256: String
  let subject: String?
  let validFrom: Date?
  let validTo: Date?
}

private func localUntrustedCertificateDetails(
  trust: SecTrust,
  host: String
) -> LocalCertificateDetails? {
  guard
    let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
    let leaf = chain.first,
    let anchor = chain.last
  else {
    return nil
  }
  guard
    SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess,
    SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
  else {
    return nil
  }
  var anchoredError: CFError?
  guard SecTrustEvaluateWithError(trust, &anchoredError) else {
    return nil
  }
  let data = SecCertificateCopyData(leaf) as Data
  var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
  data.withUnsafeBytes { bytes in
    _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
  }
  let values = SecCertificateCopyValues(
    leaf,
    [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray,
    nil
  ) as? [CFString: [CFString: Any]]
  return LocalCertificateDetails(
    fingerprintSHA256: digest.map { String(format: "%02x", $0) }.joined(),
    subject: SecCertificateCopySubjectSummary(leaf) as String?,
    validFrom: values?[kSecOIDX509V1ValidityNotBefore]?[kSecPropertyKeyValue]
      as? Date,
    validTo: values?[kSecOIDX509V1ValidityNotAfter]?[kSecPropertyKeyValue]
      as? Date
  )
}

func isTemporaryLocalCertificateHost(_ value: String) -> Bool {
  let host =
    value
    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    .lowercased()
  if host == "localhost"
    || host == "0.0.0.0"
    || host.hasSuffix(".localhost")
    || host.hasSuffix(".local")
  {
    return true
  }

  var ipv4Address = in_addr()
  if host.withCString({ inet_pton(AF_INET, $0, &ipv4Address) }) == 1 {
    return withUnsafeBytes(of: &ipv4Address) { bytes in
      let canonicalHost = "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
      guard host == canonicalHost else { return false }
      return bytes[0] == 10
        || bytes[0] == 127
        || (bytes[0] == 169 && bytes[1] == 254)
        || (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)
        || (bytes[0] == 192 && bytes[1] == 168)
    }
  }

  var ipv6Address = in6_addr()
  guard host.withCString({ inet_pton(AF_INET6, $0, &ipv6Address) }) == 1 else {
    return false
  }
  return withUnsafeBytes(of: &ipv6Address) { bytes in
    let isLoopback =
      bytes.dropLast().allSatisfy { $0 == 0 }
      && bytes.last == 1
    let isLinkLocal = bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80
    return isLoopback || isLinkLocal
  }
}

extension BrowserPage: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard navigationAction.navigationType == .linkActivated else {
      owner?.emit([
        "type": "popupBlocked",
        "pageId": id,
        "url": navigationAction.request.url?.absoluteString ?? "",
      ])
      return nil
    }
    return owner?.createTransientPopup(
      opener: self,
      configuration: configuration,
      navigationAction: navigationAction
    )
  }

  func webViewDidClose(_ webView: WKWebView) {
    owner?.closePage(id)
    owner?.emit(["type": "pageClosed", "pageId": id])
  }

  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    let resources: [String]
    switch type {
    case .camera:
      resources = ["camera"]
    case .microphone:
      resources = ["microphone"]
    case .cameraAndMicrophone:
      resources = ["camera", "microphone"]
    @unknown default:
      decisionHandler(.deny)
      return
    }
    let port = origin.port == 0 ? "" : ":\(origin.port)"
    owner?.requestPermissionDecision(
      page: self,
      origin: "\(origin.protocol)://\(origin.host)\(port)",
      resources: resources,
      completion: decisionHandler
    )
  }

  func webView(
    _ webView: WKWebView,
    runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping ([URL]?) -> Void
  ) {
    guard var urls = pendingUploadURLs else {
      completionHandler(nil)
      return
    }
    if !parameters.allowsMultipleSelection {
      urls = Array(urls.prefix(1))
    }
    guard !parameters.allowsDirectories else {
      finishUpload(
        error: BrowserMethodError(
          "directory_upload_unavailable", "Directory upload is unavailable.")
      )
      completionHandler(nil)
      return
    }
    completionHandler(urls)
    finishUpload()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(false)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    completionHandler(nil)
  }
}
