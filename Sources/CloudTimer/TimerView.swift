import SwiftUI

struct TimerView: View {
    @ObservedObject var session: TimerSession

    init(session: TimerSession) {
        self.session = session
    }

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.40)

    private var layoutAnimation: Animation { .spring(response: 0.62, dampingFraction: 0.86) }
    private var introAnimation: Animation { .easeInOut(duration: 0.8) }

    var body: some View {
        GeometryReader { geo in
            let s = min(max(min(geo.size.width / 960, geo.size.height / 560), 1.0), 2.4)
            let tankW = max(260, geo.size.width * 0.38)
            let topicW = max(200 * s, geo.size.width - tankW - 84 * s)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 28 * s) {
                    lyrics(s: s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    cards(tankW: tankW, s: s)
                        .frame(width: tankW)
                }
                .padding(.top, 34 * s)
                .padding([.leading, .trailing, .bottom], 28 * s)
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(layoutAnimation, value: session.tacticalActive)

                topicBlock(size: geo.size, smallWidth: topicW, s: s)

                // End screen: mirrors the intro - one big message in the middle.
                Text("수고하셨습니다")
                    .font(.system(size: 44 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: -16 * s)
                    .opacity(session.finished ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8).delay(session.finished ? 0.35 : 0), value: session.finished)
                    .allowsHitTesting(false)
                    .accessibilityHidden(!session.finished)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(introAnimation, value: session.introActive)
            .animation(introAnimation, value: session.finished)
        }
        .background(sideBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: Topic (intro <-> top-left)

    /// Two fixed-size copies of the topic that never re-wrap: a big centered one for the intro, and the
    /// small top-left one. On leaving the intro the big copy shrinks toward the corner while fading out
    /// and the small copy fades in, so the move is smooth and the text is sharp at both ends.
    private func topicBlock(size: CGSize, smallWidth: CGFloat, s: CGFloat) -> some View {
        let intro = session.introActive
        let hasTopic = !session.topic.isEmpty
        let text = hasTopic ? session.topic : session.presetName
        let bigWidth = size.width * 0.7
        // Where the shrunken big copy ends up: roughly the small copy's centre.
        let cornerDX = 28 * s + smallWidth * 0.5 - size.width / 2
        let cornerDY = 66 * s - size.height / 2
        return ZStack(alignment: .topLeading) {
            // Big, centered (intro)
            VStack(spacing: 8 * s) {
                if hasTopic {
                    Text("주제")
                        .font(.system(size: 18 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(text)
                    .font(.system(size: 44 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: bigWidth)
            .scaleEffect(intro ? 1 : 0.42)
            .offset(x: intro ? 0 : cornerDX, y: intro ? -16 * s : cornerDY)
            .animation(.easeInOut(duration: 0.8), value: intro)
            .opacity(intro ? 1 : 0)
            .animation(.easeInOut(duration: 0.4).delay(intro ? 0 : 0.3), value: intro)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // Small, top-left (after the intro)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text("주제")
                    .font(.system(size: 11 * s, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(text)
                    .font(.system(size: 17 * s, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: smallWidth, alignment: .leading)
            .scaleEffect(intro ? 1.5 : 1, anchor: .topLeading)
            .animation(.easeInOut(duration: 0.8), value: intro)
            .opacity(intro || !hasTopic || session.finished ? 0 : 1)
            .animation(.easeInOut(duration: 0.35).delay(intro ? 0 : 0.5), value: intro)
            .animation(.easeInOut(duration: 0.5), value: session.finished)
            .padding(.top, 40 * s)
            .padding(.leading, 28 * s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: Cards

    /// The tactical card lands on top of the main card in the same slot. The main card stays
    /// underneath, nudged left and dimmed so a sliver remains visible. The container keeps a fixed
    /// width so the transition offsets are measured against the container, not the card.
    private func cards(tankW: CGFloat, s: CGFloat) -> some View {
        let tactical = session.tacticalActive
        return ZStack {
            if !session.introActive && !session.finished {
                tank(width: tankW, s: s)
                    .frame(width: tankW)
                    .scaleEffect(tactical ? 0.94 : 1, anchor: .center)
                    .offset(x: tactical ? -28 * s : 0)
                    .opacity(tactical ? 0.6 : 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if tactical {
                tacticalTank(width: tankW, s: s)
                    .frame(width: tankW)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))
                    .zIndex(1)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Team

    private var teamName: String { session.tacticalTeam == .red ? "빨강팀" : "파랑팀" }

    private var teamAccent: Color {
        session.tacticalTeam == .red
            ? Color(red: 1.0, green: 0.55, blue: 0.52)
            : Color(red: 0.55, green: 0.75, blue: 1.0)
    }

    /// Opaque dark base so the tactical card fully covers the main card beneath it.
    private var teamBase: Color {
        session.tacticalTeam == .red
            ? Color(red: 0.20, green: 0.035, blue: 0.055)
            : Color(red: 0.03, green: 0.08, blue: 0.24)
    }

    // MARK: Background

    /// Three stacked gradients cross-faded by opacity so the side change blends smoothly.
    /// While a tactical timeout is open the team color (red = 찬성 palette, blue = 반대 palette) wins.
    private enum Backdrop { case neutral, red, blue }

    /// Intro and "no team" steps use the original navy; 찬성 is dark red, 반대 dark blue; while a
    /// 작전타임 card is open the team color wins.
    private var backdrop: Backdrop {
        if session.introActive || session.finished { return .neutral }
        if session.tacticalActive { return session.tacticalTeam == .red ? .red : .blue }
        switch session.currentSide {
        case .none: return .neutral
        case .pro: return .red
        case .con: return .blue
        }
    }

    private var sideBackground: some View {
        let palette: GradientPalette
        switch backdrop {
        case .neutral: palette = .init(top: (0.047, 0.098, 0.157), bottom: (0.027, 0.055, 0.098))
        case .red:     palette = .init(top: (0.32, 0.05, 0.08),    bottom: (0.17, 0.02, 0.04))
        case .blue:    palette = .init(top: (0.04, 0.12, 0.34),    bottom: (0.02, 0.065, 0.20))
        }
        return GradientBackdrop(palette: palette)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: backdrop)
    }

    // MARK: Lyrics

    private func lyrics(s: CGFloat) -> some View {
        let tactical = session.tacticalActive
        let intro = session.introActive
        let rowH = 120 * s
        return ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        ForEach(Array(session.steps.enumerated()), id: \.element.id) { i, step in
                            row(i, step, s: s, rowH: rowH)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.2),
                                .init(color: .black, location: 0.8),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: session.displayIndex)
                }
                .opacity(tactical || intro || session.finished ? 0 : 1)
                .animation(.easeInOut(duration: 0.5), value: session.finished)
                .allowsHitTesting(!tactical && !intro && !session.finished)
                .accessibilityHidden(tactical || intro || session.finished)

                VStack(alignment: .leading, spacing: 6 * s) {
                    Text(session.tacticalName)
                        .font(.system(size: 40 * s, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(teamName)
                        .font(.system(size: 20 * s, weight: .semibold))
                        .foregroundStyle(teamAccent)
                        .lineLimit(1)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .opacity(tactical ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(!tactical)
            }
            .animation(.easeInOut(duration: 0.5), value: tactical)
        }
        .animation(.easeInOut(duration: 0.6).delay(session.introActive ? 0 : 0.25), value: intro)
    }

    private func row(_ i: Int, _ step: Step, s: CGFloat, rowH: CGFloat) -> some View {
        let current = session.displayIndex
        let d = abs(i - current)
        let isCurrent = i == current
        let opacity: Double = d == 0 ? 1.0 : d == 1 ? 0.35 : d == 2 ? 0.15 : 0

        return VStack(alignment: .leading, spacing: 6 * s) {
            Text(step.title)
                .font(.system(size: 32 * s, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption(i, step))
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 0.92).opacity(0.8))
                .padding(.top, 2 * s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowH, alignment: .center)
        .scaleEffect(isCurrent ? 1.0 : 0.88, anchor: .leading)
        .opacity(opacity)
        .offset(y: CGFloat(i - current) * rowH)
        .allowsHitTesting(false)
        .accessibilityHidden(!isCurrent)
    }

    private func caption(_ i: Int, _ step: Step) -> String {
        var text = "\(i + 1) / \(session.steps.count) · \(durationLabel(step))"
        switch step.side {
        case .pro: text += " · 찬성"
        case .con: text += " · 반대"
        case .none: break
        }
        return text
    }

    private func durationLabel(_ step: Step) -> String {
        let total = step.duration
        let m = total / 60, s = total % 60
        if m == 0 { return "\(s)초" }
        return s == 0 ? "\(m)분" : "\(m)분 \(s)초"
    }

    // MARK: Tank

    private func tank(width: CGFloat, s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28 * s, style: .continuous)
        return TimelineView(.animation) { timeline in
            let date = timeline.date
            ZStack {
                OceanView(level: session.level(at: date),
                          time: date.timeIntervalSinceReferenceDate)
                clockOverlay(at: date, tankWidth: width, s: s)
            }
        }
        .background(shape.fill(Color.black.opacity(0.28)))
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func clockOverlay(at date: Date, tankWidth: CGFloat, s: CGFloat) -> some View {
        let duration = session.currentDuration
        let elapsed = session.elapsed(at: date)
        let remaining = Int(ceil(max(0, duration - elapsed)))
        let over = max(0, Int(elapsed - duration))
        let fontSize = min(tankWidth * 0.3, 84 * s)
        let stepTitle = session.index < session.steps.count ? session.steps[session.index].title : ""

        return VStack(spacing: 8 * s) {
            if session.finished {
                Text("완료")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8 * s, y: 2 * s)
            } else {
                Text("남은 시간")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(formatClock(remaining))
                    .font(.system(size: fontSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8 * s, y: 2 * s)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if session.timeUp {
                    Text("+\(formatClock(over)) 초과")
                        .font(.system(size: 18 * s, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(coral)
                        .shadow(color: .black.opacity(0.4), radius: 4 * s, y: 1 * s)
                }
                Text(stepTitle)
                    .font(.system(size: 14 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.4), radius: 4 * s, y: 1 * s)
                    .padding(.top, 4 * s)
                if session.paused {
                    Text("일시정지")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12 * s)
                        .padding(.vertical, 4 * s)
                        .background(Capsule().fill(Color.black.opacity(0.3)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                        .padding(.top, 4 * s)
                }
            }
        }
        .padding(.horizontal, 16 * s)
        .multilineTextAlignment(.center)
    }

    // MARK: Tactical tank

    private func tacticalTank(width: CGFloat, s: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28 * s, style: .continuous)
        return TimelineView(.animation) { timeline in
            let date = timeline.date
            ZStack {
                OceanView(level: session.tacticalLevel(at: date),
                          time: date.timeIntervalSinceReferenceDate)
                tacticalClockOverlay(at: date, tankWidth: width, s: s)
            }
        }
        .background(
            ZStack {
                shape.fill(teamBase)
                shape.fill(teamAccent.opacity(0.10))
            }
        )
        .clipShape(shape)
        .overlay(shape.stroke(teamAccent.opacity(0.75), lineWidth: 1.5))
    }

    private func tacticalClockOverlay(at date: Date, tankWidth: CGFloat, s: CGFloat) -> some View {
        let duration = session.tacticalDuration
        let elapsed = session.tacticalElapsed(at: date)
        let remaining = Int(ceil(max(0, duration - elapsed)))
        let over = max(0, Int(elapsed - duration))
        let fontSize = min(tankWidth * 0.3, 84 * s)

        return VStack(spacing: 8 * s) {
            Text(session.tacticalName)
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Text(teamName)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(teamAccent)
                .padding(.horizontal, 12 * s)
                .padding(.vertical, 3 * s)
                .background(Capsule().fill(Color.black.opacity(0.3)))
                .overlay(Capsule().stroke(teamAccent.opacity(0.6), lineWidth: 0.5))
            Text(formatClock(remaining))
                .font(.system(size: fontSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8 * s, y: 2 * s)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if session.tacticalTimeUp {
                Text("+\(formatClock(over)) 초과")
                    .font(.system(size: 18 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(coral)
                    .shadow(color: .black.opacity(0.4), radius: 4 * s, y: 1 * s)
            }
            switch session.tacticalPhase {
            case .ready:
                tacticalBadge("Space로 시작", s: s)
            case .paused:
                tacticalBadge("일시정지", s: s)
            case .running:
                EmptyView()
            }
        }
        .padding(.horizontal, 16 * s)
        .multilineTextAlignment(.center)
    }

    private func tacticalBadge(_ text: String, s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12 * s, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12 * s)
            .padding(.vertical, 4 * s)
            .background(Capsule().fill(Color.black.opacity(0.3)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            .padding(.top, 4 * s)
    }
}


/// Six color components (top rgb + bottom rgb) that SwiftUI can interpolate, so a background change
/// is a true color fade instead of a cross-fade of two layers.
private struct GradientPalette: VectorArithmetic {
    var v: [Double]

    init(top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        v = [top.0, top.1, top.2, bottom.0, bottom.1, bottom.2]
    }
    private init(v: [Double]) { self.v = v }

    static var zero: GradientPalette { GradientPalette(v: Array(repeating: 0, count: 6)) }
    static func + (l: GradientPalette, r: GradientPalette) -> GradientPalette {
        GradientPalette(v: zip(l.v, r.v).map(+))
    }
    static func - (l: GradientPalette, r: GradientPalette) -> GradientPalette {
        GradientPalette(v: zip(l.v, r.v).map(-))
    }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
}

private struct GradientBackdrop: View, Animatable {
    var palette: GradientPalette
    var animatableData: GradientPalette {
        get { palette }
        set { palette = newValue }
    }

    var body: some View {
        let c = palette.v
        return LinearGradient(
            colors: [Color(red: c[0], green: c[1], blue: c[2]), Color(red: c[3], green: c[4], blue: c[5])],
            startPoint: .top, endPoint: .bottom)
    }
}
