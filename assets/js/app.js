import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

// [신규] 사운드 관리자
const SoundManager = {
  ctx: new (window.AudioContext || window.webkitAudioContext)(),
  // 저장된 설정 불러오기 (없으면 false = 소리 켜짐)
  isMuted: localStorage.getItem("cursor_party_muted") === "true",

  playHit() {
    if (this.isMuted) return; // 음소거면 실행 안 함
    if (this.ctx.state === "suspended") this.ctx.resume();

    // (이전에 선택하신 2번 레이저 스타일)
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.connect(gain);
    gain.connect(this.ctx.destination);

    osc.type = "sawtooth";
    osc.frequency.setValueAtTime(800, now);
    osc.frequency.exponentialRampToValueAtTime(100, now + 0.15);

    gain.gain.setValueAtTime(0.1, now);
    gain.gain.exponentialRampToValueAtTime(0.01, now + 0.15);

    osc.start(now);
    osc.stop(now + 0.15);
  },

  playWin() {
    if (this.isMuted) return; // 음소거면 실행 안 함
    if (this.ctx.state === "suspended") this.ctx.resume();

    // (승리 화음)
    const now = this.ctx.currentTime;
    const notes = [261.63, 329.63, 392.0, 523.25];

    notes.forEach((freq, i) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.connect(gain);
      gain.connect(this.ctx.destination);
      osc.type = "triangle";
      osc.frequency.value = freq;

      const startTime = now + i * 0.05;
      gain.gain.setValueAtTime(0, startTime);
      gain.gain.linearRampToValueAtTime(0.2, startTime + 0.1);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + 2.0);

      osc.start(startTime);
      osc.stop(startTime + 2.0);
    });
  },
};

let Hooks = {};

// 1. 커서 트래킹
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

// 2. 보스 이펙트 & 사운드 트리거
Hooks.BossEffect = {
  mounted() {
    this.el.addEventListener("mousedown", (e) => {
      SoundManager.playHit();
      this.showDamage(e.clientX, e.clientY);
      this.animateBoss();
    });
    this.handleEvent("play-win-sound", () => {
      SoundManager.playWin();
    });
  },
  showDamage(x, y) {
    const el = document.createElement("div");
    el.innerText = "-1";
    el.className = "damage-number";
    const randomX = (Math.random() - 0.5) * 40;
    const randomY = (Math.random() - 0.5) * 20;
    el.style.left = `${x + randomX}px`;
    el.style.top = `${y - 50 + randomY}px`;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 800);
  },
  animateBoss() {
    const bossContainer = this.el.querySelector("div");
    if (bossContainer) {
      bossContainer.classList.add("boss-hit-effect");
      setTimeout(() => bossContainer.classList.remove("boss-hit-effect"), 100);
    }
  },
};

// 3. [신규] 사운드 버튼 제어 훅
Hooks.SoundControl = {
  mounted() {
    this.updateIcon();

    this.el.addEventListener("click", () => {
      // 상태 토글 및 저장
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
      this.el.classList.add("opacity-50"); // 꺼졌을 때 흐리게
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
    const chatBox = this.el;
    chatBox.scrollTop = chatBox.scrollHeight;
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
