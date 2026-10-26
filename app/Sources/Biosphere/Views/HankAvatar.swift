import SwiftUI

/// Hank's expressions. The chat panel drives these; the avatar animates between them.
enum HankMood: String, CaseIterable {
    case idle        // resting, blinks now and then
    case listening   // she's typing: attentive, eyes follow the text (see `gaze`)
    case surprised   // she just sent a message: quick perk-up / bounce
    case thinking    // waiting for Claude: eyes up/aside, thinking dots
    case talking     // reply streaming in: animated mouth
    case happy       // reply finished: pleased squint/smile, small hop
    case blush       // she poked him: flustered, rosy cheeks
}

/// Hank: a glossy lavender sphere wearing big round specs. Everything he does is driven from
/// `mood` and `gaze`; the motion is procedural (a pure function of time), so it's cheap and needs no timers.
struct HankAvatar: View {
    var size: CGFloat = 40
    var mood: HankMood = .idle
    /// Where he's looking horizontally: -1 (far left) … 0 (centre) … 1 (far right). nil = centre.
    var gaze: CGFloat? = nil
    /// false = a still drawing (for lists of chat bubbles, so dozens of Hanks don't animate at once).
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seed = Double(Int.random(in: 0..<997))   // de-syncs blinks between instances
    @State private var fromPose: HankPose?                      // what was on screen when the mood last changed
    @State private var moodSince: Double = -10_000
    @State private var gazeFrom: CGFloat = 0
    @State private var gazeSince: Double = -10_000

    private static let moodBlend = 0.3
    private static let gazeBlend = 0.32

    private var motion: CGFloat { reduceMotion ? 0 : (size < 26 ? 0.5 : 1) }

    var body: some View {
        if animated { live } else {
            HankFace(size: size, pose: HankRig.pose(mood, t: 1, since: -100, gaze: 0, seed: 0, motion: 0)).frame(width: size, height: size)
        }
    }

    private var live: some View {
        TimelineView(.animation(minimumInterval: size < 30 ? 1.0 / 30 : nil)) { ctx in
            HankFace(size: size, pose: pose(at: ctx.date.timeIntervalSinceReferenceDate, mood: mood, gazeTarget: gaze ?? 0))
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { old, _ in
            let now = Date.now.timeIntervalSinceReferenceDate
            fromPose = pose(at: now, mood: old, gazeTarget: gaze ?? 0)
            moodSince = now
        }
        .onChange(of: gaze) { old, _ in
            let now = Date.now.timeIntervalSinceReferenceDate
            gazeFrom = shownGaze(at: now, target: old ?? 0)
            gazeSince = now
        }
    }

    private func shownGaze(at t: Double, target: CGFloat) -> CGFloat {
        let k = HankRig.easeOut(CGFloat((t - gazeSince) / Self.gazeBlend))
        return gazeFrom + (target - gazeFrom) * k
    }

    private func pose(at t: Double, mood: HankMood, gazeTarget: CGFloat) -> HankPose {
        let since = t - moodSince
        let live = HankRig.pose(mood, t: t + seed, since: since,
                                gaze: max(-1, min(1, shownGaze(at: t, target: gazeTarget))), seed: seed, motion: motion)
        guard let fromPose, since < Self.moodBlend else { return live }
        return HankPose.mix(fromPose, live, HankRig.easeInOut(CGFloat(since / Self.moodBlend)))
    }
}

// MARK: - Pose

/// One frame of Hank. Lengths are fractions of the avatar's size; `tilt` is in degrees.
struct HankPose {
    var bodyY: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var tilt: CGFloat = 0          // head tilt (face rotates on the sphere)
    var faceX: CGFloat = 0         // features slide across the sphere = head turn
    var faceY: CGFloat = 0
    var glassesY: CGFloat = 0      // specs bounce independently of the eyes
    var eyeScale: CGFloat = 1
    var eyeOpen: CGFloat = 1       // 0 = blink
    var pupilX: CGFloat = 0
    var pupilY: CGFloat = 0
    var happyEyes: CGFloat = 0     // ^ ^
    var squeeze: CGFloat = 0       // > <
    var mouthW: CGFloat = 0.15
    var smile: CGFloat = 0.032     // how far the middle of the mouth dips below the corners
    var mouthOpen: CGFloat = 0
    var mouthX: CGFloat = 0
    var mouthRound: CGFloat = 0    // 1 = little "o"
    var blush: CGFloat = 0
    var thinking: CGFloat = 0      // thought bubble
    var sparkle: CGFloat = 0       // celebration twinkles
    var clock: Double = 0

