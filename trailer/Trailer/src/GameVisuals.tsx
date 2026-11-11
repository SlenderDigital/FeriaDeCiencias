import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";

export const FONTS = {
  heading:
    "'Inter', 'Space Grotesk', 'Segoe UI', 'Helvetica Neue', 'Arial', system-ui, sans-serif",
  mono:
    "'JetBrains Mono', 'Fira Code', 'Ubuntu Mono', 'DejaVu Sans Mono', monospace",
};

export const MUSIC_BPM = 128.0;
export const BEAT_SEC = 60.0 / MUSIC_BPM; // 0.46875s

export function getBeatPhase(frame: number, fps: number): number {
  const sec = Math.max(0, frame / fps);
  return (sec % BEAT_SEC) / BEAT_SEC;
}

export function getKickEnvelope(frame: number, fps: number): number {
  const phase = getBeatPhase(frame, fps);
  return Math.pow(1.0 - phase, 2.2);
}

// Mirrors Shapes.saw(radius, teeth=16, inner_ratio=0.70) from shapes.gd
export function getSawPolygonPoints(
  radius: number,
  teeth = 16,
  innerRatio = 0.7
): string {
  const total = Math.max(teeth * 2, 8);
  const pts: string[] = [];
  for (let i = 0; i < total; i++) {
    const cant = i % 2 === 0 ? -0.045 : 0.03;
    const r = i % 2 === 0 ? radius : radius * innerRatio;
    const angle = (Math.PI * 2 * i) / total + cant;
    pts.push(`${(Math.cos(angle) * r).toFixed(2)},${(Math.sin(angle) * r).toFixed(2)}`);
  }
  return pts.join(" ");
}

// Mirrors Shapes.star(outer_r, inner_r, points_count) from shapes.gd
export function getStarPolygonPoints(
  outerR: number,
  innerR: number,
  pointsCount: number
): string {
  const total = Math.max(pointsCount * 2, 6);
  const pts: string[] = [];
  for (let i = 0; i < total; i++) {
    const r = i % 2 === 0 ? outerR : innerR;
    const angle = (Math.PI * 2 * i) / total;
    pts.push(`${(Math.cos(angle) * r).toFixed(2)},${(Math.sin(angle) * r).toFixed(2)}`);
  }
  return pts.join(" ");
}

// Mirrors Shapes.swept_triangle(radius) from shapes.gd
export function getSweptTrianglePoints(radius: number): string {
  const raw = [
    [radius * 1.12, 0.0],
    [-radius * 0.76, -radius * 0.88],
    [-radius * 0.38, -radius * 0.26],
    [-radius * 0.68, 0.0],
    [-radius * 0.38, radius * 0.26],
    [-radius * 0.76, radius * 0.88],
  ];
  return raw.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
}

