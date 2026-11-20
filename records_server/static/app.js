(() => {
  "use strict";

  const FILTER_ORDER = ["-1", "0", "1", "2", "3"];
  const COMPACT_BREAKPOINT_PX = 560;
  const RECORD_HIGHLIGHT_MS = 4000;
  const FALLBACK_POLL_MS = 2000;

  let selectedFilter = "-1";
  let currentSnapshot = null;
  let eventSource = null;
  let fallbackPollTimer = null;
  const highlightedKeys = new Map();
  let highlightCleanupTimer = null;
  let lastCompactMode = window.innerWidth < COMPACT_BREAKPOINT_PX;

  const playerLabelEl = document.getElementById("records-player-label");
  const highestLabelEl = document.getElementById("records-highest-label");
  const statEasyEl = document.getElementById("stat-easy");
  const statNormalEl = document.getElementById("stat-normal");
  const statHardEl = document.getElementById("stat-hard");
  const statBossEl = document.getElementById("stat-boss");
  const leaderboardPanelEl = document.getElementById("leaderboard-panel");
  const leaderboardListEl = document.getElementById("leaderboard-list");
  const liveIndicatorEl = document.getElementById("live-indicator");
  const liveTextEl = document.getElementById("live-text");
  const footerMetaEl = document.getElementById("footer-meta");
  const filterButtons = Array.from(document.querySelectorAll(".filter-btn"));

  function setConnectionState(mode, labelText) {
    liveIndicatorEl.classList.remove("is-live", "is-reconnecting", "is-waiting", "is-connecting");
    liveIndicatorEl.classList.add(mode);
    liveTextEl.textContent = labelText;
  }

  function formatPlayerCount(count) {
    return count === 1 ? "1 PLAYER" : `${count} PLAYERS`;
  }

  function updateFilterSelection(nextFilter) {
    if (!FILTER_ORDER.includes(nextFilter)) {
      return;
    }
    selectedFilter = nextFilter;
    for (const btn of filterButtons) {
      const isSelected = btn.dataset.filter === selectedFilter;
      btn.setAttribute("aria-selected", isSelected ? "true" : "false");
      if (isSelected) {
        leaderboardPanelEl.setAttribute("aria-labelledby", btn.id);
      }
    }
    if (currentSnapshot) {
      renderHeaderAndStats(currentSnapshot);
      renderLeaderboardRows(currentSnapshot);
    }
  }

  function renderHeaderAndStats(snapshot) {
    const rank = Number((snapshot.player_ranks || {})[selectedFilter] || 0);
    const rankSuffix = rank > 0 ? `  •  RANK #${rank}` : "  •  UNRANKED";
    const playerUpper = snapshot.player_name_upper || "PLAYER";
    playerLabelEl.textContent = `PLAYER: ${playerUpper}${rankSuffix}`;
    highestLabelEl.textContent = snapshot.best_summary || "No runs yet";

    const stats = snapshot.personal_stats || {};
    statEasyEl.textContent = stats["0"] || "EASY:  No runs recorded";
    statNormalEl.textContent = stats["1"] || "NORMAL:  No runs recorded";
    statHardEl.textContent = stats["2"] || "HARD:  No runs recorded";
    statBossEl.textContent = stats["3"] || "BOSS:  No runs recorded";

    const totalPlayers = Number(snapshot.total_players || 0);
    footerMetaEl.textContent = formatPlayerCount(totalPlayers);
  }

  function pruneExpiredHighlights() {
    const now = Date.now();
    for (const [key, expiresAt] of highlightedKeys.entries()) {
      if (expiresAt <= now) {
        highlightedKeys.delete(key);
      }
    }
  }

  function scheduleHighlightCleanup() {
    if (highlightCleanupTimer !== null) {
      clearTimeout(highlightCleanupTimer);
      highlightCleanupTimer = null;
    }
    if (highlightedKeys.size === 0) {
      return;
    }
    highlightCleanupTimer = setTimeout(() => {
      pruneExpiredHighlights();
      if (currentSnapshot) {
        renderLeaderboardRows(currentSnapshot);
      }
    }, RECORD_HIGHLIGHT_MS + 50);
  }

  function recordRecentUpdates(snapshot) {
    const updates = Array.isArray(snapshot.recent_updates) ? snapshot.recent_updates : [];
    if (updates.length === 0) {
      return;
    }
    const expiresAt = Date.now() + RECORD_HIGHLIGHT_MS;
    for (const upd of updates) {
      if (upd && typeof upd.key === "string") {
        highlightedKeys.set(upd.key, expiresAt);
      }
    }
    scheduleHighlightCleanup();
  }

  function renderLeaderboardRows(snapshot) {
    pruneExpiredHighlights();
    const prevScrollTop = leaderboardPanelEl.scrollTop;
    const compact = window.innerWidth < COMPACT_BREAKPOINT_PX;
    const entries = ((snapshot.leaderboards || {})[selectedFilter]) || [];
    const showTierBadge = selectedFilter === "-1";

    const fragment = document.createDocumentFragment();

    if (entries.length === 0) {
      const emptyEl = document.createElement("p");
      emptyEl.className = "empty-leaderboard";
      emptyEl.textContent =
        "No player scores recorded in this category yet.\nEnter your username and press Play to set the #1 record!";
      fragment.appendChild(emptyEl);
    } else {
      for (const entry of entries) {
        const rank = Number(entry.rank || 1);
        const isCurrent = Boolean(entry.is_current);
        const isPodium = rank <= 3;
        const completed = Boolean(entry.completed);

        const row = document.createElement("div");
        row.className = "rank-row";
        if (isCurrent) {
          row.classList.add("is-current");
        } else if (rank === 1) {
          row.classList.add("is-rank-1");
        } else if (isPodium) {
          row.classList.add("is-podium");
        }
        if (completed) {
          row.classList.add("is-completed");
        }
        if (highlightedKeys.has(entry.key)) {
          row.classList.add("is-updated");
        }

        const rankEl = document.createElement("span");
        rankEl.className = "row-rank";
        rankEl.textContent = `#${rank}`;
        row.appendChild(rankEl);

        const nameEl = document.createElement("span");
        nameEl.className = "row-name";
        const baseName = entry.player_name_upper || "PLAYER";
        nameEl.textContent = isCurrent ? `${baseName}  ◀ YOU` : baseName;
        row.appendChild(nameEl);

        if (showTierBadge) {
          const tierEl = document.createElement("span");
          tierEl.className = "row-tier";
          tierEl.textContent = `[${entry.difficulty_upper || "NORMAL"}]`;
          row.appendChild(tierEl);
        }

        const scoreEl = document.createElement("span");
        scoreEl.className = "row-score";
        scoreEl.textContent = compact
          ? (entry.score_compact || entry.score_full || "")
          : (entry.score_full || "");
        row.appendChild(scoreEl);

        fragment.appendChild(row);
      }
    }

    leaderboardListEl.replaceChildren(fragment);
    leaderboardPanelEl.scrollTop = prevScrollTop;
  }

  function applySnapshot(snapshot, isLivePush) {
    if (!snapshot || typeof snapshot !== "object") {
      return;
    }
    if (isLivePush) {
      recordRecentUpdates(snapshot);
    }
    currentSnapshot = snapshot;
    renderHeaderAndStats(snapshot);
    renderLeaderboardRows(snapshot);

    if (snapshot.source_exists === false) {
      setConnectionState("is-waiting", "WAITING FOR SAVE FILE");
    } else if (eventSource && eventSource.readyState === EventSource.OPEN) {
      setConnectionState("is-live", "LIVE • READ-ONLY");
    }
  }

  async function fetchSnapshotOnce() {
    try {
      const response = await fetch("/api/records", { cache: "no-store" });
      if (!response.ok) {
        return;
      }
      const snapshot = await response.json();
      applySnapshot(snapshot, false);
    } catch (_err) {
      // Transient fetch failure handled by SSE / retry loop.
    }
  }

  function startFallbackPolling() {
    if (fallbackPollTimer !== null) {
      return;
    }
    fallbackPollTimer = setInterval(fetchSnapshotOnce, FALLBACK_POLL_MS);
  }

  function stopFallbackPolling() {
    if (fallbackPollTimer !== null) {
      clearInterval(fallbackPollTimer);
      fallbackPollTimer = null;
    }
  }

  function connectEvents() {
    if (typeof EventSource === "undefined") {
      setConnectionState("is-live", "AUTO-POLLING");
      startFallbackPolling();
      return;
    }

    eventSource = new EventSource("/events");
    eventSource.onopen = () => {
      stopFallbackPolling();
      if (currentSnapshot && currentSnapshot.source_exists === false) {
        setConnectionState("is-waiting", "WAITING FOR SAVE FILE");
      } else {
        setConnectionState("is-live", "LIVE • READ-ONLY");
      }
    };

    eventSource.addEventListener("records", (event) => {
      try {
        const snapshot = JSON.parse(event.data);
        applySnapshot(snapshot, true);
      } catch (_err) {
        // Ignore malformed SSE frames.
      }
    });

    eventSource.onerror = () => {
      setConnectionState("is-reconnecting", "RECONNECTING...");
      startFallbackPolling();
    };
  }

  function bindTabs() {
    for (const btn of filterButtons) {
      btn.addEventListener("click", () => {
        updateFilterSelection(btn.dataset.filter || "-1");
      });
    }

    window.addEventListener("keydown", (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey) {
        return;
      }
      if (event.key >= "1" && event.key <= "5") {
        const target = FILTER_ORDER[Number(event.key) - 1];
        updateFilterSelection(target);
        const btn = filterButtons.find((b) => b.dataset.filter === target);
        if (btn) {
          btn.focus();
        }
        return;
      }
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        const idx = FILTER_ORDER.indexOf(selectedFilter);
        const step = event.key === "ArrowRight" ? 1 : -1;
        const nextIdx = (idx + step + FILTER_ORDER.length) % FILTER_ORDER.length;
        const target = FILTER_ORDER[nextIdx];
        updateFilterSelection(target);
        const btn = filterButtons.find((b) => b.dataset.filter === target);
        if (btn) {
          btn.focus();
        }
      }
    });

    window.addEventListener("resize", () => {
      const compactNow = window.innerWidth < COMPACT_BREAKPOINT_PX;
      if (compactNow !== lastCompactMode) {
        lastCompactMode = compactNow;
        if (currentSnapshot) {
          renderLeaderboardRows(currentSnapshot);
        }
      }
    });
  }

  function initBackdrop() {
    const canvas = document.getElementById("bg-canvas");
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    let viewW = window.innerWidth;
    let viewH = window.innerHeight;
    let dpr = Math.min(window.devicePixelRatio || 1, 2);

    const square = { x: 210, y: 160, vx: 135, vy: 95 };
    const PARTICLE_COUNT = 36;
    const particles = [];

    function spawnParticle(p, prewarm) {
      const spreadAngle = ((Math.random() * 2 - 1) * 15 * Math.PI) / 180;
      const speed = 14 + Math.random() * 26;
      const lifetime = 8.0;
      const age = prewarm ? Math.random() * lifetime : 0;
      p.x = Math.random() * viewW;
      p.y = viewH + 12;
      p.vx = Math.sin(spreadAngle) * speed;
      p.vy = -Math.cos(spreadAngle) * speed;
      p.x += p.vx * age;
      p.y += p.vy * age;
      p.age = age;
      p.lifetime = lifetime;
      p.size = 1.5 + Math.random() * 2.0;
    }

    for (let i = 0; i < PARTICLE_COUNT; i++) {
      const p = {};
      spawnParticle(p, true);
      particles.push(p);
    }

    function resizeCanvas() {
      viewW = Math.max(1, window.innerWidth);
      viewH = Math.max(1, window.innerHeight);
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(viewW * dpr);
      canvas.height = Math.round(viewH * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    resizeCanvas();
    window.addEventListener("resize", resizeCanvas);

    let animTime = 0;
    let lastTs = performance.now();

    function drawFrame(nowTs) {
      const dt = Math.min(0.05, Math.max(0, (nowTs - lastTs) / 1000));
      lastTs = nowTs;
      const animate = !reducedMotionQuery.matches;
      if (animate) {
        animTime += dt;
      }

      ctx.fillStyle = "#000000";
      ctx.fillRect(0, 0, viewW, viewH);

      const beamLen = Math.hypot(viewW, viewH) + 320;

      // DecorBeamA: position (w*0.5, h*0.28), rotation -0.28, half-height 18
      const pulseA = Math.round((0.16 + 0.06 * Math.sin(animTime * 2.0)) * 255);
      ctx.save();
      ctx.translate(viewW * 0.5, viewH * 0.28);
      ctx.rotate(-0.28);
      ctx.fillStyle = `rgb(${pulseA},${pulseA},${pulseA})`;
      ctx.fillRect(-beamLen, -18, beamLen * 2, 36);
      ctx.restore();

      // DecorBeamB: position (w*0.5, h*0.77), rotation +0.22, half-height 14
      const pulseB = Math.round((0.12 + 0.05 * Math.cos(animTime * 1.6)) * 255);
      ctx.save();
      ctx.translate(viewW * 0.5, viewH * 0.77);
      ctx.rotate(0.22);
      ctx.fillStyle = `rgb(${pulseB},${pulseB},${pulseB})`;
      ctx.fillRect(-beamLen, -14, beamLen * 2, 28);
      ctx.restore();

      // DecorSquare: 48x48 bouncing inside 34px margin
      const margin = 34;
      if (animate) {
        square.x += square.vx * dt;
        square.y += square.vy * dt;
        if (square.x < margin || square.x > viewW - margin) {
          square.x = Math.max(margin, Math.min(viewW - margin, square.x));
          square.vx = -square.vx;
        }
        if (square.y < margin || square.y > viewH - margin) {
          square.y = Math.max(margin, Math.min(viewH - margin, square.y));
          square.vy = -square.vy;
        }
      }
      const sqGray = Math.round((0.24 + 0.06 * Math.sin(animTime * 2.4)) * 255);
      ctx.save();
      ctx.translate(square.x, square.y);
      ctx.rotate(animTime * 0.65);
      ctx.fillStyle = `rgba(${sqGray},${sqGray},${sqGray},0.65)`;
      ctx.fillRect(-24, -24, 48, 48);
      ctx.restore();

      // AmbientParticles: 36 rising squares, white alpha 0.30
      ctx.fillStyle = "rgba(255,255,255,0.30)";
      for (const p of particles) {
        if (animate) {
          p.age += dt;
          p.x += p.vx * dt;
          p.y += p.vy * dt;
          if (p.age >= p.lifetime || p.y < -12) {
            spawnParticle(p, false);
          }
        }
        ctx.fillRect(p.x - p.size * 0.5, p.y - p.size * 0.5, p.size, p.size);
      }

      if (animate) {
        requestAnimationFrame(drawFrame);
      }
    }

    requestAnimationFrame(drawFrame);
    if (typeof reducedMotionQuery.addEventListener === "function") {
      reducedMotionQuery.addEventListener("change", () => {
        lastTs = performance.now();
        requestAnimationFrame(drawFrame);
      });
    }
  }

  bindTabs();
  initBackdrop();
  fetchSnapshotOnce();
  connectEvents();
})();
