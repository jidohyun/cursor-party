import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// ============================================================================
// 1. 사운드 관리자 (SoundManager)
// ============================================================================
const SoundManager = {
  ctx: new (window.AudioContext || window.webkitAudioContext)(),
  isMuted: localStorage.getItem("cursor_party_muted") === "true",

  // (1) 일반 타격음
  playHit() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.type = "sawtooth";
    osc.frequency.setValueAtTime(800, now);
    osc.frequency.exponentialRampToValueAtTime(100, now + 0.1);
    gain.gain.setValueAtTime(0.05, now);
    gain.gain.exponentialRampToValueAtTime(0.01, now + 0.1);
    osc.start(now);
    osc.stop(now + 0.1);
  },

  // (2) 크리티컬음
  playCrit() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;

    // 저음 베이스
    const osc1 = this.ctx.createOscillator();
    const gain1 = this.ctx.createGain();
    osc1.connect(gain1);
    gain1.connect(this.ctx.destination);
    osc1.type = "square";
    osc1.frequency.setValueAtTime(150, now);
    osc1.frequency.exponentialRampToValueAtTime(40, now + 0.3);
    gain1.gain.setValueAtTime(0.2, now);
    gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.3);
    osc1.start(now);
    osc1.stop(now + 0.3);

    // 고음 임팩트
    const osc2 = this.ctx.createOscillator();
    const gain2 = this.ctx.createGain();
    osc2.connect(gain2);
    gain2.connect(this.ctx.destination);
    osc2.type = "sawtooth";
    osc2.frequency.setValueAtTime(600, now);
    osc2.frequency.linearRampToValueAtTime(200, now + 0.2);
    gain2.gain.setValueAtTime(0.1, now);
    gain2.gain.linearRampToValueAtTime(0.01, now + 0.2);
    osc2.start(now);
    osc2.stop(now + 0.2);
  },

  // (3) 승리음
  playWin() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    const notes = [261.63, 329.63, 392.0, 523.25, 783.99];
    notes.forEach((freq, i) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.connect(gain);
      gain.connect(this.ctx.destination);
      osc.type = "triangle";
      osc.frequency.value = freq;
      const startTime = now + i * 0.08;
      gain.gain.setValueAtTime(0, startTime);
      gain.gain.linearRampToValueAtTime(0.2, startTime + 0.1);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + 2.0);
      osc.start(startTime);
      osc.stop(startTime + 2.0);
    });
  },

  // (4) [신규] 상점 열기 (띠리링~)
  playShopOpen() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    // 맑은 아르페지오 (C -> E -> G)
    [523.25, 659.25, 783.99].forEach((freq, i) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.connect(gain);
      gain.connect(this.ctx.destination);
      osc.type = "sine"; // 부드러운 사인파
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.1, now + i * 0.05);
      gain.gain.exponentialRampToValueAtTime(0.01, now + i * 0.05 + 0.4);
      osc.start(now + i * 0.05);
      osc.stop(now + i * 0.05 + 0.4);
    });
  },

  // (5) [신규] 아이템 구매 (차-칭!)
  playBuy() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    // 코인 소리 (High B -> High E)
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.type = "square"; // 레트로 게임 코인 느낌
    osc.frequency.setValueAtTime(987, now);
    osc.frequency.setValueAtTime(1318, now + 0.08); // 빠른 피치 변경
    gain.gain.setValueAtTime(0.1, now);
    gain.gain.linearRampToValueAtTime(0.01, now + 0.4);
    osc.start(now);
    osc.stop(now + 0.4);
  },

  // (6) [신규] 채팅 알림 (뽁!)
  playChat() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    // 물방울 소리
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.type = "sine";
    osc.frequency.setValueAtTime(800, now);
    osc.frequency.exponentialRampToValueAtTime(400, now + 0.1); // 피치가 떨어짐
    gain.gain.setValueAtTime(0.1, now);
    gain.gain.exponentialRampToValueAtTime(0.01, now + 0.1);
    osc.start(now);
    osc.stop(now + 0.1);
  },
};

// ============================================================================
// 2. 파티클 시스템 (ParticleManager)
// ============================================================================
const ParticleManager = {
  canvas: null,
  ctx: null,
  particles: [],
  fireworksActive: false,

  init() {
    this.canvas = document.createElement("canvas");
    this.canvas.style.position = "fixed";
    this.canvas.style.top = "0";
    this.canvas.style.left = "0";
    this.canvas.style.width = "100%";
    this.canvas.style.height = "100%";
    this.canvas.style.pointerEvents = "none";
    this.canvas.style.zIndex = "9999";
    document.body.appendChild(this.canvas);

    this.ctx = this.canvas.getContext("2d");
    this.resize();
    window.addEventListener("resize", () => this.resize());
    this.loop();
  },

  resize() {
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
  },

  burst(x, y, color = "white", count = 10, speed = 1) {
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const velocity = Math.random() * 5 * speed;
      this.particles.push({
        x: x,
        y: y,
        vx: Math.cos(angle) * velocity,
        vy: Math.sin(angle) * velocity,
        life: 1.0,
        decay: 0.02 + Math.random() * 0.03,
        color: color,
        gravity: 0.2,
      });
    }
  },

  startFireworks() {
    this.fireworksActive = true;
    let count = 0;
    const interval = setInterval(() => {
      const x = Math.random() * window.innerWidth;
      const y = Math.random() * (window.innerHeight * 0.6);
      const color = `hsl(${Math.random() * 360}, 100%, 50%)`;
      this.burst(x, y, color, 30, 2);
      SoundManager.playHit();

      count++;
      if (count > 15) {
        clearInterval(interval);
        this.fireworksActive = false;
      }
    }, 300);
  },

  loop() {
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy += p.gravity;
      p.life -= p.decay;

      if (p.life <= 0) {
        this.particles.splice(i, 1);
      } else {
        this.ctx.globalAlpha = p.life;
        this.ctx.fillStyle = p.color;
        this.ctx.beginPath();
        this.ctx.arc(p.x, p.y, 3, 0, Math.PI * 2);
        this.ctx.fill();
      }
    }
    requestAnimationFrame(() => this.loop());
  },
};