// Mirrors arena_grid.gd 1:1 in 1920x1080 SVG
export const ArenaGridBackground: React.FC<{
  energy?: number;
  pulse?: number;
  showCenterReticle?: boolean;
}> = ({ energy = 0.6, pulse = 0, showCenterReticle = true }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const beatPhase = getBeatPhase(frame, fps);
  const kick = getKickEnvelope(frame, fps);

  const effPulse = Math.min(1, pulse + energy * 0.28 + kick * 0.22);
  const spacing = 96;
  const cols = Math.floor(width / spacing);
  const rows = Math.floor(height / spacing);

  const centerX = width * 0.5;
  const centerY = height * 0.5;
  const minDim = Math.min(width, height);
  const outerR = minDim * (0.16 + 0.014 * effPulse);
  const innerR = minDim * (0.075 + 0.008 * energy);
  const waveR = innerR + (outerR * 1.18 - innerR) * beatPhase;
  const waveAlpha = (1.0 - beatPhase) * energy * 0.45;
  const centerGray = Math.round((0.14 + 0.22 * effPulse) * 255);
  const centerColor = `rgba(${centerGray}, ${centerGray}, ${centerGray}, 0.88)`;

  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      <svg width={width} height={height} style={{ display: "block" }}>
        {/* Vertical Grid Lines */}
        {Array.from({ length: cols }).map((_, idx) => {
          const colIdx = idx + 1;
          const x = colIdx * spacing;
          const isMajor = colIdx % 2 === 0;
          const alpha = isMajor ? 0.68 + 0.28 * effPulse : 0.55 + 0.22 * effPulse;
          const val = isMajor ? 26 : 16;
          return (
            <line
              key={`v-${colIdx}`}
              x1={x}
              y1={0}
              x2={x}
              y2={height}
              stroke={`rgba(${val},${val},${val},${alpha})`}
              strokeWidth={1}
            />
          );
        })}

        {/* Horizontal Grid Lines */}
        {Array.from({ length: rows }).map((_, idx) => {
          const rowIdx = idx + 1;
          const y = rowIdx * spacing;
          const isMajor = rowIdx % 2 === 0;
          const alpha = isMajor ? 0.68 + 0.28 * effPulse : 0.55 + 0.22 * effPulse;
          const val = isMajor ? 26 : 16;
          return (
            <line
              key={`h-${rowIdx}`}
              x1={0}
              y1={y}
              x2={width}
              y2={y}
              stroke={`rgba(${val},${val},${val},${alpha})`}
              strokeWidth={1}
            />
          );
        })}

        {/* Grid Crosshair Nodes */}
        {Array.from({ length: Math.floor(cols / 2) }).map((_, gxIdx) =>
          Array.from({ length: Math.floor(rows / 2) }).map((__, gyIdx) => {
            const gx = (gxIdx + 1) * spacing * 2;
            const gy = (gyIdx + 1) * spacing * 2;
            return (
              <g
                key={`node-${gx}-${gy}`}
                stroke={`rgba(55,55,55,${0.55 + 0.3 * effPulse})`}
                strokeWidth={1.2}
              >
                <line x1={gx - 4} y1={gy} x2={gx + 4} y2={gy} />
                <line x1={gx} y1={gy - 4} x2={gx} y2={gy + 4} />
              </g>
            );
          })
        )}

        {/* Center Reticle & Beat Wave */}
        {showCenterReticle && (
          <g>
            <line
              x1={centerX}
              y1={centerY - 26}
              x2={centerX}
              y2={centerY + 26}
              stroke={centerColor}
              strokeWidth={1.2}
            />
            <line
              x1={centerX - 26}
              y1={centerY}
              x2={centerX + 26}
              y2={centerY}
              stroke={centerColor}
              strokeWidth={1.2}
            />
            <circle
              cx={centerX}
              cy={centerY}
              r={outerR}
              fill="none"
              stroke={centerColor}
              strokeWidth={1.4}
            />
            {/* Octagonal inner ring like draw_arc(..., 8) in Godot */}
            <polygon
              points={getStarPolygonPoints(innerR, innerR, 4)}
              transform={`translate(${centerX}, ${centerY}) rotate(${frame * 0.15})`}
              fill="none"
              stroke={centerColor}
              strokeWidth={1.2}
            />
            <circle
              cx={centerX}
              cy={centerY}
              r={waveR}
              fill="none"
              stroke={`rgba(165, 165, 165, ${waveAlpha})`}
              strokeWidth={1.5}
            />
            {Array.from({ length: 8 }).map((_, i) => {
              const angle = (Math.PI * 2 * i) / 8;
              const barLen = (7 + 14 * (energy + kick * 0.4)) * (i % 2 === 0 ? 1 : 0.55);
              const x1 = centerX + Math.cos(angle) * outerR;
              const y1 = centerY + Math.sin(angle) * outerR;
              const x2 = centerX + Math.cos(angle) * (outerR + barLen);
              const y2 = centerY + Math.sin(angle) * (outerR + barLen);
              return (
                <line
                  key={`tick-${i}`}
                  x1={x1}
                  y1={y1}
                  x2={x2}
                  y2={y2}
                  stroke={centerColor}
                  strokeWidth={1.5}
                />
              );
            })}
          </g>
        )}

        {/* Outer Arena Border & Corner Ticks */}
        <rect
          x={16}
          y={16}
          width={width - 32}
          height={height - 32}
          fill="none"
          stroke={`rgba(255,255,255,${0.18 + 0.25 * effPulse})`}
          strokeWidth={2}
        />
        {[
          [16, 16, 1, 1],
          [width - 16, 16, -1, 1],
          [16, height - 16, 1, -1],
          [width - 16, height - 16, -1, -1],
        ].map(([cx, cy, dx, dy], i) => (
          <g key={`corner-${i}`} stroke="rgba(240,240,240,0.9)" strokeWidth={3.5}>
            <line x1={cx} y1={cy} x2={cx + 28 * dx} y2={cy} />
            <line x1={cx} y1={cy} x2={cx} y2={cy + 28 * dy} />
          </g>
        ))}
      </svg>
    </AbsoluteFill>
  );
};

