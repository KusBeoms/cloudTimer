import AppKit
import Foundation

enum TacticalPhase { case ready, running, paused }

/// F = red team (찬성), J = blue team (반대); each team has its own 작전타임 budget.
enum TacticalTeam { case red, blue }

@MainActor
final class TimerSession: ObservableObject {
    let presetName: String
    let topic: String
    // 작전타임 (timeout) card, opened with J
    let tacticalName: String
    let tacticalDuration: TimeInterval
    var tacticalAvailable: Bool { tacticalDuration > 0 }
    let steps: [Step]

    @Published private(set) var index: Int = 0
    @Published private(set) var finished: Bool
    @Published private(set) var paused: Bool = false
    @Published private(set) var timeUp: Bool = false
    /// True until the user presses Enter/Space on the topic title screen.
    @Published private(set) var introActive: Bool
    @Published private(set) var tacticalActive: Bool = false
    @Published private(set) var tacticalTeam: TacticalTeam = .red
    @Published private(set) var tacticalPhase: TacticalPhase = .ready
    @Published private(set) var tacticalTimeUp: Bool = false

    private var accumulated: TimeInterval = 0
    private var runStart: Date = Date()
    private var resetFromLevel: Double = 0
    private var resetStart: Date = .distantPast
    private var tacticalAccumulated: TimeInterval = 0
    private var tacticalRunStart: Date = Date()
    private var pausedBeforeTactical = false
    /// Time already used (and whether it ran out) per team, kept while the card is closed.
    private var tacticalSaved: [TacticalTeam: (elapsed: TimeInterval, timeUp: Bool)] = [:]
    private var ticker: Timer?
    private var alarmTask: Task<Void, Never>?
    private var alarmSounds: [NSSound] = []

    private static let drainDuration: TimeInterval = 0.9
    private static let tacticalAlarmRepeats = 5

    init(preset: Preset, tactical: Preset? = nil) {
        presetName = preset.name
        topic = preset.topic
        tacticalName = tactical?.name ?? ""
        tacticalDuration = TimeInterval(tactical?.totalSeconds ?? 0)
        introActive = !preset.steps.isEmpty
        steps = preset.steps
        finished = preset.steps.isEmpty
        runStart = Date()

        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.tick()
            }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    var currentSide: Side {
        guard !finished, steps.indices.contains(index) else { return .none }
        return steps[index].side
    }

    var displayIndex: Int { finished ? steps.count : index }

    var currentDuration: TimeInterval {
        guard !finished, steps.indices.contains(index) else { return 0 }
        return TimeInterval(steps[index].duration)
    }

    func elapsed(at now: Date) -> TimeInterval {
        if finished || introActive { return 0 }
        let running = paused ? 0 : max(0, now.timeIntervalSince(runStart))
        return accumulated + running
    }

    func level(at now: Date) -> Double {
        let duration = currentDuration
        let real: Double = (finished || duration <= 0) ? 0 : min(1, max(0, elapsed(at: now) / duration))
        let p = min(1, max(0, now.timeIntervalSince(resetStart) / Self.drainDuration))
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        let drain = resetFromLevel * (1 - eased)
        return min(1, max(0, max(real, drain)))
    }

    func next() {
        if finished || introActive || tacticalActive { return }
        let now = Date()
        beginReset(at: now)
        if index >= steps.count - 1 {
            finished = true
        } else {
            index += 1
        }
    }

    func previous() {
        if introActive || tacticalActive { return }
        let now = Date()
        if finished {
            guard !steps.isEmpty else { return }
            beginReset(at: now)
            finished = false
        } else if index > 0 {
            beginReset(at: now)
            index -= 1
        }
    }

    func togglePause() {
        if introActive || tacticalActive { return }
        let now = Date()
        if paused {
            runStart = now
            paused = false
        } else {
            accumulated = elapsed(at: now)
            paused = true
        }
    }

    // MARK: Key actions (routed by the window)

