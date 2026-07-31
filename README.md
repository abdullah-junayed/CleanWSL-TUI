# 🧹 Clean‑WSL TUI

A **terminal‑based system cleaner** for Ubuntu (including WSL 1/2 and native installations).  
It uses a simple **TUI menu** (with whiptail or dialog) and even works in plain text terminals, helping you reclaim disk space safely.

---

## ✨ Features

- **Interactive TUI** – choose tasks via checkboxes (whiptail / dialog), with a **fallback text menu** if neither is installed.
- **Two modes**:
  - **Recommended** – safe set of everyday cleanup tasks (APT cache, temp files, thumbnails, logs, npm/pip caches, trash, old snaps, Docker prune).
  - **Custom** – full control: enable/disable each of the 14 available tasks.
- **Preview & size estimation** – before cleaning, the script shows what will be deleted and how much space it currently occupies.
- **Space statistics** – disk usage of `/` is displayed **before and after** cleanup.
- **Safe defaults** – dangerous tasks (like emptying all of `~/.cache` or interactive deletion of `node_modules`) require extra confirmation.
- **Cross‑platform** – works on **WSL Ubuntu** (22.04, 24.04, 26.04) and standard **Ubuntu** systems.

---

## 📦 Requirements

- **Operating system**: Ubuntu (or Debian‑based) – tested on Ubuntu 22.04+ and WSL.
- **Bash** >= 4.0 (standard on modern systems).
- **sudo** privileges (most tasks need `sudo`).
- **whiptail** or **dialog** for the graphical TUI (optional – a text‑based fallback is included).
  Install if missing:
  ```bash
  sudo apt update && sudo apt install whiptail
  ```
## 🚀 Installation
1. Download the script:
   ```bash
   curl -O https://your-host/clean-wsl.sh   # or clone the repository
   ```
   (Alternatively, copy the script content into a file named clean-wsl.sh.)
2. Make it executable:
   ```bash
   chmod +x clean-wsl.sh
   ```
3. (Optional) Move it to your PATH for easy access:
   ```bash
   sudo mv clean-wsl.sh /usr/local/bin/clean-wsl
   ```

## 🎮 Usage
Run the script from your terminal:

```bash
./clean-wsl.sh
```
### Main menu
- **Recommended** – automatically selects safe tasks that are currently applicable (e.g., npm cache is skipped if npm isn’t installed).
You’ll still see a confirmation prompt before anything is deleted.
- **Custom** – opens a checklist. Navigate with arrow keys, toggle with SPACE, confirm with ENTER.

## Fallback text menu
If neither whiptail nor dialog is available, a plain‑text interactive menu appears.
Type the numbers of the tasks you want to toggle, then enter 0 to finish.

