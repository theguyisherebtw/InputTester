# Input Tester

A lightweight **bench diagnostic tool for keyboards, mice, and controllers** on Windows — made for repair work. Plug in a device, press every key / button, and see exactly what registers. It catches the faults that matter when you fix hardware:

- **Key chatter** — one press registering twice (switch bounce)
- **Stuck keys** — a key that stays down
- **Mouse double-click fault** — a single click firing twice from a worn switch
- **Controller stick drift** — a stick that doesn't rest at center

No installation. One file. Just double-click.

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%2F%2011-0078D6)
![License](https://img.shields.io/badge/license-MIT-green)
![Install](https://img.shields.io/badge/install-none-brightgreen)
![Open%20Source](https://img.shields.io/badge/open%20source-yes-blueviolet)

---

## Features

### ⌨️ Keyboard
- On-screen keyboard layout; **every key lights green the first time it registers**, so you can confirm each one works.
- A key **stuck down stays bright** — instantly visible.
- **Chatter detection:** if a key re-fires within 50 ms of release, it flashes **red** and is logged — the classic sign of a bad/bouncing switch.
- Live timestamped log of every key down/up (numpad and extra keys included).
- Counters for keys seen, chatter events, and keys currently held.

### 🖱️ Mouse
- Live indicators and click counts for **Left, Right, Middle, and both side buttons (X1/X2)**.
- **Scroll** up/down counters and live **cursor position**.
- **Double-click / chatter flag:** a single click that fires twice (gap under ~35 ms) is counted — the most common worn-mouse fault.

### 🎮 Controller (XInput)
- All buttons, D-pad, bumpers, and thumbstick clicks light up.
- **Triggers** shown as 0–255 bars.
- **Sticks** shown as a live dot plus raw values. At rest the values should sit near 0 — a large standing value (shown **red**) means **stick drift**.

---

## Is it safe? Does it contain a virus?

**No — and because it is open source, you don't have to take my word for it. Every line it runs is in this repository.** Read it yourself.

Specifically, this tool:

- **Only reads input while its own window is focused.** It does **not** install a global/system-wide keyboard hook, so it physically cannot see what you type in other apps. This is the key difference between a bench tester and a keylogger.
- **Never writes anything to disk.** Nothing is logged to a file, ever.
- **Never makes a network connection.** Nothing is uploaded, sent, or "phoned home."
- Uses only **standard, documented Windows APIs** — WinForms for the window and XInput for controllers.
- Has **no installer, no background service, no autostart, and no persistence.** Close the window and it is completely gone.

### "Windows SmartScreen / my antivirus warned about it"

That's an expected **false positive**, not a real detection. Heuristic scanners often warn about *any* `.bat` file that launches PowerShell, regardless of what it does, and because this tool isn't code-signed (certificates cost money) Windows can't verify the publisher. You can:

1. **Read the source** — it's short and commented.
2. Click **More info → Run anyway** on the SmartScreen prompt.
3. Or right-click the file → **Properties → Unblock** if it was downloaded.

If you still aren't comfortable, run it on a spare/test machine first. The source is fully auditable — that's the whole point of open source.

---

## How to run

1. Download **`InputTester.bat`**.
2. Double-click it.
3. The window opens with three tabs: **Keyboard**, **Mouse**, **Controller**. Click into a tab and start testing.

No install, no dependencies — it uses Windows PowerShell 5.1, which ships with Windows 10 and 11.

> **Tip:** The tool captures input only while **its own window is focused**. Click inside it before testing a device.

---

## How it works

`InputTester.bat` is a batch + PowerShell "polyglot": the batch part launches PowerShell, which reads the rest of the file and builds a small WinForms app. Keyboard capture is done with a focused, window-level message handler (`WM_KEYDOWN` / `WM_KEYUP`) — so it reads precise key codes (including left/right modifiers and auto-repeat) **only while the window has focus**. Controllers are polled through `XInput`.

Everything is in the single `.bat` file. There is nothing else to trust.

---

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (built in — nothing to install)
- For the Controller tab: an **XInput** (Xbox-style) controller. PlayStation / generic pads need an XInput wrapper such as DS4Windows to appear.

## Known limitations

- Captures input only while focused (by design).
- Pressing the **Windows key** may still open the Start menu (the shell grabs it system-wide), though the test still logs the press.
- Media / Fn-layer keys handled entirely in the keyboard's hardware may not send a standard code.

---

## Author

Made by **Tamim**
- GitHub: [@tamimmadrasa989-art](https://github.com/tamimmadrasa989-art)
- Snapchat: **tamim4561**

Issues, ideas, and pull requests are welcome.

## License

Released under the **MIT License** — free to use, modify, and share. See [LICENSE](LICENSE).

Copyright (c) 2026 Tamim.
