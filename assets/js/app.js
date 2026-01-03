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

  playCrit() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;

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

  playShopOpen() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    [523.25, 659.25, 783.99].forEach((freq, i) => {
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.connect(gain);
      gain.connect(this.ctx.destination);
      osc.type = "sine";
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.1, now + i * 0.05);
      gain.gain.exponentialRampToValueAtTime(0.01, now + i * 0.05 + 0.4);
      osc.start(now + i * 0.05);
      osc.stop(now + i * 0.05 + 0.4);
    });
  },

  playBuy() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.type = "square";
    osc.frequency.setValueAtTime(987, now);
    osc.frequency.setValueAtTime(1318, now + 0.08);
    gain.gain.setValueAtTime(0.1, now);
    gain.gain.linearRampToValueAtTime(0.01, now + 0.4);
    osc.start(now);
    osc.stop(now + 0.4);
  },

  playChat() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();
    const now = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.type = "sine";
    osc.frequency.setValueAtTime(800, now);
    osc.frequency.exponentialRampToValueAtTime(400, now + 0.1);
    gain.gain.setValueAtTime(0.1, now);
    gain.gain.exponentialRampToValueAtTime(0.01, now + 0.1);
    osc.start(now);
    osc.stop(now + 0.1);
  },

  playThunder() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();

    const bufferSize = this.ctx.sampleRate * 1.5;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1;
    }

    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;

    const gain = this.ctx.createGain();
    const filter = this.ctx.createBiquadFilter();

    filter.type = "lowpass";
    filter.frequency.value = 800;

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.ctx.destination);

    gain.gain.setValueAtTime(0.8, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, this.ctx.currentTime + 1.2);

    noise.start();
  },
};

// ============================================================================
// 2. 파티클 시스템 (ParticleManager)
// ============================================================================
const ParticleManager = {
  canvas: null,
  ctx: null,
  particles: [],

  init() {
    this.canvas = document.createElement("canvas");
    Object.assign(this.canvas.style, {
      position: "fixed",
      top: "0",
      left: "0",
      width: "100%",
      height: "100%",
      pointerEvents: "none",
      // 👇 [수정] Z-Index 대폭 하향 (9999 -> 30)
      // 보스(10)보다는 위, 일반 UI(50~)보다는 아래에 위치시킴
      zIndex: "30",
    });
    document.body.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d", { alpha: true });

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
        type: "circle",
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
    let count = 0;
    const interval = setInterval(() => {
      const x = Math.random() * window.innerWidth;
      const y = Math.random() * (window.innerHeight * 0.6);
      this.burst(x, y, `hsl(${Math.random() * 360}, 100%, 60%)`, 15, 2);
      count++;
      if (count > 10) clearInterval(interval);
    }, 300);
  },

  drawLightning() {
    // 1. 화면 화이트 아웃 효과
    const flash = document.createElement("div");
    Object.assign(flash.style, {
      position: "fixed",
      inset: "0",
      backgroundColor: "white",
      // 👇 [수정] Z-Index 하향 (9998 -> 30)
      zIndex: "30",
      pointerEvents: "none",
      opacity: "0.6", // 불투명도 약간 낮춤 (눈부심 방지)
      transition: "opacity 0.5s ease-out", // 👇 [수정] 지속 시간 0.15s -> 0.5s (부드럽게)
    });
    document.body.appendChild(flash);

    // 애니메이션 프레임 확보 후 실행
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        flash.style.opacity = "0";
        // 👇 [수정] 삭제 타이머 0.15s -> 0.5s
        setTimeout(() => flash.remove(), 500);
      });
    });

    const startX = Math.random() * this.canvas.width;
    const startY = -50;
    const endX = this.canvas.width / 2;
    const endY = this.canvas.height / 2;

    this.createBolt(startX, startY, endX, endY, 5, "#CCFFFF");

    for (let i = 0; i < 3; i++) {
      this.createBolt(
        startX + (Math.random() - 0.5) * 100,
        -50,
        endX + (Math.random() - 0.5) * 300,
        endY + (Math.random() - 0.5) * 200,
        2,
        "#5599FF",
      );
    }

    this.burst(endX, endY, "#AAFFFF", 30, 3);
    this.burst(endX, endY, "#FFFFFF", 20, 2);
  },

  createBolt(x1, y1, x2, y2, thickness, color) {
    const positions = [];
    const steps = 10;
    const dx = (x2 - x1) / steps;
    const dy = (y2 - y1) / steps;

    for (let i = 0; i <= steps; i++) {
      const jitter = (Math.random() - 0.5) * 40;
      positions.push({
        x: x1 + dx * i + jitter,
        y: y1 + dy * i,
      });
    }
    positions[positions.length - 1] = { x: x2, y: y2 };

    this.particles.push({
      type: "bolt",
      path: positions,
      life: 1.0,
      decay: 0.03, // 👇 [수정] 0.1 -> 0.03 (번개가 훨씬 천천히 사라짐)
      color: color,
      width: thickness,
      shake: 2,
    });
  },

  loop() {
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];

      if (p.type === "bolt") {
        if (p.life > 0) {
          this.ctx.beginPath();
          this.ctx.strokeStyle = p.color;
          this.ctx.lineWidth = p.width;
          this.ctx.lineCap = "round";
          this.ctx.lineJoin = "round";

          if (p.path.length > 0) {
            this.ctx.moveTo(p.path[0].x, p.path[0].y);
            for (let j = 1; j < p.path.length; j++) {
              const shake = (Math.random() - 0.5) * p.shake;
              this.ctx.lineTo(p.path[j].x + shake, p.path[j].y);
            }
          }
          this.ctx.globalAlpha = p.life;
          this.ctx.stroke();

          p.life -= p.decay;
        } else {
          this.particles.splice(i, 1);
        }
      } else {
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
          this.ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
          this.ctx.fill();
        }
      }
    }
    this.ctx.globalAlpha = 1.0;
    requestAnimationFrame(() => this.loop());
  },
};

