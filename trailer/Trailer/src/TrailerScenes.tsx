import React from "react";
import {
  AbsoluteFill,
  Easing,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Video } from "@remotion/media";
import {
  ArenaGridBackground,
  CutFlashOverlay,
  FONTS,
  HandSkeletonSVG,
  getKickEnvelope,
  getSawPolygonPoints,
  getStarPolygonPoints,
  getSweptTrianglePoints,
} from "./GameVisuals";
import { FramedGameplayShot } from "./FramedGameplayShot";

// ============================================================================
// ACT 1 (0s - 4s / 240 frames): HOOK & TITLE REVEAL
// ============================================================================
export const Act1HookTitle: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const kick = getKickEnvelope(frame, fps);

  // Diagonal Light Beams telegraphing (0 - 65f) then firing (65f - 105f)
  const beamTelegraph = interpolate(frame, [5, 56], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const beamFire = frame >= 56 && frame <= 95;
  const beamFade = interpolate(frame, [56, 95], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Title slam at frame 56 (0.93s, right on Beat 3!)
  const titleSpring = interpolate(frame, [54, 76], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.back(1.6)),
  });

  const subtitleOpacity = interpolate(frame, [82, 108], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const actFadeOut = interpolate(frame, [224, 240], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ opacity: actFadeOut }}>
      <ArenaGridBackground energy={0.65} pulse={beamFire ? 0.9 : kick * 0.35} />

      {/* Background subtle gameplay glimpse in low opacity after beat drop */}
      {frame >= 56 && (
        <AbsoluteFill style={{ opacity: 0.24 }}>
          <Video
            src={staticFile("recording.mp4")}
            muted
            trimBefore={Math.round(16 * fps)}
            durationInFrames={190}
            objectFit="cover"
            style={{
              width: "100%",
              height: "100%",
              scale: `${1.08 + frame * 0.0005}`,
            }}
          />
        </AbsoluteFill>
      )}

      {/* Vector Light Beams & Geometric Shapes */}
      <svg
        width={width}
        height={height}
        style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      >
        {/* Crossing Diagonal Light Beam 1 */}
        <g transform={`translate(${width * 0.5}, ${height * 0.5}) rotate(-18)`}>
          {frame < 56 ? (
            <>
              <rect
                x={-1400}
                y={-28}
                width={2800}
                height={56}
                fill={`rgba(90,90,90,${0.25 + 0.35 * beamTelegraph})`}
              />
              <rect
                x={-1400}
                y={-28 * Math.pow(beamTelegraph, 1.6)}
                width={2800}
                height={56 * Math.pow(beamTelegraph, 1.6)}
                fill={`rgba(235,235,235,${0.6 + 0.35 * beamTelegraph})`}
              />
            </>
          ) : (
            <rect
              x={-1400}
              y={-36 * beamFade}
              width={2800}
              height={72 * beamFade}
              fill={`rgba(255,255,255,${beamFade})`}
            />
          )}
        </g>

        {/* Crossing Diagonal Light Beam 2 */}
        <g transform={`translate(${width * 0.5}, ${height * 0.5}) rotate(16)`}>
          {frame < 56 ? (
            <>
              <rect
                x={-1400}
                y={-24}
                width={2800}
                height={48}
                fill={`rgba(90,90,90,${0.25 + 0.35 * beamTelegraph})`}
              />
              <rect
                x={-1400}
                y={-24 * Math.pow(beamTelegraph, 1.6)}
                width={2800}
                height={48 * Math.pow(beamTelegraph, 1.6)}
                fill={`rgba(235,235,235,${0.6 + 0.35 * beamTelegraph})`}
              />
            </>
          ) : (
            <rect
              x={-1400}
              y={-30 * beamFade}
              width={2800}
              height={60 * beamFade}
              fill={`rgba(255,255,255,${beamFade})`}
            />
          )}
        </g>

        {/* Orbiting Saws & Chasers in corners */}
        <g
          transform={`translate(250, 220) rotate(${frame * 4.2}) scale(${interpolate(
            frame,
            [20, 56],
            [0, 1.3],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
          )})`}
        >
          <polygon
            points={getSawPolygonPoints(46, 16, 0.7)}
            fill="rgba(245,245,245,0.9)"
          />
          <circle cx={0} cy={0} r={20} fill="#0b0b0b" stroke="#fff" strokeWidth={2} />
        </g>

        <g
          transform={`translate(${width - 250}, ${height - 220}) rotate(${-frame * 3.6}) scale(${interpolate(
            frame,
            [30, 64],
            [0, 1.35],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
          )})`}
        >
          <polygon
            points={getStarPolygonPoints(48, 25, 8)}
            fill="rgba(245,245,245,0.9)"
          />
          <circle cx={0} cy={0} r={22} fill="#0b0b0b" stroke="#fff" strokeWidth={2} />
        </g>
      </svg>

      {/* Center Player Core before title slam */}
      {frame < 56 && (
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
          <div
            style={{
              width: 44,
              height: 44,
              backgroundColor: "#ffffff",
              boxShadow: `0 0 ${45 + beamTelegraph * 55}px #ffffff`,
              scale: `${interpolate(frame, [0, 55], [0.4, 1.35])}`,
            }}
          />
        </AbsoluteFill>
      )}

      {/* Title Card Reveal at frame 56 */}
      {frame >= 54 && (
        <AbsoluteFill
          style={{
            justifyContent: "center",
            alignItems: "center",
            flexDirection: "column",
            gap: 24,
          }}
        >
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 12,
              border: "2px solid rgba(255,255,255,0.85)",
              backgroundColor: "rgba(10,10,10,0.9)",
              padding: "8px 22px",
              fontFamily: FONTS.mono,
              fontSize: 18,
              fontWeight: 700,
              color: "#ffffff",
              letterSpacing: 4,
              opacity: subtitleOpacity,
            }}
          >
            <span>◆ FERIA DE CIENCIAS • ETEC MENDOZA ◆</span>
          </div>

          <div
            style={{
              fontFamily: FONTS.heading,
              fontSize: 132,
              fontWeight: 700,
              color: "#ffffff",
              letterSpacing: 6,
              lineHeight: 0.98,
              textShadow: `0 0 ${38 + kick * 28}px rgba(255, 255, 255, 0.55)`,
              scale: `${interpolate(titleSpring, [0, 1], [0.72, 1 + kick * 0.018])}`,
              opacity: interpolate(frame, [54, 64], [0, 1], {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
              }),
              padding: "16px 48px",
              backgroundColor: "rgba(0,0,0,0.78)",
              border: "3px solid #ffffff",
            }}
          >
            SHAPES & BEAMS
          </div>

          <div
            style={{
              fontFamily: FONTS.mono,
              fontSize: 27,
              fontWeight: 700,
              color: "#e0e0e0",
              letterSpacing: 5,
              textTransform: "uppercase",
              opacity: subtitleOpacity,
              backgroundColor: "rgba(0,0,0,0.85)",
              padding: "10px 28px",
              border: "1px solid rgba(255,255,255,0.4)",
            }}
          >
            SUPERVIVENCIA GEOMÉTRICA • VISIÓN ARTIFICIAL EN TIEMPO REAL
          </div>
        </AbsoluteFill>
      )}

      {frame >= 56 && frame < 70 && (
        <Sequence from={56} durationInFrames={14}>
          <CutFlashOverlay durationInFrames={14} maxOpacity={0.85} />
        </Sequence>
      )}
    </AbsoluteFill>
  );
};

