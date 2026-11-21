import XCTest
import WebKit
@testable import AntigravityRemote

@MainActor
final class AccountRecoveryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "com.heran.antirc.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testColdSettingsRestoreUsesNumericRouteWithoutProfileEmail() throws {
        let entry = "https://antigravity.google.com/r/mac?p=c%2Fconversation#chat"
        var settings: AppSettings? = AppSettings(defaults: defaults)
        _ = settings!.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings!.activeAccountId)
        settings!.recordAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: id)
        settings = nil
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let url = try XCTUnwrap(restored.prepareConnection(urlString: entry, recordID: id))
        XCTAssertEqual(url.path, "/u/2/r/mac")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "c/conversation")
        XCTAssertEqual(url.fragment, "chat")
        XCTAssertEqual(restored.historyList.count, 1)
        XCTAssertNil(restored.historyList[0].accountName)
    }

    func testRescanningSameBareLinkRetainsSelectedAccount() throws {
        let settings = AppSettings(defaults: defaults)
        let entry = "https://antigravity.google.com/r/mac"
        _ = settings.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/3/")!, for: id)
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.prepareConnection(urlString: entry)?.path, "/u/3/r/mac")
        XCTAssertEqual(restored.activeAccountId, id)
        XCTAssertEqual(restored.historyList.count, 1)
    }

    func testExplicitNewAccountLinkWinsAndHistoryKeepsItsOwnAccount() throws {
        let settings = AppSettings(defaults: defaults)
        let first = "https://antigravity.google.com/r/mac"
        _ = settings.prepareConnection(urlString: first)
        let firstID = try XCTUnwrap(settings.activeAccountId)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: firstID)
        let second = "https://antigravity.google.com/u/1/r/office"
        XCTAssertEqual(settings.prepareConnection(urlString: second)?.path, "/u/1/r/office")
        let secondID = try XCTUnwrap(settings.activeAccountId)
        settings.recordAccountRoute(URL(string: second)!, for: secondID)
        XCTAssertEqual(settings.prepareConnection(urlString: first, recordID: firstID)?.path, "/u/2/r/mac")
        XCTAssertEqual(settings.prepareConnection(urlString: "https://antigravity.google.com/u/0/r/mac")?.path, "/u/0/r/mac")
    }

    func testTransientLoginAndUnscopedURLCannotReplaceSavedRoute() throws {
        let settings = AppSettings(defaults: defaults)
        let entry = "https://antigravity.google.com/r/mac"
        _ = settings.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: id)
        for value in [entry, "https://accounts.google.com/u/0/AccountChooser", "https://antigravity.google.com/u/0/oauth/start", "https://antigravity.google.com.evil.test/u/0/r/mac"] {
            settings.recordAccountRoute(URL(string: value)!, for: id)
        }
        settings.recordSuccessfulLogin(account: "Google Account: person@example.com", for: id)
        XCTAssertEqual(settings.prepareConnection(urlString: entry, recordID: id)?.path, "/u/2/r/mac")
        XCTAssertEqual(settings.historyList[0].urlString, entry)
    }

    func testLegacyRecordsDecodeAndNumericRouteMigrates() throws {
        let id = UUID()
        let record: [String: Any] = ["id": id.uuidString, "urlString": "https://antigravity.google.com/u/4/r/mac", "accountName": "Person"]
        defaults.set(try JSONSerialization.data(withJSONObject: [record]), forKey: "Antigravity_Connection_History")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.historyList[0].googleSessionIndex, "4")
        XCTAssertEqual(settings.prepareConnection(urlString: settings.historyList[0].urlString, recordID: id)?.path, "/u/4/r/mac")
    }

    func testLegacyAccountChooserHistoryMigratesAndRemembersSelectionAcrossRelaunch() throws {
        let destination = "https://antigravity.google.com/r/mac?p=c%2Fthread#chat"
        var chooser = URLComponents(string: "https://accounts.google.com/AccountChooser")!
        chooser.queryItems = [URLQueryItem(name: "continue", value: destination)]
        let id = UUID()
        let legacy = ConnectionRecord(id: id, deviceAlias: "My Mac", accountName: "person@example.com", urlString: chooser.url!.absoluteString)
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "Antigravity_Connection_History")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.historyList[0].id, id)
        XCTAssertEqual(settings.historyList[0].deviceAlias, "My Mac")
        XCTAssertEqual(settings.historyList[0].urlString, destination)
        XCTAssertEqual(settings.prepareConnection(urlString: chooser.url!.absoluteString, recordID: id)?.absoluteString, destination)
        settings.selectAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: id)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/0/r/mac")!, for: id)
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let target = try XCTUnwrap(restored.prepareConnection(urlString: chooser.url!.absoluteString, recordID: id))
        XCTAssertEqual(target.path, "/u/2/r/mac")
        XCTAssertEqual(URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "c/thread")
        XCTAssertEqual(target.fragment, "chat")
        XCTAssertEqual(restored.historyList.count, 1)
    }

    func testLoginContinuationUnwrapsOnlyKnownGoogleHostsToOfficialRemotePages() throws {
        let destination = URL(string: "https://antigravity.google.com/u/3/r/mac")!
        var chooser = URLComponents(string: "https://accounts.google.com/AccountChooser")!
        chooser.queryItems = [URLQueryItem(name: "continue", value: destination.absoluteString)]
        var nested = URLComponents(string: "https://accounts.google.com/signin/v2/identifier")!
        nested.queryItems = [URLQueryItem(name: "continue", value: chooser.url!.absoluteString)]
        XCTAssertEqual(AntigravityAccountRoute.remoteDestination(in: nested.url!), destination)
        chooser.queryItems = [URLQueryItem(name: "continue", value: "https://antigravity.google.com.evil.test/r/mac")]
        XCTAssertNil(AntigravityAccountRoute.remoteDestination(in: chooser.url!))
        chooser.host = "evil.test"
        chooser.queryItems = [URLQueryItem(name: "continue", value: destination.absoluteString)]
        XCTAssertNil(AntigravityAccountRoute.remoteDestination(in: chooser.url!))
    }

    func testDismissedNoticeStaysHiddenUntilNewNavigation() {
        let model = WebViewModel()
        model.isInstanceDisconnected = true
        model.loadError = "Previous failure"
        XCTAssertTrue(model.showsConnectionNotice)
        model.dismissConnectionNotice()
        model.isInstanceDisconnected = true // Late DOM observer notification.
        XCTAssertFalse(model.showsConnectionNotice)
        XCTAssertTrue(model.isInstanceDisconnected)
        model.resetConversation()
        model.isInstanceDisconnected = true
        XCTAssertTrue(model.showsConnectionNotice)
        model.openAccountChooser()
        XCTAssertFalse(model.showsConnectionNotice)
        model.resetConversation(resetNotice: false) // Google menu opens a new document.
        model.isInstanceDisconnected = true
        XCTAssertFalse(model.showsConnectionNotice)
    }

    func testDisplayedURLCannotIssueAnotherLoad() throws {
        let model = WebViewModel()
        model.load(URL(string: "https://antigravity.google.com/u/2/r/mac")!, connectionID: UUID())
        let request = try XCTUnwrap(model.loadRequest)
        model.currentURL = URL(string: "https://antigravity.google.com/u/3/r/mac")!
        XCTAssertEqual(model.loadRequest, request)
    }

    func testDiagnosticsPersistBoundedTraceWithoutURLSecrets() throws {
        let trace = AccountDiagnostics(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "https://antigravity.google.com/u/2/r/private-instance?authuser=person%40example.com&token=secret-token#access_token=fragment-secret"))
        trace.record(.prepareInput, url: url, selectedIndex: "person@example.com")
        let report = AccountDiagnostics(defaults: defaults).report
        XCTAssertTrue(report.contains("pathIndex=2"))
        for secret in ["private-instance", "person", "example.com", "secret-token", "fragment-secret"] {
            XCTAssertFalse(report.contains(secret))
        }
        XCTAssertEqual(AccountDiagnostics.routeSummary(URL(string: "https://private-host.example/private")), "other pathIndex=none authuser=none")
        for _ in 0..<130 { trace.record(.committed, url: url) }
        XCTAssertEqual(trace.report.split(separator: "\n").count, 121) // Header plus 120 retained events.
    }

    func testPassiveDefaultFallbackCannotOverwriteSelectedAccount() throws {
        let settings = AppSettings(defaults: defaults)
        let entry = "https://antigravity.google.com/r/mac"
        _ = settings.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: id)
        XCTAssertEqual(settings.prepareConnection(urlString: entry)?.path, "/u/2/r/mac")
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/0/r/mac")!, for: id)
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.prepareConnection(urlString: entry)?.path, "/u/2/r/mac")
        // A deliberate menu selection of the default account must still work.
        restored.selectAccountRoute(URL(string: "https://antigravity.google.com/u/0/r/mac")!, for: id)
        XCTAssertEqual(restored.prepareConnection(urlString: entry)?.path, "/u/0/r/mac")
    }

    func testGoogleMenuQuerySelectionIsPersistedBeforeAnyCommit() throws {
        let settings = AppSettings(defaults: defaults)
        let entry = "https://antigravity.google.com/r/mac?p=c%2Fthread#chat"
        _ = settings.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings.activeAccountId)
        let model = WebViewModel()
        model.onAccountSelected = { settings.selectAccountRoute($0, for: $1) }
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = WKWebView()
        coordinator.load(WebLoadRequest(url: URL(string: entry)!, connectionID: id), in: web)
        web.stopLoading()
        coordinator.selectAccount("3", in: web)
        web.stopLoading()
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let target = try XCTUnwrap(restored.prepareConnection(urlString: entry, recordID: id))
        XCTAssertEqual(target.path, "/u/3/r/mac")
        XCTAssertEqual(URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "c/thread")
        XCTAssertEqual(target.fragment, "chat")
        let menu = "https://antigravity.google.com/?authuser=1&pageId=none"
        let menuTarget = try XCTUnwrap(restored.prepareConnection(urlString: menu))
        XCTAssertEqual(URLComponents(url: menuTarget, resolvingAgainstBaseURL: false)?.percentEncodedPath, "/u/1/")
        // The global preference is only a first-request guess for a new instance; it is not persisted,
        // so the route the instance actually works under can still become its preference.
        XCTAssertEqual(restored.prepareConnection(urlString: "https://antigravity.google.com/r/office")?.path, "/u/1/r/office")
        XCTAssertEqual(restored.lastPreparedAccountSource, .guessed)
        let officeID = try XCTUnwrap(restored.activeAccountId)
        XCTAssertNil(restored.historyList.first { $0.id == officeID }?.googleSessionIndex)
        restored.recordAccountRoute(URL(string: "https://antigravity.google.com/u/0/r/office")!, for: officeID)
        XCTAssertEqual(restored.prepareConnection(urlString: "https://antigravity.google.com/r/office", recordID: officeID)?.path, "/u/0/r/office")
        XCTAssertEqual(restored.lastPreparedAccountSource, .saved)
    }

    func testGuessedAccountIsNotEnforcedByRecovery() throws {
        let model = WebViewModel()
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        var request = WebLoadRequest(url: URL(string: "https://antigravity.google.com/u/1/r/office")!, connectionID: UUID())
        request.guessedAccount = true
        coordinator.load(request, in: web)
        web.simulatedURL = URL(string: "https://antigravity.google.com/r/office")!
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.count, 1, "A guessed account must not be forced back after the page lands elsewhere")
    }

    func testPopupMenuSelectionKeepsInstanceAndPersists() throws {
        let settings = AppSettings(defaults: defaults)
        let entry = "https://antigravity.google.com/r/mac?p=c%2Fthread"
        _ = settings.prepareConnection(urlString: entry)
        let id = try XCTUnwrap(settings.activeAccountId)
        let model = WebViewModel()
        model.onAccountSelected = { settings.selectAccountRoute($0, for: $1) }
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        coordinator.load(WebLoadRequest(url: URL(string: entry)!, connectionID: id), in: web)
        let popup = FakeNavigationAction(url: URL(string: "https://antigravity.google.com/?authuser=2&pageId=none")!, type: .other)
        XCTAssertNil(coordinator.webView(web, createWebViewWith: WKWebViewConfiguration(), for: popup, windowFeatures: WKWindowFeatures()))
        let target = try XCTUnwrap(web.requests.last?.url)
        XCTAssertEqual(target.path, "/u/2/r/mac")
        XCTAssertEqual(URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "c/thread")
        XCTAssertEqual(settings.historyList.first { $0.id == id }?.googleSessionIndex, "2")
    }

    func testRedirectedMenuSelectionIsInterceptedForAnyNavigationType() throws {
        let model = WebViewModel()
        var selected: URL?
        model.onAccountSelected = { url, _ in selected = url }
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        coordinator.load(WebLoadRequest(url: URL(string: "https://antigravity.google.com/u/0/r/mac")!, connectionID: UUID()), in: web)
        var policy: WKNavigationActionPolicy?
        coordinator.webView(web, decidePolicyFor: FakeNavigationAction(url: URL(string: "https://antigravity.google.com/?authuser=3")!, type: .other)) { policy = $0 }
        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(selected?.path, "/u/3/r/mac")
    }

    func testUserInitiatedGoogleAccountFlowLandingBecomesSelection() throws {
        let model = WebViewModel()
        var selected: URL?
        model.onAccountSelected = { url, _ in selected = url }
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        coordinator.load(WebLoadRequest(url: URL(string: "https://antigravity.google.com/u/1/r/mac")!, connectionID: UUID()), in: web)
        var policy: WKNavigationActionPolicy?
        coordinator.webView(web, decidePolicyFor: FakeNavigationAction(url: URL(string: "https://accounts.google.com/AddSession")!, type: .linkActivated)) { policy = $0 }
        XCTAssertEqual(policy, .allow)
        XCTAssertTrue(coordinator.userAccountFlow)
        web.simulatedURL = URL(string: "https://antigravity.google.com/u/3/r/mac")!
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.count, 1, "The user's new account must not be reverted to the old preference")
        XCTAssertEqual(selected?.path, "/u/3/r/mac")
        XCTAssertFalse(coordinator.userAccountFlow)
    }

    func testAutomaticLoginRedirectStillRecoversSavedAccount() throws {
        let model = WebViewModel()
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        coordinator.load(WebLoadRequest(url: URL(string: "https://antigravity.google.com/u/2/r/mac")!, connectionID: UUID()), in: web)
        coordinator.webView(web, decidePolicyFor: FakeNavigationAction(url: URL(string: "https://accounts.google.com/ServiceLogin")!, type: .other)) { _ in }
        XCTAssertFalse(coordinator.userAccountFlow)
        web.simulatedURL = URL(string: "https://antigravity.google.com/r/mac")!
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.last?.url?.path, "/u/2/r/mac")
    }

    func testIdentityMismatchNeedsConfirmationAndCanBeAdopted() throws {
        let settings = AppSettings(defaults: defaults)
        _ = settings.prepareConnection(urlString: "https://antigravity.google.com/r/mac")
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.selectAccountRoute(URL(string: "https://antigravity.google.com/u/1/r/mac")!, for: id)
        XCTAssertEqual(settings.recordIdentifiedAccount("Alice (alice@example.com)", for: id), .recorded)
        XCTAssertEqual(settings.recordIdentifiedAccount("ALICE@example.com", for: id), .recorded)
        XCTAssertEqual(settings.recordIdentifiedAccount("bob@example.com", for: id), .mismatch(expected: "alice@example.com"))
        XCTAssertEqual(settings.historyList[0].accountName, "alice@example.com")
        XCTAssertEqual(settings.knownGoogleAccounts, [KnownGoogleAccount(index: "1", email: "alice@example.com")])
        settings.adoptCurrentAccount(url: URL(string: "https://antigravity.google.com/r/mac")!, email: "bob@example.com", for: id)
        XCTAssertEqual(settings.historyList[0].googleSessionIndex, "0")
        XCTAssertEqual(settings.historyList[0].accountName, "bob@example.com")
    }

    func testStaleStatusesResetOnLaunchAndOnlyOneSessionIsActive() throws {
        let settings = AppSettings(defaults: defaults)
        _ = settings.prepareConnection(urlString: "https://antigravity.google.com/r/mac")
        let mac = try XCTUnwrap(settings.activeAccountId)
        settings.updateSessionStatus(id: mac, status: .connected)
        _ = settings.prepareConnection(urlString: "https://antigravity.google.com/r/office")
        let office = try XCTUnwrap(settings.activeAccountId)
        settings.updateSessionStatus(id: office, status: .connected)
        XCTAssertEqual(settings.historyList.filter { $0.status == .connected }.map(\.id), [office])
        let relaunched = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(relaunched.historyList.allSatisfy { $0.status == .disconnected })
    }

    func testDefaultFallbackRecoveryIsBoundedAndCannotChangePreference() throws {
        let model = WebViewModel()
        let coordinator = RemoteWebView(viewModel: model, userAgent: "").makeCoordinator()
        let web = AccountNavigationWebView()
        coordinator.load(WebLoadRequest(url: URL(string: "https://antigravity.google.com/u/2/r/mac?p=c%2Fthread")!, connectionID: UUID()), in: web)
        web.simulatedURL = URL(string: "https://antigravity.google.com/r/mac?p=c%2Fthread")!
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.count, 2)
        XCTAssertEqual(web.requests.last?.url?.path, "/u/2/r/mac")
        // A repeated server fallback must not create a redirect loop.
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.count, 2)
        // An explicit selection of default is accepted and doesn't trigger recovery to 2.
        coordinator.selectAccount("0", in: web)
        web.simulatedURL = URL(string: "https://antigravity.google.com/r/mac")!
        coordinator.webView(web, didCommit: nil)
        XCTAssertEqual(web.requests.count, 3)
        XCTAssertEqual(web.requests.last?.url?.path, "/u/0/r/mac")
    }

    func testActualWebKitHistoryChangeCannotOverwriteAccountPreference() async throws {
        let settings = AppSettings(defaults: defaults)
        _ = settings.prepareConnection(urlString: "https://antigravity.google.com/r/mac")
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.selectAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/mac")!, for: id)
        let model = WebViewModel()
        let switched = expectation(description: "WebKit commits /u/3/ after history.replaceState")
        switched.assertForOverFulfill = false
        model.onAccountRouteChanged = { url, recordID in
            settings.recordAccountRoute(url, for: recordID)
            if AntigravityAccountRoute.sessionIndex(in: url) == "3" { switched.fulfill() }
        }
        let representable = RemoteWebView(viewModel: model, userAgent: "")
        let coordinator = representable.makeCoordinator()
        let web = WKWebView()
        web.navigationDelegate = coordinator
        coordinator.setupObservers(for: web)
        coordinator.load(WebLoadRequest(url: URL(string: "about:blank")!, connectionID: id), in: web)
        web.stopLoading()
        web.loadHTMLString("<html><body>Fixture<script>setTimeout(() => history.replaceState(null, '', '/u/3/r/mac'), 300)</script></body></html>", baseURL: URL(string: "https://antigravity.google.com/u/1/r/mac")!)
        await fulfillment(of: [switched], timeout: 10)
        let restored = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.prepareConnection(urlString: "https://antigravity.google.com/r/mac", recordID: id)?.path, "/u/2/r/mac")
        web.stopLoading()
        web.navigationDelegate = nil
    }
}

