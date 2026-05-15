import Foundation
import Combine

// ─── WebSocket Client ─────────────────────────────────────────────────────────
// Speaks Socket.IO v4 / Engine.IO v4 over raw WebSocket.
// Connects to: {WS_BASE}/socket.io/?EIO=4&transport=websocket&token=TOKEN
// Events format (send/receive): 42["event_name", {...payload...}]

// MAP: GameSocketClient — Socket.IO/Engine.IO client (266 lines)
// - connect ................................ L39
// - disconnect ............................. L59
// - joinTable / leaveTable ................. L70 / L78
// - sendAction / sendChat .................. L85 / L91
// - showCard (voluntary fold-show) ......... L102
// - requestTimeExtension / sendPing ........ L112 / L116
// - sendEvent (raw 42[…] frame) ............ L123
// - startReceiving / parseSocketEvent ...... L136 / L188
// - handleDisconnect / scheduleReconnect ... L242 / L251
// - startPing (keep-alive) ................. L260

final class GameSocketClient: ObservableObject {

    static let shared = GameSocketClient()

    // ─── State ────────────────────────────────────────────────────────────────

    @Published var isConnected = false
    @Published var lastError:  String?

    // Event publishers — ViewModel subscribes to these
    let gameStateSubject    = PassthroughSubject<ClientGameState, Never>()
    let playerActionSubject = PassthroughSubject<PlayerActionEvent, Never>()
    let chatSubject         = PassthroughSubject<ChatMessage, Never>()
    let handEndedSubject    = PassthroughSubject<[WinnerPayout], Never>()
    let playerEventSubject  = PassthroughSubject<(String, String), Never>() // (event, userId)
    let kickedSubject       = PassthroughSubject<String, Never>()
    let errorSubject        = PassthroughSubject<WsErrorData, Never>()
    // Canonical socket-side balance update — fires whenever the server's
    // chips ledger changes for the current user outside an HTTP response.
    // Sources (per TECH_DEBT.md "Balance sync via socket"):
    //   • leave_table → softLeaveCashOut         (reason: "cash_out")
    //   • join_table  → rejoinRedebit            (reason: "rejoin_redebit" | "rejoin_noop")
    //   • idle-table sweeper → forceCloseIdleTable (reason: "idle_table_closed")
    // Future emit sources (admin grant, tipping, tournament prizes) should
    // ride this same channel rather than introducing parallel events.
    let chipsUpdatedSubject = PassthroughSubject<ChipsUpdatedEvent, Never>()

    private var webSocket:    URLSessionWebSocketTask?
    private var pingTimer:    Timer?
    private var reconnectTask: Task<Void, Never>?
    private var currentToken: String?
    private var currentTableId: String?

    private let decoder = JSONDecoder()

    // Serial background queue for parsing + decoding incoming socket events.
    // The full ClientGameState JSON is non-trivial (9 seats, hole cards,
    // run-out boards, winners, revealedCards…) and decoding it on the main
    // thread used to hitch button taps and animation transactions whenever
    // a state update landed mid-frame. Decoding here off-main and letting
    // each subject's downstream `.receive(on: RunLoop.main)` hop the typed
    // value back to main keeps the UI thread free.
    //
    // Why serial (not concurrent): event order matters — a `game_state`
    // emit immediately followed by another must be applied in send order,
    // otherwise the UI can briefly snap backward to an older snapshot.
    // A serial queue preserves that ordering at zero coordination cost.
    private let eventQueue = DispatchQueue(label: "GameSocketClient.events", qos: .userInteractive)

    private init() {}

    // ─── Connect ──────────────────────────────────────────────────────────────

    func connect(token: String) {
        // Prevent duplicate connections
        guard !isConnected, webSocket == nil else { return }
        currentToken = token

        let wsBase = APIConfig.wsURL
        var comps  = URLComponents(string: wsBase + "/socket.io/")!
        comps.queryItems = [
            URLQueryItem(name: "EIO",       value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "token",     value: token),
        ]
        guard let url = comps.url else { return }

        let session = URLSession(configuration: .default)
        webSocket   = session.webSocketTask(with: url)
        webSocket?.resume()
        startReceiving()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        reconnectTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket   = nil
        isConnected = false
    }

    // ─── Join / Leave ─────────────────────────────────────────────────────────

    func joinTable(_ tableId: String) {
        currentTableId = tableId
        // If already connected, send immediately; otherwise queued until "40" received
        if isConnected {
            sendEvent("join_table", data: ["tableId": tableId])
        }
    }

    func leaveTable(_ tableId: String) {
        sendEvent("leave_table", data: ["tableId": tableId])
        currentTableId = nil
    }

    // ─── Game Actions ─────────────────────────────────────────────────────────

    func sendAction(tableId: String, action: PokerAction, amount: Int? = nil) {
        var data: [String: Any] = ["tableId": tableId, "action": action.rawValue]
        if let amount { data["amount"] = amount }
        sendEvent("player_action", data: data)
    }

    func sendChat(tableId: String, message: String) {
        sendEvent("table_chat", data: ["tableId": tableId, "message": message])
    }

    /// Tap-to-show: tells the server the user wants to expose their hole
    /// card at `cardIndex` to the rest of the table. Server validates the
    /// index and re-broadcasts a fresh ClientGameState; the new state
    /// carries the card under `revealedCards` for every viewer's seat,
    /// including the sender, so we render the reveal off the broadcast
    /// rather than optimistically. Idempotent on the server side — a
    /// duplicate tap is a no-op.
    ///
    /// `handNumber` lets the server reject taps that landed during the
    /// next hand. Without it, a late tap at hand-end could expose a card
    /// in the *new* deal's hole cards because the index pushes onto the
    /// post-startHand seat. Optional on the wire so older builds still
    /// work; the server only enforces the match when the field is sent.
    func showCard(tableId: String, cardIndex: Int, handNumber: Int) {
        sendEvent("show_cards", data: [
            "tableId":    tableId,
            "cardIndex":  cardIndex,
            "handNumber": handNumber,
        ])
    }