// ============================================================================
// ACT 2 (4s - 11s / 420 frames): THE ARENA & 45s SURVIVAL THREATS
// ============================================================================
export const Act2ArenaThreats: React.FC = () => {
  return (
    <AbsoluteFill>
      <ArenaGridBackground energy={0.72} showCenterReticle={false} />

      {/* Sub-shot 2A (0 - 210f / 3.5s): 45s Survival & Light Beams / Filling Circles */}
      <Sequence durationInFrames={210}>
        <FramedGameplayShot
          trimBeforeSec={34.2}
          durationSec={3.5}
          mode="floating"
          zoomFrom={1.0}
          zoomTo={1.04}
          alignText="left"
          badgeText="OBJETIVO: 45 SEGUNDOS"
          headlineText="ESQUIVÁ EL CAOS GEOMÉTRICO"
          subText="Rayos láser telegrafiados, círculos expansivos y proyectiles radiales en una arena cerrada."
        />
        <CutFlashOverlay durationInFrames={10} maxOpacity={0.55} />
      </Sequence>

      {/* Sub-shot 2B (210 - 420f / 3.5s): Closing Walls, Saws & Autonomous Enemies */}
      <Sequence from={210} durationInFrames={210}>
        <FramedGameplayShot
          trimBeforeSec={41.8}
          durationSec={3.5}
          mode="floating"
          zoomFrom={1.0}
          zoomTo={1.04}
          alignText="right"
          badgeText="DIRECTOR DE OLEADAS"
          headlineText="AMENAZAS DINÁMICAS"
          subText="Muros de cierre, sierras rebotadoras y 4 tipos de enemigos autónomos al ritmo de 128 BPM."
        />
        <CutFlashOverlay durationInFrames={10} maxOpacity={0.55} />
      </Sequence>
    </AbsoluteFill>
  );
};

