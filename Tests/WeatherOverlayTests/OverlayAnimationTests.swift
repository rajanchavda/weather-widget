import XCTest
@testable import WeatherOverlayCore

final class OverlayAnimationTests: XCTestCase {
    func testFirstParticleFadesInFromTheStart() {
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 0, count: 10, elapsed: 0), 0)
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 0, count: 10, elapsed: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 0, count: 10, elapsed: 1.0), 1)
    }

    func testLaterParticlesJoinAcrossTheRamp() {
        // Particle 5 of 10 starts halfway through the 4 s ramp.
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 5, count: 10, elapsed: 1.9), 0)
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 5, count: 10, elapsed: 2.5), 0.5, accuracy: 0.0001)
    }

    func testEveryParticleIsFullyVisibleAfterRampAndFade() {
        let elapsed = OverlayAnimation.particleRampDuration + OverlayAnimation.particleFadeInDuration
        for index in 0..<40 {
            XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: index, count: 40, elapsed: elapsed), 1)
        }
    }

    func testFrozenFrameShowsFullStrength() {
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 39, count: 40, elapsed: .infinity), 1)
    }

    func testEmptyEffectIsFullyOpaque() {
        XCTAssertEqual(OverlayAnimation.particleRampOpacity(index: 0, count: 0, elapsed: 0), 1)
    }

    func testRampAndCrossfadeDurations() {
        XCTAssertEqual(OverlayAnimation.particleRampDuration, 4.0)
        XCTAssertEqual(OverlayAnimation.particleFadeInDuration, 1.0)
        XCTAssertEqual(OverlayAnimation.weatherCrossfadeDuration, 1.5)
    }
}
