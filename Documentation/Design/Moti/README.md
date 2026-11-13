# Moti source artwork

The PNGs and SVG expressions in this folder are the original references supplied for the app. The yarn is bundled as `MotiYarn`; its 750-pixel source comes from the same artwork in Figma. `Winking.svg` and `Thinking.svg` are also bundled as vector face assets for the static empty states.

`MotiEmptyStateView` composes these faces over the yarn using the placement from Figma nodes `777:4679` and `777:8074`. Empty lists use the wink; empty search results and offline feedback use the sad expression. These illustrations do not run timers or animation loops.

The login mascot uses Core Animation for interruptible expression morphing. `MotiFaceGeometry` builds matching Bézier contours for the eyes, eyelids, mouth, brows, highlights, and cheeks. `MotiMotion` contains the authored idle, typing, error, loading, and success gestures. `MotiAnimationView` blends from each layer's current presentation value, so a new emotion can interrupt a blink or another transition without resetting the face.

The transition takes 0.26 seconds. The gestures run on Core Animation without a display link, timer, or per-frame SwiftUI state. Error and success play once; the other states loop with matching start/end poses. Reduce Motion, inactive scenes, and removal from the window stop playback and display the requested emotion's resting pose.

The original `MotiSplash.json` remains unchanged and continues to use Lottie.

`Typing.svg` is the supplied close-up reference for the typing expression. Its raised brows, asymmetric eye angles, downward highlights, cheeks, and smile are mapped into the same face rig. Idle gestures move the pupils right and left while keeping the brows and mouth anchored.
