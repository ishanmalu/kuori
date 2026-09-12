import Foundation
import QuartzCore

/// Motion primitives for the wheel.
///
/// The HUD is one custom-drawn view rather than a tree of layers, so nothing
/// animates itself — every moving quantity is a number here that the view
/// advances once per frame and then reads while drawing. Springs for anything
/// that chases a target (hover, progress), a plain clock for anything that
/// plays once and stops (the entrance, a success pulse).
struct Spring {
    var value: CGFloat = 0
    var target: CGFloat = 0
    private var velocity: CGFloat = 0

    /// Critically-damped-ish by default: quick, no visible overshoot.
    var stiffness: CGFloat = 220
    var damping: CGFloat = 27

    init(_ initial: CGFloat = 0) { value = initial; target = initial }

    /// Semi-implicit Euler. `dt` is clamped by the caller — a dropped frame
    /// must not be integrated in one step or the spring explodes.
    mutating func step(_ dt: CGFloat) {
        let force = -stiffness * (value - target) - damping * velocity
        velocity += force * dt
        value += velocity * dt
    }

    var settled: Bool { abs(value - target) < 0.0015 && abs(velocity) < 0.02 }

    mutating func snap(to x: CGFloat) { value = x; target = x; velocity = 0 }
}

enum Ease {
    static func clamp(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }

    static func out(_ t: CGFloat) -> CGFloat {
        let t = clamp(t)
        return 1 - pow(1 - t, 3)
    }

    /// Overshoots a little before settling — what makes the petals feel thrown
    /// outward rather than stretched.
    static func outBack(_ t: CGFloat, _ overshoot: CGFloat = 1.5) -> CGFloat {
        let t = clamp(t) - 1
        return 1 + (overshoot + 1) * t * t * t + overshoot * t * t
    }

    static func inOut(_ t: CGFloat) -> CGFloat {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

/// A one-shot timeline. `start()` marks now; `elapsed` counts from there.
struct Clock {
    private var began: CFTimeInterval?
    var duration: CFTimeInterval

    init(duration: CFTimeInterval) { self.duration = duration }

    mutating func start() { began = CACurrentMediaTime() }
    mutating func stop() { began = nil }

    var running: Bool { elapsed.map { $0 < duration } ?? false }
    var elapsed: CFTimeInterval? { began.map { CACurrentMediaTime() - $0 } }

    /// 0…1 across `duration`, or nil when the clock was never started.
    var progress: CGFloat? {
        elapsed.map { Ease.clamp(CGFloat($0 / duration)) }
    }
}
