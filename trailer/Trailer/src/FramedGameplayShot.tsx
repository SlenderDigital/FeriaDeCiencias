import React from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Video } from "@remotion/media";
import { FONTS, getKickEnvelope } from "./GameVisuals";

export const FramedGameplayShot: React.FC<{
  trimBeforeSec: number;
  durationSec: number;
  mode?: "floating" | "fullbleed";
  zoomFrom?: number;
  zoomTo?: number;
  focusX?: number; // -200 to 200 px offset
  focusY?: number;
  badgeText?: string;
  headlineText?: string;
  subText?: string;
  alignText?: "left" | "right" | "bottom-left";
}> = ({
  trimBeforeSec,
  durationSec,
  mode = "floating",
  zoomFrom = 1.04,
  zoomTo = 1.16,
  focusX = 0,
  focusY = 0,
  badgeText,
  headlineText,
  subText,
  alignText = "left",
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const totalFrames = Math.round(durationSec * fps);
  const kick = getKickEnvelope(frame, fps);

  const scale = interpolate(frame, [0, totalFrames], [zoomFrom, zoomTo], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const textEnter = interpolate(frame, [4, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.16, 1, 0.3, 1),
  });

  const textExit = interpolate(
    frame,
    [totalFrames - 12, totalFrames],
    [1, 0],
    {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    }
  );

  const textOpacity = textEnter * textExit;

  return (
    <AbsoluteFill>
      {mode === "fullbleed" ? (
        <AbsoluteFill style={{ overflow: "hidden", backgroundColor: "#000" }}>
          <Video
            src={staticFile("recording.mp4")}
            muted
            trimBefore={Math.round(trimBeforeSec * fps)}
            durationInFrames={totalFrames}
            objectFit="cover"
            style={{
              width: "100%",
              height: "100%",
              scale: `${scale + kick * 0.015}`,
              translate: `${focusX}px ${focusY}px`,
            }}
          />
          {/* Subtle dark vignette for text legibility */}
          <AbsoluteFill
            style={{
              background:
                "radial-gradient(circle at center, rgba(0,0,0,0.08) 45%, rgba(0,0,0,0.82) 100%)",
              pointerEvents: "none",
            }}
          />
        </AbsoluteFill>
      ) : (
        /* Floating HUD frame over the ArenaGridBackground (8:5 native aspect ratio -> 1088x680) */
        <AbsoluteFill
          style={{
            justifyContent: "center",
            alignItems: alignText === "left" ? "flex-end" : "flex-start",
            paddingLeft: 96,
            paddingRight: 96,
          }}
        >
          <div
            style={{
              width: 1088,
              height: 680,
              position: "relative",
              backgroundColor: "#050505",
              border: `2px solid rgba(255, 255, 255, ${0.7 + kick * 0.3})`,
              boxShadow: `0 0 ${32 + kick * 24}px rgba(255, 255, 255, ${
                0.15 + kick * 0.12
              }), 0 28px 70px rgba(0,0,0,0.9)`,
              overflow: "hidden",
              scale: `${interpolate(frame, [0, 18], [0.92, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.out(Easing.back(1.2)),
              })}`,
            }}
          >
            <Video
              src={staticFile("recording.mp4")}
              muted
              trimBefore={Math.round(trimBeforeSec * fps)}
              durationInFrames={totalFrames}
              objectFit="cover"
              style={{
                width: "100%",
                height: "100%",
                scale: `${scale}`,
                translate: `${focusX}px ${focusY}px`,
              }}
            />
            {/* Corner HUD brackets */}
            {[
              { top: 10, left: 10, borderTop: "3px solid #fff", borderLeft: "3px solid #fff" },
              { top: 10, right: 10, borderTop: "3px solid #fff", borderRight: "3px solid #fff" },
              { bottom: 10, left: 10, borderBottom: "3px solid #fff", borderLeft: "3px solid #fff" },
              { bottom: 10, right: 10, borderBottom: "3px solid #fff", borderRight: "3px solid #fff" },
            ].map((pos, i) => (
              <div
                key={i}
                style={{
                  position: "absolute",
                  width: 22,
                  height: 22,
                  ...pos,
                }}
              />
            ))}
          </div>
        </AbsoluteFill>
      )}

      {/* Kinetic Typography Callout */}
      {(badgeText || headlineText || subText) && (
        <div
          style={{
            position: "absolute",
            ...(alignText === "left"
              ? { left: 88, top: 250, width: 610 }
              : alignText === "right"
              ? { right: 88, top: 250, width: 610 }
              : { left: 88, bottom: 84, width: 980 }),
            opacity: textOpacity,
            translate: `0px ${interpolate(textEnter, [0, 1], [28, 0])}px`,
            display: "flex",
            flexDirection: "column",
            gap: 16,
            backgroundColor:
              mode === "fullbleed" ? "rgba(6, 6, 6, 0.84)" : "rgba(8, 8, 8, 0.92)",
            border: "2px solid rgba(255, 255, 255, 0.88)",
            padding: "28px 34px",
            boxShadow: "0 0 36px rgba(255,255,255,0.14)",
          }}
        >
          {badgeText && (
            <div
              style={{
                display: "inline-flex",
                alignSelf: "flex-start",
                alignItems: "center",
                gap: 10,
                backgroundColor: "#ffffff",
                color: "#000000",
                fontFamily: FONTS.mono,
                fontSize: 16,
                fontWeight: 700,
                letterSpacing: 2.5,
                padding: "6px 14px",
                textTransform: "uppercase",
              }}
            >
              <span>◆</span>
              <span>{badgeText}</span>
            </div>
          )}
          {headlineText && (
            <div
              style={{
                fontFamily: FONTS.heading,
                fontSize: mode === "fullbleed" ? 54 : 50,
                fontWeight: 700,
                color: "#ffffff",
                lineHeight: 1.06,
                letterSpacing: -1,
                textTransform: "uppercase",
              }}
            >
              {headlineText}
            </div>
          )}
          {subText && (
            <div
              style={{
                fontFamily: FONTS.mono,
                fontSize: 21,
                fontWeight: 400,
                color: "#cfcfcf",
                lineHeight: 1.4,
              }}
            >
              {subText}
            </div>
          )}
        </div>
      )}
    </AbsoluteFill>
  );
};
