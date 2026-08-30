#!/usr/bin/env bash
set -e

# ==========================================
# Mise Development Container Entrypoint
# ==========================================

WORKSPACE="${WORKSPACE_DIR:-/root/workspace}"

if [ -d "$WORKSPACE" ]; then
    cd "$WORKSPACE"
fi

USER_HOME="${HOME:-/root}"

# Ensure PNPM and Cargo environment paths are properly configured
if [ -n "$PNPM_HOME" ]; then
    export PATH="$PNPM_HOME/bin:$PNPM_HOME:$USER_HOME/.cargo/bin:$USER_HOME/.nix-profile/bin:$PATH"
else
    export PATH="$USER_HOME/.cargo/bin:$USER_HOME/.nix-profile/bin:$PATH"
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

# Ensure direnv configuration and workspace whitelist are in place
mkdir -p "$USER_HOME/.config/direnv" "$USER_HOME/.local/share/direnv"
if [ ! -f "$USER_HOME/.config/direnv/direnv.toml" ]; then
    printf '[whitelist]\nprefix = [ "/root/workspace", "%s" ]\n' "$WORKSPACE" > "$USER_HOME/.config/direnv/direnv.toml"
fi
if [ ! -f "$USER_HOME/.config/direnv/direnvrc" ]; then
    printf 'type -P mise &>/dev/null && eval "$(mise direnv activate 2>/dev/null || true)"\n' > "$USER_HOME/.config/direnv/direnvrc"
fi

# Ensure ~/.bashrc hooks mise and direnv for interactive subshells and VS Code terminal sessions
if [ ! -f "$USER_HOME/.bashrc" ] || ! grep -q "mise activate" "$USER_HOME/.bashrc"; then
    echo 'eval "$(mise activate bash)"' >> "$USER_HOME/.bashrc"
fi
if [ ! -f "$USER_HOME/.bashrc" ] || ! grep -q "direnv hook" "$USER_HOME/.bashrc"; then
    echo 'eval "$(direnv hook bash)"' >> "$USER_HOME/.bashrc"
fi

if [ $CONFIG_FOUND -eq 1 ]; then
    echo "[mise-entrypoint] Found workspace mise config ($FOUND_PATH). Initializing environment..."
    mise trust --all 2>/dev/null || true
    echo "[mise-entrypoint] Installing tools via mise..."
    mise install || true
else
    echo "[mise-entrypoint] No workspace-specific mise configuration found in $WORKSPACE."
    echo "[mise-entrypoint] Using global mise configurations (~/.config/mise/conf.d/*.toml)."
    mise trust --all 2>/dev/null || true
fi

# Load mise environment variables into current shell so child processes inherit them
eval "$(mise env -s bash 2>/dev/null || true)"

# Workspace direnv auto-loading: detect .envrc and export environment
DIRENV_CONFIG_FOUND=0
if [ -f ".envrc" ] || [ -f ".envrc.local" ] || compgen -G ".envrc.*" > /dev/null 2>&1; then
    DIRENV_CONFIG_FOUND=1
fi

if [ $DIRENV_CONFIG_FOUND -eq 1 ] && (command -v direnv >/dev/null 2>&1 || mise which direnv >/dev/null 2>&1); then
    echo "[mise-entrypoint] Found workspace direnv configuration (.envrc). Initializing direnv..."
    direnv allow "$WORKSPACE" 2>/dev/null || direnv allow . 2>/dev/null || true
    eval "$(direnv export bash 2>/dev/null || true)"
    echo "[mise-entrypoint] Direnv environment loaded."
fi

# Pre-fetch all Cargo dependencies if Cargo.lock exists and cargo tool is available
if [ -f "Cargo.lock" ] && (command -v cargo >/dev/null 2>&1 || mise which cargo >/dev/null 2>&1); then
    LOCK_HASH_FILE="$USER_HOME/.cargo/.silex_cargo_lock_hash"
    CURRENT_HASH=$(sha256sum Cargo.lock 2>/dev/null | awk '{print $1}')
    SAVED_HASH=$(cat "$LOCK_HASH_FILE" 2>/dev/null || echo "")

    if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" != "$SAVED_HASH" ]; then
        echo "[mise-entrypoint] Cargo.lock change detected."
        echo "[mise-entrypoint] Pre-fetching all Cargo dependencies..."
        cargo fetch --locked 2>/dev/null || mise exec -- cargo fetch --locked 2>/dev/null || true
        mkdir -p "$USER_HOME/.cargo"
        echo "$CURRENT_HASH" > "$LOCK_HASH_FILE"
        echo "[mise-entrypoint] Cargo dependencies synchronized."
    fi
fi

echo "[mise-entrypoint] Mise & Direnv environment ready."

# Hand over execution to the base NixOS container entrypoint
exec /bin/entrypoint.sh "$@"
