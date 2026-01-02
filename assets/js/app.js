import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

let Hooks = {};

// 1. 기존 커서 트래킹 훅
Hooks.CursorTrack = {
  mounted() {
    console.log("CursorTrack mounted!");
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

    this.el.addEventListener("mousemove", (e) => {
      handleMove(e.clientX, e.clientY);
    });

    this.el.addEventListener("touchmove", (e) => {
      e.preventDefault();
      const touch = e.touches[0];
      handleMove(touch.clientX, touch.clientY);
    });
  },
};

// 2. [신규] 보스 타격 이펙트 훅 (추가된 부분)
Hooks.BossEffect = {
  mounted() {
    this.el.addEventListener("mousedown", (e) => {
      // 마우스 위치에 대미지 숫자 띄우기
      this.showDamage(e.clientX, e.clientY);
      // 보스 흔들림 효과
      this.animateBoss();
    });
  },

  showDamage(x, y) {
    const el = document.createElement("div");
    el.innerText = "-1";
    el.className = "damage-number"; // CSS에 정의된 클래스

    // 위치를 약간 랜덤하게 흩뿌리기
    const randomX = (Math.random() - 0.5) * 40;
    const randomY = (Math.random() - 0.5) * 20;

    el.style.left = `${x + randomX}px`;
    el.style.top = `${y - 50 + randomY}px`; // 커서보다 조금 위쪽

    document.body.appendChild(el);

    // 애니메이션 시간(0.8s) 후 제거
    setTimeout(() => {
      el.remove();
    }, 800);
  },

  animateBoss() {
    // 훅이 걸린 요소 내부의 div(보스 이미지 컨테이너)를 찾음
    const bossContainer = this.el.querySelector("div");
    if (bossContainer) {
      bossContainer.classList.add("boss-hit-effect"); // CSS 번쩍임 효과
      setTimeout(() => {
        bossContainer.classList.remove("boss-hit-effect");
      }, 100);
    }
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...Hooks }, // Hooks 객체 등록
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      reloader.enableServerLogs();
      let keyDown;
      window.addEventListener("keydown", (e) => {
        keyDown = e.key;
        return keyDown;
      });
      window.addEventListener("keyup", (_e) => {
        keyDown = null;
        return keyDown;
      });
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );
      window.liveReloader = reloader;
    },
  );
}
