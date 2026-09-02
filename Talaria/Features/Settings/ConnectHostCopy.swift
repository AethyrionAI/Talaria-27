import Foundation

/// Every user-visible string on the Connect Host surfaces, in one place
/// (#309 Lane B).
///
/// **Why a copy file rather than literals in the views.** Two surfaces — the
/// wizard and the Settings screen — render the same eight states, and the
/// whole point of Owen's design is that a state's NAME is the same wherever
/// the user meets it. Split across two view files, the vocabulary drifts by
/// one careless edit; here, a drift is a diff.
///
/// **This is also the #180 convention's home (Owen's ruling, 2026-08-25).**
/// The state vocabulary the umbrella spent a year looking for is enumerated
/// below; #180's register names this file as the standard members migrate to.
///
/// **⚠️ 2026-09-01 — THE TITLE LINE ABOVE IS NO LONGER THE WHOLE TRUTH.** These
/// constants stopped being "the Connect Host surfaces' strings" the moment the
/// first member migrated: the 180-CONVENTION lane routed the three host-fed
/// list screens (Skills / Tasks / Insights) onto `NO ANSWER`, `KEY TURNED
/// DOWN`, `NOT HERMES` and `RUNNING LOCALLY` through
/// `Talaria/Core/HostFailurePresentation.swift`, which reads them from HERE
/// rather than re-spelling them. So an edit below now changes words on five
/// surfaces, not two — and that is the point of the ruling, not a leak from
/// it. A copy file whose stated scope is narrower than its real one is the
/// next reader's trap, which is why this note exists rather than a rename.
/// The reach is pinned by
/// `HostFailureConventionTests.everyFailureNameComesFromTheConnectHostVocabulary`,
/// which reads both files and fails if the two spellings ever diverge.
///
/// ### The vocabulary
/// 1. **MEASURED OR NAMED-AS-UNMEASURED.** Every status is something the app
///    watched happen (`REACHABLE · 18MS`, `LAST ANSWERED 7:32 AM`) or is
///    labelled `NOT CHECKED`. There is no third option; a guess wearing a
///    green pip is the defect #180 was filed for.
/// 2. **SAVED ≠ REACHABLE.** Holding credentials and being answerable are two
///    facts with two labels. A host that stops answering is `NOT ANSWERING`,
///    still saved, and the disconnect action stays truthful offline.
/// 3. **EMPTY IS NOT AN ERROR.** "No host" names the current answer
///    (`RUNNING LOCALLY · ON-DEVICE BRAIN`) instead of rendering a failure
///    surface for a state the user chose.
/// 4. **FAILURES ARE NAMED PER CHECK.** A ladder of real discriminations, so
///    a card can point at the rung that broke — never a bare "failed", never
///    an HTTP code quoted at a human.
/// 5. **THE GUILTY FIELD, AND ONLY IT.** A failure re-offers one input and
///    leaves the others alone, with the measurement that exonerates them.
/// 6. **NO CLAIM THE CODE CANNOT VERIFY.** Storage claims, not encryption
///    claims; tier claims that survive the tier's own escape hatches.
enum ConnectHostCopy {

    // Every string below is ON a surface. Six were removed before merge
    // for failing exactly that: duplicate spellings of lines the views
    // already render from another constant. A copy file whose entries no
    // reader can reach is a second vocabulary drifting beside the first.

    // MARK: Wizard — step 0, the choice (design A1)

    static let wizardTitle = "TALARIA"
    static let wizardSubtitle = "READY TO CHAT · NO SETUP DONE"

    static let localOptionTitle = "START LOCALLY"
    static let localOptionBadge = "RECOMMENDED"

    /// **The falsehood the fact-check caught, corrected (spec §4.1).**
    ///
    /// The design read *"Chat, photos, and the device tool belt run on this
    /// phone. No account, no host, nothing leaves the device."* The last
    /// clause is FALSE while Private Cloud β is electable: that tier sends the
    /// request — and since #390 attached images — to Apple's Private Cloud
    /// Compute. This is the #385 tier-honesty class, and the privacy policy
    /// published against the same fact.
    ///
    /// The constraint the replacement had to meet: **no absolute
    /// nothing-leaves claim while PCC is electable.** The rest of the
    /// sentence — no account, no host — is true and stays.
    static let localOptionBlurb =
        "Chat, photos, and the device tool belt run on this phone — or Apple's Private Cloud when you pick that model. No account. No host."
    static let localOptionFootnote = "ONE TAP · LANDS IN CHAT"

