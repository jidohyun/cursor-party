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

  // [신규] 천둥 소리 추가 (노이즈 필터링)
  playThunder() {
    if (this.isMuted) return;
    if (this.ctx.state === "suspended") this.ctx.resume();

    // 백색 소음 생성 (White Noise)
    const bufferSize = this.ctx.sampleRate * 1.5; // 1.5초 길이
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1;
    }

    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;

    const gain = this.ctx.createGain();
    const filter = this.ctx.createBiquadFilter();

    // 저역 통과 필터 (Lowpass)로 웅장한 소리 만들기
    filter.type = "lowpass";
    filter.frequency.value = 800; // 주파수 낮춤

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.ctx.destination);

    // 볼륨 페이드 아웃
    gain.gain.setValueAtTime(0.8, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, this.ctx.currentTime + 1.2);

    noise.start();
  },
};

// ============================================================================
// 2. 파티클 시스템 (ParticleManager)
// ============================================================================
// ... (SoundManager는 기존 코드 유지) ...

// ============================================================================
// 2. [최적화] 파티클 시스템 (ParticleManager) - 가볍지만 화려하게
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
      zIndex: "9999",
    });
    document.body.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d", { alpha: true }); // 투명도 지원 명시

    this.resize();
    window.addEventListener("resize", () => this.resize());
    this.loop();
  },

  resize() {
    // [최적화] 고해상도 디스플레이에서도 1:1 픽셀 매칭으로 성능 확보
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
  },

  // 폭발 이펙트 (개수 감소)
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
      // 폭죽 파티클 개수도 30 -> 15로 줄임
      this.burst(x, y, `hsl(${Math.random() * 360}, 100%, 60%)`, 15, 2);
      count++;
      if (count > 10) clearInterval(interval);
    }, 300);
  },

  // 번개 그리기 (최적화됨)
  drawLightning() {
    // 1. 화면 전체 화이트 아웃 (강렬함)
    const flash = document.createElement("div");
    Object.assign(flash.style, {
      position: "fixed",
      inset: "0",
      backgroundColor: "white",
      zIndex: "9998",
      pointerEvents: "none",
      opacity: "0.9",
      transition: "opacity 0.15s ease-out",
    });
    document.body.appendChild(flash);
    requestAnimationFrame(() => {
      flash.style.opacity = "0";
      setTimeout(() => flash.remove(), 150);
    });

    const startX = Math.random() * this.canvas.width; // 하늘 어딘가
    const startY = -50;
    const endX = this.canvas.width / 2; // 보스 (화면 중앙)
    const endY = this.canvas.height / 2;

    // 2. 메인 줄기 생성 (굵고 강함)
    this.createBolt(startX, startY, endX, endY, 5, "#CCFFFF");

    // 3. 보조 줄기 생성 (주변으로 퍼짐)
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

    // 4. 타격 지점 대폭발 (전기 스파크)
    this.burst(endX, endY, "#AAFFFF", 30, 3); // 청록색 스파크
    this.burst(endX, endY, "#FFFFFF", 20, 2); // 흰색 스파크
  },

  createBolt(x1, y1, x2, y2, thickness, color) {
    const positions = [];
    const steps = 10; // [최적화] 꺾이는 횟수 20 -> 10 (계산량 절반)
    const dx = (x2 - x1) / steps;
    const dy = (y2 - y1) / steps;

    for (let i = 0; i <= steps; i++) {
      const jitter = (Math.random() - 0.5) * 40; // 떨림 범위 축소
      positions.push({
        x: x1 + dx * i + jitter,
        y: y1 + dy * i, // Y축 떨림 제거 (계산 단순화)
      });
    }
    // 마지막 위치 보정
    positions[positions.length - 1] = { x: x2, y: y2 };

    this.particles.push({
      type: "bolt",
      path: positions,
      life: 1.0,
      decay: 0.1, // [최적화] 0.05 -> 0.1 (2배 빨리 사라짐)
      color: color,
      width: thickness,
      shake: 2, // [최적화] 떨림 강도 5 -> 2
    });
  },

  loop() {
    // [최적화] clearRect는 전체 지우기 중 가장 빠름
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    // [최적화] globalCompositeOperation 'lighter' 제거 (성능 부하 큼)
    // 대신 색상을 좀 더 밝게 설정하는 것으로 대체

    // 파티클 순회 (역순)
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];

      if (p.type === "bolt") {
        // --- 번개 ---
        if (p.life > 0) {
          this.ctx.beginPath();
          this.ctx.strokeStyle = p.color;
          this.ctx.lineWidth = p.width;
          this.ctx.lineCap = "round";
          this.ctx.lineJoin = "round";

          // [최적화] ShadowBlur 제거 (성능 킬러)
          // this.ctx.shadowBlur = 0;

          if (p.path.length > 0) {
            this.ctx.moveTo(p.path[0].x, p.path[0].y);
            for (let j = 1; j < p.path.length; j++) {
              // 매 프레임 떨림 효과 (Shake)
              // [최적화] Math.random 호출 최소화
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
        // --- 일반 원형 입자 ---
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
          // [최적화] 작은 원은 fillRect가 arc보다 빠를 수 있음 (여기선 arc 유지하되 크기 작게)
          this.ctx.arc(p.x, p.y, 2, 0, Math.PI * 2);
          this.ctx.fill();
        }
      }
    }

    // 알파값 복구
    this.ctx.globalAlpha = 1.0;

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
    // 1. 단순화된 기기 정보 탐지 (Mobile vs Desktop)
    const getDeviceInfo = () => {
      const ua = navigator.userAgent;
      // 모바일 관련 키워드가 포함되어 있는지 정규식으로 검사
      const isMobile =
        /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobi/i.test(
          ua,
        );

      return { deviceType: isMobile ? "Mobile" : "Desktop" };
    };

    // 2. 서버로 전송
    this.pushEvent("device-info", getDeviceInfo());

    // 3. 커서 이동 로직 (기존 유지)
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
      // e.preventDefault(); // 스크롤 허용하려면 주석 처리
      const touch = e.touches[0];
      handleMove(touch.clientX, touch.clientY);
    });
  },
};