// ============================================================================
// ACT 3 (11s - 19s / 480 frames): HERO FEATURE — MEDIAPIPE HAND TRACKING & FIST SHIELD
// ============================================================================
export const Act3HandTrackingHero: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const kick = getKickEnvelope(frame, fps);

  // Interactive vector Hand Skeleton choreography on the left panel
  // 0 - 240f: Open palm moving smoothly in a figure-8 path
  // 240 - 480f: Hand clenches into a fist -> Shield Ring activates and blocks incoming projectiles!
  const fistProgress = interpolate(frame, [238, 258], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const handOffsetX = Math.sin(frame * 0.055) * (frame < 240 ? 48 : 16);
  const handOffsetY = Math.cos(frame * 0.04) * (frame < 240 ? 34 : 12);

  const isSecondHalf = frame >= 240;

  return (
    <AbsoluteFill>
      <ArenaGridBackground energy={0.82} pulse={isSecondHalf ? 0.45 : 0.2} />

      {/* Right Side: Live Gameplay Recording showing actual hand skeleton & shield in action */}
      <Sequence durationInFrames={240}>
        <FramedGameplayShot
          trimBeforeSec={25.0}
          durationSec={4.0}
          mode="floating"
          zoomFrom={1.0}
          zoomTo={1.05}
          focusX={0}
          focusY={0}
          alignText="left"
        />
      </Sequence>

      <Sequence from={240} durationInFrames={240}>
        <FramedGameplayShot
          trimBeforeSec={48.5}
          durationSec={4.0}
          mode="floating"
          zoomFrom={1.0}
          zoomTo={1.05}
          focusX={0}
          focusY={0}
          alignText="left"
        />
        <CutFlashOverlay durationInFrames={12} maxOpacity={0.65} />
      </Sequence>

      {/* Left Side: High-Tech Vector Breakdown of MediaPipe 21-Point Hand Tracking + Fist Shield */}
      <div
        style={{
          position: "absolute",
          left: 76,
          top: 90,
          width: 630,
          height: 900,
          backgroundColor: "rgba(8, 8, 8, 0.94)",
          border: "2px solid #ffffff",
          boxShadow: "0 0 42px rgba(255,255,255,0.16)",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: "34px 38px",
        }}
      >
        {/* Top Tech Header */}
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div
            style={{
              display: "inline-flex",
              alignSelf: "flex-start",
              alignItems: "center",
              gap: 10,
              backgroundColor: "#ffffff",
              color: "#000000",
              fontFamily: FONTS.mono,
              fontSize: 15,
              fontWeight: 700,
              letterSpacing: 2.2,
              padding: "6px 14px",
            }}
          >
            <span>◆ MEDIAPIPE + OPENCV + UDP (21 LANDMARKS)</span>
          </div>

          <div
            style={{
              fontFamily: FONTS.heading,
              fontSize: 48,
              fontWeight: 700,
              color: "#ffffff",
              lineHeight: 1.05,
              letterSpacing: -0.8,
            }}
          >
            {isSecondHalf
              ? "CERRÁ EL PUÑO: ESCUDO ACTIVO"
              : "CONTROLÁ EL NÚCLEO CON TU MANO"}
          </div>

          <div
            style={{
              fontFamily: FONTS.mono,
              fontSize: 20,
              color: "#d0d0d0",
              lineHeight: 1.38,
            }}
          >
            {isSecondHalf
              ? "Al flexionar los dedos, activás el escudo de energía recargable para bloquear todo el daño entrante."
              : "Mové la palma abierta frente a la cámara. También jugable en todo momento con Teclado y Mouse."}
          </div>
        </div>

        {/* Center Live Vector Hand Diagram */}
        <div
          style={{
            position: "relative",
            width: "100%",
            height: 430,
            border: "1px solid rgba(255,255,255,0.22)",
            backgroundColor: "rgba(0,0,0,0.7)",
            overflow: "hidden",
          }}
        >
          <svg width={554} height={430}>
            {/* Incoming simulated projectiles deflected when shield is active */}
            {isSecondHalf &&
              [0, 1, 2, 3, 4].map((pIdx) => {
                const localF = (frame - 240 + pIdx * 28) % 90;
                const angle = -0.8 + pIdx * 0.42;
                const dist = interpolate(localF, [0, 55, 90], [270, 74, 210]);
                const px = 277 + handOffsetX + Math.cos(angle) * dist;
                const py = 225 + handOffsetY + Math.sin(angle) * dist;
                const impact = localF >= 50 && localF <= 62;
                return (
                  <g key={`proj-${pIdx}`}>
                    <circle
                      cx={px}
                      cy={py}
                      r={impact ? 11 : 7}
                      fill="#ffffff"
                    />
                    {impact && (
                      <circle
                        cx={px}
                        cy={py}
                        r={22}
                        fill="none"
                        stroke="#ffffff"
                        strokeWidth={2.5}
                      />
                    )}
                  </g>
                );
              })}

            <HandSkeletonSVG
              x={277 + handOffsetX}
              y={195 + handOffsetY}
              scale={1.12}
              fistFactor={fistProgress}
              pulse={kick}
            />
          </svg>

          {/* Status HUD pill inside diagram */}
          <div
            style={{
              position: "absolute",
              bottom: 14,
              left: 16,
              right: 16,
              display: "flex",
              justifyContent: "space-between",
              fontFamily: FONTS.mono,
              fontSize: 15,
              color: "#ffffff",
              backgroundColor: "rgba(20,20,20,0.9)",
              padding: "8px 14px",
              border: "1px solid rgba(255,255,255,0.35)",
            }}
          >
            <span>
              GESTO: <strong>{isSecondHalf ? "PUÑO CERRADO" : "PALMA ABIERTA"}</strong>
            </span>
            <span>
              ESCUDO: <strong>{isSecondHalf ? "BLOQUEANDO" : "LISTO (100%)"}</strong>
            </span>
          </div>
        </div>

        {/* Bottom Hybrid Input Bar */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            borderTop: "1px solid rgba(255,255,255,0.28)",
            paddingTop: 14,
            fontFamily: FONTS.mono,
            fontSize: 15,
            color: "#b8b8b8",
          }}
        >
          <span>CAM: 127.0.0.1:5005</span>
          <span>•</span>
          <span>FALLBACK: WASD / MOUSE / ESPACIO</span>
        </div>
      </div>

      <CutFlashOverlay durationInFrames={10} maxOpacity={0.55} />
    </AbsoluteFill>
  );
};