    private static let channels: [WritableKeyPath<HankPose, CGFloat>] = [
        \.bodyY, \.scaleX, \.scaleY, \.tilt, \.faceX, \.faceY, \.glassesY, \.eyeScale, \.eyeOpen,
        \.pupilX, \.pupilY, \.happyEyes, \.squeeze, \.mouthW, \.smile, \.mouthOpen, \.mouthX, \.mouthRound,
        \.blush, \.thinking, \.sparkle,
    ]

    static func mix(_ a: HankPose, _ b: HankPose, _ k: CGFloat) -> HankPose {
        var out = b
        for c in channels { out[keyPath: c] = a[keyPath: c] + (b[keyPath: c] - a[keyPath: c]) * k }
        return out
    }
}

// MARK: - Rig (moods → poses)

enum HankRig {
    /// - t: clock in seconds; since: seconds since this mood began; gaze: -1…1; motion: 0 (reduce motion) … 1.
    static func pose(_ mood: HankMood, t: Double, since s: Double, gaze g: CGFloat, seed: Double, motion m: CGFloat) -> HankPose {
        var p = HankPose()
        p.clock = t
        let breath = CGFloat(sin(t * 2 * .pi / 3.4))
        p.bodyY = -0.012 * breath * m
        p.scaleY = 1 + 0.012 * breath * m
        p.scaleX = 1 - 0.006 * breath * m
        let blinkOpen = blink(t, seed: seed)

        switch mood {
        case .idle:
            let look = wander(t, seed: seed, slot: 4.6, move: 0.35)
            p.pupilX = look * 0.03
            p.pupilY = wander(t + 2.3, seed: seed + 7, slot: 6.1, move: 0.45) * 0.01
            p.faceX = look * 0.012
            p.tilt = look * 2.5 * m
            p.eyeOpen = blinkOpen

        case .listening:
            p.eyeScale = 1.14
            p.pupilX = g * 0.05
            p.pupilY = 0.022                       // looking down at what she's typing
            p.faceX = g * 0.035
            p.faceY = 0.012
            p.tilt = g * 6 * max(m, 0.4)
            p.scaleX *= 1.025; p.scaleY *= 1.025   // leaning in
            p.eyeOpen = blink(t, seed: seed, slot: 5.4)
            p.mouthW = 0.1; p.smile = 0.02; p.mouthOpen = 0.012

        case .surprised:
            // crouch → hop (stretch) → land (squash wobble)
            var y: CGFloat = 0, sq: CGFloat = 0     // sq > 0 = squash
            if s < 0.07 {
                sq = 0.1 * CGFloat(s / 0.07)
            } else if s < 0.37 {
                let u = CGFloat((s - 0.07) / 0.3)
                y = -0.1 * sin(.pi * u)
                sq = u < 0.15 ? 0.1 - 0.17 * (u / 0.15) : -0.07 * (1 - (u - 0.15) / 0.85)
            } else if s < 1.0 {
                let u = s - 0.37
                sq = CGFloat(0.09 * exp(-8 * u) * cos(22 * u))
            }
            p.bodyY += y * m
            p.scaleY *= 1 - sq * m
            p.scaleX *= 1 + sq * m
            let ring = CGFloat(exp(-5 * s) * cos(16 * s))
            p.eyeScale = 1.3 + 0.14 * ring
            p.glassesY = -0.022 - 0.04 * ring * max(m, 0.4)
            p.pupilY = -0.006
            p.eyeOpen = s < 1.6 ? 1 : blinkOpen
            p.mouthW = 0.095; p.smile = 0; p.mouthOpen = 0.115 + 0.025 * ring; p.mouthRound = 1

        case .thinking:
            p.bodyY = -0.01 * CGFloat(sin(t * 2 * .pi / 4.8)) * m
            p.pupilX = 0.045; p.pupilY = -0.052
            p.faceX = 0.015; p.faceY = -0.01
            p.tilt = (-7 + 2.2 * CGFloat(sin(t * 0.9))) * max(m, 0.5)
            p.eyeScale = 0.97
            p.eyeOpen = blink(t, seed: seed, slot: 4.4, duration: 0.45)
            p.mouthW = 0.07; p.smile = -0.004; p.mouthX = -0.035
            p.thinking = 1

        case .talking:
            let v = talkLevel(t)
            p.mouthW = 0.145 - 0.035 * v
            p.smile = 0.03 - 0.012 * v
            p.mouthOpen = 0.01 + 0.085 * v
            p.eyeScale = 1.06
            p.pupilX = wander(t, seed: seed + 3, slot: 1.15, move: 0.12) * 0.026
            p.pupilY = -0.004
            p.glassesY = -0.008 * v
            p.bodyY += -0.012 * v * m
            p.tilt = CGFloat(sin(t * 1.6)) * 3 * m
            p.eyeOpen = blinkOpen

        case .happy:
            p.happyEyes = 1
            p.eyeScale = 1.05
            p.mouthW = 0.19; p.smile = 0.045; p.mouthOpen = 0.055
            p.blush = 0.55
            p.sparkle = 1
            if s < 1.2 {
                let decay = exp(-2.4 * s)
                p.bodyY += CGFloat(-0.075 * abs(sin(.pi * s / 0.32)) * decay) * m
                let sq = CGFloat(0.07 * decay * pow(cos(.pi * s / 0.32), 8))
                p.scaleY *= 1 - sq * m; p.scaleX *= 1 + sq * m
            }
            p.tilt = CGFloat(sin(t * 2.4)) * 4 * m

        case .blush:
            let look = smoothstep(1.2, 1.7, CGFloat(s))      // 0 = eyes squeezed shut, 1 = peeking away
            p.squeeze = 1 - look
            p.eyeScale = 1 - 0.1 * look
            p.pupilX = -0.045 * look; p.pupilY = 0.03 * look
            p.faceX = -0.02 * look
            p.blush = 1
            let wiggle = CGFloat(7 * exp(-2.2 * s) * sin(24 * s))
            p.tilt = (wiggle + 6 * look) * max(m, 0.5) + CGFloat(sin(t * 1.8)) * 1.5 * m
            p.scaleX *= 1.025; p.scaleY *= 0.975; p.bodyY += 0.01
            p.mouthW = 0.085; p.smile = 0.02
            p.eyeOpen = look > 0.5 ? blinkOpen : 1
        }
        return p
    }

