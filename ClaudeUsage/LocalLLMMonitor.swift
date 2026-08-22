import Foundation
import Combine
import IOKit

// MARK: - A local model that's working right now

// Ollama and LM Studio report very differently, so this is the common shape the
// menu bar and popover see. One job = one model actively doing work.
struct LocalJob: Identifiable, Equatable {
    enum Engine: String {
        case ollama = "Ollama"
        case lmStudio = "LM Studio"
    }

    let engine: Engine
    var model: String
    var title: String?          // the prompt — LM Studio only; Ollama never logs it
    var startedAt: Date
    var tokensPerSec: Double?
    var isPreparing: Bool       // still reading the prompt, not generating yet

    var id: String { "\(engine.rawValue)|\(model)" }
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    // "reading prompt · 12s" / "86 tok/s · 1m 4s"
    var detail: String {
        var parts: [String] = []
        if isPreparing { parts.append("reading prompt") }
        if let rate = tokensPerSec, rate > 0 { parts.append("\(Int(rate.rounded())) tok/s") }
        parts.append(DateUtils.compactElapsed(elapsed))
        return parts.joined(separator: " · ")
    }
}

// A finished burst of local activity. One run may be a single generation or
// thousands of back-to-back calls from an agent loop.
struct LocalRun {
    var jobCount: Int
    var models: [String]     // distinct, in the order first seen
    var engines: [String]
    var duration: TimeInterval
    var lastTitle: String?
}

// MARK: - Monitor

// Watches the local inference engines and publishes what's running.
//
// The obvious approach — ask each engine's HTTP API what's loaded — does not
// work: both keep a model resident in VRAM for minutes after the work finishes,
// so "loaded" would sit lit up all afternoon. Each watcher below uses the one
// signal its engine actually exposes for *working*.
final class LocalLLMMonitor: ObservableObject {
    @Published private(set) var jobs: [LocalJob] = []

    // How many jobs have completed in the current burst of activity (0 when idle).
    @Published private(set) var completedInRun = 0

    // Fired once when a whole burst of local activity goes quiet — NOT once per
    // job. An agent loop or batch can fire thousands of calls back to back, and
    // a banner per call is unusable; what you actually want to know is that the
    // run is over.
    var onRunFinished: ((LocalRun) -> Void)?

    private let ollama = OllamaWatcher()
    private let lmStudio = LMStudioWatcher()
    private var timer: Timer?
    private var running: [String: LocalJob] = [:]
    private let queue = DispatchQueue(label: "tally.localllm")

    // Whether to show the indicator. Held briefly past the last observed job so a
    // batch of short calls reads as one continuous run.
    @Published private(set) var isBusy = false
    private static let indicatorHold: TimeInterval = 8
    private var lastActivityAt: Date?

    func start() {
        stop()
        lmStudio.startTitleStream()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lmStudio.stopTitleStream()
        if !jobs.isEmpty { jobs = [] }
        if isBusy { isBusy = false }
        lastActivityAt = nil
        running = [:]
    }

