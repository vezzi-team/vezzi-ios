# Moti source artwork

The PNGs and SVG expressions in this folder are the original references supplied for the app. They are kept for editing and are not copied into the app bundle. Only `Yarn.png` is copied into the `MotiYarn` image asset.

The login mascot uses Core Animation for interruptible expression morphing. `MotiFaceGeometry` builds matching Bézier contours for the eyes, eyelids, mouth, brows, highlights, and cheeks. `MotiMotion` contains the authored idle, typing, error, loading, and success gestures. `MotiAnimationView` blends from each layer's current presentation value, so a new emotion can interrupt a blink or another transition without resetting the face.

The transition takes 0.26 seconds. The gestures run on Core Animation without a display link, timer, or per-frame SwiftUI state. Error and success play once; the other states loop with matching start/end poses. Reduce Motion, inactive scenes, and removal from the window stop playback and display the requested emotion's resting pose.

The original `MotiSplash.json` remains unchanged and continues to use Lottie.

`Typing.svg` is the supplied close-up reference for the typing expression. Its raised brows, asymmetric eye angles, downward highlights, cheeks, and smile are mapped into the same face rig. Idle gestures move the pupils right and left while keeping the brows and mouth anchored.