    // MARK: helpers

    static func easeOut(_ x: CGFloat) -> CGFloat { let u = max(0, min(1, x)); return 1 - (1 - u) * (1 - u) * (1 - u) }
    static func easeInOut(_ x: CGFloat) -> CGFloat { let u = max(0, min(1, x)); return u * u * (3 - 2 * u) }
    static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat { easeInOut((x - a) / (b - a)) }

    /// Deterministic 0..<1 noise.
    static func rand(_ x: Double, _ seed: Double) -> Double {
        let v = sin(x * 12.9898 + seed * 78.233) * 43758.5453
        return v - floor(v)
    }

    /// 1 = open, 0 = shut. One blink at a random moment in each `slot`, sometimes a double blink.
    static func blink(_ t: Double, seed: Double, slot: Double = 3.8, duration: Double = 0.16) -> CGFloat {
        let k = floor(t / slot)
        var shut = 0.0
        for kk in [k - 1, k] {
            let start = kk * slot + 0.3 + rand(kk, seed) * (slot - 0.9)
            shut = max(shut, bump((t - start) / duration))
            if rand(kk + 0.37, seed) < 0.22 { shut = max(shut, bump((t - start - duration - 0.1) / duration)) }
        }
        return CGFloat(1 - shut)
    }

    private static func bump(_ u: Double) -> Double { (u > 0 && u < 1) ? sin(.pi * u) : 0 }

    /// Little glances: a new target (-1…1, often centre) every `slot` seconds, moved to over `move` seconds.
    static func wander(_ t: Double, seed: Double, slot: Double, move: Double) -> CGFloat {
        func target(_ k: Double) -> CGFloat { rand(k + 0.71, seed) < 0.4 ? 0 : CGFloat(rand(k, seed + 1.3) * 2 - 1) }
        let k = floor(t / slot)
        let a = target(k - 1), b = target(k)
        return a + (b - a) * easeInOut(CGFloat((t - k * slot) / move))
    }

