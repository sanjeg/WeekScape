//
//  Theme.swift
//  Weekend Planner
//
//  A small, centralized design system: spacing, radii, and the accent palette
//  used for color-coding plans. Keeping these in one place makes the UI feel
//  consistent and easy to retune.
//

import SwiftUI

enum Theme {
    // Spacing scale
    static let spacing1: CGFloat = 4
    static let spacing2: CGFloat = 8
    static let spacing3: CGFloat = 12
    static let spacing4: CGFloat = 16
    static let spacing5: CGFloat = 24

    // Corner radii
    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 14

    /// Share of the stream's height the pinned Wishlist card's rows may occupy
    /// before they scroll inside the card, so it never takes over the screen.
    static let wishlistRowsHeightFraction: CGFloat = 0.26

    /// Floor and ceiling for that share, so the card stays usable on a small
    /// screen and doesn't sprawl on a large one.
    static let wishlistRowsMinHeight: CGFloat = 96
    static let wishlistRowsMaxHeight: CGFloat = 220

    /// Row area cap for a stream of `containerHeight` points.
    static func wishlistRowsHeight(in containerHeight: CGFloat) -> CGFloat {
        let target = containerHeight * wishlistRowsHeightFraction
        return min(max(target, wishlistRowsMinHeight), wishlistRowsMaxHeight)
    }

    /// Backdrop for a subtle same-day grouping of plans inside a week card.
    static let dayGroupFill = Color.primary.opacity(0.04)

    static let cardShadow = Color.black.opacity(0.06)

    /// Rotating accent hue for week cards so the stream feels lively without
    /// being noisy. The current week is always the primary blue.
    static func weekAccent(for week: Week) -> PlanColor {
        if week.isCurrent { return .blue }
        let cycle: [PlanColor] = [.teal, .purple, .orange, .pink, .green]
        let index = ((week.offsetFromNow % cycle.count) + cycle.count) % cycle.count
        return cycle[index]
    }

    /// Soft multi-hue wash behind the week stream. Very low opacity so content
    /// stays legible in both light and dark mode.
    static var backgroundWash: some View {
        LinearGradient(
            colors: [
                PlanColor.blue.color.opacity(0.10),
                PlanColor.purple.color.opacity(0.06),
                PlanColor.pink.color.opacity(0.05),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(Color.plannerBackground)
        .ignoresSafeArea()
    }
}

/// Named accent colors for plans. Stored by raw value for CloudKit friendliness.
enum PlanColor: String, CaseIterable, Identifiable {
    case blue, teal, green, orange, pink, purple, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return Color(red: 0.30, green: 0.56, blue: 0.98)
        case .teal:   return Color(red: 0.16, green: 0.70, blue: 0.72)
        case .green:  return Color(red: 0.30, green: 0.72, blue: 0.44)
        case .orange: return Color(red: 0.96, green: 0.62, blue: 0.20)
        case .pink:   return Color(red: 0.95, green: 0.40, blue: 0.60)
        case .purple: return Color(red: 0.60, green: 0.44, blue: 0.94)
        case .gray:   return Color(red: 0.56, green: 0.60, blue: 0.66)
        }
    }

    /// A slightly brighter companion shade used for gradients.
    var lighter: Color {
        color.opacity(0.75)
    }

    /// Signature gradient for badges, buttons, and accents.
    var gradient: LinearGradient {
        LinearGradient(colors: [lighter, color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var displayName: String {
        rawValue.capitalized
    }
}

extension ShapeStyle where Self == Color {
    /// App background that adapts to light/dark mode.
    static var plannerBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Elevated surface color for cards.
    static var plannerSurface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
