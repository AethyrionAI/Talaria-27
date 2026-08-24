// #402 PCC-on-sim probe — SCRATCH FILE, NOT FOR COMMIT (bar 402-D).
//
// Deliberately bypasses `LocalChatBackend.pccGrantConfirmed`: that gate is
// compile-time false on every simulator build by design (#72), and #402's
// question is what the SERVICE does now that Apple's beta 7 notes claim
// "Private Cloud Compute might not work when you use simulators" is FIXED
// (id 177684296). Availability proves nothing here — the 2026-08-20 lane
// measured `.isAvailable == true` on an UNENTITLED beta5 sim binary — so the
// discriminator is respond() (bar 402-B), and every reading carries its
// runtime build (bar 402-C).
import Testing
import Foundation
import FoundationModels

@Suite("PCC sim probe (#402)")
struct PCCSimProbeTests {

    @Test("availability, quota, contextSize, languages, then one respond()", .timeLimit(.minutes(4)))
    func probe() async throws {
        var report: [String] = []
        let env = ProcessInfo.processInfo.environment
        report.append("env: runtime_build=\(env["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "?") runtime_version=\(env["SIMULATOR_RUNTIME_VERSION"] ?? "?") device=\(env["SIMULATOR_MODEL_IDENTIFIER"] ?? "?")")

        let pcc = PrivateCloudComputeLanguageModel()
        report.append("availability=\(pcc.availability)")
        report.append("isAvailable=\(pcc.isAvailable)")
        report.append("quotaUsage=\(String(describing: pcc.quotaUsage))")
        do {
            let cs = try await pcc.contextSize
            report.append("contextSize=\(cs)")
        } catch {
            report.append("contextSize THREW: \(Self.describe(error))")
        }
        do {
            let langs = try await pcc.supportedLanguages
            report.append("supportedLanguages.count=\(langs.count)")
        } catch {
            report.append("supportedLanguages THREW: \(Self.describe(error))")
        }

        // 402-B generation half — the discriminator. Bounded so a service
        // hang cannot park the run past the trait's own limit.
        let session = LanguageModelSession(
            model: pcc,
            tools: [],
            instructions: Instructions("Reply with one word.")
        )
        let gen = Task { try await session.respond(to: Prompt("Say the word ping and nothing else."), options: GenerationOptions()) }
        let watchdog = Task { try await Task.sleep(for: .seconds(120)); gen.cancel() }
        do {
            let response = try await gen.value
            watchdog.cancel()
            report.append("respond OK: \(String(describing: response).prefix(400))")
        } catch {
            watchdog.cancel()
            let timedOut = gen.isCancelled ? " (after 120s watchdog cancel)" : ""
            report.append("respond THREW\(timedOut): \(Self.describe(error))")
        }

        for line in report { print("PCC-402| \(line)") }
        #expect(true)  // the probe records; it does not judge
    }

    @Test("arm 2: PCC respond with NO instructions", .timeLimit(.minutes(4)))
    func pccNoInstructions() async throws {
        let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: [])
        let gen = Task { try await session.respond(to: Prompt("Say the word ping and nothing else."), options: GenerationOptions()) }
        let watchdog = Task { try await Task.sleep(for: .seconds(120)); gen.cancel() }
        do {
            let response = try await gen.value
            watchdog.cancel()
            print("PCC-402|arm2 respond OK: \(String(describing: response).prefix(400))")
        } catch {
            watchdog.cancel()
            print("PCC-402|arm2 respond THREW\(gen.isCancelled ? " (watchdog)" : ""): \(Self.describe(error))")
        }
        #expect(true)
    }

    @Test("arm 3: SYSTEM model metadata + respond on this sim", .timeLimit(.minutes(4)))
    func systemModelRespond() async throws {
        let sys = SystemLanguageModel.default
        print("PCC-402|arm3 sys availability=\(sys.availability) isAvailable=\(sys.isAvailable)")
        if #available(iOS 27.0, *) {
            print("PCC-402|arm3 sys variant=\(sys.variant.displayName)")
        }
        print("PCC-402|arm3 sys contextSize=\(sys.contextSize)")
        let session = LanguageModelSession(model: sys, tools: [], instructions: Instructions("Reply with one word."))
        let gen = Task { try await session.respond(to: Prompt("Say the word ping and nothing else."), options: GenerationOptions()) }
        let watchdog = Task { try await Task.sleep(for: .seconds(120)); gen.cancel() }
        do {
            let response = try await gen.value
            watchdog.cancel()
            print("PCC-402|arm3 SYSTEM respond OK: \(String(describing: response).prefix(400))")
        } catch {
            watchdog.cancel()
            print("PCC-402|arm3 SYSTEM respond THREW\(gen.isCancelled ? " (watchdog)" : ""): \(Self.describe(error))")
        }
        #expect(true)
    }

    /// Error identity verbatim — 324-W4: typed casts can be blind to the
    /// un-bridged NSError family, so record BOTH the typed view and the raw
    /// domain string + code + underlying chain.
    static func describe(_ error: Error) -> String {
        var out = ""
        if let typed = error as? PrivateCloudComputeLanguageModel.Error {
            out += "[typed PCC.Error: \(typed.debugDescription)] "
        }
        var ns = error as NSError
        out += "domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)"
        var depth = 0
        while let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, depth < 4 {
            out += " | underlying domain=\(u.domain) code=\(u.code) desc=\(u.localizedDescription)"
            ns = u; depth += 1
        }
        return out
    }
}