    /// Irregular 0…1 mouth openness with little pauses between "words".
    static func talkLevel(_ t: Double) -> CGFloat {
        let syllables = 0.45 + 0.35 * sin(t * 17.0) + 0.25 * sin(t * 10.7 + 1.3) + 0.12 * sin(t * 5.9 + 0.4)
        let words = max(0, min(1, (sin(t * 1.3 + 0.7) + 0.7) * 2.2))
        return CGFloat(max(0, min(1, syllables)) * words)
    }
}

// MARK: - Drawing

enum HankColors {
    static let bodyHi = Color(red: 0.89, green: 0.84, blue: 1.0)
    static let bodyMid = Color(red: 0.66, green: 0.52, blue: 0.98)
    static let bodyLo = Color(red: 0.45, green: 0.24, blue: 0.87)
    static let rim = Color(red: 0.33, green: 0.13, blue: 0.68)
    static let ink = Color(red: 0.13, green: 0.07, blue: 0.24)      // frames, eyes, mouth
    static let mouthInside = Color(red: 0.26, green: 0.06, blue: 0.27)
    static let blush = Color(red: 1.0, green: 0.42, blue: 0.66)
    static let tongue = Color(red: 1.0, green: 0.52, blue: 0.68)
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.22)
}

/// Draws one pose. Detail drops away at small sizes so he stays readable.
struct HankFace: View {
    var size: CGFloat
    var pose: HankPose

    var body: some View {
        let d = size
        ZStack {
            sphere(d)
            face(d)
                .rotationEffect(.degrees(Double(pose.tilt)), anchor: UnitPoint(x: 0.5, y: 0.62))
                .offset(x: pose.faceX * d, y: pose.faceY * d)
                .frame(width: d, height: d)
                .clipShape(Circle().inset(by: d * 0.02))
        }
        .frame(width: d, height: d)
        .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
        .offset(y: pose.bodyY * d)
        .overlay { if d >= 26 { extras(d) } }
    }

