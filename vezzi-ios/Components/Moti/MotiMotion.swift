import Foundation

/// Authored gestures use a common resting pose at the start and end of every cycle.
struct MotiMotion {
    struct Frame {
        let time: TimeInterval
        let pose: MotiPose
    }

    let frames: [Frame]
    let repeats: Bool
    var duration: TimeInterval { frames.last?.time ?? 0 }
    var restingPose: MotiPose { frames[0].pose }

    init(state: MotiMascotView.State) {
        let base: MotiPose
        let duration: TimeInterval
        let gestures: [(TimeInterval, (inout MotiPose) -> Void)]
        switch state {
        case .idle:
            base = MotiPose()
            duration = 4.8
            gestures = [
                (0.55, { $0.gazeX = 0.9; $0.lift = 1; $0.mouthOpen = 0.04 }),
                (0.95, { $0.gazeX = 0.9; $0.lift = 2 }),
                (1.4, { $0.gazeX = -0.9; $0.lift = 2 }),
                (1.6, { $0.gazeX = -0.9; $0.lift = 2 }),
                (1.71, { $0.gazeX = -0.9; $0.leftEye = 0.02; $0.rightEye = 0.02; $0.lift = 2 }),
                (1.84, { $0.gazeX = -0.9; $0.lift = 2 }),
                (2.35, { $0.lift = 1 }),
                (2.8, { $0.smile = 1; $0.mouthOpen = 0.18; $0.tilt = -1 }),
                (3.05, { $0.smile = 1; $0.mouthOpen = 0.03 }),
                (3.45, { $0.rightEye = 0.03; $0.eyeSmile = 1; $0.tilt = -1.5 }),
                (3.62, { $0.smile = 1 }),
            ]
        case .typing:
            base = MotiPose(brows: 1, isTyping: true)
            duration = 3.2
            gestures = [
                (0.5, { $0.gazeX = 0.3; $0.lift = 1 }),
                (1.1, { $0.gazeX = -0.2 }),
                (1.65, { $0.mouthOpen = 0.04 }),
                (2, { $0.gazeX = 0.1 }),
                (2.1, { $0.leftEye = 0.02; $0.rightEye = 0.02 }),
                (2.23, { $0.gazeX = 0.1 }),
            ]
        case .error:
            base = MotiPose(leftEye: 0.72, rightEye: 0.72, smile: -0.7, brows: 0.8, tilt: -2)
            duration = 1.2
            gestures = [
                (0.18, { $0.tilt = 2; $0.leftEye = 0.5; $0.rightEye = 0.5 }),
                (0.36, { $0.tilt = -2.5; $0.mouthOpen = 0.12 }),
                (0.58, { $0.leftEye = 0.05; $0.rightEye = 0.05; $0.mouthOpen = 0.08 }),
                (0.8, { $0.leftEye = 0.6; $0.rightEye = 0.6 }),
            ]
        case .loading:
            base = MotiPose(smile: 0.35, mouthOpen: 0.08, brows: 0.2, tilt: -1)
            duration = 2.2
            gestures = [
                (0.38, { $0.gazeX = 0.65; $0.mouthOpen = 0.25; $0.brows = 0.4; $0.tilt = 2; $0.lift = 2 }),
                (0.76, { $0.gazeX = 0.1; $0.mouthOpen = 0.02 }),
                (1.05, { $0.leftEye = 0.02; $0.rightEye = 0.02; $0.lift = 1 }),
                (1.18, { $0.gazeX = -0.3 }),
                (1.65, { $0.mouthOpen = 0.18; $0.tilt = -2; $0.gazeX = -0.4 }),
            ]
        case .success:
            base = MotiPose(leftEye: 0.04, rightEye: 0.04, eyeSmile: 1, smile: 1, mouthOpen: 0.75)
            duration = 0.62
            gestures = [
                (0.15, { $0.mouthOpen = 1; $0.lift = 8; $0.stretch = 1.025; $0.tilt = -1.5 }),
                (0.3, { $0.mouthOpen = 0.6; $0.lift = 3 }),
                (0.47, { $0.mouthOpen = 0.95; $0.lift = 1; $0.tilt = 1 }),
            ]
        }
        frames = [Frame(time: 0, pose: base)] + gestures.map { time, edit in
            var pose = base
            edit(&pose)
            return Frame(time: time, pose: pose)
        } + [Frame(time: duration, pose: base)]
        repeats = state != .error && state != .success
    }
}
