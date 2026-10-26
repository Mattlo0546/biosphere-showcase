import SwiftUI

/// A draggable divider between panels. Drag to resize, double-click to reset.
/// `growsRight`: true when the panel being sized sits to the LEFT of the handle.
/// `snap` maps the raw dragged width to the stored one (use it to collapse/clamp).
struct ResizeHandle: View {
    @Binding var width: Double
    var growsRight: Bool
    var defaultWidth: Double
    var snap: (Double) -> Double
    @State private var start: Double?
    @State private var hover = false
    @State private var cursorPushed = false

    var body: some View {
        let active = hover || start != nil
        Rectangle()
            .fill(active ? Palette.violet.opacity(0.7) : Palette.stroke)
            .frame(width: active ? 2 : 1)
            .frame(maxHeight: .infinity)
            .overlay(
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())
                    .onHover { h in
                        hover = h
                        if h && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
                        if !h && start == nil && cursorPushed { NSCursor.pop(); cursorPushed = false }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in
                                if start == nil { start = width }
                                let raw = start! + (growsRight ? v.translation.width : -v.translation.width)
                                width = snap(raw)
                            }
                            .onEnded { _ in
                                start = nil
                                if !hover && cursorPushed { NSCursor.pop(); cursorPushed = false }
                            }
                    )
                    .onTapGesture(count: 2) { withAnimation(.snappy) { width = defaultWidth } }
            )
            .zIndex(10)
            .help("Drag to resize · double-click to reset")
    }
}

enum PanelWidth {
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