    // glossy sphere, lit from the top-left
    private func sphere(_ d: CGFloat) -> some View {
        let large = d >= 40
        return Circle()
            .fill(RadialGradient(colors: [HankColors.bodyHi, HankColors.bodyMid, HankColors.bodyLo],
                                 center: UnitPoint(x: 0.36, y: 0.27), startRadius: 0, endRadius: d * 0.74))
            .overlay {
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.4, height: d * 0.19)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -d * 0.17, y: -d * 0.29)
            }
            .overlay {
                if large {   // soft bounce light along the bottom edge
                    Circle().inset(by: d * 0.035).trim(from: 0.12, to: 0.38)
                        .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: d * 0.022, lineCap: .round))
                }
            }
            .overlay(Circle().strokeBorder(HankColors.rim.opacity(0.4), lineWidth: max(0.6, d * 0.014)))
            .frame(width: d * 0.96, height: d * 0.96)
            .shadow(color: Palette.purple.opacity(0.28), radius: max(0.8, d * 0.05), y: d * 0.035)
    }

    private func face(_ d: CGFloat) -> some View {
        let p = pose
        let tiny = d < 26, large = d >= 40
        let lensD = d * (tiny ? 0.4 : 0.355)
        let lensX = d * (tiny ? 0.205 : 0.195)
        let lensY = -d * 0.035
        let fw = max(1.3, d * (tiny ? 0.07 : 0.052))       // frame thickness
        let gY = lensY + p.glassesY * d * (tiny ? 0.5 : 1)
        let pupilK: CGFloat = tiny ? 0.6 : 1
        let lensFill = large
            ? LinearGradient(colors: [.white, Color(red: 0.88, green: 0.84, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.white, .white.opacity(tiny ? 1 : 0.92)], startPoint: .top, endPoint: .bottom)

        return ZStack {
            // cheeks
            if p.blush > 0.01 {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse()
                        .fill(RadialGradient(colors: [HankColors.blush, HankColors.blush.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: d * 0.12))
                        .frame(width: d * 0.24, height: d * 0.15)
                        .offset(x: side * d * 0.31, y: d * 0.18)
                        .opacity(Double(p.blush))
                    if large {
                        HankBlushLines()
                            .stroke(HankColors.blush.opacity(0.9), style: StrokeStyle(lineWidth: d * 0.014, lineCap: .round))
                            .frame(width: d * 0.11, height: d * 0.045)
                            .offset(x: side * d * 0.31, y: d * 0.18)
                            .opacity(Double(max(0, p.blush - 0.6) / 0.4))
                    }
                }
            }
            // lenses
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(lensFill).frame(width: lensD, height: lensD).offset(x: side * lensX, y: gY)
            }
            // eyes
            ForEach([-1.0, 1.0], id: \.self) { side in
                eye(side, d: d, tiny: tiny).offset(x: side * lensX + p.pupilX * d * pupilK, y: lensY + p.pupilY * d * pupilK)
            }
            // glare across each lens
            if large {
                ForEach([-1.0, 1.0], id: \.self) { side in
                    HankGlare()
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: lensD * 0.075, lineCap: .round))
                        .frame(width: lensD * 0.7, height: lensD * 0.7)
                        .offset(x: side * lensX, y: gY)
                }
            }
            // frames
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().strokeBorder(HankColors.ink, lineWidth: fw)
                    .frame(width: lensD, height: lensD).offset(x: side * lensX, y: gY)
                if !tiny {
                    Circle().inset(by: fw * 0.5).trim(from: 0.57, to: 0.7)
                        .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: fw * 0.3, lineCap: .round))
                        .frame(width: lensD, height: lensD).offset(x: side * lensX, y: gY)
                    Capsule().fill(HankColors.ink)       // arm running round the sphere
                        .frame(width: d * 0.14, height: fw * 0.85)
                        .offset(x: side * (lensX + lensD / 2 + d * 0.06), y: gY - lensD * 0.14)
                }
            }
            // bridge
            Capsule().fill(HankColors.ink)
                .frame(width: 2 * lensX - lensD + fw * 2, height: fw * 0.9)
                .offset(y: gY - lensD * 0.1)
            // mouth
            do {
                let lw = tiny ? max(1.1, d * 0.06) : max(1, d * 0.036)
                let mk: CGFloat = tiny ? 1.3 : 1
                let shape = HankMouthShape(smile: p.smile * d * mk, open: p.mouthOpen * d * mk)
                ZStack {
                    shape.fill(HankColors.mouthInside)
                        .overlay {
                            if large && p.mouthOpen > 0.03 {
                                Ellipse().fill(HankColors.tongue)
                                    .frame(width: p.mouthW * d * 0.6, height: p.mouthOpen * d * 0.9)
                                    .offset(y: (p.smile + p.mouthOpen) * d * 0.85)
                            }
                        }
                        .clipShape(shape)
                    shape.stroke(HankColors.ink, style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                }
                .opacity(Double(1 - p.mouthRound))
                .frame(width: p.mouthW * d * mk, height: d * 0.3)
                .offset(x: p.mouthX * d, y: d * (tiny ? 0.27 : 0.235))
                if p.mouthRound > 0.01 {
                    Ellipse().fill(HankColors.mouthInside)
                        .overlay(Ellipse().strokeBorder(HankColors.ink, lineWidth: lw * 0.8))
                        .frame(width: max(lw * 2, p.mouthW * d * mk), height: max(lw * 2, p.mouthOpen * d * mk))
                        .offset(x: p.mouthX * d, y: d * (tiny ? 0.28 : 0.25))
                        .opacity(Double(p.mouthRound))
                }
            }
        }
        .frame(width: d, height: d)
    }

    private func eye(_ side: CGFloat, d: CGFloat, tiny: Bool) -> some View {
        let p = pose
        let es = tiny ? min(p.eyeScale, 1.05) : p.eyeScale
        let w = d * (tiny ? 0.13 : 0.105) * es
        let h = d * (tiny ? 0.19 : 0.165) * es
        let openH = max(max(1, d * 0.035), h * p.eyeOpen)
        let arcW = max(1.2, d * 0.046)
        let round = Double(max(0, 1 - p.happyEyes - p.squeeze))
        return ZStack {
            Capsule().fill(HankColors.ink)
                .frame(width: w, height: openH)
                .overlay(alignment: .top) {
                    if !tiny && p.eyeOpen > 0.6 {
                        Circle().fill(.white).frame(width: w * 0.42, height: w * 0.42)
                            .offset(x: w * 0.13, y: w * 0.17)
                    }
                }
                .opacity(round)
            if p.happyEyes > 0.01 {
                HankEyeArc(sharp: false)
                    .stroke(HankColors.ink, style: StrokeStyle(lineWidth: arcW, lineCap: .round, lineJoin: .round))
                    .frame(width: w * 2, height: h * 0.5)
                    .opacity(Double(p.happyEyes))
            }
            if p.squeeze > 0.01 {
                HankEyeArc(sharp: true)
                    .stroke(HankColors.ink, style: StrokeStyle(lineWidth: arcW, lineCap: .round, lineJoin: .round))
                    .frame(width: w * 1.8, height: h * 0.6)
                    .rotationEffect(.degrees(side < 0 ? 90 : -90))
                    .opacity(Double(p.squeeze))
            }
        }
    }

    // thought bubble + sparkles sit outside the squash so they don't wobble
    private func extras(_ d: CGFloat) -> some View {
        let p = pose
        return ZStack {
            if p.thinking > 0.01 && d >= 34 {
                ZStack {
                    Circle().fill(.white).frame(width: d * 0.075, height: d * 0.075)
                        .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: max(0.5, d * 0.01)))
                        .offset(x: d * 0.2, y: -d * 0.27)
                    Capsule().fill(.white)
                        .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: max(0.5, d * 0.012)))
                        .frame(width: d * 0.36, height: d * 0.19)
                        .shadow(color: Palette.purple.opacity(0.18), radius: d * 0.03, y: d * 0.01)
                        .overlay {
                            HStack(spacing: d * 0.035) {
                                ForEach(0..<3, id: \.self) { i in
                                    let ph = sin(p.clock * 6.5 - Double(i) * 0.9)
                                    Circle().fill(Palette.purple)
                                        .frame(width: d * 0.055, height: d * 0.055)
                                        .opacity(0.45 + 0.55 * max(0, ph))
                                        .offset(y: -d * 0.022 * CGFloat(max(0, ph)))
                                }
                            }
                        }
                        .offset(x: d * 0.33, y: -d * 0.39)
                }
                .scaleEffect(0.4 + 0.6 * p.thinking, anchor: UnitPoint(x: 0.6, y: 0.3))
                .opacity(Double(p.thinking))
            }
            if p.sparkle > 0.01 && d >= 30 {
                ForEach(0..<3, id: \.self) { i in
                    let spots: [(CGFloat, CGFloat, CGFloat)] = [(-0.43, -0.36, 0.17), (0.44, -0.4, 0.13), (0.5, 0.02, 0.09)]
                    let (x, y, s) = spots[i]
                    let tw = 0.55 + 0.45 * CGFloat(abs(sin(p.clock * 3.1 + Double(i) * 2.1)))
                    HankSparkle()
                        .fill(i == 1 ? Palette.violet : HankColors.gold)
                        .frame(width: d * s, height: d * s)
                        .scaleEffect(tw * p.sparkle)
                        .rotationEffect(.degrees(Double(tw) * 25))
                        .offset(x: d * x, y: d * y)
                }
            }
        }
        .frame(width: d, height: d)
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes

/// Mouth: corners at the vertical centre; the upper lip dips by `smile`, the lower lip by `smile + open` (points).
struct HankMouthShape: Shape {
    var smile: CGFloat
    var open: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(smile, open) }
        set { smile = newValue.first; open = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = CGPoint(x: r.minX, y: r.midY), rt = CGPoint(x: r.maxX, y: r.midY)
        p.move(to: l)
        p.addQuadCurve(to: rt, control: CGPoint(x: r.midX, y: r.midY + 2 * smile))
        p.addQuadCurve(to: l, control: CGPoint(x: r.midX, y: r.midY + 2 * (smile + open)))
        p.closeSubpath()
        return p
    }
}

/// ^ (rounded arch for happy eyes, or a sharp chevron that becomes > < when rotated).
struct HankEyeArc: Shape {
    var sharp: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        if sharp {
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: 2 * r.minY - r.maxY))
        }
        return p
    }
}

/// A curved glint hugging the lower-right of a lens, plus a dot.
struct HankGlare: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), rad = r.width / 2
        p.addArc(center: c, radius: rad, startAngle: .degrees(18), endAngle: .degrees(62), clockwise: false)
        let a = 78.0 * Double.pi / 180
        let dot = CGPoint(x: c.x + rad * CGFloat(cos(a)), y: c.y + rad * CGFloat(sin(a)))
        p.move(to: dot); p.addLine(to: dot)
        return p
    }
}

/// /// anime-style blush hatching.
struct HankBlushLines: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<3 {
            let x = r.minX + r.width * (0.15 + 0.35 * CGFloat(i))
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.width * 0.2, y: r.minY))
        }
        return p
    }
}

/// Four-point twinkle.
struct HankSparkle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: c)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: c)
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: c)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: c)
        p.closeSubpath()
        return p
    }
}