    private func tick() {
        // Both watchers touch files/subprocesses — keep that off the main thread.
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.ollama.poll() + self.lmStudio.poll()
            DispatchQueue.main.async { self.apply(found) }
        }
    }

    // Last-resort backstop against an engine that reports work it isn't doing,
    // which would pin the menu bar indicator on until it's restarted.
    //
    // Deliberately very conservative: an idle desktop still reports ~15% GPU
    // (window compositing), while active inference pegs it at 90-100%. Firing
    // this wrongly would hide a real job, which is worse than a stuck dot — so it
    // takes a full minute of "engine says busy, GPU flat" before we overrule the
    // engine. Under normal use it never fires; the engines' own signals are
    // accurate.
    private static let stallTicks = 30          // ~60s at the 2s tick
    private static let gpuIdleThreshold = 25

    private var idleTicks: [String: Int] = [:]

    private var runStartedAt: Date?
    private var runLastActive: Date?
    private var runJobCount = 0
    private var runModels: [String] = []
    private var runEngines: [String] = []
    private var runLastTitle: String?

    private func apply(_ found: [LocalJob]) {
        // If the GPU reading is unavailable, trust the engines rather than
        // second-guessing them.
        let gpuBusy = (GPUUtilization.current() ?? 100) >= Self.gpuIdleThreshold

        var live: [LocalJob] = []
        var stalled = Set<String>()
        for job in found {
            if gpuBusy {
                idleTicks[job.id] = 0
                live.append(job)
                continue
            }
            let ticks = (idleTicks[job.id] ?? 0) + 1
            idleTicks[job.id] = ticks
            if ticks >= Self.stallTicks { stalled.insert(job.id) } else { live.append(job) }
        }
        let foundIDs = Set(found.map(\.id))
        idleTicks = idleTicks.filter { foundIDs.contains($0.key) }

        var byID: [String: LocalJob] = [:]
        for job in live { byID[job.id] = job }   // last wins; ids are engine+model

        // Anything that was running and isn't any more just finished — unless we
        // dropped it as stale, which is a wedged engine, not a completed job.
        // Finished jobs are tallied into the current run rather than announced.
        for (id, job) in running where byID[id] == nil {
            guard !stalled.contains(id) else { continue }
            // Both engines are tallied exactly from their event sources below —
            // counting poll transitions here too would double-count.
            if !job.model.isEmpty, job.model != OllamaWatcher.unknownModel,
               !runModels.contains(job.model) { runModels.append(job.model) }
            if !runEngines.contains(job.engine.rawValue) { runEngines.append(job.engine.rawValue) }
            if let title = job.title { runLastTitle = title }
        }
        // Exact, and catches generations too short to land on a poll.
        let ollamaDone = ollama.drainCompleted()
        let lmDone = lmStudio.drainCompleted()
        for (count, engine) in [(ollamaDone, LocalJob.Engine.ollama),
                                (lmDone, LocalJob.Engine.lmStudio)] where count > 0 {
            runJobCount += count
            if !runEngines.contains(engine.rawValue) { runEngines.append(engine.rawValue) }
        }
        let eventActivity = ollamaDone + lmDone > 0
        if eventActivity {
            if runStartedAt == nil { runStartedAt = Date() }
            runLastActive = Date()
        }
        running = byID
        let ordered = live.sorted { $0.startedAt < $1.startedAt }
        if ordered != jobs { jobs = ordered }

        // A batch fires many sub-second calls with gaps between them. Reporting
        // the raw instantaneous state would strobe the menu bar dot on and off;
        // holding it briefly reads as "still working", which is the truth.
        if !live.isEmpty || eventActivity { lastActivityAt = Date() }
        let held = lastActivityAt.map { Date().timeIntervalSince($0) < Self.indicatorHold } ?? false
        if isBusy != held { isBusy = held }

        updateRun(active: held)
    }

    // MARK: - Run tracking

    // A "run" is one burst of local work: it opens on the first job and closes
    // only once everything has been quiet for `settleWindow`. Back-to-back calls
    // in a batch land well inside that window, so a 2,000-call job is a single
    // run — and a single notification — instead of 2,000 of them.
    //
    // The cost is that a lone generation is announced up to `settleWindow` late.
    // That's the right trade: the notification exists for when you've walked
    // away, and if you're sitting there watching, you don't need it at all.
    private static let settleWindow: TimeInterval = 30
    private static let minRunDuration: TimeInterval = 10

    private func updateRun(active: Bool) {
        let now = Date()
        if active {
            if runStartedAt == nil {
                runStartedAt = now
                runJobCount = 0
                runModels = []
                runEngines = []
                runLastTitle = nil
            }
            runLastActive = now
        } else if let started = runStartedAt, let last = runLastActive,
                  now.timeIntervalSince(last) >= Self.settleWindow {
            // Measure to the last activity, not to now — the settle window is our
            // bookkeeping, not part of how long the work took.
            let duration = last.timeIntervalSince(started)
            if runJobCount > 0, duration >= Self.minRunDuration {
                onRunFinished?(LocalRun(jobCount: runJobCount,
                                        models: runModels,
                                        engines: runEngines,
                                        duration: duration,
                                        lastTitle: runLastTitle))
            }
            runStartedAt = nil
            runLastActive = nil
            runJobCount = 0
            runModels = []
            runEngines = []
            runLastTitle = nil
        }
        if completedInRun != runJobCount { completedInRun = runJobCount }
    }

    deinit { timer?.invalidate() }
}