    /// Requests a +15s extension on the active player's decision timer.
    /// The server is authoritative — it'll respond with a new
    /// `actionDeadline` in the next state update. Locally rate-limited to
    /// once per turn (see `GameViewModel.turnExtensionUsed`). Backend is
    /// expected to handle a `request_time_extension` event and only honor
    /// it for the active player.
    func requestTimeExtension(tableId: String) {
        sendEvent("request_time_extension", data: ["tableId": tableId])
    }

    func sendPing() {
        sendEvent("ping", data: [:])
    }

    // ─── Private: Socket.IO send ──────────────────────────────────────────────
    // Format: 42["event_name", {...data...}]

    private func sendEvent(_ event: String, data: [String: Any]) {
        let payload: [Any] = [event, data]
        guard let jsonData   = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webSocket?.send(.string("42" + jsonString)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.handleDisconnect(error.localizedDescription) }
            }
        }
    }

    // ─── Private: Receive loop ────────────────────────────────────────────────

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async { self.handleDisconnect(err.localizedDescription) }

            case .success(let message):
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d):   text = String(data: d, encoding: .utf8) ?? ""
                @unknown default:    text = ""
                }
                if !text.isEmpty {
                    DispatchQueue.main.async { self.handleRawMessage(text) }
                }
                self.startReceiving()
            }
        }
    }

    // ─── Private: Engine.IO / Socket.IO protocol ──────────────────────────────

    private func handleRawMessage(_ text: String) {
        // Engine.IO OPEN packet: "0{...}" — handshake, respond with Socket.IO CONNECT
        if text.first == "0" && !text.hasPrefix("40") {
            webSocket?.send(.string("40")) { _ in }
            startPing()
            return
        }

        // Socket.IO CONNECT confirmation: "40" or "40{...}" — ready to send events
        if text.hasPrefix("40") {
            isConnected = true
            if let tableId = currentTableId {
                sendEvent("join_table", data: ["tableId": tableId])
            }
            return
        }

        // Engine.IO PING from server: "2" — respond with PONG
        if text == "2" {
            webSocket?.send(.string("3")) { _ in }
            return
        }

        // Socket.IO EVENT: "42[...]"
        // Offload parsing + JSON decode to the serial background queue so
        // the main thread isn't doing decode work during animations. Order
        // is preserved by the queue's serial nature.
        guard text.hasPrefix("42") else { return }
        let payload = String(text.dropFirst(2))
        eventQueue.async { [weak self] in
            self?.parseSocketEvent(payload)
        }
    }

    private func parseSocketEvent(_ json: String) {
        guard let rawData    = json.data(using: .utf8),
              let array      = try? JSONSerialization.jsonObject(with: rawData) as? [Any],
              array.count   >= 2,
              let eventName  = array[0] as? String,
              let envelope   = array[1] as? [String: Any],
              let envData    = try? JSONSerialization.data(withJSONObject: envelope)
        else { return }

        switch eventName {
        case "game_state":
            if let gs = try? decoder.decode(WsEnvelope<ClientGameState>.self, from: envData) {
                gameStateSubject.send(gs.data)
            }

        case "player_action":
            if let pa = try? decoder.decode(WsEnvelope<PlayerActionEvent>.self, from: envData) {
                playerActionSubject.send(pa.data)
            }

        case "table_chat":
            if let cm = try? decoder.decode(WsEnvelope<ChatMessage>.self, from: envData) {
                chatSubject.send(cm.data)
            }

        case "hand_ended":
            struct HandEndedData: Decodable { let winners: [WinnerPayout]; let handNumber: Int }
            if let he = try? decoder.decode(WsEnvelope<HandEndedData>.self, from: envData) {
                handEndedSubject.send(he.data.winners)
            }

        case "player_reconnected", "player_left", "player_disconnected":
            struct PlayerEvent: Decodable { let userId: String; let username: String }
            if let pe = try? decoder.decode(WsEnvelope<PlayerEvent>.self, from: envData) {
                playerEventSubject.send((eventName, pe.data.userId))
            }

        case "your_chips_updated":
            if let cu = try? decoder.decode(WsEnvelope<ChipsUpdatedEvent>.self, from: envData) {
                chipsUpdatedSubject.send(cu.data)
            }

        case "kicked":
            kickedSubject.send("You were removed from the table")

        case "error":
            if let err = try? decoder.decode(WsEnvelope<WsErrorData>.self, from: envData) {
                errorSubject.send(err.data)
                // `lastError` is @Published — must be written on main so
                // SwiftUI's objectWillChange fires on the UI thread. The
                // subject above is consumed via .receive(on:) downstream
                // so it doesn't need this hop, but the direct property
                // write does.
                let message = err.data.message
                DispatchQueue.main.async { [weak self] in
                    self?.lastError = message
                }
            }

        case "pong":
            break

        default:
            break
        }
    }

    private func handleDisconnect(_ reason: String) {
        isConnected = false
        lastError   = reason
        webSocket   = nil
        pingTimer?.invalidate()
        pingTimer = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            guard !Task.isCancelled, let token = currentToken else { return }
            connect(token: token)
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.sendPing() }
        }
    }
}
