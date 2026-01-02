# 🖱️ Cursor Party

[![Elixir](https://img.shields.io/badge/Elixir-4B275F?style=for-the-badge&logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white)](https://www.phoenixframework.org/)
[![Tailwind CSS v4](https://img.shields.io/badge/Tailwind_v4-38B2AC?style=for-the-badge&logo=tailwind-css&logoColor=white)](https://tailwindcss.com/)
[![Koyeb](https://img.shields.io/badge/Koyeb-121212?style=for-the-badge&logo=koyeb&logoColor=white)](https://www.koyeb.com/)

> **"Can I build a real-time MMO game in just 1 hour?"**
> A project to experiment with the distributed processing capabilities of Elixir and Phoenix LiveView.

[🇰🇷 Read in Korean](./README.ko.md)

---

## 🎮 Play Demo

👉 **[Live Demo](https://cursor-party.koyeb.app)**
_(Currently in Open Beta. The server is always open, so come join the raid!)_

---

## 📸 Screenshots

![Game Screenshot](https://via.placeholder.com/800x400?text=Gameplay+Screenshot+PlaceHolder)

---

## 💡 Introduction

**Cursor Party** is a massive multiplayer browser game where every user's cursor is visible in real-time, and players cooperate to defeat a boss monster.

Inspired by how **Discord** handles millions of concurrent users using **Elixir**, I started this "1-Hour Challenge" to verify if I could handle real-time synchronization purely with server-side logic.

### ✨ Key Features

- **Real-time Cursor Tracking:** Share cursor positions with all connected users via WebSockets with near-zero latency.
- **Boss Raid System:** Synchronized Boss HP managed by Server-side state (GenServer).
- **No Client-side Logic:** All real-time logic is handled by Phoenix LiveView, without complex JavaScript frameworks.

---

## 🛠 Tech Stack

- **Backend:** Elixir, Phoenix LiveView (1.7+)
- **Styling:** Tailwind CSS v4.0 (Alpha)
- **Deployment:** Docker, Koyeb
- **Architecture:** OTP (Open Telecom Platform) based distributed system

---

## 🚀 How to Run (Local)

Prerequisites: Elixir and Erlang must be installed.

1.  **Clone the repository**

    ```bash
    git clone [https://github.com/jidohyun/cursor-party.git](https://github.com/jidohyun/cursor-party.git)
    cd cursor-party
    ```

2.  **Install dependencies**

    ```bash
    mix setup
    ```

3.  **Install Tailwind v4 (Local)**

    ```bash
    mix tailwind.install
    ```

4.  **Start the server**
    ```bash
    mix phx.server
    ```

Now you can visit `localhost:4000` from your browser.

---

## 🤝 Contributing

Bug reports and pull requests are welcome on GitHub at this repository. This project is intended to be a safe, welcoming space for collaboration.