// MARK: - Ollama

// Ollama exposes no "am I busy" field anywhere in its API, and its logs never
// contain prompt text. What the server log *does* give is a precise bracket
// around each request — "processing task" … "all slots are idle" — plus the live
// generation speed. So: tail the log for state, and ask /api/ps for the model
// name once per job (rather than polling, which would spam the same log).
final class OllamaWatcher {
    // Shown until /api/ps answers with the real name; never worth putting in a
    // run summary.
    static let unknownModel = "Ollama model"

    private let logPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".ollama/logs/server.log")

    private var offset: UInt64 = 0
    private var primed = false

    private var busy = false
    private var startedAt: Date?
    private var tokensPerSec: Double?
    private var model: String?
    private var completed = 0

    // Exact count of tasks that finished since the last call, taken straight from
    // the log. Poll-transition counting would miss short generations — a small
    // prompt can finish in under 2 seconds, well inside one tick — which would
    // badly undercount a long batch.
    func drainCompleted() -> Int {
        defer { completed = 0 }
        return completed
    }

    func poll() -> [LocalJob] {
        consumeNewLines()
        guard busy, let startedAt else { return [] }
        return [LocalJob(engine: .ollama,
                         model: model ?? Self.unknownModel,
                         title: nil,
                         startedAt: startedAt,
                         tokensPerSec: tokensPerSec,
                         isPreparing: false)]
    }

    private func consumeNewLines() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logPath),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return }

        // First look: jump to the end so we don't replay old requests as live.
        if !primed {
            offset = size
            primed = true
            return
        }
        if size < offset { offset = 0 }     // log rotated or truncated
        guard size > offset else { return }

        guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            offset = size
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                process(String(line))
            }
        } catch {
            offset = size
        }
    }

    private func process(_ line: String) {
        if line.contains("processing task") {
            if !busy {
                busy = true
                startedAt = Date()
                tokensPerSec = nil
                fetchResidentModel()
            }
            return
        }
        if line.contains("stop processing") {
            completed += 1
            return
        }
        if line.contains("all slots are idle") {
            busy = false
            startedAt = nil
            tokensPerSec = nil
            return
        }
        if let rate = Self.tokensPerSecond(in: line) { tokensPerSec = rate }
    }

    // Pulls 86.39 out of "... n_decoded = 260, tg =  86.39 t/s, ..."
    private static let tgRegex = try! NSRegularExpression(
        pattern: #"tg\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*t/s"#)

    static func tokensPerSecond(in line: String) -> Double? {
        let ns = line as NSString
        guard let match = tgRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    // One call per job, not per tick — /api/ps requests show up in the very log
    // we're tailing, so polling it would bloat the file for no benefit.
    private func fetchResidentModel() {
        guard let url = URL(string: "http://127.0.0.1:11434/api/ps") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]],
                  let first = models.first else { return }
            let name = (first["name"] as? String) ?? (first["model"] as? String)
            guard let name else { return }
            DispatchQueue.main.async { self?.model = LocalName.short(name) }
        }.resume()
    }
}

// MARK: - LM Studio

