# Third-Party Licenses and Attribution

Talaria is MIT licensed (see [LICENSE](LICENSE)). This file records external code
that ships in the app, external work used as reference, and the project's own
origin — three different things that are easy to conflate.

---

## Bundled dependencies

Code that is compiled into or linked by shipping builds.

### WebRTC — `stasel/WebRTC` 130.0.0

- Source: https://github.com/stasel/WebRTC
- Used by: voice mode (real-time speech-to-speech transport)
- Declared in: `project.yml` → `packages.WebRTC`; pinned in `Package.resolved`
- License: the underlying WebRTC project is BSD 3-Clause (Copyright the WebRTC
  project authors), distributed here as prebuilt XCFramework binaries.

The verbatim notices below are reproduced from the distributed package
(`LICENSE.md` at the pinned `130.0.0` tag; the binary `WebRTC.xcframework`
additionally embeds the WebRTC project notice as its own `LICENSE` file).
Note: the distributed package ships **no PATENTS file** — the upstream
webrtc.org tree carries one, but it is not part of what this app
redistributes, so it is deliberately not reproduced here.

<details>
<summary>Verbatim license text (stasel/WebRTC packaging + Google WebRTC)</summary>

```
BSD 3-Clause License
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



Google WebRTC
Copyright (c) 2011, The WebRTC project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

</details>

This is currently the only third-party package Talaria links.

---

## Reference and inspiration

Work that informed design or architecture but whose **code is not present** in
this repository. No license obligation attaches to reading a project; these are
recorded as credit.

### Hermex — `uzairansaruzi/hermex` (MIT)

- Source: https://github.com/uzairansaruzi/hermex
- License: MIT
- Author: Uzair Ansar

A native SwiftUI iPhone client for a self-hosted agent. Reviewed 2026-07-22 as
architecture and UX reference for an agent-introspection surface Talaria lacks —
scheduled tasks, a skills browser, a memory panel, usage insights, session
projects, and mid-run steering (see OPEN_ITEMS #156).

Two things worth stating precisely:

1. **Hermex targets a different server.** It is a client for
   `nesquena/hermes-webui`, not `NousResearch/hermes-agent`. The projects share
   the word "Hermes" and nothing else. Its endpoint shapes therefore do not
   transfer to Talaria, and any resemblance in these features is convergent
   design against a similar problem, not shared plumbing.
2. **No Hermex source is used.** If that ever changes — if actual Swift is
   adopted rather than the idea of a screen — this entry must be upgraded to a
   full MIT notice reproducing their copyright and permission text, and the
   affected files annotated. Until then this is attribution, not a license
   obligation.

The `UPSTREAM_TESTED_SHA` convention in this repo was also borrowed from Hermex,
which pins the upstream server commit it is tested against.

### Foundation-Models-Framework-Lab — `rudrankriyam/Foundation-Models-Framework-Lab` (MIT)

- Source: https://github.com/rudrankriyam/Foundation-Models-Framework-Lab
- License: MIT
- Author: Rudrank Riyam

Unlike the entries above, one file from this repo **is vendored verbatim** into
this repository (not compiled into shipping builds): `fmf.md` — their 9,737-line
transcription of the Xcode 27 beta FoundationModels swiftinterface including doc
comments — copied to `docs/reference/fmf-beta4-swiftinterface.md` (2026-07-28,
upstream `0c8fda2`) as grep-reference for the OPEN_ITEMS #200-family lanes. The
MIT notice is therefore reproduced in full:

<details>
<summary>Verbatim MIT license text (rudrankriyam/Foundation-Models-Framework-Lab)</summary>

```
MIT License

Copyright (c) 2025 Rudrank Riyam

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

</details>

The repo's app code (Foundation Lab) and its `rryam/FoundationModelsKit`
dependency were additionally reviewed 2026-07-28 as prior art for the #200
tool-calling lanes (see `planning/FM-SDK-SEAM-SURVEY-2026-07-28.md`); no other
source from either project is present in this repository.

---

## Project lineage

Not third-party, and not merely reference — this is where Talaria came from.

### Dylan Buck — original author

Talaria's first commit is Dylan Buck's (`c4e5b36`, 2026-03-31,
"scaffold HermesMobile from template"). He authored the original app shell, the
relay foundation, the connector-based host relay, the iOS pairing flow, and the
initial design system. Substantial portions of the connector and MCP surfaces
descend directly from that work, and his commits remain in this repository's
history.

The MIT `LICENSE` is held by "Hermes iOS Contributors", which includes him. This
section exists because a collective copyright line does not, on its own, tell a
reader who built the foundation — and the git history that does is not the first
thing anyone reads.

The current development line (`AethyrionAI/Talaria-27`, targeting iOS 27) is a
continuation of that lineage, not a separate project.

---

## Not covered here

- Apple system frameworks (FoundationModels, HealthKit, CoreMotion, AlarmKit,
  AVFoundation, and so on) — used under the Apple Developer Program License
  Agreement, no attribution obligation.
- `NousResearch/hermes-agent` — the server Talaria connects to. It is a separate
  program the user installs and runs themselves; Talaria neither bundles nor
  redistributes it.

**WeatherKit was in that first list and should not have been.** Using the
framework carries no attribution obligation; DISPLAYING the data it returns
does, and the two are easy to conflate. Apple's WeatherKit terms require the
Apple Weather trademark plus a link to Apple's legal attribution page wherever
Apple's weather data is shown — and, for a *value-added* service or product
built from that data, the same attribution "along with a notice that the data
provided by Apple has been modified." A model's prose about the weather is such
a product, so Talaria owes both halves.

It renders them deterministically rather than leaving compliance to generated
text: any reply whose persisted transcript records a completed `currentWeather`
tool call carries the line **"Weather data by Apple Weather, modified by
Talaria"**, linking to

- https://weatherkit.apple.com/legal-attribution.html

A reply that never called the weather tool — and one whose call failed, was
stopped, or is still running — carries no attribution, because no Apple data
was displayed. The rule lives in
`Talaria/Features/Chat/WeatherAttribution.swift`.