Hooks.BossEffect = {
  mounted() {
    this.el.addEventListener("mousedown", (e) => {
      SoundManager.playHit();
      this.animateBoss();
      ParticleManager.burst(e.clientX, e.clientY, "white", 8, 1);
      this.lastClickX = e.clientX;
      this.lastClickY = e.clientY;
    });

    this.handleEvent("play-win-sound", () => {
      SoundManager.playWin();
      ParticleManager.startFireworks();
    });

    this.handleEvent("damage-effect", ({ damage, is_crit }) => {
      const x = this.lastClickX || window.innerWidth / 2;
      const y = this.lastClickY || window.innerHeight / 2;

      if (is_crit) {
        SoundManager.playCrit();
        ParticleManager.burst(x, y, "#FFD700", 25, 1.5);
      }
      this.showDamage(x, y, damage, is_crit);
    });

    this.handleEvent("play-shop-sound", () => SoundManager.playShopOpen());
    this.handleEvent("play-buy-sound", () => SoundManager.playBuy());
    this.handleEvent("play-chat-sound", () => SoundManager.playChat());

    // [신규] 글로벌 이펙트 (번개 등) 리스너 추가
    this.handleEvent("global-effect", ({ type }) => {
      if (type === "thunder") {
        SoundManager.playThunder(); // 천둥 소리 재생
        ParticleManager.drawLightning(); // 번개 그리기

        // 보스에게 강한 타격감 주기
        const bossContainer = document.querySelector("#boss-target > div");
        if (bossContainer) {
          bossContainer.classList.add("boss-hit-effect");
          setTimeout(
            () => bossContainer.classList.remove("boss-hit-effect"),
            200,
          );
        }
      }
    });
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

Hooks.SkillTimer = {
  timer: null,

  mounted() {
    this.startTimer();
  },

  updated() {
    // 서버에서 시간이 바뀌면(스킬 발동 후) 다시 타이머 시작
    this.startTimer();
  },

  destroyed() {
    if (this.timer) clearInterval(this.timer);
  },

  startTimer() {
    if (this.timer) clearInterval(this.timer);

    const tick = () => {
      // 1. 목표 시간(Unix Timestamp MS) 가져오기
      const readyAt = parseInt(this.el.dataset.readyAt || "0");
      const now = Date.now();
      const diff = readyAt - now;

      const overlay = this.el.querySelector(".cooldown-overlay");
      const text = this.el.querySelector(".cooldown-text");
      const readyEffect = this.el.querySelector(".ready-effect");

      if (diff > 0) {
        // [쿨타임 중]
        const seconds = (diff / 1000).toFixed(1); // 소수점 1자리
        const percent = Math.min((diff / 30000) * 100, 100); // 30초 기준 퍼센트

        if (text) text.innerText = seconds;
        // 높이로 쿨타임 표시 (위에서 아래로 줄어듦)
        if (overlay) overlay.style.height = `${percent}%`;

        this.el.classList.add("opacity-80"); // 약간 어둡게
        if (readyEffect) readyEffect.classList.add("hidden");
      } else {
        // [준비 완료 / 발동 직전]
        if (text) text.innerText = ""; // 텍스트 숨김
        if (overlay) overlay.style.height = "0%";

        this.el.classList.remove("opacity-80");
        if (readyEffect) readyEffect.classList.remove("hidden");
      }
    };

    tick(); // 즉시 실행
    this.timer = setInterval(tick, 100); // 0.1초마다 갱신
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
