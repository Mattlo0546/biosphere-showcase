import SwiftUI
import AppKit

/// Debug-only contact sheet for reviewing Hank: every mood at 18 / 28 / 48 / 120pt plus a strip of
/// frames from each mood's animation. Call `HankPreview.renderSheet(to:)` from anywhere on the main actor.
enum HankPreview {
    @MainActor static func renderSheet(to url: URL) {
        let renderer = ImageRenderer(content: HankContactSheet())
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

extension HankRig {
    /// A representative still for each mood (eyes open, mid-gesture).
    static func sample(_ mood: HankMood) -> HankPose {
        switch mood {
        case .idle: return still(mood, t: 0.5, since: 100)
        case .listening: return still(mood, t: 0.5, since: 100, gaze: 0.6)
        case .surprised: return still(mood, t: 0.5, since: 0.62)
        case .thinking: return still(mood, t: 0.62, since: 100)
        case .talking: return still(mood, t: 2.0, since: 100)
        case .happy: return still(mood, t: 0.3, since: 100)
        case .blush: return still(mood, t: 0.4, since: 0.65)
        }
    }

    /// A handful of frames across the mood's motion, with short captions.
    static func storyboard(_ mood: HankMood) -> [(String, HankPose)] {
        switch mood {
        case .idle:
            return [("rest", still(mood, t: 0.5, since: 100)), ("glance", still(mood, t: 5.2, since: 100, seed: 4)),
                    ("blink", { var p = still(mood, t: 0.5, since: 100); p.eyeOpen = 0; return p }()),
                    ("breathe", still(mood, t: 0.85, since: 100))]
        case .listening:
            return [-1.0, -0.35, 0.35, 1.0].map { g in ("gaze \(g)", still(mood, t: 0.5, since: 100, gaze: CGFloat(g))) }
        case .surprised:
            return [0.05, 0.22, 0.4, 0.62, 1.5].map { s in ("\(s)s", still(mood, t: 0.5, since: s)) }
        case .thinking:
            return [0.0, 0.24, 0.48, 0.72].map { t in ("\(t)s", still(mood, t: 0.3 + t, since: 100)) }
        case .talking:
            return [1.7, 1.9, 2.0, 2.15, 3.9].map { t in ("\(t)s", still(mood, t: t, since: 100)) }
        case .happy:
            return [0.05, 0.16, 0.32, 1.5].map { s in ("\(s)s", still(mood, t: 0.3, since: s)) }
        case .blush:
            return [0.03, 0.1, 0.4, 2.2].map { s in ("\(s)s", still(mood, t: 0.4, since: s)) }
        }
    }

    private static func still(_ mood: HankMood, t: Double, since: Double, gaze: CGFloat = 0, seed: Double = 0) -> HankPose {
        var p = pose(mood, t: t, since: since, gaze: gaze, seed: seed, motion: 1)
        if p.eyeOpen < 1 && mood != .blush { p.eyeOpen = 1 }
        return p
    }
}

private struct HankContactSheet: View {
    let sizes: [CGFloat] = [18, 28, 48, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hank · contact sheet").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
            Text("sizes 18 · 28 · 48 · 120pt, then frames from each animation at 56pt")
                .font(.system(size: 12)).foregroundStyle(Palette.dim).padding(.bottom, 14)
            ForEach(HankMood.allCases, id: \.self) { mood in
                HStack(alignment: .center, spacing: 22) {
                    Text(mood.rawValue).font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.lilac).frame(width: 82, alignment: .leading)
                    ForEach(sizes, id: \.self) { s in
                        HankFace(size: s, pose: HankRig.sample(mood)).frame(width: max(s, 30), height: 150)
                    }
                    Rectangle().fill(Palette.stroke).frame(width: 1, height: 110)
                    ForEach(Array(HankRig.storyboard(mood).enumerated()), id: \.offset) { _, frame in
                        VStack(spacing: 6) {
                            HankFace(size: 56, pose: frame.1).frame(width: 70, height: 84)
                            Text(frame.0).font(.system(size: 9.5)).foregroundStyle(Palette.faint)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(Palette.stroke)
            }
            Text("in context").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Palette.lilac)
                .padding(.top, 16).padding(.bottom, 8)
            HStack(spacing: 22) {
                HStack(spacing: 6) { HankFace(size: 18, pose: HankRig.sample(.idle)); Text("Ask Hank") }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Palette.cardHi, in: Capsule()).overlay(Capsule().strokeBorder(Palette.stroke))
                HStack(spacing: 8) {
                    HankFace(size: 24, pose: HankRig.sample(.idle))
                    Text("Hank says hi").font(.system(size: 13)).foregroundStyle(Palette.text)
                }
                .padding(10).background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 10) {
                    HankFace(size: 52, pose: HankRig.sample(.talking))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hank").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                        Text("typing…").font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                }
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
                HankFace(size: 34, pose: HankRig.sample(.happy)).padding(8).background(Palette.purple, in: Circle())
                HankAvatar(size: 34, mood: .idle)   // the live view, rendered through its TimelineView
            }
        }
        .padding(28)
        .frame(width: 1240, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
