import Foundation
import SwiftUI

enum Side: String, Codable, CaseIterable, Identifiable {
    case none, pro, con
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "없음"
        case .pro: return "찬성"
        case .con: return "반대"
        }
    }
}

struct Step: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var title: String = ""
    var note: String = ""
    var minutes: Int = 1
    var seconds: Int = 0
    var side: Side = .none

    /// Total seconds, always at least 1 so the timer never divides by zero.
    var duration: Int {
        let m = min(max(0, minutes), 9_999)
        let sec = min(max(0, seconds), 3_599)
        return max(1, m * 60 + sec)
    }
}

struct Preset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = "새 프리셋"
    var topic: String = ""
    var steps: [Step] = [Step(title: "새 단계", note: "", minutes: 1, seconds: 0)]

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.duration } }
}

extension Step {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 1
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
        side = (try? c.decodeIfPresent(Side.self, forKey: .side)) ?? .none
    }
}

extension Preset {
    // Older saved files have no "topic" key; decode it as optional.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "새 프리셋"
        topic = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
    }
}

private struct StoreFile: Codable {
    var presets: [Preset]
    var defaultID: UUID?
    var version: Int?
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published var presets: [Preset] = []
    /// The preset opened as the 작전타임 card with the J key (persisted under the legacy "defaultID" key).
    @Published var tacticalID: UUID?

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cloudTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("presets.json")

        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(StoreFile.self, from: data) {
            presets = file.presets
            tacticalID = file.defaultID
            // Migration: the built-in debate preset gets its default topic if it has none yet.
            var migrated = false
            for i in presets.indices where presets[i].name == Self.seedName && presets[i].topic.isEmpty {
                presets[i].topic = Self.seedTopic
                migrated = true
            }
            // v2: pro/con sides for the debate preset, plus a 작전타임 preset bound to ⌘N (one time only).
            if (file.version ?? 1) < 2 {
                for i in presets.indices where presets[i].name == Self.seedName {
                    let sides = Self.debateSides
                    if presets[i].steps.count == sides.count, presets[i].steps.allSatisfy({ $0.side == .none }) {
                        for j in presets[i].steps.indices { presets[i].steps[j].side = sides[j] }
                    }
                }
                if !presets.contains(where: { $0.name == Self.tacticalName }) {
                    let t = Self.tacticalSeed()
                    presets.append(t)
                    tacticalID = t.id
                }
                migrated = true
            }
            if migrated { save() }
        } else {
            // Never overwrite an existing file we failed to read: keep a copy first.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = base.appendingPathComponent("presets.corrupt-\(stamp).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
            }
            let seed = Self.debateSeed()
            let tactical = Self.tacticalSeed()
            presets = [seed, tactical]
            tacticalID = tactical.id
            save()
        }
    }

    var tacticalPreset: Preset? { preset(id: tacticalID) }

    func preset(id: UUID?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    func update(_ preset: Preset) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        guard presets[i] != preset else { return }
        presets[i] = preset
        save()
    }

    @discardableResult
    func add() -> Preset {
        let p = Preset()
        presets.append(p)
        save()
        return p
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        if tacticalID == id { tacticalID = nil }
        save()
    }

    func setTactical(_ id: UUID?) {
        tacticalID = id
        save()
    }

    func save() {
        let file = StoreFile(presets: presets, defaultID: tacticalID, version: 2)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(file) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Seed (퍼블릭 포럼 디베이트)

    private static let seedName = "퍼블릭 포럼 디베이트"
    private static let seedTopic = "생성형 AI를 개발하기 위해 저작물을 학습시킬 때, 개발사가 원저작자에게 대가를 지불하도록 의무화해야한다."

    private static let tacticalName = "작전타임"

    /// Side per debate step (1..12): 찬성 = our team, 반대 = the opponent; crossfires/작전타임 are neutral.
    private static let debateSides: [Side] = [.pro, .con, .none, .pro, .con, .none, .pro, .con, .none, .pro, .con, .none]

    private static func tacticalSeed() -> Preset {
        Preset(name: tacticalName, topic: seedTopic,
               steps: [Step(title: "작전타임", note: "팀당 3분", minutes: 3, seconds: 0)])
    }

    private static func debateSeed() -> Preset {
        func s(_ t: String, _ n: String, _ m: Int) -> Step { Step(title: t, note: n, minutes: m, seconds: 0) }
        var preset = Preset(name: seedName, topic: seedTopic, steps: [
            s("입안 (Constructive Speech)", "첫 번째 연사가 나와 팀의 입장과 주장을 개진", 4),
            s("입안 (Constructive Speech)", "상대편 첫 번째 연사가 나와 팀의 입장 및 주장을 개진", 4),
            s("교차질의 (Crossfire)", "각 팀의 첫 번째 연사 간 질문 및 응답", 3),
            s("반박 (Rebuttal)", "두 번째 연사가 나와 상대방 의견에 대한 반박 전개", 4),
            s("반박 (Rebuttal)", "상대편 두 번째 연사가 나와 상대방 의견에 대한 반박 전개", 4),
            s("교차질의 (Crossfire)", "각 팀의 두 번째 연사간 질문 및 응답", 3),
            s("요약 (Summary)", "세 번째 연사가 자신의 입장과 상대방 입장에 대한 반박을 정리하여 요약 발표", 2),
            s("요약 (Summary)", "상대편 첫 번째 연사가 자신의 입장과 상대방 입장에 대한 반박을 정리하여 요약 발표", 2),
            s("전원 교차질의 (Grand Crossfire)", "모든 연사가 나서서 질문 및 응답", 5),
            s("마지막 초점 (Final Focus)", "세 번째 연사가 나와 지금까지 토론한 내용에 기반하여 왜 자신의 팀이 이겨야 하는지 설명", 2),
            s("마지막 초점 (Final Focus)", "상대편 세 번째 연사가 나와 지금까지 토론한 내용에 기반하여 왜 자신의 팀이 이겨야 하는지 설명", 2),
            s("작전타임", "팀당 3분씩 (입안/반박/요약/마지막 초점 시작 전 사용가능)", 6),
        ])
        for i in preset.steps.indices { preset.steps[i].side = debateSides[i] }
        return preset
    }
}

func formatClock(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}
