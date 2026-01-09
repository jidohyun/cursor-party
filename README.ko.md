## 📢 서비스 운영 중단 안내

**Cursor Party**의 베타 테스트 운영이 종료되었습니다.
테스트를 위해 사용하던 호스팅 플랫폼의 무료 플랜(14일)이 만료됨에 따라, 부득이하게 라이브 서비스를 중단하게 되었습니다.

짧은 기간이었지만 관심을 갖고 플레이해 주신 모든 분께 진심으로 감사드립니다! 🙇‍♂️
라이브 서버는 닫혔지만, 코드를 다운로드하여 로컬 환경에서 직접 실행해 보실 수 있습니다.


# 🖱️ Cursor Party

[![Elixir](https://img.shields.io/badge/Elixir-4B275F?style=for-the-badge&logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white)](https://www.phoenixframework.org/)
[![Tailwind CSS v4](https://img.shields.io/badge/Tailwind_v4-38B2AC?style=for-the-badge&logo=tailwind-css&logoColor=white)](https://tailwindcss.com/)
[![Koyeb](https://img.shields.io/badge/Koyeb-121212?style=for-the-badge&logo=koyeb&logoColor=white)](https://www.koyeb.com/)

> **"1시간 만에 실시간 MMO 게임을 만들 수 있을까?"**
> Elixir와 Phoenix LiveView의 강력한 분산 처리 성능을 실험하기 위해 만든 프로젝트입니다.

[🇺🇸 Read in English](./README.md)


## 🎮 데모 플레이

👉 **[Live Demo 보러가기](https://cursor-party.koyeb.app)**
_(현재 Open Beta 상태입니다. 서버는 언제든 열려있으니 들어와서 보스를 때려주세요!)_

## 💡 프로젝트 소개

**Cursor Party**는 접속한 모든 유저가 서로의 커서를 실시간으로 볼 수 있고, 협력하여 보스 몬스터를 처치하는 웹 게임입니다.

<strong>디스코드(Discord)</strong>가 수백만 명의 동시 접속자를 처리하는 비결이 **Elixir**라는 글을 보고 영감을 받았습니다.
<strong>"서버가 모든 상태를 관리하면서 실시간 동기화가 가능할까?"</strong>라는 기술적 호기심을 검증하기 위해 **1시간 챌린지**로 시작된 프로젝트입니다.

### ✨ 주요 기능

- **실시간 커서 공유:** WebSocket을 통해 지연 없이 모든 유저의 커서 위치를 공유합니다.
- **보스 레이드 시스템:** GenServer를 통한 서버 사이드 상태 관리로 보스 체력을 동기화합니다.
- **No Client-side Logic:** 복잡한 JS 프레임워크 없이 Phoenix LiveView만으로 실시간성을 구현했습니다.


## 🛠 기술 스택

- **Backend:** Elixir, Phoenix LiveView (1.7+)
- **Styling:** Tailwind CSS v4.0 (Alpha)
- **Deployment:** Docker, Koyeb
- **Architecture:** OTP (Open Telecom Platform) 기반의 분산 처리


## 🚀 실행 방법 (Local)

로컬 환경에서 실행하려면 Elixir가 설치되어 있어야 합니다.

1.  **레포지토리 클론**

    ```bash
    git clone [https://github.com/jidohyun/cursor-party.git](https://github.com/jidohyun/cursor-party.git)
    cd cursor-party
    ```

2.  **의존성 설치 및 설정**

    ```bash
    mix setup
    ```

3.  **Tailwind v4 설치 (로컬)**

    ```bash
    mix tailwind.install
    ```

4.  **서버 실행**
    ```bash
    mix phx.server
    ```

이제 `localhost:4000`에 접속하면 게임을 실행할 수 있습니다.


## 🤝 기여하기 (Contributing)

버그 제보나 기능 제안은 언제나 환영입니다! Issues 탭을 이용해 주세요.