// ============================================================================
// ACT 4 (19s - 26s / 420 frames): CLIMAX MONTAGE (128 BPM RAPID CUTS)
// ============================================================================
export const Act4ClimaxMontage: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const kick = getKickEnvelope(frame, fps);

  return (
    <AbsoluteFill>
      {/* Cut 4A (0 - 112f / 1.87s): Full-bleed radial exploder + enemy swarm */}
      <Sequence durationInFrames={112}>
        <FramedGameplayShot
          trimBeforeSec={46.8}
          durationSec={1.87}
          mode="fullbleed"
          zoomFrom={1.08}
          zoomTo={1.22}
          alignText="bottom-left"
          badgeText="3 MODOS DE DIFICULTAD"
          headlineText="EASY • NORMAL • HARD"
          subText="3 puntos de vida. Velocidad y frecuencia de amenazas al límite."
        />
        <CutFlashOverlay durationInFrames={8} maxOpacity={0.7} />
      </Sequence>

      {/* Cut 4B (112 - 224f / 1.87s): Full-bleed closing walls + laser beam crossfire */}
      <Sequence from={112} durationInFrames={112}>
        <FramedGameplayShot
          trimBeforeSec={56.6}
          durationSec={1.87}
          mode="fullbleed"
          zoomFrom={1.12}
          zoomTo={1.26}
          focusY={-30}
          alignText="bottom-left"
          badgeText="AUDIO 100% PROCEDURAL"
          headlineText="SINTETIZADO EN CÓDIGO"
          subText="Música a 128 BPM y efectos generados dinámicamente en memoria."
        />
        <CutFlashOverlay durationInFrames={8} maxOpacity={0.7} />
      </Sequence>

      {/* Cut 4C (224 - 336f / 1.87s): Final seconds survival & high-intensity dodge */}
      <Sequence from={224} durationInFrames={112}>
        <FramedGameplayShot
          trimBeforeSec={60.2}
          durationSec={1.87}
          mode="fullbleed"
          zoomFrom={1.14}
          zoomTo={1.3}
          alignText="bottom-left"
          badgeText="RÉCORDS Y PERFILES"
          headlineText="SUPERÁ LA MEJOR MARCA"
          subText="Historial persistente de récords por jugador y dificultad."
        />
        <CutFlashOverlay durationInFrames={8} maxOpacity={0.7} />
      </Sequence>

      {/* Cut 4D (336 - 420f / 1.4s): Vector Boss-Rush / Geometric Finale Showcase */}
      <Sequence from={336} durationInFrames={84}>
        <AbsoluteFill>
          <ArenaGridBackground energy={1.0} pulse={0.85} />
          <svg width={width} height={height} style={{ position: "absolute", inset: 0 }}>
            {/* Four iconic Enemy Types surrounding the shielded player core */}
            <g transform={`translate(460, 290) rotate(${frame * 3}) scale(2.1)`}>
              <polygon points={getStarPolygonPoints(25, 21, 6)} fill="#f0f0f0" />
              <polygon points={getSweptTrianglePoints(11)} fill="#080808" />
            </g>
            <g transform={`translate(${width - 460}, 290) rotate(${-frame * 4}) scale(2.1)`}>
              <polygon points={getStarPolygonPoints(23, 12, 8)} fill="#f0f0f0" />
              <circle cx={0} cy={0} r={10} fill="#080808" />
            </g>
            <g transform={`translate(460, ${height - 290}) rotate(${frame * 5}) scale(1.9)`}>
              <polygon points={getSawPolygonPoints(32, 16, 0.7)} fill="#ffffff" />
              <circle cx={0} cy={0} r={14} fill="#080808" />
            </g>
            <g transform={`translate(${width - 460}, ${height - 290}) rotate(${-frame * 3.5}) scale(2.1)`}>
              <polygon points={getSweptTrianglePoints(24)} fill="#ffffff" />
              <polygon points={getSweptTrianglePoints(12)} fill="#080808" />
            </g>
          </svg>

          <AbsoluteFill
            style={{
              justifyContent: "center",
              alignItems: "center",
              flexDirection: "column",
              gap: 18,
            }}
          >
            <div
              style={{
                fontFamily: FONTS.mono,
                fontSize: 22,
                fontWeight: 700,
                color: "#000000",
                backgroundColor: "#ffffff",
                padding: "6px 20px",
                letterSpacing: 4,
              }}
            >
              ★ ¿PODÉS SOBREVIVIR LOS 45 SEGUNDOS? ★
            </div>
            <div
              style={{
                fontFamily: FONTS.heading,
                fontSize: 92,
                fontWeight: 700,
                color: "#ffffff",
                letterSpacing: 3,
                textShadow: `0 0 ${35 + kick * 30}px rgba(255,255,255,0.7)`,
                backgroundColor: "rgba(0,0,0,0.85)",
                padding: "14px 42px",
                border: "3px solid #ffffff",
                scale: `${1 + kick * 0.03}`,
              }}
            >
              PONÉ A PRUEBA TUS REFLEJOS
            </div>
          </AbsoluteFill>
          <CutFlashOverlay durationInFrames={10} maxOpacity={0.8} />
        </AbsoluteFill>
      </Sequence>
    </AbsoluteFill>
  );
};