// Mirrors hand_shadow.gd 21-point MediaPipe skeleton + fist contraction + shield ring
export const HandSkeletonSVG: React.FC<{
  x: number;
  y: number;
  scale?: number;
  fistFactor?: number; // 0 = open palm, 1 = closed fist (shield active)
  pulse?: number;
}> = ({ x, y, scale = 1, fistFactor = 0, pulse = 0 }) => {
  // Canonical 21 MediaPipe landmarks relative to wrist (0, 120)
  const basePoints: [number, number][] = [
    [0, 125], // 0: Wrist
    [-46, 98], // 1: Thumb CMC
    [-82, 56], // 2: Thumb MCP
    [-108, 12], // 3: Thumb IP
    [-126, -28], // 4: Thumb Tip
    [-42, 12], // 5: Index MCP
    [-54, -48], // 6: Index PIP
    [-62, -96], // 7: Index DIP
    [-68, -138], // 8: Index Tip
    [-10, 4], // 9: Middle MCP
    [-12, -62], // 10: Middle PIP
    [-14, -114], // 11: Middle DIP
    [-15, -156], // 12: Middle Tip
    [24, 14], // 13: Ring MCP
    [30, -48], // 14: Ring PIP
    [35, -96], // 15: Ring DIP
    [39, -136], // 16: Ring Tip
    [54, 34], // 17: Pinky MCP
    [68, -16], // 18: Pinky PIP
    [78, -56], // 19: Pinky DIP
    [86, -92], // 20: Pinky Tip
  ];

  // Palm center (average of [0, 5, 9, 13, 17] like hand_shadow.gd)
  const palmCenter: [number, number] = [0, 38];

  const clampedFist = Math.max(0, Math.min(1, fistFactor));

  const pts: [number, number][] = basePoints.map(([px, py], idx) => {
    // Distal joints curl strongly into palmCenter when fist is closed
    let curl = 0;
    if ([4, 8, 12, 16, 20].includes(idx)) curl = 0.72 * clampedFist;
    else if ([3, 7, 11, 15, 19].includes(idx)) curl = 0.56 * clampedFist;
    else if ([2, 6, 10, 14, 18].includes(idx)) curl = 0.32 * clampedFist;

    return [
      px + (palmCenter[0] - px) * curl,
      py + (palmCenter[1] - py) * curl,
    ];
  });

  const palmPolygonIndices = [0, 1, 5, 9, 13, 17];
  const bones = [
    [0, 1, 2, 3, 4],
    [0, 5, 6, 7, 8],
    [0, 9, 10, 11, 12],
    [0, 13, 14, 15, 16],
    [0, 17, 18, 19, 20],
    [1, 5, 9, 13, 17, 0],
  ];
  const fingertips = [4, 8, 12, 16, 20];

  const palmPts = palmPolygonIndices.map((i) => `${pts[i][0]},${pts[i][1]}`).join(" ");
  const brightness = Math.min(1, 0.45 + 0.45 * clampedFist + 0.25 * pulse);

  return (
    <g transform={`translate(${x}, ${y}) scale(${scale})`}>
      {/* Palm Polygon */}
      <polygon
        points={palmPts}
        fill={`rgba(210, 210, 210, ${0.22 + 0.26 * clampedFist})`}
        stroke={`rgba(255, 255, 255, ${0.4 + 0.35 * clampedFist})`}
        strokeWidth={2}
      />

      {/* Finger & Palm Bridge Bones */}
      {bones.map((indices, bIdx) => (
        <polyline
          key={`bone-${bIdx}`}
          points={indices.map((i) => `${pts[i][0]},${pts[i][1]}`).join(" ")}
          fill="none"
          stroke={`rgba(255, 255, 255, ${brightness})`}
          strokeWidth={bIdx === 5 ? 2 : 3.2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      ))}

      {/* All 21 Landmarks */}
      {pts.map(([lx, ly], idx) => {
        const isTip = fingertips.includes(idx);
        const r = isTip ? 6.5 + 2.5 * clampedFist : 3.2;
        return (
          <circle
            key={`lm-${idx}`}
            cx={lx}
            cy={ly}
            r={r}
            fill={isTip ? "#ffffff" : "rgba(220,220,220,0.85)"}
          />
        );
      })}

      {/* Player Core at Palm Center (28x28 square + radial glow + shield ring) */}
      <g transform={`translate(${palmCenter[0]}, ${palmCenter[1]})`}>
        {/* Radial Glow */}
        <circle
          cx={0}
          cy={0}
          r={54 + 28 * clampedFist}
          fill={`rgba(255,255,255,${0.14 + 0.16 * clampedFist})`}
        />
        <circle
          cx={0}
          cy={0}
          r={34 + 16 * clampedFist}
          fill={`rgba(255,255,255,${0.26 + 0.22 * clampedFist})`}
        />
        {/* Shield Ring when Fist is closed */}
        {clampedFist > 0.05 && (
          <>
            <circle
              cx={0}
              cy={0}
              r={42 + 6 * pulse}
              fill={`rgba(255,255,255,${0.16 * clampedFist})`}
              stroke={`rgba(255,255,255,${0.95 * clampedFist})`}
              strokeWidth={3.5}
            />
            <circle
              cx={0}
              cy={0}
              r={52 + 12 * pulse}
              fill="none"
              stroke={`rgba(255,255,255,${0.45 * clampedFist})`}
              strokeWidth={1.5}
              strokeDasharray="8 6"
            />
          </>
        )}
        {/* Player Outer Square */}
        <rect
          x={-16}
          y={-16}
          width={32}
          height={32}
          fill="#ffffff"
          stroke="#ffffff"
          strokeWidth={2}
        />
      </g>
    </g>
  );
};

// Flash impact transition at scene cuts
export const CutFlashOverlay: React.FC<{ durationInFrames?: number; maxOpacity?: number }> = ({
  durationInFrames = 10,
  maxOpacity = 0.65,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, durationInFrames], [maxOpacity, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill
      style={{
        backgroundColor: "#ffffff",
        opacity,
        pointerEvents: "none",
      }}
    />
  );
};
