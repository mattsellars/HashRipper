//
//  Color+Helpers.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import SwiftUI

extension Color {
    /// A “traffic-light” gradient that runs
    ///   green ➝ yellow ➝ red as the **value** rises.
    ///
    /// * `value   ≤ low`   → `Color.green`
    /// * `low  …  mid`    → green-to-yellow gradient
    /// * `mid  …  high`   → yellow-to-red   gradient
    /// * `value   ≥ high`  → `Color.red`
    ///
    /// You can tweak `low`, `mid`, and `high` if your thresholds ever change.
    static func tempGradient(
        for value: Double?,
        low:  Double = 45,
        mid:  Double = 60,
        high: Double = 68
    ) -> Color {

        /// Build a SwiftUI `Color` from a hue in degrees (0–360).
        @inline(__always)
        func color(fromHue degrees: Double) -> Color {
            Color(hue: degrees / 360, saturation: 1, brightness: 1)
        }

        guard let value = value else {
            return .green
        }

        switch value {
        case ..<low:              // below 45 → pure green
            return .green

        case low..<mid:           // 45–55: green (120°) → yellow (60°)
            let proportion = (value - low) / (mid - low)          // 0…1
            let hueDeg     = 120 - 60 * proportion                // 120°→60°
            return color(fromHue: hueDeg)

        case mid..<high:          // 55–63: yellow (60°) → red (0°)
            let proportion = (value - mid) / (high - mid)         // 0…1
            let hueDeg     =  60 - 60 * proportion                // 60°→0°
            return color(fromHue: hueDeg)

        default:                  // 63 and above → pure red
            return .red
        }
    }
}