// ============================================================================
// ACT 5 (26s - 30s / 240 frames): OUTRO — FERIA DE CIENCIAS SHOWCASE & CREDITS
// ============================================================================
export const Act5OutroCredits: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const kick = getKickEnvelope(frame, fps);

  const cardEnter = interpolate(frame, [0, 26], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.back(1.25)),
  });

  const badgesOpacity = interpolate(frame, [24, 52], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const finalFadeOut = interpolate(frame, [215, 240], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ opacity: finalFadeOut }}>
      <ArenaGridBackground energy={0.55} pulse={kick * 0.3} />

      {/* Rotating subtle DecorSquare from credits.tscn */}
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <div
          style={{
            width: 520,
            height: 520,
            backgroundColor: "rgba(24, 24, 24, 0.55)",
            border: "2px solid rgba(255, 255, 255, 0.14)",
            rotate: `${frame * 0.35}deg`,
          }}
        />
      </AbsoluteFill>

      <AbsoluteFill
        style={{
          justifyContent: "center",
          alignItems: "center",
          padding: 60,
        }}
      >
        <div
          style={{
            width: 1380,
            backgroundColor: "rgba(6, 6, 6, 0.94)",
            border: "3px solid #ffffff",
            boxShadow: `0 0 ${48 + kick * 24}px rgba(255, 255, 255, 0.22)`,
            padding: "54px 72px",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 28,
            scale: `${interpolate(cardEnter, [0, 1], [0.88, 1])}`,
            opacity: interpolate(frame, [0, 16], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
          }}
        >
          {/* Event Banner */}
          <div
            style={{
              backgroundColor: "#ffffff",
              color: "#000000",
              fontFamily: FONTS.mono,
              fontSize: 20,
              fontWeight: 700,
              letterSpacing: 3.5,
              padding: "8px 26px",
              textTransform: "uppercase",
            }}
          >
            ★ JUGALO AHORA EN EL STAND — FERIA DE CIENCIAS ★
          </div>

          {/* Main Game Title */}
          <div
            style={{
              fontFamily: FONTS.heading,
              fontSize: 112,
              fontWeight: 700,
              color: "#ffffff",
              letterSpacing: 6,
              lineHeight: 0.96,
              textShadow: "0 0 32px rgba(255,255,255,0.45)",
            }}
          >
            SHAPES & BEAMS
          </div>

          {/* School & Year */}
          <div
            style={{
              fontFamily: FONTS.mono,
              fontSize: 24,
              fontWeight: 700,
              color: "#d8d8d8",
              letterSpacing: 3,
              textTransform: "uppercase",
            }}
          >
            ETEC UNIVERSIDAD DE MENDOZA • 6° AÑO INFORMÁTICA
          </div>

          {/* Divider */}
          <div
            style={{
              width: "75%",
              height: 2,
              backgroundColor: "rgba(255,255,255,0.28)",
            }}
          />

          {/* Developers */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 8,
            }}
          >
            <div
              style={{
                fontFamily: FONTS.mono,
                fontSize: 15,
                color: "#9e9e9e",
                letterSpacing: 4,
              }}
            >
              DESARROLLADO POR
            </div>
            <div
              style={{
                fontFamily: FONTS.heading,
                fontSize: 42,
                fontWeight: 700,
                color: "#ffffff",
                letterSpacing: 1.5,
              }}
            >
              FACUNDO GUIÑAZÚ &nbsp;•&nbsp; BAUTISTA PRIETO
            </div>
          </div>

          {/* Tech Stack Badges */}
          <div
            style={{
              display: "flex",
              gap: 18,
              flexWrap: "wrap",
              justifyContent: "center",
              opacity: badgesOpacity,
              marginTop: 6,
            }}
          >
            {[
              "GODOT ENGINE 4.7",
              "MEDIAPIPE HAND TRACKING",
              "OPENCV",
              "AUDIO 100% PROCEDURAL",
            ].map((tech) => (
              <div
                key={tech}
                style={{
                  border: "1.5px solid rgba(255,255,255,0.75)",
                  backgroundColor: "rgba(22,22,22,0.9)",
                  padding: "8px 18px",
                  fontFamily: FONTS.mono,
                  fontSize: 16,
                  fontWeight: 700,
                  color: "#f0f0f0",
                  letterSpacing: 2,
                }}
              >
                {tech}
              </div>
            ))}
          </div>
        </div>
      </AbsoluteFill>

      <CutFlashOverlay durationInFrames={14} maxOpacity={0.85} />
    </AbsoluteFill>
  );
};
