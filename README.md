# Linux AI Stack Installer

`Linux AI Stack Installer` is a Bash installer for Ubuntu/Debian and Fedora/RedHat-family Linux that sets up:

- Ollama
- `gemma2:9b`
- Node.js
- Flowise
- PM2 startup for Flowise on boot/login
- Optional swap file on Linux
- Optional PM2 log rotation
- Desktop or launcher shortcuts for Flowise and the installer

## Supported Platforms

- Ubuntu and Debian-based Linux
- Fedora, RHEL, Rocky, AlmaLinux, and similar RedHat-family Linux

## Files

- `install.sh` is the canonical installer
- `install-ubuntu-ai-stack.sh` is a compatibility wrapper that points to `install.sh`

## Quick Start

### Run from a local copy

```bash
chmod +x install.sh
./install.sh
```

### Run directly from GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/unnopjob/Linux-AI-Stack-Installer/main/install.sh | bash -s --
```

The direct GitHub form also supports arguments:

```bash
curl -fsSL https://raw.githubusercontent.com/unnopjob/Linux-AI-Stack-Installer/main/install.sh | bash -s -- --status
curl -fsSL https://raw.githubusercontent.com/unnopjob/Linux-AI-Stack-Installer/main/install.sh | bash -s -- --open-flowise
```

When you run it in a terminal, long steps show a live spinner automatically and the installer shows a filling progress bar for the install phases.

## Extra Commands

```bash
./install.sh --status
./install.sh --open-flowise
```

## Optional Overrides

You can tweak the install with environment variables:

```bash
OLLAMA_MODEL=gemma2:9b FLOWISE_PORT=3000 NODE_MAJOR=22 ./install.sh
```

If you want to skip the short `gemma2:9b` smoke test after download:

```bash
RUN_MODEL_SMOKE_TEST=0 ./install.sh
```

To enable swap creation and PM2 log rotation on Linux:

```bash
ENABLE_SWAP=1 SWAP_SIZE_GB=8 ENABLE_PM2_LOGROTATE=1 ./install.sh
```

If you do not want the installer to create launcher shortcuts:

```bash
CREATE_DESKTOP_LAUNCHER=0 ./install.sh
```

If you want to disable the live spinner output:

```bash
SPINNER_ENABLED=0 ./install.sh
```

If you want to change the width of the progress bar:

```bash
INSTALL_PROGRESS_BAR_WIDTH=30 ./install.sh
```

If you mirror the script somewhere else, override the raw URL:

```bash
INSTALLER_URL=https://raw.githubusercontent.com/<user>/<repo>/main/install.sh ./install.sh
```

## What the Installer Does

- On Linux, it uses the distro package manager to install prerequisites, installs Node.js from NodeSource, starts Ollama with systemd, and registers PM2 startup
- It pulls `gemma2:9b` by default after Ollama is ready
- It creates local launchers so you can reopen Flowise or rerun the installer quickly

## After Install

- Flowise opens at `http://localhost:3000`
- Ollama API is at `http://localhost:11434`
- PM2 restores Flowise automatically after restart or login
- Linux launchers are created under `~/.local/share/applications` and copied to the Desktop when available

## Notes

- `gemma2:9b` is a fairly large model, so make sure the machine has enough RAM and disk space
- This installer is Linux-only and expects a `systemd`-based distro
- If you want to expose Flowise beyond `localhost`, add a reverse proxy and authentication first
