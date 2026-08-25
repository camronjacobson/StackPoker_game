import SwiftUI

// MAP: LegalDocumentView.swift
//   LegalDocument (enum)        L20  — case .terms / .privacy
//     .title                    L23
//     .lastUpdated              L29
//     .body                     L32
//   LegalDocumentView (View)    L210
//   termsBody (raw string)      L60
//   privacyBody (raw string)    L130

// In-app Terms of Service and Privacy Policy. Apple App Store Review
// Guideline 5.1.1 requires the privacy policy to be reachable from within
// the app; we keep both documents bundled so they render offline and the
// review team can verify the text without our marketing domain needing
// to be live. Operator details (contact email = camron.r.jacobson@gmail.com,
// governing-law state = California) are baked into the string literals
// below — update them in place if the business setup changes.

enum LegalDocument: String, Identifiable {
    case terms, privacy

    // Identifiable so SwiftUI's `.sheet(item:)` modifier can drive
    // presentation directly from an optional LegalDocument @State.
    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:   return "Terms of Service"
        case .privacy: return "Privacy Policy"
        }
    }

    // Bumped any time the body text changes. Surfaced in the document
    // header so users can tell when terms were last revised.
    var lastUpdated: String { "May 27, 2026" }

    var body: String {
        switch self {
        case .terms:   return Self.termsBody
        case .privacy: return Self.privacyBody
        }
    }

    // ─── Terms of Service ────────────────────────────────────────────────────
    // Apple-required EULA provisions are included in §11. If StackPoker™
    // later adopts Apple's standard EULA template wholesale, this section
    // can be replaced with a link to https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
    // and the corresponding URL set in App Store Connect.

    private static let termsBody = """
**Last updated: May 27, 2026**

These Terms of Service ("Terms") govern your access to and use of StackPoker™ (the "App"), a social poker game for iOS provided by StackPoker™ ("we", "us", "our"). By creating an account or using the App you agree to these Terms. If you do not agree, do not use the App.

**1. Eligibility**

You must be at least 17 years old to use the App. By using StackPoker™ you represent that you meet this age requirement. The App is not directed to children under 13 and we do not knowingly collect personal information from children under 13.

**2. Account**

To play, you create an account using Sign in with Apple, an email and password, or both. You are responsible for keeping your credentials secure and for all activity that occurs under your account. You agree to provide accurate information and not to impersonate any other person.

**3. Virtual Chips — No Real Money**

StackPoker™ is a social game for entertainment only. Chips, items, and other virtual goods in the App have no monetary value, cannot be exchanged for real money, goods, or services, and are not your property. You receive a limited, personal, non-transferable license to use them within the App. The App is not gambling. There are no cash prizes, no real-money wagers, and no real-money payouts under any circumstances.

**4. Purchases**

If we offer in-app purchases of chip bundles or premium items, all purchases are processed by Apple under the App Store terms. Purchases are non-refundable except as required by law or by Apple's refund policy. We may add, modify, or remove items at our discretion. Virtual goods you purchase are consumed within the App and have no value outside of it.

**5. Acceptable Use**

You agree not to: (a) cheat, collude with other players, exploit bugs, or use automation, bots, or unauthorized third-party software; (b) harass, threaten, dox, or send abusive, hateful, sexually explicit, or otherwise objectionable content via chat, display names, club names, or any other field; (c) impersonate another person or misrepresent any affiliation; (d) reverse engineer, decompile, or scrape the App except as expressly permitted by law; or (e) use the App for any unlawful purpose or in violation of these Terms.

**6. User Content**

You are responsible for content you submit, including your display name, avatar selection, chat messages, and any club names you create. You grant us a worldwide, royalty-free, non-exclusive license to host, store, reproduce, and display this content within the App as needed to operate the service. We may remove content, suspend accounts, or terminate access for violations of these Terms.

**7. Reporting and Moderation**

You can report abusive behavior in-app. We aim to review reports promptly but do not pre-screen every message or display name. We reserve the right to remove content and to suspend or terminate accounts at our sole discretion. Players who repeatedly violate these Terms will be removed from the service.

**8. Termination**

You may delete your account at any time from Settings or by contacting us at camron.r.jacobson@gmail.com. We may suspend or terminate your access for breach of these Terms or for any other reason at our reasonable discretion. Virtual chips associated with a terminated account are forfeited and not recoverable.

**9. Disclaimers**

THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED. WE DISCLAIM ALL WARRANTIES INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.

**10. Limitation of Liability**

TO THE MAXIMUM EXTENT PERMITTED BY LAW, STACKPOKER™ AND ITS AFFILIATES WILL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES, OR FOR ANY LOSS OF VIRTUAL CHIPS, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE APP, WHETHER BASED ON WARRANTY, CONTRACT, TORT, OR ANY OTHER LEGAL THEORY.

**11. Apple App Store Terms**

You acknowledge that these Terms are between you and StackPoker™ only — not with Apple Inc. ("Apple"). Apple is not responsible for the App or its content. Apple has no obligation to provide maintenance or support for the App. In the event of any failure of the App to conform to any applicable warranty, you may notify Apple, and Apple will refund the purchase price (if any). To the maximum extent permitted by law, Apple has no other warranty obligation whatsoever with respect to the App. Apple is not responsible for product claims, intellectual property infringement claims, or any third-party legal compliance. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you. You represent that (i) you are not located in a country subject to a U.S. government embargo or designated by the U.S. government as a "terrorist supporting" country, and (ii) you are not on any U.S. government list of prohibited or restricted parties.

**12. Changes**

We may update these Terms from time to time. We will update the "Last updated" date above and, for material changes, notify you in-app. Continued use of the App after changes take effect constitutes acceptance.

**13. Governing Law**

These Terms are governed by the laws of the State of California, United States, without regard to its conflicts-of-law principles.

**14. Contact**

Questions about these Terms? Reach us at camron.r.jacobson@gmail.com.
"""

    // ─── Privacy Policy ──────────────────────────────────────────────────────
    // Apple Review Guideline 5.1.1 requires explicit disclosure of: data
    // collected, purpose, third parties, retention, security, deletion
    // mechanism, and a contact channel. The structure below maps 1:1 onto
    // those requirements. Update the §1 inventory whenever a new field is
    // added to the User / TableSession / ChipTransaction Prisma models or
    // a new SDK with data access is integrated.

    private static let privacyBody = """
**Last updated: May 27, 2026**

This Privacy Policy describes how StackPoker™ ("we", "us") collects, uses, and discloses information when you use StackPoker™ (the "App").

**1. Information We Collect**

*Account information:* username (chosen by you), display name (visible to other players), email address (if you sign up by email), Apple ID identifier (if you use Sign in with Apple), a hashed form of your password (we never store your plaintext password), and the avatar you select from in-app icons. We do not upload photos from your device.

*Gameplay information:* the tables you join, hands you play, your chip balance and transaction history, friend connections you create in-app, chat messages you send at tables, clubs you join, and cosmetic items you equip.

*Device and diagnostic information:* app version, iOS version, crash logs, and basic session metadata used to diagnose problems.

*Automatically collected:* IP address (for security, rate limiting, and abuse prevention), standard server request logs, and your push notification token (only if you grant notification permission).

We do not collect contacts, location, photos, microphone, camera, or HealthKit data.

**2. How We Use Information**

We use the information above to operate the game (deal hands, persist chip balances, deliver chat, sync friends), to authenticate you and protect your account, to detect and prevent cheating, abuse, and fraud, to respond to support requests, and to send notifications about game events if you have opted in. We do not use your personal information for targeted advertising. We do not sell your personal information.

**3. How We Share Information**

We share information only as needed to run the service:

• *Other players* can see your display name, avatar, and gameplay at tables you share with them, and (if added) on their friends list.

• *Service providers* that host our servers, database, and push delivery, operating under data-processing agreements.

• *Apple,* for Sign in with Apple authentication and (if applicable) in-app purchase processing.

• *Legal compliance:* we may disclose information when required by law, subpoena, or to protect rights, safety, or property.

**4. Data Retention**

Account data is retained while your account is active. Hand history and chip transaction logs are retained for fraud prevention and game integrity audits, typically up to 24 months after the hand is played. Crash and security logs are retained up to 90 days. When you delete your account, personal identifiers are removed within 30 days of your request; aggregated or anonymized records may be retained.

**5. Your Choices and Rights**

• *Delete your account:* available in Settings within the App, or by emailing camron.r.jacobson@gmail.com.

• *Edit your display name and avatar:* in Settings → Profile.

• *Manage notifications:* in iOS Settings → StackPoker → Notifications.

• *Access or correct your data:* contact us at camron.r.jacobson@gmail.com.

If you reside in the EEA, the United Kingdom, or California, you may have additional rights including access, deletion, portability, and the right to object to certain processing. We will honor verified requests in line with applicable law (GDPR, UK GDPR, CCPA/CPRA).

**6. Children's Privacy**

StackPoker™ is not directed to children under 13 and we do not knowingly collect personal information from children under 13. If we learn that we have collected such information, we will delete it. If you believe a child has provided us information, please contact camron.r.jacobson@gmail.com.

**7. Security**

We use industry-standard technical and organizational safeguards including TLS encryption in transit, password hashing for stored credentials, and role-based access controls on our backend. No system is perfectly secure; you use the App at your own risk.

**8. International Data Transfers**

Our servers are operated in the United States. If you use the App from outside the U.S., your information may be transferred to and processed in the U.S.

**9. Third-Party Services**

The App relies on Apple services (Sign in with Apple, the App Store, and Apple Push Notification service). Apple's use of your information is governed by Apple's own privacy policy at https://www.apple.com/legal/privacy/.

**10. Changes**

We may update this Privacy Policy from time to time. We will update the "Last updated" date above and, for material changes, notify you in-app.

**11. Contact**

Questions about this Privacy Policy? Reach us at camron.r.jacobson@gmail.com.
"""
}

