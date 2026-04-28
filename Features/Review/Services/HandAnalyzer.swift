import Foundation

// ─── Hand Analyzer ────────────────────────────────────────────────────────────
// Heuristic analyzer that walks a `RecordedHand` and produces one
// `FrameAnalysis` per significant decision point. Messages are picked from
// variant pools seeded by (handId, frameIndex, callSiteTag) so replaying a
// hand is deterministic, but the phrasing varies both between frames of the
// same hand and between different hands. The language is plain English and
// improvement-oriented — jargon is expanded where possible.

enum HandAnalyzer {

    static func analyze(_ hand: RecordedHand) -> [FrameAnalysis] {
        var out: [FrameAnalysis] = []
        var preflopAggressorId: String? = nil
        var heroIsPreflopAggressor = false
        var raiseCountThisStreet = 0
        var currentStreet = "PREFLOP"

        // Opening note — sets the scene.
        if let first = hand.frames.first {
            let pos  = heroPositionLabel(in: first, userId: hand.userId)
            let chen = chenScore(hand.myHoleCards)
            let cls  = classify(chen: chen)
            let s = seed(hand, 0, 1)
            let hole = holeCardLabel(hand.myHoleCards)
            out.append(FrameAnalysis(
                id: UUID().uuidString,
                frameIndex: 0,
                title: "Dealt in · \(pos)",
                yourMove: nil,
                recommendation: nil,
                opponentRead: pick([
                    "You're holding \(hole) — a \(cls.label.lowercased()) starting hand. Let's see how it played out.",
                    "Dealt \(hole) in the \(pos.lowercased()) — that lands in the \(cls.label.lowercased()) tier. Here we go.",
                    "Your cards: \(hole). That's a \(cls.label.lowercased()) hand from \(pos.lowercased()). Let's walk through it.",
                ], seed: s),
                verdict: .info
            ))
        }

        for (i, frame) in hand.frames.enumerated() {
            // Reset per-street raise counter when the street advances
            if frame.street != currentStreet {
                raiseCountThisStreet = 0
                currentStreet = frame.street
                if i > 0, frame.street != "PREFLOP" {
                    let streetName = streetLabel(frame.street)
                    let strength = handStrengthLabel(hole: hand.myHoleCards, board: frame.communityCards).lowercased()
                    let s = seed(hand, i, 2)
                    out.append(FrameAnalysis(
                        id: UUID().uuidString,
                        frameIndex: i,
                        title: "\(streetName) is out",
                        yourMove: nil,
                        recommendation: nil,
                        opponentRead: pick([
                            "Board: \(boardLabel(frame.communityCards)). Your hand is now \(strength).",
                            "The \(streetName.lowercased()) brings \(boardLabel(frame.communityCards)) — that gives you \(strength).",
                            "\(streetName) card: \(boardLabel(frame.communityCards)). You've got \(strength) to work with.",
                        ], seed: s),
                        verdict: .info
                    ))
                }
            }

            guard let action = frame.lastAction else { continue }

            if action.action == "RAISE" || action.action == "ALL_IN" {
                raiseCountThisStreet += 1
                if frame.street == "PREFLOP", preflopAggressorId == nil {
                    preflopAggressorId = action.playerId
                    heroIsPreflopAggressor = (action.playerId == hand.userId)
                }
            }

            if action.playerId == hand.userId {
                let analysis = analyzeHeroAction(
                    hand: hand,
                    frame: frame,
                    action: action,
                    frameIndex: i,
                    raiseCountThisStreet: raiseCountThisStreet,
                    heroIsPreflopAggressor: heroIsPreflopAggressor
                )
                out.append(analysis)
            } else if let read = analyzeOpponentAction(
                hand: hand,
                frame: frame,
                action: action,
                frameIndex: i,
                raiseCountThisStreet: raiseCountThisStreet
            ) {
                out.append(read)
            }
        }

        // Closing summary frame
        if hand.frames.last != nil {
            let s = seed(hand, hand.frames.count - 1, 3)
            let result: String
            if hand.iWon {
                let amt = hand.winners.first(where: { $0.playerId == hand.userId })?.amount ?? 0
                let handName = hand.winningHandName ?? "the best hand"
                result = pick([
                    "Nice — you took down \(formatChips(amt)) with \(handName). Good work.",
                    "Pot to you: \(formatChips(amt)) with \(handName). Well played.",
                    "You scoop \(formatChips(amt)) with \(handName). That's the one.",
                ], seed: s)
            } else if let w = hand.winners.first {
                let name = w.handName.lowercased()
                result = pick([
                    "\(w.username) won \(formatChips(w.amount)) with \(name). Tough one — review the spots above and you'll catch it next time.",
                    "\(w.username) takes it with \(name) for \(formatChips(w.amount)). Look back at the decision points — that's where the edge hides.",
                    "\(w.username) wins \(formatChips(w.amount)) holding \(name). Don't sweat it — the lessons are in the hands you lose.",
                ], seed: s)
            } else {
                result = pick([
                    "Hand complete.",
                    "That's the hand.",
                    "End of hand.",
                ], seed: s)
            }
            out.append(FrameAnalysis(
                id: UUID().uuidString,
                frameIndex: hand.frames.count - 1,
                title: "Hand complete",
                yourMove: nil,
                recommendation: nil,
                opponentRead: result,
                verdict: .info
            ))
        }

        return out
    }