ParticleManager.init();

// ============================================================================
// 3. Hooks 정의
// ============================================================================
let Hooks = {};

Hooks.AccountSync = {
  mounted() {
    this.handleEvent("update_uuid", ({ new_uuid }) => {
      localStorage.setItem("user_uuid", new_uuid);
      alert("계정이 성공적으로 연동되었습니다! 게임을 다시 로드합니다.");
      window.location.reload();
    });
  },
};

Hooks.Locale = {
  mounted() {
    this.handleEvent("save_locale", ({ locale }) => {
      localStorage.setItem("user_locale", locale);
      window.location.reload();
    });
  },
};

Hooks.CursorTrack = {
  mounted() {
    const getDeviceInfo = () => {
      const ua = navigator.userAgent;
      const isMobile =
        /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobi/i.test(
          ua,
        );
      return { deviceType: isMobile ? "Mobile" : "Desktop" };
    };

    this.pushEvent("device-info", getDeviceInfo());

    let lastSent = 0;
    const throttleMs = 30;
    const handleMove = (x, y) => {
      // LiveView 연결 상태 확인
      if (!window.liveSocket.isConnected()) return;

      const now = Date.now();
      if (now - lastSent > throttleMs) {
        const xPct = (x / window.innerWidth) * 100;
        const yPct = (y / window.innerHeight) * 100;

        try {
          this.pushEvent("cursor-move", { x: xPct, y: yPct });
        } catch (e) {
          return;
        }
        lastSent = now;
      }
    };

    this.el.addEventListener("mousemove", (e) =>
      handleMove(e.clientX, e.clientY),
    );
    this.el.addEventListener("touchmove", (e) => {
      const touch = e.touches[0];
      handleMove(touch.clientX, touch.clientY);
    });
  },
};

