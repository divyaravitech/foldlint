import FoldLintCore
import XCTest

final class RuleTests: XCTestCase {
    private func ids(_ source: String, configuration: Configuration = Configuration()) -> [String] {
        Linter(configuration: configuration).lint(source: source).map(\.ruleID)
    }

    // MARK: uiscreen-main

    func testUIScreenMainFlagged() {
        XCTAssertEqual(ids("let s = UIScreen.main.scale"), ["uiscreen-main"])
    }

    func testUIScreenMainBoundsReportedOnce() {
        XCTAssertEqual(ids("let w = UIScreen.main.bounds.width"), ["uiscreen-main"])
    }

    func testDisplayScaleNotFlagged() {
        XCTAssertEqual(ids("let s = traitCollection.displayScale"), [])
    }

    func testCommentsAndStringsIgnored() {
        XCTAssertEqual(ids("""
        // UIScreen.main.scale is bad
        let text = "UIScreen.main"
        """), [])
    }

    // MARK: screen-bounds-layout

    func testWindowScreenBoundsFlagged() {
        XCTAssertEqual(ids("let w = view.window?.windowScene?.screen.bounds.width"), ["screen-bounds-layout"])
        XCTAssertEqual(ids("let w = screen!.nativeBounds"), ["screen-bounds-layout"])
    }

    func testViewBoundsNotFlagged() {
        XCTAssertEqual(ids("let w = view.bounds.width"), [])
    }

    // MARK: idiom-branching

    func testIdiomFlagged() {
        XCTAssertEqual(ids("if UIDevice.current.userInterfaceIdiom == .pad { }"), ["idiom-branching"])
        XCTAssertEqual(ids("if traitCollection.userInterfaceIdiom == .phone { }"), ["idiom-branching"])
    }

    // MARK: orientation-branching

    func testOrientationFlagged() {
        XCTAssertEqual(ids("if scene.interfaceOrientation.isLandscape { }"), ["orientation-branching"])
        XCTAssertEqual(ids("let o = UIDevice.current.orientation"), ["orientation-branching"])
        XCTAssertEqual(ids("NotificationCenter.default.addObserver(self, selector: #selector(f), name: UIDevice.orientationDidChangeNotification, object: nil)"), ["orientation-branching"])
    }

    func testOtherOrientationNotFlagged() {
        XCTAssertEqual(ids("stack.axis = layout.orientation"), [])
    }

    // MARK: orientation-lock

    func testOrientationLockFlagged() {
        XCTAssertEqual(ids("""
        class VC: UIViewController {
            override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
        }
        """), ["orientation-lock"])
        XCTAssertEqual(ids("""
        class AppDelegate {
            func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .all }
        }
        """), ["orientation-lock"])
    }

    // MARK: standalone-bar

    func testStandaloneBarsFlagged() {
        XCTAssertEqual(ids("let t = UIToolbar()"), ["standalone-bar"])
        XCTAssertEqual(ids("let n = UINavigationBar(frame: .zero)"), ["standalone-bar"])
        XCTAssertEqual(ids("let b = UITabBar.init()"), ["standalone-bar"])
        XCTAssertEqual(ids("final class FancyBar: UIToolbar {}"), ["standalone-bar"])
    }

    func testManagedBarsNotFlagged() {
        XCTAssertEqual(ids("navigationController?.isToolbarHidden = false"), [])
        XCTAssertEqual(ids("let tbc = UITabBarController()"), [])
    }

    // MARK: text-only-bar-item

    func testUIKitTextOnlyItemFlagged() {
        XCTAssertEqual(ids("let i = UIBarButtonItem(title: \"Share\", style: .plain, target: nil, action: nil)"), ["text-only-bar-item"])
    }

    func testUIKitItemWithImageNotFlagged() {
        XCTAssertEqual(ids("let i = UIBarButtonItem(title: \"Share\", image: UIImage(systemName: \"square.and.arrow.up\"), primaryAction: nil)"), [])
    }

    func testSwiftUITextOnlyToolbarButtonFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                Text("Hi").toolbar {
                    Button("Share") { }
                }
            }
        }
        """), ["text-only-bar-item"])
    }

    func testSwiftUIToolbarButtonWithSymbolNotFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                Text("Hi").toolbar {
                    Button("Share", systemImage: "square.and.arrow.up") { }
                }
            }
        }
        """), [])
    }

    func testCancelAndMenuButtonsNotFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                Text("Hi").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { } }
                    ToolbarItem { Menu("More", systemImage: "ellipsis") { Button("Rename") { } } }
                }
            }
        }
        """), [])
    }

    func testButtonOutsideToolbarNotFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View { Button("Tap") { } }
        }
        """), [])
    }

    // MARK: arrangements

    func testArrangementInListFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                List {
                    ArrangementView { Text("A") } secondary: { Text("B") }
                }
            }
        }
        """), ["arrangement-in-scroll"])
    }

    func testNavigationInsideArrangementFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                ArrangementView {
                    NavigationStack { Text("A") }
                } secondary: {
                    Text("B")
                }
            }
        }
        """), ["navigation-inside-arrangement"])
    }

    func testCorrectArrangementNotFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                NavigationStack {
                    ArrangementView {
                        List { Text("A") }
                    } secondary: {
                        ScrollView { Text("B") }
                    }
                    .arrangementViewStyle(.split)
                }
            }
        }
        """), [])
    }

    // MARK: app-wide-window

    func testAppWideWindowFlagged() {
        XCTAssertEqual(ids("let w = UIApplication.shared.keyWindow"), ["app-wide-window"])
        XCTAssertEqual(ids("let w = UIApplication.shared.windows.first"), ["app-wide-window"])
        XCTAssertEqual(ids("let s = UIApplication.shared.connectedScenes.first"), ["app-wide-window"])
    }

    func testViewWindowNotFlagged() {
        XCTAssertEqual(ids("let w = view.window"), [])
    }

    // MARK: camera

    func testVideoMirroringWithoutGuardFlagged() {
        XCTAssertEqual(ids("connection.isVideoMirrored = true"), ["video-mirroring"])
    }

    func testVideoMirroringWithGuardNotFlagged() {
        XCTAssertEqual(ids("""
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
        """), [])
    }

    func testReadingMirroringNotFlagged() {
        XCTAssertEqual(ids("let mirrored = connection.isVideoMirrored"), [])
    }

    func testFrontCameraComparisonFlagged() {
        XCTAssertEqual(ids("if device.position == .front { }"), ["front-camera-assumption"])
        XCTAssertEqual(ids("let selfie = AVCaptureDevice.Position.front == camera.position"), ["front-camera-assumption"])
        XCTAssertEqual(ids("""
        switch device.position {
        case .front: mirror()
        default: break
        }
        """), ["front-camera-assumption"])
    }

    func testFrontCameraDiscoveryNotFlagged() {
        // Apple: keep discovering the front camera this way; on iPhone Duo it returns the virtual front camera.
        XCTAssertEqual(ids("let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)"), [])
        XCTAssertEqual(ids("""
        let s = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        """), [])
    }

    func testUnrelatedSwitchNotFlagged() {
        XCTAssertEqual(ids("""
        switch layer.position {
        case .zero: break
        default: break
        }
        switch side {
        case .front: break
        default: break
        }
        """), [])
    }

    func testDuoCameraViaDefaultFlagged() {
        XCTAssertEqual(ids("let c = AVCaptureDevice.default(.builtInOuterUltraWideCamera, for: .video, position: .unspecified)"), ["camera-discovery"])
        XCTAssertEqual(ids("let c = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInInnerUltraWideCamera, for: .video, position: .front)"), ["camera-discovery"])
    }

    func testDuoCameraViaDiscoverySessionNotFlagged() {
        XCTAssertEqual(ids("""
        let s = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera], mediaType: .video, position: .unspecified)
        """), [])
    }

    func testToolbarOverflowMenuTextButtonsNotFlagged() {
        XCTAssertEqual(ids("""
        struct V: View {
            var body: some View {
                Text("Hi").toolbar {
                    ToolbarOverflowMenu {
                        Button("Duplicate") { }
                        Button("Archive") { }
                    }
                }
            }
        }
        """), [])
    }

    // MARK: suppression and config

    func testDisableNextLine() {
        XCTAssertEqual(ids("""
        // foldlint:disable-next-line uiscreen-main
        let s = UIScreen.main.scale
        let t = UIScreen.main.scale
        """), ["uiscreen-main"])
    }

    func testDisableLineAllRules() {
        XCTAssertEqual(ids("let s = UIScreen.main.scale // foldlint:disable-line"), [])
    }

    func testDisableFile() {
        XCTAssertEqual(ids("""
        // foldlint:disable-file idiom-branching
        let a = UIDevice.current.userInterfaceIdiom
        let b = UIScreen.main
        """), ["uiscreen-main"])
    }

    func testDisabledRuleInConfig() {
        var configuration = Configuration()
        configuration.disabledRules = ["uiscreen-main"]
        XCTAssertEqual(ids("let s = UIScreen.main.scale", configuration: configuration), [])
    }

    func testSeverityOverride() throws {
        let json = #"{"severity": {"uiscreen-main": "error"}, "excluded": ["Vendor"]}"#
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        XCTAssertTrue(configuration.excluded.contains("Vendor"))
        XCTAssertTrue(configuration.excluded.contains("Pods"))
        let findings = Linter(configuration: configuration).lint(source: "let s = UIScreen.main.scale")
        XCTAssertEqual(findings.first?.severity, .error)
    }

    func testLocation() {
        let findings = Linter().lint(source: "\n    let s = UIScreen.main.scale")
        XCTAssertEqual(findings.first?.line, 2)
        XCTAssertEqual(findings.first?.column, 13)
    }
}