    // ─── Hero-action analysis ─────────────────────────────────────────────────

    private static func analyzeHeroAction(hand: RecordedHand,
                                          frame: ReplayFrame,
                                          action: PFAction,
                                          frameIndex: Int,
                                          raiseCountThisStreet: Int,
                                          heroIsPreflopAggressor: Bool) -> FrameAnalysis {
        let street = frame.street
        let isPreflop = (street == "PREFLOP")
        let chen = chenScore(hand.myHoleCards)
        let cls  = classify(chen: chen)
        let title = "\(streetLabel(street)) · You \(verbForAction(action))"
        let hole = holeCardLabel(hand.myHoleCards)
        let sA = seed(hand, frameIndex, 10)   // yourMove seed
        let sB = seed(hand, frameIndex, 11)   // recommendation seed

        // ── Preflop analysis ──────────────────────────────────────────────────
        if isPreflop {
            switch action.action {
            case "FOLD":
                if cls == .premium {
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "Folding \(hole) gives up a hand that wins more than its share long-term.",
                            "\(hole) is one of the strongest starting hands — folding it here is hard to justify.",
                            "Letting go of \(hole) preflop leaves real money on the table.",
                        ], seed: sA),
                        recommendation: pick([
                            "Strong hands like this should almost always be raising or re-raising. Lock in the value.",
                            "Build the pot with hands like this. They profit when the chips go in.",
                            "Premium holdings want action — raise for value and go from there.",
                        ], seed: sB),
                        opponentRead: nil,
                        verdict: .mistake
                    )
                }
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Folding the weaker hands here is exactly right — discipline pays off.",
                        "Good discipline. Folding \(cls.label.lowercased()) hands saves chips for better spots.",
                        "Fine fold. Not every hand needs to play — patience is a weapon.",
                    ], seed: sA),
                    recommendation: nil, opponentRead: nil, verdict: .fine
                )

            case "CALL":
                let priorRaises = raiseCountThisStreet
                if priorRaises == 0 {
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "Just calling the big blind (limping) lets the blinds see a cheap flop and gives away your initiative.",
                            "Limping in is usually a leak — you flatten the pot and lose the chance to win it right now.",
                            "Calling the blind instead of raising surrenders the lead before the flop even comes.",
                        ], seed: sA),
                        recommendation: pick([
                            "Either raise (about 3× the big blind) or fold. With \(hole), \(cls == .premium || cls == .strong ? "raising is easy" : "raising is the play in late position; otherwise prefer fold").",
                            "Pick a side: raise to define your hand, or fold and wait. Limping is rarely the best of the three.",
                            "Open with a raise or pass altogether. Limping leaves you stuck between plans.",
                        ], seed: sB),
                        opponentRead: nil,
                        verdict: .mistake
                    )
                }
                if priorRaises >= 2 {
                    if cls == .weak || cls == .marginal {
                        return FrameAnalysis(
                            id: UUID().uuidString, frameIndex: frameIndex, title: title,
                            yourMove: pick([
                                "Calling a re-raise with \(cls.label.lowercased()) hands tends to play badly — you'll often be second-best.",
                                "Flatting a 3-bet with these holdings puts you in tough spots after the flop.",
                                "These hands struggle against a re-raiser's range — you're usually behind and out of position.",
                            ], seed: sA),
                            recommendation: pick([
                                "Save the call for hands like 99–JJ, AQ, or suited broadways. With anything weaker, just fold.",
                                "Tighten up here. Fold most of the range and reserve calls for the hands that flop well.",
                                "Against a 3-bet, your calling range should be narrow — pairs, AQ, strong suited broadways.",
                            ], seed: sB),
                            opponentRead: nil,
                            verdict: .mistake
                        )
                    }
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "Calling a re-raise with \(cls.label.lowercased()) hands is reasonable when the price is right.",
                            "Defensible flat. \(cls.label) holdings can call a 3-bet when you have position or a deep stack.",
                            "Okay call — you've got enough hand to see a flop and evaluate from there.",
                        ], seed: sA),
                        recommendation: nil, opponentRead: nil, verdict: .fine
                    )
                }
                if cls == .weak {
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "Calling a raise with \(cls.label.lowercased()) hands rarely pays off — you're guessing postflop with the worst of it.",
                            "Cold-calling these hands burns chips over time — you flop strong rarely and bleed when you don't.",
                            "This is a loose call. Weak hands don't realize their equity after a raise.",
                        ], seed: sA),
                        recommendation: pick([
                            "Fold here. Calls add up. Save chips for spots where you have the better hand.",
                            "Pass and wait. The next hand is free.",
                            "Fold is the clean move. Pick your battles with hands that want to play big pots.",
                        ], seed: sB),
                        opponentRead: nil, verdict: .questionable
                    )
                }
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Standard call — \(cls.label.lowercased()) hands play fine here.",
                        "Clean flat. You've got enough to see a flop and take it from there.",
                        "Reasonable call with \(cls.label.lowercased()) holdings.",
                    ], seed: sA),
                    recommendation: nil, opponentRead: nil, verdict: .fine
                )

            case "CHECK":
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Free flop in the big blind — happy to take it.",
                        "Good — take the free look.",
                        "Checking the big blind when it's free is automatic.",
                    ], seed: sA),
                    recommendation: nil, opponentRead: nil, verdict: .fine
                )

            case "RAISE":
                let verdict: AnalysisVerdict
                let move: String
                let rec: String?
                switch cls {
                case .premium:
                    verdict = .correct
                    move = pick([
                        "Raising with \(hole) builds the pot with one of the best hands in poker. Textbook.",
                        "Easy raise. \(hole) wants to get chips in — you're doing exactly that.",
                        "Perfect. \(hole) plays big, and a raise here matches its strength.",
                    ], seed: sA)
                    rec = nil
                case .strong:
                    verdict = .correct
                    move = pick([
                        "Solid open with \(hole) — this hand profits over time when raised.",
                        "Good raise. \(hole) is a strong opener from most positions.",
                        "Clean open. \(hole) is a hand that wants to play, and a raise sets the tone.",
                    ], seed: sA)
                    rec = nil
                case .marginal:
                    verdict = .fine
                    move = pick([
                        "Opening \(hole) is okay, but it depends on your seat.",
                        "\(hole) is a position-sensitive open — fine from the right seat.",
                        "This is a borderline opener — playable, but not from every spot.",
                    ], seed: sA)
                    rec = pick([
                        "Late position (button/cutoff) — raise away. Early position — lean toward folding the bottom of this group.",
                        "From the button or cutoff this is standard. From under the gun, prefer to fold.",
                        "Position matters: in late, open freely. In early, tighten up and let marginal hands go.",
                    ], seed: sB)
                case .weak:
                    verdict = .questionable
                    move = pick([
                        "Raising \(hole) is on the loose side — these hands tend to lose money over many sessions.",
                        "This is a loose open. \(hole) doesn't profit enough to justify putting chips in first.",
                        "Opening hands like \(hole) drips chips over time — not a hand that wants to play big.",
                    ], seed: sA)
                    rec = pick([
                        "Tighten up your opening range. Pick stronger starting hands and you'll see steadier results.",
                        "Fold these and wait for better cards. A tighter range wins slower but wins.",
                        "Save the aggression for hands that can flop something worth defending.",
                    ], seed: sB)
                }
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: move, recommendation: rec, opponentRead: nil, verdict: verdict
                )

            case "ALL_IN":
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: cls == .premium
                        ? pick([
                            "Shoving \(hole) is fine, especially with a short stack — these hands love the all-in.",
                            "Fine shove. \(hole) is exactly the range that wants to get it in preflop.",
                            "No problem with the all-in — \(hole) plays great against almost any calling range.",
                          ], seed: sA)
                        : pick([
                            "Going all-in preflop with \(cls.label.lowercased()) hands is risky — usually only correct with a short stack (about 15 big blinds or fewer).",
                            "Preflop shoves want the top of your range. \(cls.label) hands rarely beat a caller's range.",
                            "Jamming \(hole) is aggressive — unless your stack is short, the risk outweighs the reward.",
                          ], seed: sA),
                    recommendation: cls == .premium ? nil
                        : pick([
                            "Save shoves for the very top of your range, or for short-stack situations where folding gives up too much.",
                            "Pick shove spots carefully — premiums, or when your stack is small enough that raise-call becomes all-in anyway.",
                            "All-in is the last tool. Use it with your best hands, or when you're short enough that smaller bets don't do anything.",
                          ], seed: sB),
                    opponentRead: nil,
                    verdict: cls == .premium ? .correct : .questionable
                )

            default:
                return infoFrame(at: frameIndex, title: title, text: "Posted blind.")
            }
        }

        // ── Postflop analysis ─────────────────────────────────────────────────

        let strengthLabel = handStrengthLabel(hole: hand.myHoleCards, board: frame.communityCards)
        let strength = postflopStrength(hole: hand.myHoleCards, board: frame.communityCards)
        let strLow = strengthLabel.lowercased()

        switch action.action {
        case "FOLD":
            if strength == .premium {
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Folding \(strLow) leaves a lot of value on the table.",
                        "\(strengthLabel) is way too strong to fold here.",
                        "Letting go of \(strLow) gives up chips you'd normally be winning.",
                    ], seed: sA),
                    recommendation: pick([
                        "Strong made hands rarely fold profitably. Bet or raise — get the money in while you're ahead.",
                        "Play it forward. Bet for value and make opponents pay to see the next card.",
                        "This is a value-betting hand. Keep building the pot until someone slows you down.",
                    ], seed: sB),
                    opponentRead: nil, verdict: .mistake
                )
            }
            return FrameAnalysis(
                id: UUID().uuidString, frameIndex: frameIndex, title: title,
                yourMove: pick([
                    "Folding with \(strLow) is the disciplined call. Saved chips count too.",
                    "Fine fold. When your hand isn't strong enough, walking away is the right play.",
                    "Good release. Folding weak holdings is how you preserve your stack for better spots.",
                ], seed: sA),
                recommendation: nil, opponentRead: nil, verdict: .fine
            )

        case "CHECK":
            if strength == .premium {
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Checking \(strLow) gives opponents a free card on a draw-heavy board.",
                        "Slow-playing here is risky — the board changes and you might lose the lead.",
                        "Checking a strong hand lets opponents catch up for free.",
                    ], seed: sA),
                    recommendation: pick([
                        "Bet for value. Opponents may call with weaker pairs or chase draws — let them pay.",
                        "Put out a bet. Even a small one charges draws and gets value from worse hands.",
                        "Lead out. Draws need to pay to hit, and worse made hands will often call.",
                    ], seed: sB),
                    opponentRead: nil, verdict: .questionable
                )
            }
            return FrameAnalysis(
                id: UUID().uuidString, frameIndex: frameIndex, title: title,
                yourMove: pick([
                    "Checking with \(strLow) keeps the pot small — sensible when you're not sure.",
                    "Good pot control. Checking marginal hands avoids bloating pots you don't want big.",
                    "Reasonable check. You stay in the hand without committing more chips.",
                ], seed: sA),
                recommendation: nil, opponentRead: nil, verdict: .fine
            )

        case "CALL":
            let toCall = action.amount ?? 0
            let potBeforeCall = max(0, frame.pot - toCall)
            let oddsRequired: Double = toCall > 0
                ? Double(toCall) / Double(potBeforeCall + toCall + toCall)
                : 0
            let estEquity = estimatedEquity(strength: strength, street: street)
            if toCall > 0 {
                if estEquity + 0.03 < oddsRequired {
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "You'd need to win about \(percent(oddsRequired)) of the time, but \(strLow) only wins around \(percent(estEquity)) here.",
                            "The price says \(percent(oddsRequired)) to break even — \(strLow) is closer to \(percent(estEquity)). That gap costs chips.",
                            "To call profitably you'd want \(percent(oddsRequired)) equity; this hand is more like \(percent(estEquity)).",
                        ], seed: sA),
                        recommendation: pick([
                            "Fold. The math says this call loses chips on average.",
                            "Let it go. You don't have the hand or the odds to continue.",
                            "Pass. When the price is worse than your equity, fold every time.",
                        ], seed: sB),
                        opponentRead: nil, verdict: .mistake
                    )
                }
                if estEquity > oddsRequired + 0.10 {
                    return FrameAnalysis(
                        id: UUID().uuidString, frameIndex: frameIndex, title: title,
                        yourMove: pick([
                            "Easy call. You only need \(percent(oddsRequired)) to break even and your hand is closer to \(percent(estEquity)).",
                            "Great price. \(percent(oddsRequired)) to call with \(percent(estEquity)) equity is a clear win over time.",
                            "The odds fit. Getting \(percent(oddsRequired)) when you have \(percent(estEquity)) is a profitable call.",
                        ], seed: sA),
                        recommendation: nil, opponentRead: nil, verdict: .correct
                    )
                }
            }
            return FrameAnalysis(
                id: UUID().uuidString, frameIndex: frameIndex, title: title,
                yourMove: pick([
                    "Calling with \(strLow) is fine — close spot, defensible either way.",
                    "Standard call. The spot is borderline but your hand does enough.",
                    "Okay call. Not a lock either way, but the line holds up.",
                ], seed: sA),
                recommendation: nil, opponentRead: nil, verdict: .fine
            )

        case "RAISE", "ALL_IN":
            switch strength {
            case .premium, .strong:
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Strong bet with \(strLow). Build the pot while you're ahead.",
                        "Good raise. \(strengthLabel) is a clear value hand — charge the draws.",
                        "Bet for value. \(strLow) is ahead of most calling hands — get the chips in.",
                    ], seed: sA),
                    recommendation: nil, opponentRead: nil, verdict: .correct
                )
            case .draw:
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Nice semi-bluff with a \(strLow) — they might fold, and if they call you can still hit.",
                        "Good aggression. A \(strLow) has two ways to win: fold equity now, card equity later.",
                        "Solid semi-bluff. Bets with a draw put pressure on and keep outs alive.",
                    ], seed: sA),
                    recommendation: pick([
                        "Aim for 60–75% of the pot — big enough to pressure, small enough to keep weaker hands in.",
                        "Size between half and three-quarter pot. That's the sweet spot for semi-bluffs.",
                        "Keep the sizing moderate — you want folds, but you also want to get called when your draw hits.",
                    ], seed: sB),
                    opponentRead: nil, verdict: .correct
                )
            case .medium:
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Raising a medium hand turns it into a bluff and only gets called by stronger stuff.",
                        "Raising here folds out worse hands and keeps the hands that beat you — that's backwards.",
                        "Medium hands don't want to raise — they want to showdown cheaply.",
                    ], seed: sA),
                    recommendation: pick([
                        "Calling and seeing the next card is usually safer unless you have a strong read.",
                        "Call and reassess. Keep the pot manageable and let the next street tell the story.",
                        "Prefer a flat. Medium hands win more by showing down than by pushing.",
                    ], seed: sB),
                    opponentRead: nil, verdict: .questionable
                )
            case .weak, .air:
                return FrameAnalysis(
                    id: UUID().uuidString, frameIndex: frameIndex, title: title,
                    yourMove: pick([
                        "Bluffing with \(strLow) without a clear story rarely works long-term.",
                        "This is a tough bluff — the board doesn't support a believable strong hand.",
                        "Aggression without a story gets picked off over time.",
                    ], seed: sA),
                    recommendation: pick([
                        "Pick bluffing spots where you'd have a strong hand if a key card hit — those tell a believable story.",
                        "Save bluffs for runouts where your range has real nuts. Random bluffs get called down.",
                        "Bluff where the board favors your range — that's where fold equity actually exists.",
                    ], seed: sB),
                    opponentRead: nil, verdict: .questionable
                )
            }

        default:
            return infoFrame(at: frameIndex, title: title, text: action.action.capitalized)
        }
    }

    // ─── Opponent-action reads ────────────────────────────────────────────────

    private static func analyzeOpponentAction(hand: RecordedHand,
                                              frame: ReplayFrame,
                                              action: PFAction,
                                              frameIndex: Int,
                                              raiseCountThisStreet: Int) -> FrameAnalysis? {
        // Skip blinds — they're forced and uninteresting
        if action.action == "SMALL_BLIND" || action.action == "BIG_BLIND" { return nil }

        let title  = "\(streetLabel(frame.street)) · \(action.username) \(verbForAction(action))"
        let street = frame.street
        let s      = seed(hand, frameIndex, 20)
        let name   = action.username
        let read: String?

        switch (street, action.action) {
        case ("PREFLOP", "RAISE") where raiseCountThisStreet == 1:
            read = pick([
                "Standard open. From early seats they're tight; from the button or cutoff, much wider.",
                "Looks like a regular open. Expect a tighter range from early position, looser from late.",
                "\(name)'s opening range depends on their seat — premiums early, a wider set from late position.",
            ], seed: s)
        case ("PREFLOP", "RAISE") where raiseCountThisStreet >= 2:
            read = pick([
                "Re-raising represents real strength — usually big pairs (QQ+) and AK, sometimes a bluff.",
                "A 3-bet narrows their range fast — think queens or better, ace-king, occasionally a bluff.",
                "\(name) is showing strength. Their re-raising range is mostly premium pairs and big aces.",
            ], seed: s)
        case ("PREFLOP", "ALL_IN"):
            read = pick([
                "All-in preflop is almost always a top hand — QQ+ and AK at deep stacks, slightly wider when short.",
                "Preflop shoves are weighted toward the top of the range. With deep stacks, it's almost all premiums.",
                "\(name)'s jamming range is tight — big pairs and ace-king lead it.",
            ], seed: s)
        case ("PREFLOP", "CALL") where raiseCountThisStreet >= 1:
            read = pick([
                "Just calling often means a hand that wants to see a flop cheaply — small pairs or suited connectors looking to flop a monster.",
                "Flatting after a raise usually hides small pairs and suited connectors hoping to hit big.",
                "\(name)'s flat-call range is the 'set-mining' kind — pairs and suited hands that flop well.",
            ], seed: s)
        case ("PREFLOP", "FOLD"):
            return nil

        case ("FLOP", "RAISE"), ("TURN", "RAISE"), ("RIVER", "RAISE"):
            if raiseCountThisStreet >= 2 {
                read = pick([
                    "A raise on top of a bet is a strong move — usually a real hand, occasionally a well-timed bluff.",
                    "Raising over a bet is weighted toward value. Bluffs show up here, but not often.",
                    "When \(name) raises a bet, respect it. Their range skews toward strong made hands.",
                ], seed: s)
            } else {
                read = pick([
                    "Could be a value bet or a continuation bet. Watch the size: big = strong or pure bluff, small = protective.",
                    "Standard bet. The sizing tells the story — bigger bets are polarized, smaller ones usually protect a medium hand.",
                    "\(name)'s bet could be many things. Read the size: large bets mean strength or bluff, small bets mean 'I have something'.",
                ], seed: s)
            }
        case ("FLOP", "CALL"), ("TURN", "CALL"), ("RIVER", "CALL"):
            read = pick([
                "Calling without raising suggests a middling hand or a draw. Their range gets clearer with each street.",
                "A call keeps their range wide — medium pairs, draws, floats. Later streets narrow it down.",
                "\(name) is playing passively — usually a hand that wants to see more cards but isn't ready to bet.",
            ], seed: s)
        case (_, "ALL_IN"):
            read = pick([
                "All-in postflop is usually a very strong hand or a pure bluff. Stack sizes vs. pot tell you which is more likely.",
                "Postflop jams are polarized — monster or air. The stack-to-pot ratio hints at which.",
                "When \(name) shoves postflop, it's rarely marginal — expect strength or a pure bluff.",
            ], seed: s)
        case (_, "CHECK"):
            read = pick([
                "A check after leading earlier can mean giving up, controlling the pot, or trapping. Their next bet sizes will reveal more.",
                "Check could be give-up or slow-play. Watch the next action closely.",
                "\(name) is pausing — could be weak, could be strong. The following street's action will tell.",
            ], seed: s)
        case (_, "FOLD"):
            return nil
        default:
            read = nil
        }

        guard let read else { return nil }

        return FrameAnalysis(
            id: UUID().uuidString,
            frameIndex: frameIndex,
            title: title,
            yourMove: nil,
            recommendation: nil,
            opponentRead: read,
            verdict: .info
        )
    }

    // ─── Variant helpers ──────────────────────────────────────────────────────

    /// Deterministic but hand-specific seed. Same hand + same frame + same
    /// callsite always yields the same pick, so a replay is stable. Different
    /// hands / frames get different picks.
    private static func seed(_ hand: RecordedHand, _ frame: Int, _ tag: Int) -> Int {
        var h = hand.id.hashValue
        h = h &* 31 &+ frame
        h = h &* 31 &+ tag
        return h
    }

    private static func pick(_ variants: [String], seed: Int) -> String {
        guard !variants.isEmpty else { return "" }
        return variants[abs(seed) % variants.count]
    }

    // ─── Hole-card classification (Chen formula) ──────────────────────────────

    enum PreflopClass: String { case premium, strong, marginal, weak
        var label: String {
            switch self {
            case .premium:  return "Premium"
            case .strong:   return "Strong"
            case .marginal: return "Marginal"
            case .weak:     return "Weak"
            }
        }
    }

    static func classify(chen: Double) -> PreflopClass {
        switch chen {
        case 12...:      return .premium
        case 9..<12:     return .strong
        case 7..<9:      return .marginal
        default:         return .weak
        }
    }

    static func chenScore(_ hole: [PFCard]) -> Double {
        guard hole.count == 2 else { return 0 }
        let r0 = rankValue(hole[0].rank)
        let r1 = rankValue(hole[1].rank)
        let high = max(r0, r1), low = min(r0, r1)

        func chenRank(_ v: Int) -> Double {
            switch v {
            case 14: return 10
            case 13: return 8
            case 12: return 7
            case 11: return 6
            case 10: return 5
            default: return Double(v) / 2.0
            }
        }

        var score: Double
        if r0 == r1 {
            score = max(5, chenRank(high) * 2)
        } else {
            score = chenRank(high)
            if hole[0].suit == hole[1].suit { score += 2 }
            let gap = high - low - 1
            switch gap {
            case 0:   break
            case 1:   score -= 1
            case 2:   score -= 2
            case 3:   score -= 4
            default:  score -= 5
            }
            if gap <= 1 && high < 12 { score += 1 }
        }
        return ceil(score)
    }

    // ─── Postflop strength categorisation ─────────────────────────────────────

    enum PostflopStrength: String {
        case premium, strong, medium, draw, weak, air
    }

    static func postflopStrength(hole: [PFCard], board: [PFCard]) -> PostflopStrength {
        guard hole.count == 2, board.count >= 3 else { return .air }
        let label = handStrengthLabel(hole: hole, board: board).lowercased()
        if label.contains("flush") && !label.contains("draw") { return .premium }
        if label.contains("straight") && !label.contains("draw") { return .premium }
        if label.contains("four")     { return .premium }
        if label.contains("full")     { return .premium }
        if label.contains("three of") { return .premium }
        if label.contains("two pair") { return .premium }

        if label.contains("flush draw") || label.contains("straight draw") { return .draw }

        if label.contains("one pair") {
            let topRank = board.map { rankValue($0.rank) }.max() ?? 0
            let pairedHigh = hole.contains { rankValue($0.rank) == topRank }
            let pairedHole = hole.contains { c in board.contains { $0.rank == c.rank } }
            if pairedHigh {
                let kicker = hole.first { rankValue($0.rank) != topRank }.map { rankValue($0.rank) } ?? 0
                return kicker >= 12 ? .strong : .medium
            }
            if hole[0].rank == hole[1].rank {
                let pairVal = rankValue(hole[0].rank)
                if pairVal > topRank { return .strong }
                return .medium
            }
            return pairedHole ? .medium : .weak
        }

        if hole.contains(where: { $0.rank == "A" }) { return .weak }
        return .air
    }

    static func estimatedEquity(strength: PostflopStrength, street: String) -> Double {
        switch (strength, street) {
        case (.premium, _):   return 0.85
        case (.strong, "FLOP"):  return 0.70
        case (.strong, "TURN"):  return 0.72
        case (.strong, "RIVER"): return 0.78
        case (.medium, "FLOP"):  return 0.45
        case (.medium, "TURN"):  return 0.42
        case (.medium, "RIVER"): return 0.38
        case (.draw,   "FLOP"):  return 0.32
        case (.draw,   "TURN"):  return 0.18
        case (.draw,   "RIVER"): return 0.00
        case (.weak,   "FLOP"):  return 0.20
        case (.weak,   "TURN"):  return 0.15
        case (.weak,   "RIVER"): return 0.10
        case (.air,    _):       return 0.06
        default:                 return 0.20
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static func rankValue(_ r: String) -> Int {
        switch r {
        case "A": return 14
        case "K": return 13
        case "Q": return 12
        case "J": return 11
        case "T": return 10
        default:  return Int(r) ?? 0
        }
    }

    private static func streetLabel(_ s: String) -> String {
        switch s {
        case "PREFLOP":  return "Preflop"
        case "FLOP":     return "Flop"
        case "TURN":     return "Turn"
        case "RIVER":    return "River"
        case "SHOWDOWN": return "Showdown"
        default:         return s.capitalized
        }
    }

    private static func verbForAction(_ a: PFAction) -> String {
        switch a.action {
        case "FOLD":  return "folded"
        case "CHECK": return "checked"
        case "CALL":  return a.amount.map { "called \(formatChips($0))" } ?? "called"
        case "RAISE": return a.amount.map { "raised to \(formatChips($0))" } ?? "raised"
        case "ALL_IN": return "shoved all-in"
        default: return a.action.lowercased()
        }
    }

    private static func holeCardLabel(_ hole: [PFCard]) -> String {
        guard hole.count == 2 else { return "?" }
        let suited = hole[0].suit == hole[1].suit ? "s" : "o"
        let r0 = rankValue(hole[0].rank), r1 = rankValue(hole[1].rank)
        let hi = r0 >= r1 ? hole[0] : hole[1]
        let lo = r0 >= r1 ? hole[1] : hole[0]
        if hole[0].rank == hole[1].rank { return "\(hi.rank)\(lo.rank)" }
        return "\(hi.rank)\(lo.rank)\(suited)"
    }

    private static func boardLabel(_ board: [PFCard]) -> String {
        board.map { "\($0.rank)\($0.suit.lowercased())" }.joined(separator: " ")
    }

    private static func percent(_ d: Double) -> String {
        "\(Int((d * 100).rounded()))%"
    }

    static func handStrengthLabel(hole: [PFCard], board: [PFCard]) -> String {
        let liveHole  = hole.map { $0.live }
        let liveBoard = board.map { $0.live }
        return HandStrength.label(hole: liveHole, board: liveBoard) ?? "High Card"
    }

    private static func heroPositionLabel(in frame: ReplayFrame, userId: String) -> String {
        guard let mySeat = frame.seats.first(where: { $0.userId == userId }) else { return "Hero" }
        let seatCount = frame.seats.count
        let dealerIdx = frame.dealerSeatIndex
        let distance = ((mySeat.seatIndex - dealerIdx) + seatCount) % seatCount
        switch (seatCount, distance) {
        case (_, 0):                return "Button"
        case (_, 1):                return "Small Blind"
        case (_, 2):                return "Big Blind"
        case (3, _):                return "Late Position"
        case (let n, let d) where d == n - 1: return "Cutoff"
        case (let n, let d) where d == n - 2: return "Hijack"
        default:                    return "Middle Position"
        }
    }

    private static func infoFrame(at index: Int, title: String, text: String) -> FrameAnalysis {
        FrameAnalysis(
            id: UUID().uuidString, frameIndex: index, title: title,
            yourMove: nil, recommendation: nil, opponentRead: text,
            verdict: .info
        )
    }
}