    static let hostOptionTitle = "CONNECT MY HOST"
    static let hostOptionBlurb =
        "Adds your own agent, your desktop models, and server sessions. Needs a Hermes machine on your private network."
    static let hostOptionFootnote = "TWO VALUES · SCAN OR TYPE"

    static let localIsNotATrial =
        "Local isn't a trial. Connecting is an upgrade you can make any time from Settings."

    /// On every step, per the ruling and design B7. Taking it lands in plain
    /// chat: no banner, no nag, no empty host slot.
    static let notNow = "Not now"

    // MARK: Wizard — step 1, connect (design A2/A3)

    static let scanTitle = "SCAN YOUR HOST"
    static let scanBlurb =
        "Run hermes talaria pair-qr on your Hermes machine. It prints a code in the terminal."
    static let openScanner = "OPEN SCANNER"
    static let enterManually = "Enter it manually"
    static let enterManuallyDetail = "GATEWAY URL + API KEY"
    static let scanSecrecyFootnote =
        "THE CODE CARRIES YOUR HOST'S ADDRESS AND KEY. TREAT IT LIKE A PASSWORD."
    static let scanInstead = "Scan the code instead"

    static let gatewayFieldLabel = "GATEWAY URL"
    static let gatewayFieldPlaceholder = "http://your-host:8642"
    static let gatewayFieldHelp =
        "The address your Hermes gateway listens on — usually port 8642."

    static let keyFieldLabel = "API KEY"
    static let keyFieldPlaceholder = "Your host's API key"
    static let keyRevealPrompt = "TAP TO REVEAL"
    static let keyNotStored = "NOT STORED YET"
    static let keyNeedsAttention = "API KEY · NEEDS ATTENTION"
    /// A STORAGE claim, deliberately — see vocabulary rule 6.
    static let keyFieldHelp =
        "Your host's API_SERVER_KEY. Stored in this device's Keychain."
    static let keyFieldHelpSettings =
        "Kept in this device's Keychain. Never shown in full again."
    static let keyFieldHelpRetype =
        "It's the API_SERVER_KEY your host reads at startup."
    static let keyFieldHelpScanHint =
        "Your host prints it with hermes talaria pair-qr if it's easier to scan."

    static let checkAndConnect = "CHECK & CONNECT"
    static let checkAgain = "CHECK AGAIN"
    static let tryAgain = "TRY AGAIN"
    static let nothingSavedUntilCheckPasses = "Nothing is saved until the check passes."
    static let savedOnlyIfTheHostAnswers = "Saved only if the host answers and takes the key."
    static let bothValuesNeeded = "Both values are needed before the check can run."

    static let addressNeedsScheme = "The address needs to start with http:// or https://."
    static let addressNotAURL = "That doesn't look like a host address — try http://your-host:8642."

    // MARK: The ladder (design A4, and every failure card)

    static let checkingTitle = "CHECKING THE HOST"
    static let checkReachable = "Address reachable"
    static let checkKey = "Checking the key"
    static let checkKeyResult = "Key accepted"
    static let checkHermes = "Confirming it's a Hermes gateway"
    static let checkHermesResult = "A Hermes gateway"
    /// The number in this sentence and `BootstrapProbeSession.requestTimeout`
    /// are ONE fact. Move one, move the other.
    static let fiveSecondsAtMost = "Five seconds at most. Cancel and edit if you mistyped."
    static let cancel = "Cancel"

    // MARK: Failures (design B4/B5/B6, and settings B1)

    static let noAnswerTitle = "NO ANSWER"
    static let noAnswerHeadline = "Nothing answered at that address"
    static let noAnswerBlurb =
        "The phone waited five seconds and heard nothing back. The machine may be asleep, or your private network may not reach it right now."

    static let keyRefusedTitle = "KEY TURNED DOWN"
    static let keyRefusedHeadline = "The host is there — the key isn't right"
    static func keyRefusedBlurb(host: String, milliseconds: Int) -> String {
        "\(host) answered in \(milliseconds)ms and then refused this key. Copy it again from the host and retype it; the address is fine."
    }

    static let notHermesTitle = "NOT HERMES"
    static let notHermesHeadline = "Something's there, but it isn't Hermes"
    static let notHermesBlurb =
        "That port answered with something else. Check the port number — the gateway usually listens on 8642."
    static let notHermesFieldHint = "Try :8642 — the port hermes gateway run opens."

    static let keepChattingLocally = "Keep chatting locally for now"
    /// The measured claim bar 309-B4 exists to make true.
    static let nothingWasSaved = "NOTHING WAS SAVED. YOU ARE STILL ON-DEVICE."

