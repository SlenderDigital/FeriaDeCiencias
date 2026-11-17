from __future__ import annotations

import math
from collections.abc import Sequence

import cv2
import mediapipe as mp


class Landmarker:
    """Dual-candidate, single-lock MediaPipe hand landmarker with stabilization."""

    PALM_INDICES: tuple[int, ...] = (0, 5, 9, 13, 17)
    MAX_JUMP_DIST: float = 0.35
    PENDING_CONFIRM_DIST: float = 0.25
    MAX_CONSISTENT_SWIPE_STEP: float = 0.45
    MIN_SWIPE_COSINE: float = 0.50
    PENDING_CONFIRM_FRAMES: int = 2
    MAX_MISSING_FRAMES: int = 2
    FAST_DELTA_THRESHOLD: float = 0.10
    SMOOTH_ALPHA_SLOW: float = 0.68
    SMOOTH_ALPHA_FAST: float = 0.90

    def __init__(self) -> None:
        self.hands_solution = None
        self.hands = None
        self._locked_palm: tuple[float, float] | None = None
        self._last_smoothed: list[tuple[float, float, float]] | None = None
        self._pending_palm: tuple[float, float] | None = None
        self._pending_frames: int = 0
        self._missing_frames: int = 0

    def reset(self) -> None:
        """Clear temporal stabilization state without closing MediaPipe."""
        self._locked_palm = None
        self._last_smoothed = None
        self._pending_palm = None
        self._pending_frames = 0
        self._missing_frames = 0

    def init(self) -> None:
        """Initialize MediaPipe Hands with 2-hand detection filtered to 1 player hand."""
        self.reset()
        self.hands_solution = mp.solutions.hands

        self.hands = self.hands_solution.Hands(
            max_num_hands=2,
            model_complexity=0,   # lite: ~21ms/frame @720p, mas robusto en frames con ruido
            min_detection_confidence=0.6,
            min_tracking_confidence=0.55,
        )

    @staticmethod
    def _extract_hand_coords(hand: object) -> list[tuple[float, float, float]]:
        raw = getattr(hand, "landmark", hand)
        return [
            (
                float(pt.x if hasattr(pt, "x") else pt[0]),
                float(pt.y if hasattr(pt, "y") else pt[1]),
                float(pt.z if hasattr(pt, "z") else pt[2]),
            )
            for pt in raw
        ]

    @classmethod
    def _compute_palm_center(
        cls, coords: Sequence[tuple[float, float, float]]
    ) -> tuple[float, float]:
        count = len(cls.PALM_INDICES)
        px = sum(float(coords[idx][0]) for idx in cls.PALM_INDICES) / count
        py = sum(float(coords[idx][1]) for idx in cls.PALM_INDICES) / count
        return (px, py)

    @staticmethod
    def _compute_palm_span(coords: Sequence[tuple[float, float, float]]) -> float:
        """Estimate apparent palm size across wrist/MCP landmarks (0, 5, 9, 17)."""
        wrist_to_mid = math.hypot(
            float(coords[9][0]) - float(coords[0][0]),
            float(coords[9][1]) - float(coords[0][1]),
        )
        index_to_pinky = math.hypot(
            float(coords[17][0]) - float(coords[5][0]),
            float(coords[17][1]) - float(coords[5][1]),
        )
        return wrist_to_mid + index_to_pinky

    @staticmethod
    def _palm_distance(a: tuple[float, float], b: tuple[float, float]) -> float:
        return math.hypot(a[0] - b[0], a[1] - b[1])

    @staticmethod
    def _is_consistent_swipe(
        origin: tuple[float, float],
        mid: tuple[float, float],
        current: tuple[float, float],
        min_cosine: float = 0.50,
    ) -> bool:
        v1x, v1y = mid[0] - origin[0], mid[1] - origin[1]
        v2x, v2y = current[0] - mid[0], current[1] - mid[1]
        mag1 = math.hypot(v1x, v1y)
        mag2 = math.hypot(v2x, v2y)
        if mag1 <= 1e-6 or mag2 <= 1e-6:
            return False
        cosine = (v1x * v2x + v1y * v2y) / (mag1 * mag2)
        return cosine >= min_cosine

    @staticmethod
    def _blend_landmarks(
        current: Sequence[tuple[float, float, float]],
        previous: Sequence[tuple[float, float, float]],
        alpha: float,
    ) -> list[tuple[float, float, float]]:
        inv_alpha = 1.0 - alpha
        return [
            (
                alpha * cur[0] + inv_alpha * prev[0],
                alpha * cur[1] + inv_alpha * prev[1],
                alpha * cur[2] + inv_alpha * prev[2],
            )
            for cur, prev in zip(current, previous)
        ]

    def _select_candidate_landmarks(
        self, multi_hand_landmarks: Sequence[object]
    ) -> list[tuple[float, float, float]]:
        """Pick one hand: closest to _locked_palm when locked, else largest palm span."""
        candidates = [
            coords
            for hand in multi_hand_landmarks
            if (coords := self._extract_hand_coords(hand))
        ]
        if not candidates:
            return []
        if len(candidates) == 1:
            return candidates[0]

        if self._locked_palm is not None:
            locked = self._locked_palm
            return min(
                candidates,
                key=lambda coords: (
                    self._palm_distance(self._compute_palm_center(coords), locked),
                    -self._compute_palm_span(coords),
                ),
            )

        return max(candidates, key=self._compute_palm_span)

    def stabilize_landmarks(
        self, coords: list[tuple[float, float, float]]
    ) -> list[tuple[float, float, float]]:
        """Filter phantom jumps, bridge brief drops, and adaptively smooth landmarks."""
        if not coords:
            self._pending_palm = None
            self._pending_frames = 0
            if (
                self._last_smoothed is not None
                and self._missing_frames < self.MAX_MISSING_FRAMES
            ):
                self._missing_frames += 1
                return list(self._last_smoothed)
            self.reset()
            return []

        current: list[tuple[float, float, float]] = [
            (float(x), float(y), float(z)) for x, y, z in coords
        ]
        palm = self._compute_palm_center(current)

        if self._locked_palm is None or self._last_smoothed is None:
            self._locked_palm = palm
            self._last_smoothed = current
            self._pending_palm = None
            self._pending_frames = 0
            self._missing_frames = 0
            return list(self._last_smoothed)

        jump_dist = self._palm_distance(palm, self._locked_palm)
        if jump_dist > self.MAX_JUMP_DIST:
            if self._pending_palm is not None and self._pending_frames >= 1:
                step_dist = self._palm_distance(palm, self._pending_palm)
                consistent_swipe = (
                    step_dist <= self.MAX_CONSISTENT_SWIPE_STEP
                    and self._is_consistent_swipe(
                        self._locked_palm,
                        self._pending_palm,
                        palm,
                        self.MIN_SWIPE_COSINE,
                    )
                )
                if step_dist <= self.PENDING_CONFIRM_DIST or consistent_swipe:
                    self._pending_frames += 1
                    if self._pending_frames >= self.PENDING_CONFIRM_FRAMES:
                        smoothed = self._blend_landmarks(
                            current, self._last_smoothed, self.SMOOTH_ALPHA_FAST
                        )
                        self._last_smoothed = smoothed
                        self._locked_palm = self._compute_palm_center(smoothed)
                        self._pending_palm = None
                        self._pending_frames = 0
                        self._missing_frames = 0
                        return list(self._last_smoothed)
                    self._pending_palm = palm
                    return list(self._last_smoothed)

            self._pending_palm = palm
            self._pending_frames = 1
            return list(self._last_smoothed)

        self._pending_palm = None
        self._pending_frames = 0
        self._missing_frames = 0

        alpha = (
            self.SMOOTH_ALPHA_FAST
            if jump_dist > self.FAST_DELTA_THRESHOLD
            else self.SMOOTH_ALPHA_SLOW
        )
        smoothed = self._blend_landmarks(current, self._last_smoothed, alpha)

        self._last_smoothed = smoothed
        self._locked_palm = self._compute_palm_center(smoothed)
        return list(self._last_smoothed)

    def process(self, image: cv2.typing.MatLike) -> list[tuple[float, float, float]]:
        """Run MediaPipe inference, pick the locked/largest hand, and stabilize landmarks."""
        if self.hands is None:
            raise RuntimeError("Landmarker.init() must be called before process().")

        results = self.hands.process(image)

        if not results.multi_hand_landmarks:
            return self.stabilize_landmarks([])

        chosen = self._select_candidate_landmarks(results.multi_hand_landmarks)
        return self.stabilize_landmarks(chosen)

    def shutdown(self) -> None:
        """Close the MediaPipe Hands detector and reset tracking state."""
        if self.hands is not None:
            self.hands.close()
            self.hands = None
        self.reset()