// ─── View ────────────────────────────────────────────────────────────────────
// Renders a LegalDocument as a scrollable page. Markdown is parsed via
// AttributedString so the bold headings (`**1. Eligibility**`) render
// inline without us having to hand-split the body into structured nodes.
// The view is its own NavigationStack root so it can be pushed from any
// caller — settings sheet, profile screen, or a future onboarding flow —
// without inheriting a parent's nav-bar styling.

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SPSpacing.md) {
                    Text(document.title)
                        .font(SPFonts.title(24))
                        .foregroundStyle(SPColors.textPrimary)
                        .padding(.bottom, SPSpacing.xs)

                    // AttributedString markdown parse with
                    // `inlineOnlyPreservingWhitespace` keeps the paragraph
                    // breaks (double-newlines) intact while still resolving
                    // inline bold/italic. Falls back to plain text on parse
                    // failure — should never trigger on our static strings,
                    // but the cost of try? is one extra View resolve.
                    Text(parsed(document.body))
                        .font(SPFonts.body(15))
                        .foregroundStyle(SPColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: SPSpacing.xl)
                }
                .padding(SPSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SPColors.background.ignoresSafeArea())
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SPColors.accent)
                }
            }
        }
    }

    private func parsed(_ markdown: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: opts))
            ?? AttributedString(markdown)
    }
}

#Preview("Terms")   { LegalDocumentView(document: .terms) }
#Preview("Privacy") { LegalDocumentView(document: .privacy) }
