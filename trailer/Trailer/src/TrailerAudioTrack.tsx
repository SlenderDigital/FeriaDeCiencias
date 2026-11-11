import React from "react";
import { interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio } from "@remotion/media";

// Custom 30s Trailer Audio Design using strictly the game's procedural sound system
// (music.wav @ 128 BPM + 13 procedural WAV SFX in public/audio/)
export const TrailerAudioTrack: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Segment 1 (0s - 19s / frames 0 - 1140): Plays Intro -> Verse -> Chorus of music.wav
  const seg1Vol = interpolate(
    frame,
    [0, 18, 1110, 1140],
    [0, 0.85, 0.85, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }
  );

  // Segment 2 (18.5s - 30s / frames 1110 - 1800): Jumps to Climax & Finale of music.wav (starts at 30.0s of music.wav)
  const seg2Vol = interpolate(
    frame,
    [1110, 1140, 1730, 1795],
    [0, 0.92, 0.92, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }
  );

  return (
    <>
      {/* Backing Track Segment 1: Intro -> Verse -> Chorus */}
      <Audio
        src={staticFile("audio/music.wav")}
        trimBefore={0}
        durationInFrames={19 * fps}
        volume={seg1Vol}
      />

      {/* Backing Track Segment 2: Climax -> Finale (from 30.0s of music.wav) */}
      <Audio
        from={1110}
        src={staticFile("audio/music.wav")}
        trimBefore={30 * fps}
        durationInFrames={11.5 * fps}
        volume={seg2Vol}
      />

      {/* =================================================================== */}
      {/* ACT 1 SFX (0s - 4s): Telegraph menu clicks + Laser + Title Explosion */}
      {/* =================================================================== */}
      <Audio from={6} src={staticFile("audio/menu.wav")} volume={0.65} />
      <Audio from={28} src={staticFile("audio/menu.wav")} volume={0.75} />
      <Audio from={56} src={staticFile("audio/laser.wav")} volume={0.9} />
      <Audio from={56} src={staticFile("audio/explosion.wav")} volume={0.85} />
      <Audio from={84} src={staticFile("audio/shield_on.wav")} volume={0.7} />

      {/* =================================================================== */}
      {/* ACT 2 SFX (4s - 11s): Arena Threats, Lasers, Saws & Wall Slam       */}
      {/* =================================================================== */}
      <Audio from={240} src={staticFile("audio/laser.wav")} volume={0.85} />
      <Audio from={315} src={staticFile("audio/enemy_fire.wav")} volume={0.75} />
      <Audio from={380} src={staticFile("audio/saw_bounce.wav")} volume={0.8} />
      <Audio from={450} src={staticFile("audio/wall_slam.wav")} volume={0.95} />
      <Audio from={530} src={staticFile("audio/enemy_lunge.wav")} volume={0.8} />
      <Audio from={600} src={staticFile("audio/explosion.wav")} volume={0.8} />

      {/* =================================================================== */}
      {/* ACT 3 SFX (11s - 19s): MediaPipe Hand Tracking & Fist Shield Block  */}
      {/* =================================================================== */}
      <Audio from={660} src={staticFile("audio/menu.wav")} volume={0.8} />
      <Audio from={664} src={staticFile("audio/shield_on.wav")} volume={0.75} />
      {/* At 15s (frame 900 = 660 + 240): Fist closes -> Shield activates & blocks projectiles! */}
      <Audio from={900} src={staticFile("audio/shield_on.wav")} volume={1.0} />
      <Audio from={952} src={staticFile("audio/shield_block.wav")} volume={0.95} />
      <Audio from={980} src={staticFile("audio/shield_block.wav")} volume={0.95} />
      <Audio from={1008} src={staticFile("audio/shield_block.wav")} volume={0.95} />
      <Audio from={1042} src={staticFile("audio/shield_block.wav")} volume={1.0} />

      {/* =================================================================== */}
      {/* ACT 4 SFX (19s - 26s): Climax Rapid Cuts Synced to 128 BPM          */}
      {/* =================================================================== */}
      <Audio from={1140} src={staticFile("audio/explosion.wav")} volume={0.95} />
      <Audio from={1196} src={staticFile("audio/enemy_fire.wav")} volume={0.8} />
      <Audio from={1252} src={staticFile("audio/wall_slam.wav")} volume={0.95} />
      <Audio from={1310} src={staticFile("audio/laser.wav")} volume={0.85} />
      <Audio from={1364} src={staticFile("audio/shield_on.wav")} volume={0.9} />
      <Audio from={1420} src={staticFile("audio/saw_bounce.wav")} volume={0.85} />
      <Audio from={1476} src={staticFile("audio/explosion.wav")} volume={0.95} />
      <Audio from={1480} src={staticFile("audio/laser.wav")} volume={0.85} />

      {/* =================================================================== */}
      {/* ACT 5 SFX (26s - 30s): Outro Feria de Ciencias + Victory Fanfare    */}
      {/* =================================================================== */}
      <Audio from={1560} src={staticFile("audio/victory.wav")} volume={1.0} />
      <Audio from={1562} src={staticFile("audio/shield_on.wav")} volume={0.75} />
    </>
  );
};