    /// Space: start from the intro / start-pause the 작전타임 card / pause-resume the main timer.
    func primaryAction() {
        if introActive { startFromIntro() }
        else if tacticalActive { toggleTactical() }
        else { togglePause() }
    }

    /// Enter: start from the intro / dismiss the 작전타임 card / next step.
    func advanceAction() {
        if introActive { startFromIntro() }
        else if tacticalActive { exitTactical() }
        else { next() }
    }

    /// F (red) / J (blue): bring in that team's 작전타임 card, continuing from its remaining time.
    func tacticalKey(_ team: TacticalTeam) {
        guard !introActive, !finished, tacticalAvailable, !tacticalActive else { return }
        stopAlarm()
        pausedBeforeTactical = paused
        if !paused {
            accumulated = elapsed(at: Date())
            paused = true
        }
        let saved = tacticalSaved[team]
        tacticalTeam = team
        tacticalAccumulated = saved?.elapsed ?? 0
        tacticalRunStart = Date()
        tacticalPhase = tacticalAccumulated > 0 ? .paused : .ready
        tacticalTimeUp = saved?.timeUp ?? false
        tacticalActive = true
    }

    private func startFromIntro() {
        let now = Date()
        accumulated = 0
        runStart = now
        paused = false
        resetFromLevel = 0
        introActive = false
    }

    private func toggleTactical() {
        let now = Date()
        switch tacticalPhase {
        case .ready, .paused:
            tacticalRunStart = now
            tacticalPhase = .running
        case .running:
            tacticalAccumulated += now.timeIntervalSince(tacticalRunStart)
            tacticalPhase = .paused
        }
    }

    private func exitTactical() {
        guard tacticalActive else { return }
        stopAlarm()
        tacticalSaved[tacticalTeam] = (tacticalElapsed(at: Date()), tacticalTimeUp)
        tacticalActive = false
        tacticalPhase = .ready
        tacticalTimeUp = false
        if !pausedBeforeTactical {
            runStart = Date()
            paused = false
        }
    }

    func tacticalElapsed(at now: Date) -> TimeInterval {
        tacticalAccumulated + (tacticalPhase == .running ? max(0, now.timeIntervalSince(tacticalRunStart)) : 0)
    }

    func tacticalLevel(at now: Date) -> Double {
        guard tacticalDuration > 0 else { return 0 }
        return min(1, max(0, tacticalElapsed(at: now) / tacticalDuration))
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        stopAlarm()
    }

    private func beginReset(at now: Date) {
        resetFromLevel = level(at: now)
        resetStart = now
        accumulated = 0
        runStart = now
        timeUp = false
        paused = false
        stopAlarm()
    }

    private func tick() {
        if tacticalActive {
            if tacticalPhase == .running, !tacticalTimeUp, tacticalElapsed(at: Date()) >= tacticalDuration {
                tacticalTimeUp = true
                startAlarm(repeats: Self.tacticalAlarmRepeats)
            }
            return
        }
        guard !introActive, !finished, !timeUp, !paused else { return }
        if elapsed(at: Date()) >= currentDuration {
            timeUp = true
            startAlarm()
        }
    }

    /// Rings the alarm (~1s apart); cancelled by stopAlarm() (next/previous/exit/stop).
    private func startAlarm(repeats: Int = 3) {
        stopAlarm()
        alarmTask = Task { @MainActor in
            for _ in 0..<repeats {
                if Task.isCancelled { return }
                playAlarmSound()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func playAlarmSound() {
        // Keep strong references so a sound is not deallocated (and cut off) while it is still playing.
        alarmSounds.removeAll { !$0.isPlaying }
        let sound = NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
            ?? NSSound(named: "Glass")
        if let sound {
            sound.volume = 1.0
            alarmSounds.append(sound)
            if !sound.play() { NSSound.beep() }
        } else {
            NSSound.beep()
        }
    }

    private func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        alarmSounds.forEach { $0.stop() }
        alarmSounds.removeAll()
    }
}
