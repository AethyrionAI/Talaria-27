import Foundation

// MARK: - The conversational installer's install source + first-contact prompt (#269-B)
//
// #251 routed the shape and #269 carries it: the user connects Talaria, and
// the AGENT — which has hands on its own host — installs the talaria plugin
// itself. The first contact has to ride the app's prompt, because a skill
// cannot ship inside a plugin that is not installed yet (#269's load-bearing
// constraint).
//
// Everything the app sends is in this file, on purpose. The prose is a
// CAPABILITY CLAIM MADE ON THE AGENT'S BEHALF (#257's family), which is why
// #269 called the wording bars-worthy and why it is pinned by test rather
// than inlined at a call site.

/// Where the plugin is installed FROM. Parameterized rather than baked in:
/// the ref is how a host is pinned to a known-good commit (the README's own
/// pinned-sha path, and how #271 deployed to OJAMD), and the URL is how a
/// fork, a mirror, or a `file://` checkout is reached without a new build.
struct TalariaPluginInstallSource: Equatable, Sendable {
    /// A git source `hermes plugins install` accepts — an `https://` URL, an
    /// `owner/repo` shorthand, `git@`/`ssh://`, or a local `file://` path.
    var repositoryURL: String
    /// The `--ref` argument: a branch, a tag, or (preferably) a commit sha.
    var ref: String

    /// **The default, resolved 2026-09-01 from the deployed plugin checkout's
    /// own git remote** (`~/.hermes/plugins/talaria`, read-only) rather than
    /// from memory — this is the real origin the working hosts installed from.
    ///
    /// ⚠️ It is tied to the 269-B PUBLICATION MOMENT: the repo is private
    /// today, and #308 carries the ruling that flips it public. Until that
    /// lands, this URL only clones on a host whose git can authenticate to it
    /// — which is exactly why the prompt below tells the agent to REPORT a
    /// clone failure rather than work around it (#269-B-D's honest-degradation
    /// arm, which needs a live host to measure).
    ///
    /// `main` rather than a pinned sha: the app cannot know which sha is
    /// good, and a sha frozen into a shipped build rots into a stale install
    /// the moment the plugin moves. A caller that DOES know pins it here.
    static let `default` = TalariaPluginInstallSource(
        repositoryURL: "https://github.com/AethyrionAI/talaria-plugin.git",
        ref: "main"
    )

    /// The install command the prompt names, assembled once so the pin and the
    /// prose can never disagree about it.
    var installCommand: String {
        "hermes plugins install \(repositoryURL) --ref \(ref)"
    }
}

/// The prose the app sends as its first contact. A pure function of its
/// source — no clock, no host state, nothing that could make two sends of the
/// same source differ (269-B-I pins that too).
enum TalariaPluginSetupPrompt {

    /// The manifest name the plugin registers under, and the name `enable`
    /// takes. Matches the directory #271 installed into.
    static let pluginName = "talaria"

    /// **269-B-I.** Every constraint in here is a ruling, not a preference:
    ///
    ///  - **Narrate before acting** — #269's own shape ("the agent narrates
    ///    WHY, the app verifies WHETHER"), and the half the user actually
    ///    reads.
    ///  - **Never restart the gateway** — Owen ruled this 2026-08-25 and it is
    ///    STANDING: no new restart mechanism is ever built, and the flow ends
    ///    by pointing at the host's existing Restart Gateway affordance. The
    ///    agent runs INSIDE the gateway process, so a self-restart is also the
    ///    one step it could never narrate the far side of.
    ///  - **Report failure honestly, never retry silently** — #180's rule. A
    ///    partial install is the realistic failure (#269), and a silent
    ///    workaround is what turns it into an invisible one.
    ///  - **Do not declare success** — the app probes. Saying so in the prompt
    ///    is not decoration: it removes the incentive to claim a state the
    ///    agent cannot check, which is the #257 failure this lane inherits.
    static func firstContact(source: TalariaPluginInstallSource = .default) -> String {
        """
        Talaria — the iOS app connected to this host — is asking you to install its bridge plugin here, so the app and this agent can reach each other. The user approved this request in Talaria before it was sent.

        First, say in one or two sentences what you are about to do, before you do it.

        Then:
        1. Install the plugin: `\(source.installCommand)`
        2. Enable it: `hermes plugins enable \(pluginName)`
        3. Stop there.

        Do not restart the gateway, and do not ask any tool to restart it. You are running inside that process, and the restart is the user's own deliberate action — when you are done, tell them to use Restart Gateway on this host (the Gateway popover's power button, or the Command Palette entry).

        If a step fails, name the command that failed and quote what it printed. Do not retry silently, do not substitute another install method, and do not report a success you did not observe.

        Do not declare the plugin live. Talaria probes this host itself to decide that, and it will not take your word for it — an honest account of what you ran is the whole job.
        """
    }
}