// LM Studio does report real status — "idle" / "processingPrompt" / "generating"
// — but only through the `lms` CLI, not its HTTP API. Spawning that CLI costs
// ~0.15s, so we gate it behind a free HTTP check: if nothing is loaded, we never
// spawn at all. The same CLI can stream prediction events, which is the only
// place either engine exposes the actual prompt — that's where titles come from.
final class LMStudioWatcher {
    private let cli = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".lmstudio/bin/lms")

    private var lastStatusCheck = Date.distantPast
    private var cachedJobs: [LocalJob] = []
    private var startedAt: [String: Date] = [:]

    // Latest prompt per model, filled by the log stream. Touched from the
    // stream's background handler as well as the poll, so it's lock-guarded.
    private var titles: [String: String] = [:]
    private let titleLock = NSLock()

    private var streamProcess: Process?
    private var predictions = 0

    // Exact count of generations started since the last call, taken from the
    // event stream. Status polling runs every 2-5s and a short generation can
    // begin and end entirely between two polls, so polling undercounts a batch
    // badly — which is exactly the shape of an agent loop.
    func drainCompleted() -> Int {
        titleLock.lock(); defer { titleLock.unlock() }
        defer { predictions = 0 }
        return predictions
    }

    private var installed: Bool { FileManager.default.isExecutableFile(atPath: cli) }

    func poll() -> [LocalJob] {
        guard installed else { return [] }

        // Free gate: no model resident means nothing can be running, so skip the
        // subprocess entirely. Poll faster while something is actually working.
        guard anyModelLoaded() else {
            cachedJobs = []
            startedAt = [:]
            return []
        }
        let interval: TimeInterval = cachedJobs.isEmpty ? 5 : 2
        if Date().timeIntervalSince(lastStatusCheck) < interval { return cachedJobs }
        lastStatusCheck = Date()

        cachedJobs = readStatus()
        return cachedJobs
    }

    // Cheap socket call — LM Studio's REST API lists models and whether each is
    // resident. It does NOT say whether one is working, hence the CLI below.
    private func anyModelLoaded() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:1234/api/v0/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        var loaded = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { done.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else { return }
            loaded = list.contains { ($0["state"] as? String) == "loaded" }
        }.resume()
        _ = done.wait(timeout: .now() + 2)
        return loaded
    }

    private func readStatus() -> [LocalJob] {
        guard let output = run(cli, ["ps", "--json"], timeout: 5),
              let data = output.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var jobs: [LocalJob] = []
        var seen = Set<String>()

        for entry in entries {
            guard let identifier = (entry["identifier"] as? String)
                    ?? (entry["modelKey"] as? String) else { continue }
            let status = (entry["status"] as? String) ?? "idle"
            guard status != "idle" else { continue }

            seen.insert(identifier)
            let began = startedAt[identifier] ?? Date()
            startedAt[identifier] = began

            titleLock.lock()
            let title = titles[identifier]
            titleLock.unlock()

            jobs.append(LocalJob(engine: .lmStudio,
                                 model: LocalName.short(identifier),
                                 title: title,
                                 startedAt: began,
                                 tokensPerSec: nil,
                                 isPreparing: status == "processingPrompt"))
        }
        startedAt = startedAt.filter { seen.contains($0.key) }
        return jobs
    }

    // MARK: Title stream

    // `lms log stream` prints a block per prediction. The input block carries the
    // fully-templated prompt, which is the only prompt text either engine gives
    // us. We keep just the newest per model and use it as the job's title.
    func startTitleStream() {
        guard installed, streamProcess == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["log", "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            buffer += text
            // Blocks are separated by the next "timestamp:" line; parse whole
            // lines only and keep the trailing partial for the next chunk.
            while let newline = buffer.firstIndex(of: "\n") {
                let line = String(buffer[buffer.startIndex..<newline])
                buffer = String(buffer[buffer.index(after: newline)...])
                self?.consumeStreamLine(line)
            }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            streamProcess = nil
        }
    }

    func stopTitleStream() {
        if let process = streamProcess {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            process.terminate()
        }
        streamProcess = nil
        pendingModel = nil
        collectingInput = false
        inputLines = []
    }

    private var pendingModel: String?
    private var collectingInput = false
    private var inputLines: [String] = []

    private func consumeStreamLine(_ line: String) {
        if line.hasPrefix("timestamp:") {
            flushInput()
            pendingModel = nil
            return
        }
        if line.hasPrefix("type:") {
            collectingInput = line.contains("llm.prediction.input")
            if collectingInput {
                titleLock.lock(); predictions += 1; titleLock.unlock()
            } else {
                flushInput()
            }
            return
        }
        if line.hasPrefix("modelIdentifier:") {
            pendingModel = line
                .replacingOccurrences(of: "modelIdentifier:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return
        }
        if collectingInput {
            if line.hasPrefix("input:") { inputLines = []; return }
            inputLines.append(line)
        }
    }

    private func flushInput() {
        defer { inputLines = []; collectingInput = false }
        guard collectingInput, let model = pendingModel, !inputLines.isEmpty else { return }
        guard let title = LocalName.promptTitle(from: inputLines) else { return }
        titleLock.lock()
        titles[model] = title
        titleLock.unlock()
    }

    // MARK: Subprocess helper

    private func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }

        // Read before waiting — a full pipe buffer would otherwise deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }

        return String(data: data, encoding: .utf8)
    }

    deinit { stopTitleStream() }
}

