//
//  Compatibility.swift
//  WeekScape
//
//  Small shims that apply iOS 26 "Liquid Glass" refinements when running on
//  iOS 26+, and fall back gracefully on earlier systems (iOS 17+). Keeping the
//  availability checks here lets the call sites stay clean.
//

import SwiftUI

extension View {
    /// Applies the iOS 26 hard scroll-edge effect at the top when available.
    /// On earlier systems this is a no-op — the standard scroll edge is used.
    @ViewBuilder
    func hardTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

extension ToolbarContent {
    /// Hides the shared Liquid Glass capsule behind a toolbar item on iOS 26.
    /// On earlier systems this is a no-op — there is no shared glass background.
    @ToolbarContentBuilder
    func plainToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
