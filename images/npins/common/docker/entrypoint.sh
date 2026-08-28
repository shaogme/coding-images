#!/usr/bin/env bash
set -e

# ==========================================
# Mise Development Container Entrypoint
# ==========================================

WORKSPACE="${WORKSPACE_DIR:-/root/workspace}"

if [ -d "$WORKSPACE" ]; then
    cd "$WORKSPACE"
fi

# Candidate workspace configuration files in order of precedence:
# 1. mise.local.toml / mise.<env>.local.toml (and .mise.*.local.toml)
# 2. mise.toml / mise.<env>.toml (and .mise.*.toml)
# 3. mise/config.toml
# 4. mise/conf.d/*.toml
# 5. .mise/config.toml
# 6. .mise/conf.d/*.toml
# 7. .config/mise.toml
# 8. .config/mise/config.toml
# 9. .config/mise/conf.d/*.toml

CONFIG_FOUND=0
FOUND_PATH=""

# 1. mise.local.toml / mise.<env>.local.toml (and .mise.*.local.toml)
if [ -n "$MISE_ENV" ] && [ -f "mise.${MISE_ENV}.local.toml" ]; then
    FOUND_PATH="mise.${MISE_ENV}.local.toml"
elif [ -n "$MISE_ENV" ] && [ -f ".mise.${MISE_ENV}.local.toml" ]; then
    FOUND_PATH=".mise.${MISE_ENV}.local.toml"
elif [ -f "mise.local.toml" ]; then
    FOUND_PATH="mise.local.toml"
elif [ -f ".mise.local.toml" ]; then
    FOUND_PATH=".mise.local.toml"
elif compgen -G "mise.*.local.toml" > /dev/null 2>&1; then
    FOUND_PATH=$(compgen -G "mise.*.local.toml" | sort | head -n 1)
elif compgen -G ".mise.*.local.toml" > /dev/null 2>&1; then
    FOUND_PATH=$(compgen -G ".mise.*.local.toml" | sort | head -n 1)

# 2. mise.toml / mise.<env>.toml (and .mise.*.toml)
elif [ -n "$MISE_ENV" ] && [ -f "mise.${MISE_ENV}.toml" ]; then
    FOUND_PATH="mise.${MISE_ENV}.toml"
elif [ -n "$MISE_ENV" ] && [ -f ".mise.${MISE_ENV}.toml" ]; then
    FOUND_PATH=".mise.${MISE_ENV}.toml"
elif [ -f "mise.toml" ]; then
    FOUND_PATH="mise.toml"
elif [ -f ".mise.toml" ]; then
    FOUND_PATH=".mise.toml"
elif compgen -G "mise.*.toml" > /dev/null 2>&1; then
    FOUND_PATH=$(compgen -G "mise.*.toml" | sort | head -n 1)
elif compgen -G ".mise.*.toml" > /dev/null 2>&1; then
    FOUND_PATH=$(compgen -G ".mise.*.toml" | sort | head -n 1)

# 3. mise/config.toml
elif [ -f "mise/config.toml" ]; then
    FOUND_PATH="mise/config.toml"

# 4. mise/conf.d/*.toml
elif [ -d "mise/conf.d" ] && compgen -G "mise/conf.d/*.toml" > /dev/null 2>&1; then
    FOUND_PATH="mise/conf.d/*.toml"

# 5. .mise/config.toml
elif [ -f ".mise/config.toml" ]; then
    FOUND_PATH=".mise/config.toml"

# 6. .mise/conf.d/*.toml
elif [ -d ".mise/conf.d" ] && compgen -G ".mise/conf.d/*.toml" > /dev/null 2>&1; then
    FOUND_PATH=".mise/conf.d/*.toml"

# 7. .config/mise.toml
elif [ -f ".config/mise.toml" ]; then
    FOUND_PATH=".config/mise.toml"

# 8. .config/mise/config.toml
elif [ -f ".config/mise/config.toml" ]; then
    FOUND_PATH=".config/mise/config.toml"

# 9. .config/mise/conf.d/*.toml
elif [ -d ".config/mise/conf.d" ] && compgen -G ".config/mise/conf.d/*.toml" > /dev/null 2>&1; then
    FOUND_PATH=".config/mise/conf.d/*.toml"
fi

if [ -n "$FOUND_PATH" ]; then
    CONFIG_FOUND=1
fi

export MISE_YES=1

# Ensure ~/.bashrc hooks mise for interactive subshells and VS Code terminal sessions
if [ ! -f /root/.bashrc ] || ! grep -q "mise activate" /root/.bashrc; then
    echo 'eval "$(mise activate bash)"' >> /root/.bashrc
fi

if [ $CONFIG_FOUND -eq 1 ]; then
    echo "[mise-entrypoint] Found workspace mise config ($FOUND_PATH). Initializing environment..."
    mise trust --all 2>/dev/null || true
    echo "[mise-entrypoint] Installing tools via mise..."
    mise install || true
else
    echo "[mise-entrypoint] No workspace-specific mise configuration found in $WORKSPACE."
    echo "[mise-entrypoint] Using global mise configuration (~/.config/mise/config.toml)."
fi

# Load mise environment variables into current shell so child processes inherit them
eval "$(mise env -s bash 2>/dev/null || true)"

echo "[mise-entrypoint] Mise environment ready."

# Hand over execution to the base NixOS container entrypoint
exec /bin/entrypoint.sh "$@"
