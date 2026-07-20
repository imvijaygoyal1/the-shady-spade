import XCTest
@testable import MyApp

@MainActor
final class OnlineSessionViewModelTests: XCTestCase {
    func test_normalizedRoomCodeAcceptsPlainCodesAndUniversalLinks() {
        XCTAssertEqual(OnlineSessionViewModel.normalizedRoomCode(" ab-c123! "), "ABC123")
        XCTAssertEqual(
            OnlineSessionViewModel.normalizedRoomCode("https://shadyspade-d6b84.web.app/shadyspade/join/z9y8x7"),
            "Z9Y8X7"
        )
        XCTAssertEqual(
            OnlineSessionViewModel.normalizedRoomCode("https://shadyspade.vijaygoyal.org/join/sms123"),
            "SMS123"
        )
        XCTAssertEqual(
            OnlineSessionViewModel.normalizedRoomCode("SHADYSPADE://JOIN/qwe123"),
            "QWE123"
        )
    }

    func test_roomCodeValidationRequiresSixNormalizedCharacters() {
        XCTAssertTrue(OnlineSessionViewModel.isValidRoomCode("abc123"))
        XCTAssertTrue(OnlineSessionViewModel.isValidRoomCode("https://host/shadyspade/join/abc123"))
        XCTAssertFalse(OnlineSessionViewModel.isValidRoomCode("abc12"))
        XCTAssertFalse(OnlineSessionViewModel.isValidRoomCode("!!!"))
    }

    func test_prepareLocalSessionSeedsHostAndAISeatsWithoutNetwork() {
        let vm = OnlineSessionViewModel()

        let code = vm.prepareLocalSession(
            uid: "host-uid",
            name: "Host",
            avatar: "🦁",
            aiSeats: [2, 4],
            sessionType: "multiplayer"
        )

        XCTAssertEqual(code.count, 6)
        XCTAssertEqual(vm.sessionCode, code)
        XCTAssertFalse(vm.isSessionCodeConfirmed)
        XCTAssertTrue(vm.isHost)
        XCTAssertTrue(vm.isConnecting)
        XCTAssertEqual(vm.sessionType, "multiplayer")
        XCTAssertEqual(vm.aiSeats, [2, 4])
        XCTAssertEqual(vm.playerSlots[0].uid, "host-uid")
        XCTAssertEqual(vm.playerSlots[0].name, "Host")
        XCTAssertTrue(vm.playerSlots[0].joined)
        XCTAssertEqual(vm.playerSlots[2].uid, "AI-2")
        XCTAssertEqual(vm.playerSlots[4].uid, "AI-4")
        XCTAssertTrue(vm.playerSlots[2].joined)
        XCTAssertTrue(vm.playerSlots[4].joined)
        XCTAssertFalse(vm.humanSlotsFull)
        XCTAssertFalse(vm.allSlotsJoined)
    }

    func test_soloFallbackOnlyWhenHostHasNoOtherHumansAndHandlerExists() {
        XCTAssertTrue(OnlineSessionViewModel.canStartAsSoloFallback(
            isHost: true,
            allNonHostSlotsEmpty: true,
            hasFallbackHandler: true
        ))
        XCTAssertFalse(OnlineSessionViewModel.canStartAsSoloFallback(
            isHost: false,
            allNonHostSlotsEmpty: true,
            hasFallbackHandler: true
        ))
        XCTAssertFalse(OnlineSessionViewModel.canStartAsSoloFallback(
            isHost: true,
            allNonHostSlotsEmpty: false,
            hasFallbackHandler: true
        ))
        XCTAssertFalse(OnlineSessionViewModel.canStartAsSoloFallback(
            isHost: true,
            allNonHostSlotsEmpty: true,
            hasFallbackHandler: false
        ))
    }
}
