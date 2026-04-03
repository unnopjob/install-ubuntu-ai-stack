# Ubuntu AI Stack Installer

This folder contains one script that installs and configures:

- Ollama
- `gemma2:9b`
- Node.js
- Flowise
- PM2 startup for Flowise on boot/reboot
- Optional swap file
- Optional PM2 log rotation
- Desktop and app-menu launchers for Flowise and the installer

## Run

```bash
chmod +x install-ubuntu-ai-stack.sh
./install-ubuntu-ai-stack.sh
```

When you run it in a terminal, long steps show a live spinner automatically and the installer tags phases as `[1/8]`, `[2/8]`, and so on.

You can also use the extra modes:

```bash
./install-ubuntu-ai-stack.sh --status
./install-ubuntu-ai-stack.sh --open-flowise
```

## Optional overrides

You can tweak the install with environment variables:

```bash
OLLAMA_MODEL=gemma2:9b FLOWISE_PORT=3000 NODE_MAJOR=24 ./install-ubuntu-ai-stack.sh
```

If you want to skip the short `gemma2:9b` smoke test after download:

```bash
RUN_MODEL_SMOKE_TEST=0 ./install-ubuntu-ai-stack.sh
```

To enable swap creation and PM2 log rotation:

```bash
ENABLE_SWAP=1 SWAP_SIZE_GB=8 ENABLE_PM2_LOGROTATE=1 ./install-ubuntu-ai-stack.sh
```

If you do not want the installer to create desktop/app-menu launchers:

```bash
CREATE_DESKTOP_LAUNCHER=0 ./install-ubuntu-ai-stack.sh
```

If you want to disable the live spinner output:

```bash
SPINNER_ENABLED=0 ./install-ubuntu-ai-stack.sh
```

## After install

- Flowise opens at `http://localhost:3000`
- Ollama API is at `http://localhost:11434`
- PM2 will restore Flowise automatically after reboot
- The installer creates `~/.local/bin/open-flowise`
- The installer creates `~/.local/bin/install-ai-stack`
- The installer adds `.desktop` files for both launchers when a desktop is available

## Notes

- The script is written for Ubuntu or other Debian-based Linux systems that use `systemd`.
- `gemma2:9b` is a fairly large model, so make sure the machine has enough RAM and disk space.
- If you want to expose Flowise beyond `localhost`, add a reverse proxy and authentication first.
