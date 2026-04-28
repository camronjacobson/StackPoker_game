import Foundation
import Combine

// ─── Hand Recorder ────────────────────────────────────────────────────────────
// Lives for the lifetime of the app. The active GameViewModel notifies the
// recorder of every state change and of the final hand_ended payload, and we
// turn that into a `RecordedHand` written to disk.
//
// Why subscribe via the GameViewModel rather than directly to the socket?
// 1) The recorder only matters when the local user is actually at a table.
// 2) The VM already filters/normalises the userId we want to attribute the
//    recording to.

@MainActor
final class HandRecorder {
    static let shared = HandRecorder()

    // ─── In-progress capture ──────────────────────────────────────────────────

    private struct InProgress {
        let userId: String
        let myUsername: String
        let tableId: String
        let tableName: String
        let handNumber: Int
        let smallBlind: Int
        let bigBlind: Int
        let myStartingStack: Int
        let myHoleCards: [PFCard]
        let opponents: [String]
        let startedAt: Date
        var frames: [ReplayFrame]
        var lastSeenActionTimestamp: Int
        var lastCommunityCount: Int
        var lastStreet: String
        var lastState: ClientGameState
    }

    private var current: InProgress?

    private init() {}

    // ─── Public API (called from GameViewModel) ───────────────────────────────

    /// Called for every game-state update. Starts a new recording when the
    /// hand number changes, and appends a frame when something visibly
    /// changed (street, community cards, or someone acted).
    func observe(state: ClientGameState,
                 tableName: String,
                 userId: String,
                 myUsername: String) {
        // New hand? Reset.
        if current?.tableId != state.tableId || current?.handNumber != state.handNumber {
            startNew(state: state, tableName: tableName, userId: userId, myUsername: myUsername)
        }

        guard var c = current else { return }

        // Decide whether this state change deserves a frame. We capture on:
        //  - any new lastAction.timestamp
        //  - the street advancing
        //  - new community cards landing (covers dealing/transitions)
        //  - the very first state of the hand (handled in startNew)
        let actionAdvanced = (state.lastAction?.timestamp ?? 0) > c.lastSeenActionTimestamp
        let streetAdvanced = state.street.rawValue != c.lastStreet
        let boardAdvanced  = state.communityCards.count != c.lastCommunityCount

        if actionAdvanced || streetAdvanced || boardAdvanced {
            c.frames.append(ReplayFrame.from(state: state))
        }

        c.lastSeenActionTimestamp = state.lastAction?.timestamp ?? c.lastSeenActionTimestamp
        c.lastCommunityCount = state.communityCards.count
        c.lastStreet = state.street.rawValue
        c.lastState = state
        current = c
    }

    /// Called from `handEndedSubject`. Persists the recording (with winners
    /// folded in) and clears the in-progress slot.
    func finalize(winners: [WinnerPayout]) {
        guard let c = current else { return }
        defer { current = nil }

        let last = c.lastState
        let myEndingStack = last.seats.first(where: { $0.userId == c.userId })?.stack ?? c.myStartingStack
        let pfWinners = winners.map(PFWinner.init)

        // Append a final "showdown" frame so the analyzer & UI can show the
        // winners' best cards even if the live state never produced one.
        var frames = c.frames
        let finalFrame = ReplayFrame(
            id: UUID().uuidString,
            capturedAt: Date(),
            phase: GamePhase.ended.rawValue,
            street: Street.showdown.rawValue,
            communityCards: last.communityCards.map(PFCard.init),
            pot: last.totalPot,
            currentBet: 0,
            smallBlind: last.smallBlind,
            bigBlind: last.bigBlind,
            seats: last.seats.map(PFSeat.init),
            activePlayerId: nil,
            dealerSeatIndex: last.dealerSeatIndex,
            lastAction: nil,
            winners: pfWinners
        )
        frames.append(finalFrame)

        let hand = RecordedHand(
            id: UUID().uuidString,
            tableId: c.tableId,
            tableName: c.tableName,
            handNumber: c.handNumber,
            userId: c.userId,
            myUsername: c.myUsername,
            smallBlind: c.smallBlind,
            bigBlind: c.bigBlind,
            myStartingStack: c.myStartingStack,
            myEndingStack: myEndingStack,
            myHoleCards: c.myHoleCards,
            opponents: c.opponents,
            pot: last.totalPot,
            winners: pfWinners,
            startedAt: c.startedAt,
            endedAt: Date(),
            frames: frames
        )

        HandHistoryStore.shared.save(hand)
    }

    /// Drop the in-progress recording (e.g. user left the table mid-hand).
    func discard() { current = nil }

    // ─── Internal ─────────────────────────────────────────────────────────────

    private func startNew(state: ClientGameState,
                          tableName: String,
                          userId: String,
                          myUsername: String) {
        let mySeat = state.seats.first { $0.userId == userId }
        let myHole = (mySeat?.holeCards ?? []).map(PFCard.init)
        let opponents = state.seats
            .filter { $0.userId != userId }
            .map { $0.username }

        current = InProgress(
            userId: userId,
            myUsername: myUsername,
            tableId: state.tableId,
            tableName: tableName,
            handNumber: state.handNumber,
            smallBlind: state.smallBlind,
            bigBlind: state.bigBlind,
            myStartingStack: mySeat?.stack ?? 0,
            myHoleCards: myHole,
            opponents: opponents,
            startedAt: Date(),
            frames: [ReplayFrame.from(state: state)],
            lastSeenActionTimestamp: state.lastAction?.timestamp ?? 0,
            lastCommunityCount: state.communityCards.count,
            lastStreet: state.street.rawValue,
            lastState: state
        )
    }
}