    // MARK: Connected (design A5/A6, settings A4)

    static let hostConnectedTitle = "HOST CONNECTED"
    static let hostConnectedBlurb = "Your agent is answering on this phone."
    static let keyAcceptedInKeychain = "ACCEPTED · IN KEYCHAIN"
    static let keyInKeychain = "IN KEYCHAIN"
    static let addressRowLabel = "ADDRESS"
    static let keyRowLabel = "KEY"
    static let modelsSeenLabel = "MODELS SEEN"
    static let lastAnsweredLabel = "LAST ANSWERED"
    static let neverAnswered = "NOT CHECKED"
    static let checkNow = "Check now"
    static let editAddress = "Edit address"
    static let nameThisHost = "Name this host"
    static let carryOn = "CONTINUE"

    static let doneTitleTop = "YOU'RE"
    static let doneTitleBottom = "CONNECTED"
    static func doneBlurb(host: String) -> String {
        "\(host) is answering. Your desktop models are in the picker, and sessions now live on the host."
    }
    static let donePickModel = "Pick a desktop model any time"
    static let donePickModelTag = "MODELS"
    /// **Corrected against the real setting (spec §4.3).** The design said
    /// "Phone context stays off until you allow it"; the toggle it points at
    /// is Settings → Privacy → **Share Sensors with Hermes**, so the sentence
    /// now names what the user will actually find.
    static let doneSensors = "Sensor sharing stays off until you turn it on"
    static let doneSensorsTag = "PRIVACY"
    static let doneAddAnother = "Add another machine later"
    static let doneAddAnotherTag = "HOSTS"
    static let doneWhereItLives =
        "All of this lives in Settings → Connect Host — edit the address, swap the key, or disconnect there."
    static let startChatting = "START CHATTING"

    /// **Replaces `END-TO-END ENCRYPTED · DEVICE-BOUND KEY`** (design doc §6,
    /// bar 309-B7). The old footnote made an ENCRYPTION claim about a
    /// transport the app does not encrypt — it speaks plain HTTP to a
    /// tailnet address and lets Tailscale carry the confidentiality — and
    /// "device-bound" described a relay-minted credential that no longer
    /// exists. Both halves of the replacement are things this build does and a
    /// reader can check: the key is written to the Keychain, and it is
    /// attached to requests for the profile's own gateway and nowhere else.
    static let keyFootnote = "KEY HELD IN THIS DEVICE'S KEYCHAIN · SENT ONLY TO YOUR HOST"

    // MARK: Settings screen (design A1–A4, B1–B4)

    static let screenTitle = "Connect Host"
    static let statusNoHost = "NO HOST CONNECTED"
    static let statusNotChecked = "NOT CHECKED YET"
    static let statusChecking = "CHECKING…"
    static func statusConnected(host: String) -> String { "\(host.uppercased()) · CONNECTED" }
    static func statusNotAnswering(host: String) -> String { "\(host.uppercased()) · NOT ANSWERING" }
    static let statusCheckFailedKey = "CHECK FAILED · KEY"
    static let statusCheckFailedAddress = "CHECK FAILED · ADDRESS"
    static func statusHostCount(_ count: Int, active: String) -> String {
        "\(count) HOSTS · \(active.uppercased()) IN USE"
    }

    static let runningLocallyTitle = "RUNNING LOCALLY"
    /// Rule 3: the empty state NAMES the current answer.
    static let runningLocallyBlurb = "ON-DEVICE BRAIN · NOTHING TO CONNECT TO"
    static let scanHostCode = "SCAN HOST CODE"
    static let orTypeThem = "OR TYPE THEM"
    static let scanAHostCodeInstead = "Scan a host code instead"

    static let onYourHostHeader = "// ON YOUR HOST"
    static let onYourHostCommandOne = "hermes gateway run"
    static let onYourHostCommandTwo = "hermes talaria pair-qr"
    static let onYourHostBlurb =
        "The first starts the gateway. The second prints a code with both values in it."

    static let whatThisHostGives = "// WHAT THIS HOST GIVES YOU"
    static let desktopModelsRow = "Desktop models"
    static let serverSessionsRow = "Server sessions"
    static let serverSessionsOn = "ON"
    /// Reads the real `Share Sensors with Hermes` setting — see `doneSensors`.
    static let sensorSharingRow = "Share sensors"
    static let sensorSharingOff = "OFF · YOUR CHOICE"
    static let sensorSharingOn = "ON"

