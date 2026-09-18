import SwiftUI
import XCTest

/// Renders a SwiftUI view to an image and attaches it to the result bundle.
///
/// Several of this app's screens sit behind a full round of play — a bid, a
/// call and eight tricks — so nothing in a simulator run ever reaches them.
/// That is how three copies of the same screen drifted apart unnoticed
/// (SPADE-02). These render the screen without the game.
///
/// **Not `ImageRenderer`.** It does not lay out `ScrollView` content offscreen:
/// it produced a solid background rectangle for a screen that is almost
/// entirely inside a `ScrollView`. Hosting the view in a real window and using
/// `drawHierarchy` captures what is actually presented.
@MainActor
enum SnapshotRendering {
    static let phone = CGSize(width: 402, height: 874)

    static func image(of view: some View, size: CGSize = phone) -> UIImage {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Give SwiftUI a moment to commit the hierarchy. Screens are rendered
        // in their settled state, so this waits for layout, not animation.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        return UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }
}

extension XCTestCase {
    /// Renders, attaches, and fails if the result is blank or collapsed.
    @MainActor
    @discardableResult
    func attachSnapshot(
        of view: some View,
        named name: String,
        size: CGSize = SnapshotRendering.phone,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UIImage {
        let image = SnapshotRendering.image(of: view, size: size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        assertNotBlank(image, named: name, file: file, line: line)
        return image
    }

    /// A screen that renders as one flat colour is the failure this guards: it
    /// is what a collapsed layout or a view that lost its content looks like,
    /// and it would still build and pass everywhere else.
    @MainActor
    func assertNotBlank(
        _ image: UIImage,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let cg = image.cgImage else {
            return XCTFail("\(name): no bitmap", file: file, line: line)
        }
        XCTAssertGreaterThan(cg.width, 100, "\(name): collapsed width", file: file, line: line)
        XCTAssertGreaterThan(cg.height, 100, "\(name): collapsed height", file: file, line: line)

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
            colours.insert(UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2]))
        }
        XCTAssertGreaterThan(colours.count, 20, "\(name): rendered as a near-flat image", file: file, line: line)
    }
}
