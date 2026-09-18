import SwiftUI
import XCTest
@testable import MyApp

/// Renders the shared round-result screen to an image and attaches it to the
/// result bundle.
///
/// The screen is three modes deep in a game — bid, call, eight tricks — so it
/// is effectively unreachable in a simulator run, which is how three copies of
/// it drifted apart unnoticed (SPADE-02). `ImageRenderer` gives us the picture
/// without the game: the assertions below catch a blank or collapsed render,
/// and the attachments let a human look at what shipped.
@MainActor
final class GameRoundResultBannerSnapshotTests: XCTestCase {
    private func banner(isSet: Bool) -> some View {
        GameRoundResultBanner(
            highBid: 180,
            offensePoints: isSet ? 140 : 205,
            bidderIndex: 3,
            offenseTeam: GameFlowRules.offenseOrder(bidderIndex: 3, partner1Index: 0, partner2Index: 5),
            defenseTeam: GameFlowRules.defenseOrder(
                offense: GameFlowRules.offenseOrder(bidderIndex: 3, partner1Index: 0, partner2Index: 5)
            ),
            playerName: { ["Vijay", "Asha", "Ravi", "Meera", "Sam", "Nina"][$0] },
            playerAvatar: { ["🦊", "🐼", "🦁", "🐨", "🐯", "🐸"][$0] },
            onContinue: {},
            startsRevealed: true
        )
        .frame(width: 402, height: 874)
    }

    /// Renders through a hosted view in a real window, not `ImageRenderer`.
    ///
    /// `ImageRenderer` produced a solid rectangle here: it does not lay out
    /// `ScrollView` content offscreen, so only the background painted. Hosting
    /// the view gives it a real container, and `drawHierarchy` captures what
    /// the screen actually presents.
    private func render(_ view: some View, named name: String) -> UIImage {
        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 402, height: 874)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let SwiftUI commit the hierarchy; the screen is rendered in its
        // settled state, so this waits for layout rather than for animation.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    /// A screen that renders as one flat colour is the failure this guards:
    /// it is what a collapsed layout, or a view that lost its content, looks
    /// like — and it would still "build and pass" everywhere else.
    private func assertNotBlank(_ image: UIImage, _ name: String) {
        guard let cg = image.cgImage else { return XCTFail("\(name): no bitmap") }
        XCTAssertGreaterThan(cg.width, 100, "\(name): collapsed width")
        XCTAssertGreaterThan(cg.height, 100, "\(name): collapsed height")

        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var colours = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4 * 97) {
            colours.insert(
                UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            )
        }
        XCTAssertGreaterThan(colours.count, 20, "\(name): rendered as a near-flat image")
    }

    func testBidMadeRendersTheWholeScreen() {
        assertNotBlank(render(banner(isSet: false), named: "round-result-bid-made"), "bid made")
    }

    func testSetRendersTheWholeScreen() {
        assertNotBlank(render(banner(isSet: true), named: "round-result-set"), "set")
    }
}