@MainActor
private final class AccountNavigationWebView: WKWebView {
    var simulatedURL: URL?
    var requests: [URLRequest] = []
    override var url: URL? { simulatedURL }
    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        return nil
    }
}

private final class FakeNavigationAction: WKNavigationAction {
    private let fakeRequest: URLRequest
    private let fakeType: WKNavigationType
    init(url: URL, type: WKNavigationType) {
        fakeRequest = URLRequest(url: url)
        fakeType = type
        super.init()
    }
    override var request: URLRequest { fakeRequest }
    override var navigationType: WKNavigationType { fakeType }
    override var targetFrame: WKFrameInfo? { nil }
}

/// Run these in separate test-without-building invocations to exercise process death.
@MainActor
final class AccountColdProcessTests: XCTestCase {
    private let suite = "com.heran.antirc.tests.cold-process"

    func testWriteAccountBeforeTermination() throws {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        var legacyEntry = URLComponents(string: "https://accounts.google.com/AccountChooser")!
        legacyEntry.queryItems = [URLQueryItem(name: "continue", value: "https://antigravity.google.com/r/cold-start")]
        _ = settings.prepareConnection(urlString: legacyEntry.url!.absoluteString)
        let id = try XCTUnwrap(settings.activeAccountId)
        settings.selectAccountRoute(URL(string: "https://antigravity.google.com/u/2/r/cold-start")!, for: id)
        settings.recordAccountRoute(URL(string: "https://antigravity.google.com/u/0/r/cold-start")!, for: id)
        defaults.set(ProcessInfo.processInfo.processIdentifier, forKey: "writerPID")
        XCTAssertEqual(settings.historyList.first?.googleSessionIndex, "2")
    }

    func testRestoreInDifferentProcess() throws {
        let defaults = UserDefaults(suiteName: suite)!
        let pid = defaults.integer(forKey: "writerPID")
        try XCTSkipIf(pid == 0, "Run testWriteAccountBeforeTermination in a separate process first")
        XCTAssertNotEqual(pid, Int(ProcessInfo.processInfo.processIdentifier))
        let settings = AppSettings(defaults: defaults)
        let id = try XCTUnwrap(settings.activeAccountId)
        let url = try XCTUnwrap(settings.prepareConnection(urlString: "https://antigravity.google.com/r/cold-start", recordID: id))
        XCTAssertEqual(url.path, "/u/2/r/cold-start")
        let model = WebViewModel()
        model.load(url, connectionID: id)
        XCTAssertEqual(model.loadRequest?.url.path, "/u/2/r/cold-start")
        defaults.removePersistentDomain(forName: suite)
    }
}