    static let stillSavedBlurb =
        "Still saved, just not reachable right now. Chat is answering on-device until it comes back."
    static let commonCausesHeader = "// COMMON CAUSES"
    static let commonCausesBlurb =
        "The machine is asleep · your private network is down on this phone · the gateway isn't running."

    static let howSwitchingWorksHeader = "// HOW SWITCHING WORKS"
    static let howSwitchingWorksBlurb =
        "One host is in use at a time. Each keeps its own key. Tap a card to switch — the check runs again before anything changes."
    static let inUseTag = "IN USE"
    static let addAnotherHost = "Add another host"

    // MARK: Disconnect (design A4's row + B2's row + B4's sheet)

    static let disconnectRow = "Disconnect this host"
    static func disconnectRowBlurb(host: String) -> String {
        "Forgets the address and key, and tells \(host) to drop this phone."
    }

    /// **THE DEFERRED-REVOKE DECISION, in copy (bar 309-B6).**
    ///
    /// The design promised *"\(host) is told when it's next reachable"* — a
    /// persisted retry queue. It is not built, and the reason is not effort:
    /// **the unpair is authorised by the very credentials the same card
    /// promises to delete.** A queue would have to retain the device token
    /// (and the gateway address) past the moment bullet 1 says they are gone,
    /// so the two halves of one card would contradict each other. Copy
    /// follows mechanism, never the reverse — so the mechanism stays "tell it
    /// now if we can" and the sentence says what actually happens.
    static func disconnectRowBlurbUnreachable(host: String) -> String {
        "Forgets the address and key here. \(host) can't be told while it's unreachable — run hermes talaria unpair there to retire its record."
    }

    /// And the third one, because "we have not asked yet" is a real state and
    /// rounding it to either of the two above would put a promise (or a
    /// refusal) on the row that nothing has measured. Vocabulary rule 1.
    static func disconnectRowBlurbUnknown(host: String) -> String {
        "Forgets the address and key here, and tells \(host) to drop this phone if it answers."
    }

    static func disconnectSheetTitle(host: String) -> String { "DISCONNECT \(host.uppercased())" }
    static let disconnectTwoThings = "Two things happen"
    static let disconnectStepOneTitle = "This phone forgets the address and key"
    static let disconnectStepOneBlurb =
        "Removed from the Keychain. You'd re-enter or re-scan them to come back."
    static func disconnectStepTwoTitle(host: String) -> String { "\(host) drops this device" }
    static let disconnectStepTwoBlurb =
        "Its record for this phone is retired. Your other phones and hosts are untouched."
    /// The honest second bullet when the host is not answering right now.
    static func disconnectStepTwoTitleUnreachable(host: String) -> String {
        "\(host) can't be told right now"
    }
    static let disconnectStepTwoBlurbUnreachable =
        "It isn't answering, so its record for this phone stays until you run hermes talaria unpair there."
    static let disconnectReassurance =
        "Chat keeps working on this phone. Your saved conversations stay where they are."
    static let disconnectConfirm = "DISCONNECT"
    static let disconnectCancel = "Keep it connected"
    static let chatKeepsWorkingFootnote = "CHAT KEEPS WORKING ON-DEVICE AFTERWARDS."

    /// Shown once after a disconnect the host did not take — the outcome,
    /// reported rather than assumed.
    ///
    /// **It says "wasn't told", not "wasn't reachable".** The unpair can fail
    /// three ways — no response, a non-200, or the envelope's 200-with-an-
    /// error-body (#383 hazard 5) — and only the first of them is about
    /// reachability. Naming a cause the app did not establish is the same
    /// class of claim this whole lane exists to remove.
    static let disconnectedHostNotTold =
        "Forgotten here. The host wasn't told, so it still has a record for this phone."

    // MARK: Scanner (design B1–B3 of the wizard sheet)

    static let scannerPointAtCode = "POINT AT THE PRINTED CODE"
    static let scannerWhereItIs =
        "It's in the terminal where you ran hermes talaria pair-qr."
    static let scannerTypeInstead = "Type it instead"

    static let scannerBlockedTitle = "CAMERA BLOCKED"
    static let scannerBlockedHeadline = "Talaria can't use the camera"
    static let scannerBlockedBlurb =
        "Camera access is off for this app, so there's nothing to scan with. You can turn it on, or type the two values instead."
    static let scannerTypeTheValues = "TYPE THE VALUES"
    static let scannerOpenSettings = "Open iOS Settings"

    static let scannerUnavailableTitle = "NO SCANNER HERE"
    static let scannerUnavailableHeadline = "This device has no camera to scan with"
    static let scannerUnavailableBlurb =
        "Type the gateway URL and key — it's the same connection either way."
}