ParticleManager.init();

// ============================================================================
// 3. Hooks 정의
// ============================================================================
let Hooks = {};

Hooks.CursorTrack = {
  mounted() {
    let lastSent = 0;
    const throttleMs = 30;
    const handleMove = (x, y) => {
      const now = Date.now();
      if (now - lastSent > throttleMs) {
        const xPct = (x / window.innerWidth) * 100;
        const yPct = (y / window.innerHeight) * 100;
        this.pushEvent("cursor-move", { x: xPct, y: yPct });
        lastSent = now;
      }
    };
    this.el.addEventListener("mousemove", (e) =>
      handleMove(e.clientX, e.clientY),
    );
    this.el.addEventListener("touchmove", (e) => {
      e.preventDefault();
      const touch = e.touches[0];
      handleMove(touch.clientX, touch.clientY);
    });
  },
};

Hooks.BossEffect = {
  mounted() {
    // 1. 클릭 시 (즉각 반응)
    this.el.addEventListener("mousedown", (e) => {
      SoundManager.playHit();
      this.animateBoss();
      ParticleManager.burst(e.clientX, e.clientY, "white", 8, 1);
      this.lastClickX = e.clientX;
      this.lastClickY = e.clientY;
    });

    // 2. 승리 시 (폭죽)
    this.handleEvent("play-win-sound", () => {
      SoundManager.playWin();
      ParticleManager.startFireworks();
    });

    // 3. 서버 응답 (대미지 표시 & 크리티컬 효과)
    this.handleEvent("damage-effect", ({ damage, is_crit }) => {
      const x = this.lastClickX || window.innerWidth / 2;
      const y = this.lastClickY || window.innerHeight / 2;

      if (is_crit) {
        SoundManager.playCrit();
        ParticleManager.burst(x, y, "#FFD700", 25, 1.5);
      }

      this.showDamage(x, y, damage, is_crit);
    });

    // 4. [신규] UI 사운드 이벤트 리스너 추가
    this.handleEvent("play-shop-sound", () => SoundManager.playShopOpen());
    this.handleEvent("play-buy-sound", () => SoundManager.playBuy());
    this.handleEvent("play-chat-sound", () => SoundManager.playChat());
  },

  showDamage(x, y, damage, isCrit) {
    const el = document.createElement("div");
    el.innerText = isCrit ? `CRITICAL! -${damage}` : `-${damage}`;
    el.className = isCrit
      ? "damage-number critical text-4xl font-black drop-shadow-[0_2px_4px_rgba(0,0,0,0.8)] z-50"
      : "damage-number text-white font-bold z-40";

    if (isCrit) {
      el.style.color = "#FFD700";
      el.style.textShadow = "0 0 10px rgba(255, 215, 0, 0.7)";
    }

    const randomX = (Math.random() - 0.5) * 50;
    const randomY = (Math.random() - 0.5) * 30;

    el.style.left = `${x + randomX}px`;
    el.style.top = `${y - 50 + randomY}px`;
    el.style.position = "absolute";
    el.style.pointerEvents = "none";
    el.style.animation = "floatUp 0.8s ease-out forwards";

    document.body.appendChild(el);
    setTimeout(() => el.remove(), 800);

    if (isCrit) {
      document.body.classList.add("shake-screen");
      setTimeout(() => document.body.classList.remove("shake-screen"), 200);
    }
  },

  animateBoss() {
    const bossContainer = this.el.querySelector("div");
    if (bossContainer) {
      bossContainer.classList.add("boss-hit-effect");
      setTimeout(() => bossContainer.classList.remove("boss-hit-effect"), 100);
    }
  },
};

Hooks.SoundControl = {
  mounted() {
    this.updateIcon();
    this.el.addEventListener("click", () => {
      SoundManager.isMuted = !SoundManager.isMuted;
      localStorage.setItem("cursor_party_muted", SoundManager.isMuted);
      this.updateIcon();
    });
  },
  updateIcon() {
    const onIcon = this.el.querySelector(".icon-on");
    const offIcon = this.el.querySelector(".icon-off");
    if (SoundManager.isMuted) {
      onIcon.classList.add("hidden");
      offIcon.classList.remove("hidden");
      this.el.classList.add("opacity-50");
    } else {
      onIcon.classList.remove("hidden");
      offIcon.classList.add("hidden");
      this.el.classList.remove("opacity-50");
    }
  },
};

Hooks.ChatScroll = {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    this.scrollToBottom();
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...Hooks },
});

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();
window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();
    },
  );
}