// MARK: - GPU utilization

// System-wide GPU busy percentage, read straight from the IO registry. Inference
// on Apple Silicon runs on the GPU, so this is the ground truth for "is anything
// actually computing" — used only to catch engines that claim to be busy when
// they aren't. Read in-process (no `ioreg` subprocess), so it's cheap enough to
// sample every tick.
enum GPUUtilization {
    static func current() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Int? = nil
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged,
                                                    kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = unmanaged?.takeRetainedValue() as? [String: Any],
                  let stats = props["PerformanceStatistics"] as? [String: Any],
                  let value = stats["Device Utilization %"] as? Int else { continue }
            best = max(best ?? 0, value)
        }
        return best
    }
}

// MARK: - Naming helpers

enum LocalName {
    // "google/gemma-4-26b-a4b-qat" -> "gemma-4-26b-a4b-qat"; "gemma3:latest" -> "gemma3"
    static func short(_ raw: String) -> String {
        var name = raw
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if name.hasSuffix(":latest") { name = String(name.dropLast(":latest".count)) }
        return name.isEmpty ? raw : name
    }

    private static let roleWords: Set<String> =
        ["system", "user", "model", "assistant", "human", "think", "thought", "channel"]

    // Strips template scaffolding (<|turn>, <|im_start|>, [INST], …) so a line
    // that only carried a role marker collapses to the bare role word.
    private static func strip(_ line: String) -> String {
        line.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[/?INST\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Recovers the user's actual question from a templated prompt.
    //
    // Taking the last non-empty line is wrong: reasoning models re-send their own
    // thinking as part of the next prompt, so the tail of the input is the
    // model's monologue, not the question. Instead we find the last *user* turn
    // and read forward until the next role marker.
    static func promptTitle(from lines: [String]) -> String? {
        let bare = lines.map { strip($0) }

        var start: Int? = nil
        for (index, line) in bare.enumerated() {
            let word = line.lowercased()
            if word == "user" || word == "human" { start = index + 1 }
        }

        let candidates: [String]
        if let start, start < bare.count {
            // Everything after the user marker, stopping at the next role turn.
            var collected: [String] = []
            for line in bare[start...] {
                if roleWords.contains(line.lowercased()) { break }
                collected.append(line)
            }
            candidates = collected
        } else {
            // No recognizable turn structure — fall back to the last real line.
            candidates = bare.filter { !$0.isEmpty && !roleWords.contains($0.lowercased()) }.suffix(1)
        }

        let text = candidates
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        return text.count > 70 ? String(text.prefix(69)) + "…" : text
    }
}
