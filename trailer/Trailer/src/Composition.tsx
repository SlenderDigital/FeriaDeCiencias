import React from "react";
import { AbsoluteFill, Composition, Sequence } from "remotion";
import {
  Act1HookTitle,
  Act2ArenaThreats,
  Act3HandTrackingHero,
  Act4ClimaxMontage,
  Act5OutroCredits,
} from "./TrailerScenes";
import { TrailerAudioTrack } from "./TrailerAudioTrack";

export const MyComposition = () => {
  return (
    <Composition
      id="ShapesAndBeamsTrailer"
      component={ShapesAndBeamsTrailer}
      durationInFrames={1800}
      fps={60}
      width={1920}
      height={1080}
    />
  );
};

export const ShapesAndBeamsTrailer: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      {/* Audio Layer: 128 BPM Procedural Soundtrack + Synced Game WAV SFX */}
      <TrailerAudioTrack />

      {/* Act 1 (0s - 4s / 240f): Hook & Title Reveal */}
      <Sequence name="Act 1 - Hook & Title" durationInFrames={240}>
        <Act1HookTitle />
      </Sequence>

      {/* Act 2 (4s - 11s / 420f): The Arena & 45s Survival Threats */}
      <Sequence name="Act 2 - Arena & Threats" from={240} durationInFrames={420}>
        <Act2ArenaThreats />
      </Sequence>

      {/* Act 3 (11s - 19s / 480f): Hero Feature — MediaPipe Hand Tracking & Fist Shield */}
      <Sequence
        name="Act 3 - MediaPipe Hand Tracking"
        from={660}
        durationInFrames={480}
      >
        <Act3HandTrackingHero />
      </Sequence>

      {/* Act 4 (19s - 26s / 420f): Climax Montage synced to 128 BPM */}
      <Sequence name="Act 4 - Climax Montage" from={1140} durationInFrames={420}>
        <Act4ClimaxMontage />
      </Sequence>

      {/* Act 5 (26s - 30s / 240f): Outro & Feria de Ciencias Credits */}
      <Sequence name="Act 5 - Outro & Credits" from={1560} durationInFrames={240}>
        <Act5OutroCredits />
      </Sequence>
    </AbsoluteFill>
  );
};