Hooks.BossEffect = {
  mounted() {
    // 기본 설정
    this.locale = this.el.dataset.locale || "en";

    // 1. [최적화] 클릭 이벤트 리스너 (즉시 반응)
    this.el.addEventListener("mousedown", (e) => {
      // (1) 데이터 가져오기 (HTML data 속성에서)
      const power = parseInt(this.el.dataset.power || "1");
      const baseCrit = parseInt(this.el.dataset.critChance || "0");

      // (2) 클라이언트 측 즉시 계산 (서버 기다리지 않음!)
      // 기본 크리 15% + 아이템 크리
      const isCrit = Math.random() * 100 < 15 + baseCrit;
      const damage = isCrit ? power * 2 : power;

      // (3) 좌표 보정 (터치/마우스)
      const x =
        e.clientX ||
        (e.touches && e.touches[0].clientX) ||
        window.innerWidth / 2;
      const y =
        e.clientY ||
        (e.touches && e.touches[0].clientY) ||
        window.innerHeight / 2;

      // (4) 즉시 실행 (사운드, 파티클, 데미지 숫자, 보스 애니메이션)
      if (isCrit) {
        SoundManager.playCrit();
        ParticleManager.burst(x, y, "#FFD700", 25, 1.5);
      } else {
        SoundManager.playHit();
        ParticleManager.burst(x, y, "white", 8, 1);
      }

      this.animateBoss();
      this.showDamage(x, y, damage, isCrit);
    });

    // 2. 서버 이벤트 리스너 (번개, 승리 등 글로벌 이벤트용)
    // 주의: 단순 클릭 데미지는 위에서 처리하므로 handleEvent("damage-effect")는 제거하거나
    // 다른 유저의 데미지를 보여줄 때만 사용해야 합니다.
    // 여기서는 "내 클릭" 반응성을 위해 제거했습니다.

    this.handleEvent("play-win-sound", () => {
      if (document.hidden) return;
      SoundManager.playWin();
      ParticleManager.startFireworks();
    });

    this.handleEvent("global-effect", ({ type }) => {
      if (document.hidden) return;
      if (type === "thunder") {
        SoundManager.playThunder();
        ParticleManager.drawLightning();
        this.triggerBossHitEffect(); // 번개 맞았을 때도 보스 흔들림
      }
    });

    this.handleEvent("play-shop-sound", () => SoundManager.playShopOpen());
    this.handleEvent("play-buy-sound", () => SoundManager.playBuy());
    this.handleEvent("play-chat-sound", () => SoundManager.playChat());
  },

  // 데이터가 바뀌면(공격력 증가 등) 즉시 반영
  updated() {
    this.locale = this.el.dataset.locale || "en";
  },

  // [UI 유지] 기존 디자인과 100% 동일한 데미지 출력 함수
  showDamage(x, y, damage, isCrit) {
    const el = document.createElement("div");

    // 숫자 콤마 포맷팅 (예: 1,000)
    const formattedDamage = damage.toLocaleString();

    let text = `-${formattedDamage}`;
    if (isCrit) {
      text =
        this.locale === "ko"
          ? `치명타! -${formattedDamage}`
          : `CRITICAL! -${formattedDamage}`;
    }
    el.innerText = text;

    el.className = isCrit
      ? "damage-number critical text-4xl font-black drop-shadow-[0_2px_4px_rgba(0,0,0,0.8)] z-50"
      : "damage-number text-white font-bold z-40";

    if (isCrit) {
      el.style.color = "#FFD700";
      el.style.textShadow = "0 0 10px rgba(255, 215, 0, 0.7)";
    }

    // 랜덤하게 퍼지는 위치 계산
    const randomX = (Math.random() - 0.5) * 50;
    const randomY = (Math.random() - 0.5) * 30;

    Object.assign(el.style, {
      left: `${x + randomX}px`,
      top: `${y - 50 + randomY}px`,
      position: "absolute",
      pointerEvents: "none",
      // 애니메이션: 위로 떠오르며 사라짐
      animation: "floatUp 0.8s ease-out forwards",
    });

    document.body.appendChild(el);

    // 메모리 누수 방지 (0.8초 후 삭제)
    setTimeout(() => el.remove(), 800);

    // 크리티컬 시 화면 흔들림 효과
    if (isCrit) {
      document.body.classList.add("shake-screen");
      setTimeout(() => document.body.classList.remove("shake-screen"), 200);
    }
  },

  // 보스 피격 애니메이션 (CSS 클래스 토글)
  animateBoss() {
    this.triggerBossHitEffect();
  },

  triggerBossHitEffect() {
    const bossContainer = this.el.querySelector("div"); // 보스 이미지를 감싼 div 찾기
    if (bossContainer) {
      // 기존 애니메이션 초기화 (광클 시 끊김 방지)
      bossContainer.classList.remove("boss-hit-effect");

      // 강제 리플로우 (브라우저가 변경사항을 즉시 인식하게 함)
      void bossContainer.offsetWidth;

      bossContainer.classList.add("boss-hit-effect");

      // 타임아웃은 안전장치로 둠
      setTimeout(() => bossContainer.classList.remove("boss-hit-effect"), 100);
    }
  },
};

Hooks.SkillTimer = {
  timer: null,
  pending: false,
  mounted() {
    this.startTimer();
  },
  updated() {
    this.pending = false;
    this.startTimer();
  },
  destroyed() {
    if (this.timer) clearInterval(this.timer);
  },
  startTimer() {
    if (this.timer) clearInterval(this.timer);
    const tick = () => {
      const readyAt = parseInt(this.el.dataset.readyAt || "0");
      const now = Date.now();
      const diff = readyAt - now;

      const overlay = this.el.querySelector(".cooldown-overlay");
      const text = this.el.querySelector(".cooldown-text");
      const readyEffect = this.el.querySelector(".ready-effect");

      if (diff > 0) {
        const seconds = (diff / 1000).toFixed(1);
        const percent = Math.min((diff / 30000) * 100, 100);

        if (text) text.innerText = seconds;
        if (overlay) overlay.style.height = `${percent}%`;

        this.el.classList.add("opacity-80");
        if (readyEffect) readyEffect.classList.add("hidden");

        this.pending = false;
      } else {
        if (text) text.innerText = "";
        if (overlay) overlay.style.height = "0%";
        this.el.classList.remove("opacity-80");
        if (readyEffect) readyEffect.classList.remove("hidden");
        const winnerModal = document.getElementById("winner-modal");

        if (!this.pending && !winnerModal) {
          console.log("⚡ 번개 스킬 자동 발동!");
          this.pending = true;

          this.pushEvent("use-thunder-skill", {});
        }
      }
    };
    tick();
    this.timer = setInterval(tick, 100);
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

// Hooks 객체에 모든 훅이 포함되어 있으므로 spread 연산자 사용
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
    locale: localStorage.getItem("user_locale") || "en",
  },
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

window.addEventListener("js:play-shop-sound", () => {
  SoundManager.playShopOpen();
});
