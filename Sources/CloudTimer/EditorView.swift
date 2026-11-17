import SwiftUI
import AppKit

// Column metrics shared by the step header and the step rows so they stay aligned.
private enum Col {
    static let handle: CGFloat = 12
    static let badge: CGFloat = 24
    static let side: CGFloat = 150
    static let time: CGFloat = 206
    static let trash: CGFloat = 20
    static let spacing: CGFloat = 8
}

private let maxStepSeconds = 999 * 60 + 59

/// "41분", "3분 30초", "45초"
private func durationText(_ total: Int) -> String {
    let m = total / 60, s = total % 60
    if m == 0 { return "\(s)초" }
    return s == 0 ? "\(m)분" : "\(m)분 \(s)초"
}

private func summaryText(_ preset: Preset) -> String {
    "총 \(durationText(preset.totalSeconds)) · \(preset.steps.count)단계"
}

private func sideColor(_ side: Side) -> Color? {
    switch side {
    case .none: return nil
    case .pro: return .red
    case .con: return .blue
    }
}

struct EditorView: View {
    @ObservedObject private var store = PresetStore.shared
    @State private var selection: UUID?
    @State private var draft: Preset?
    @State private var confirmDelete = false
    @FocusState private var focusedStep: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            if let binding = Binding($draft) {
                detail(binding)
            } else {
                ContentUnavailableView("프리셋을 선택하세요", systemImage: "timer",
                                       description: Text("왼쪽 목록에서 프리셋을 고르거나 '+ 새 프리셋'으로 새로 만드세요."))
            }
        }
        .onAppear {
            if selection == nil {
                selection = (store.tacticalPreset ?? store.presets.first)?.id
            } else if draft == nil {
                draft = store.preset(id: selection)
            }
        }
        .onChange(of: selection) { _, new in
            commit()
            draft = store.preset(id: new)
        }
        .onDisappear { commit() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            commit()
        }
    }

    // MARK: Sidebar

    private var selectedName: String {
        let name = store.preset(id: selection)?.name ?? ""
        return name.isEmpty ? "(이름 없음)" : name
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.presets) { preset in
                    // The selected row mirrors the draft so edits show up while typing.
                    let shown = (draft?.id == preset.id ? draft : nil) ?? preset
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shown.name.isEmpty ? "(이름 없음)" : shown.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(summaryText(shown))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if store.tacticalID == preset.id {
                            HStack(spacing: 3) {
                                Image(systemName: "timer")
                                Text("F/J 작전타임")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .help("F/J 키로 열리는 작전타임 프리셋")
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(preset.id)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    let p = store.add()
                    selection = p.id
                } label: {
                    Label("새 프리셋", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .help("새 프리셋 만들기")
                Spacer()
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selection == nil)
                .help("선택한 프리셋 삭제")
            }
            .padding(10)
        }
        .confirmationDialog("'\(selectedName)' 프리셋을 삭제할까요?",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("삭제", role: .destructive) { deleteSelected() }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ preset: Binding<Preset>) -> some View {
        let id = preset.wrappedValue.id
        let isDirty = store.preset(id: id) != preset.wrappedValue

        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    infoCard(preset, id: id)
                    stepsCard(preset)
                }
                .padding(16)

                Divider()

                // Footer
                HStack(spacing: 12) {
                    Button {
                        let step = Step(title: "새 단계", note: "", minutes: 1, seconds: 0)
                        preset.wrappedValue.steps.append(step)
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            withAnimation { proxy.scrollTo(step.id, anchor: .bottom) }
                            focusedStep = step.id
                        }
                    } label: {
                        Label("단계 추가", systemImage: "plus")
                    }
                    .controlSize(.large)
                    .help("목록 끝에 새 단계 추가")

                    Text(summaryText(preset.wrappedValue))
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(isDirty ? "● 저장 안 됨" : "✓ 저장됨")
                        .font(.callout)
                        .foregroundStyle(isDirty ? Color.orange : Color.secondary)
                        .lineLimit(1)

                    Button {
                        commit()
                        if let saved = store.preset(id: id) {
                            TimerWindowManager.shared.open(saved)
                        }
                    } label: {
                        Label("실행", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("저장 후 타이머 창 열기 (⌘↩)")

                    Button("저장") { commit() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                        .disabled(!isDirty)
                        .help("변경 내용 저장 (⌘S)")
                }
                .padding(12)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold))
    }

    private func infoCard(_ preset: Binding<Preset>, id: UUID) -> some View {
        let tactical = Binding<Bool>(
            get: { store.tacticalID == id },
            set: { on in
                if on { store.setTactical(id) }
                else if store.tacticalID == id { store.setTactical(nil) }
            }
        )
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("프리셋 정보")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("이름")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("예: 퍼블릭 포럼 디베이트", text: preset.name)
                            .textFieldStyle(.roundedBorder)
                        Text("타이머 창 제목으로 표시됩니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("주제")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("타이머 창 왼쪽 위에 표시할 주제", text: preset.topic, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                        Text("타이머 창 왼쪽 위에 큰 글씨로 표시됩니다 (비워도 됩니다)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow(alignment: .top) {
                    Text("작전타임 프리셋")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("작전타임 프리셋", isOn: tactical)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .help("F/J 키로 여는 작전타임 프리셋으로 지정")
                        Text("켜면 타이머 창에서 F(빨강팀) · J(파랑팀) 키로 이 프리셋이 작전타임 카드로 열립니다 (팀마다 별도 시간, 닫았다 열면 남은 시간부터).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func stepsCard(_ preset: Binding<Preset>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("단계")

            HStack(spacing: Col.spacing) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: Col.handle)
                    .help("각 줄을 끌어서 순서를 바꿀 수 있습니다")
                Text("#").frame(width: Col.badge)
                Text("단계 이름").frame(maxWidth: .infinity, alignment: .leading)
                Text("팀").frame(width: Col.side, alignment: .leading)
                Text("시간").frame(width: Col.time, alignment: .leading)
                Color.clear.frame(width: Col.trash, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            Divider()

            if preset.wrappedValue.steps.isEmpty {
                Text("단계가 없습니다. 아래 '+ 단계 추가'를 눌러 시작하세요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(preset.steps) { $step in
                        let number = (preset.wrappedValue.steps.firstIndex { $0.id == step.id } ?? 0) + 1
                        stepRow(preset: preset, step: $step, number: number)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                            .listRowBackground(
                                number.isMultiple(of: 2) ? Color.primary.opacity(0.05) : Color.clear
                            )
                            .listRowSeparator(.hidden)
                    }
                    .onMove { preset.wrappedValue.steps.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }

    private func stepRow(preset: Binding<Preset>, step: Binding<Step>, number: Int) -> some View {
        let color = sideColor(step.wrappedValue.side)
        let total = step.wrappedValue.minutes * 60 + step.wrappedValue.seconds
        return HStack(spacing: Col.spacing) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: Col.handle)
                .help("끌어서 순서 바꾸기")

            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color ?? Color.secondary)
                .frame(width: Col.badge, height: Col.badge)
                .background(Circle().fill((color ?? Color.secondary).opacity(0.16)))

            TextField("단계 이름", text: step.title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedStep, equals: step.wrappedValue.id)
                .frame(minWidth: 100, maxWidth: .infinity)

            Picker("팀", selection: step.side) {
                ForEach(Side.allCases) { side in
                    Text(side.label).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(color)
            .frame(width: Col.side)
            .help("이 단계의 팀 (찬성 = 빨강, 반대 = 파랑)")

            HStack(spacing: 4) {
                NumberField(value: step.minutes, maxValue: 999, width: 52, alignment: .center)
                    .help("분")
                Text("분").frame(width: 14, alignment: .leading)
                NumberField(value: step.seconds, maxValue: 59, width: 52, alignment: .center)
                    .help("초")
                Text("초").frame(width: 14, alignment: .leading)
                HStack(spacing: 2) {
                    Button { nudge(step, by: -30) } label: {
                        Image(systemName: "minus").frame(width: 12)
                    }
                    .disabled(total <= 1)
                    .help("30초 줄이기")
                    Button { nudge(step, by: 30) } label: {
                        Image(systemName: "plus").frame(width: 12)
                    }
                    .disabled(total >= maxStepSeconds)
                    .help("30초 늘리기")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 6)
            }
            .frame(width: Col.time, alignment: .leading)

            DeleteStepButton {
                let sid = step.wrappedValue.id
                preset.wrappedValue.steps.removeAll { $0.id == sid }
            }
            .frame(width: Col.trash)
        }
    }

    // MARK: Actions

    /// Changes a step's duration by `delta` seconds (min 1s, max 999m59s).
    private func nudge(_ step: Binding<Step>, by delta: Int) {
        let current = step.wrappedValue.minutes * 60 + step.wrappedValue.seconds
        let next = min(max(current + delta, 1), maxStepSeconds)
        step.wrappedValue.minutes = next / 60
        step.wrappedValue.seconds = next % 60
    }

    /// Sanitizes the draft and writes it to the store.
    private func commit() {
        // Flush any numeric field that is still being edited into the binding.
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard let d = draft else { return }
        let clean = Self.sanitized(d)
        store.update(clean)
        if clean != d { draft = clean }
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        let list = store.presets
        let idx = list.firstIndex { $0.id == id } ?? 0
        let neighbour = list.indices.contains(idx + 1) ? list[idx + 1].id
            : (idx > 0 ? list[idx - 1].id : nil)
        draft = nil   // do not commit the preset being deleted
        store.delete(id: id)
        selection = neighbour
    }

    private static func sanitized(_ preset: Preset) -> Preset {
        var p = preset
        for i in p.steps.indices {
            var m = max(0, p.steps[i].minutes)
            var s = max(0, p.steps[i].seconds)
            m += s / 60
            s %= 60
            if m == 0 && s == 0 { s = 1 }
            p.steps[i].minutes = m
            p.steps[i].seconds = s
        }
        return p
    }
}

/// Borderless trash button that turns red on hover.
private struct DeleteStepButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(hovering ? Color.red : Color.secondary)
        }
        .buttonStyle(.borderless)
        .onHover { hovering = $0 }
        .help("단계 삭제")
    }
}

/// Digits-only field that writes to its binding on every keystroke (no Return needed),
/// clamped to 0...maxValue.
private struct NumberField: View {
    @Binding var value: Int
    let maxValue: Int
    var width: CGFloat = 46
    var alignment: TextAlignment = .trailing
    @State private var text = ""

    var body: some View {
        TextField("0", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(alignment)
            .frame(width: width)
            .onAppear { text = String(value) }
            .onChange(of: text) { _, newText in
                let digits = String(newText.filter(\.isNumber).prefix(4))
                if digits != newText { text = digits; return }
                value = min(Int(digits) ?? 0, maxValue)
            }
            .onChange(of: value) { _, newValue in
                if (Int(text) ?? 0) != newValue || (text.isEmpty && newValue != 0) {
                    text = String(newValue)
                }
            }
    }
}
