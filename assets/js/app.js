import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// [사운드 관리자]
const SoundManager = {
  ctx: new (window.AudioContext || window.webkitAudioContext)(),
  isMuted: localStorage.getItem("cursor_party_muted") === "true",

  // 1. 일반 타격음 (가벼운 소리)
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

    gain.gain.setValueAtTime(0.05, now); // 볼륨을 조금 낮춤
    gain.gain.exponentialRampToValueAtTime(0.01, now + 0.1);

    osc.start(now);
    osc.stop(now + 0.1);
  },

  // 2. [신규] 크리티컬 타격음 (무겁고 강한 소리)
  playCrit() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();

    const now = this.ctx.currentTime;

    // 저음 베이스 (둥!)
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

    // 고음 노이즈 (챙!)
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

  // 3. 승리음
  playWin() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();

    const now = this.ctx.currentTime;
    const notes = [261.63, 329.63, 392.0, 523.25, 783.99]; // C Major + High G

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
};

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
    // 1. 클릭 즉시: 일반 타격음 & 보스 흔들림 (반응속도용)
    this.el.addEventListener("mousedown", (e) => {
      SoundManager.playHit();
      this.animateBoss();
      this.lastClickX = e.clientX;
      this.lastClickY = e.clientY;
    });

    this.handleEvent("play-win-sound", () => {
      SoundManager.playWin();
    });

    // 2. 서버 응답 수신: 대미지 표시 & 크리티컬 사운드 추가 재생
    this.handleEvent("damage-effect", ({ damage, is_crit }) => {
      const x = this.lastClickX || window.innerWidth / 2;
      const y = this.lastClickY || window.innerHeight / 2;

      // [핵심] 크리티컬이면 강한 소리를 한 번 더 재생! (이중 타격감)
      if (is_crit) {
        SoundManager.playCrit();
      }

      this.showDamage(x, y, damage, is_crit);
    });
  },

  showDamage(x, y, damage, isCrit) {
    const el = document.createElement("div");
    el.innerText = isCrit ? `CRITICAL! -${damage}` : `-${damage}`;

    // [수정] 색상 강제 지정 (Golden Yellow)
    el.className = isCrit
      ? "damage-number critical text-4xl font-black drop-shadow-[0_2px_4px_rgba(0,0,0,0.8)] z-50"
      : "damage-number text-white font-bold z-40";

    // 스타일 직접 주입 (Tailwind 클래스 무시하고 확실하게 적용)
    if (isCrit) {
      el.style.color = "#FFD700"; // 확실한 황금색
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

    // 크리티컬 시 화면 흔들림
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
