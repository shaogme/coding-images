#!/usr/bin/env bash
set -e

# ==========================================
# Mise Development Container Entrypoint
# ==========================================

WORKSPACE="${WORKSPACE:-${WORKSPACE_DIR:-/workspace}}"

if [ -d "$WORKSPACE" ]; then
    cd "$WORKSPACE"
fi

# ==========================================
# Adaptive UID/GID & Home Resolution
# ==========================================
TARGET_UID=""
TARGET_GID=""

# 1. Parse from HOST_UID / HOST_GID environment variables
if [ -n "$HOST_UID" ]; then
    if [[ "$HOST_UID" == *:* ]]; then
        TARGET_UID="${HOST_UID%%:*}"
        TARGET_GID="${HOST_UID##*:}"
    else
        TARGET_UID="$HOST_UID"
        TARGET_GID="${HOST_GID:-$HOST_UID}"
    fi
elif [ -n "$HOST_GID" ]; then
    TARGET_GID="$HOST_GID"
fi

# 2. Runtime user mapping probe from workspace directory if not explicitly set
if [ -z "$TARGET_UID" ] && [ "$RUN_AS_ROOT" != "1" ] && [ -d "$WORKSPACE" ]; then
    PROBED_UID=$(stat -c '%u' "$WORKSPACE" 2>/dev/null || echo 0)
    PROBED_GID=$(stat -c '%g' "$WORKSPACE" 2>/dev/null || echo 0)
    if [ "$PROBED_UID" -gt 0 ] 2>/dev/null; then
        TARGET_UID="$PROBED_UID"
        TARGET_GID="${TARGET_GID:-$PROBED_GID}"
    fi
fi

TARGET_UID="${TARGET_UID:-0}"
TARGET_GID="${TARGET_GID:-$TARGET_UID}"

# Determine user home directory: respect CONTAINER_HOME override or resolve according to TARGET_UID
if [ -n "$CONTAINER_HOME" ]; then
    USER_HOME="$CONTAINER_HOME"
elif [ "$TARGET_UID" -ne 0 ]; then
    USER_HOME="/home/dev"
else
    USER_HOME="${HOME:-/root}"
fi

# Ensure user-specific Cargo, Nix profile, and PNPM paths are dynamically configured for the active user
export NIX_PROFILE="${NIX_PROFILE:-/nix/var/nix/profiles/default}"
USER_PATHS="$USER_HOME/.cargo/bin:$USER_HOME/.nix-profile/bin"
if [ -n "$PNPM_HOME" ]; then
    USER_PATHS="$PNPM_HOME/bin:$PNPM_HOME:$USER_PATHS"
fi
export PATH="$USER_PATHS:$PATH"

# Dynamically configure Cargo target directory based on active USER_HOME
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$USER_HOME/.cargo/target}"

# ==========================================
# Unified AI Credentials & Tool Config Setup
# ==========================================
CODING_CONFIG_DIR="${CODING_CONFIG_DIR:-/data/coding-config}"
mkdir -p "$CODING_CONFIG_DIR/claude" \
         "$CODING_CONFIG_DIR/codex" \
         "$CODING_CONFIG_DIR/gemini" \
         "$CODING_CONFIG_DIR/opencode"

if [ "$TARGET_UID" -ne 0 ]; then
    chown -R "$TARGET_UID:$TARGET_GID" "$CODING_CONFIG_DIR" 2>/dev/null || true
fi

# Helper function to create symlinks from home directories to unified storage
setup_ai_symlinks() {
    local home_dir="$1"
    local uid="$2"
    local gid="$3"

    [ -z "$home_dir" ] && return 0
    mkdir -p "$home_dir" "$home_dir/.config"
    if [ "$uid" -ne 0 ]; then
        chown "$uid:$gid" "$home_dir" "$home_dir/.config" 2>/dev/null || true
    fi

    link_ai_path() {
        local target="$1"
        local link="$2"

        # Strictly reject legacy volume mounts (no backward compatibility)
        if mountpoint -q "$link" 2>/dev/null || grep -qs " $link " /proc/mounts; then
            echo "[mise-entrypoint] FATAL: Volume mount detected at '$link'!" >&2
            echo "[mise-entrypoint] Independent AI mounts (codex-config, gemini-config, opencode-config, claude-config) are strictly unsupported." >&2
            echo "[mise-entrypoint] Please use unified volume: coding-config:/data/coding-config" >&2
            exit 1
        fi

        # Remove any non-symlink directory or file and strictly enforce symlink to unified storage
        if [ -e "$link" ] && [ ! -L "$link" ]; then
            rm -rf "$link"
        fi

        if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$target" ]; then
            rm -f "$link" 2>/dev/null || true
            ln -sfn "$target" "$link"
        fi

        if [ "$uid" -ne 0 ]; then
            chown -h "$uid:$gid" "$link" 2>/dev/null || true
        fi
    }

    link_ai_path "$CODING_CONFIG_DIR/claude" "$home_dir/.claude"
    link_ai_path "$CODING_CONFIG_DIR/codex" "$home_dir/.codex"
    link_ai_path "$CODING_CONFIG_DIR/gemini" "$home_dir/.gemini"
    link_ai_path "$CODING_CONFIG_DIR/opencode" "$home_dir/.config/opencode"
}

# Link for current resolved USER_HOME
setup_ai_symlinks "$USER_HOME" "$TARGET_UID" "$TARGET_GID"

# Also ensure /root and /home/dev have links configured if they exist
if [ "$USER_HOME" != "/root" ] && [ -d "/root" ]; then
    setup_ai_symlinks "/root" 0 0
fi
if [ "$USER_HOME" != "/home/dev" ] && [ -d "/home/dev" ]; then
    setup_ai_symlinks "/home/dev" "$TARGET_UID" "$TARGET_GID"
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

# Ensure system-wide direnv configuration and workspace whitelist are in place
if [ -w /etc/xdg/direnv ] || [ -w /etc/xdg/direnv/direnv.toml 2>/dev/null ]; then
    if [ ! -f /etc/xdg/direnv/direnv.toml ] || ! grep -q "\"$WORKSPACE\"" /etc/xdg/direnv/direnv.toml 2>/dev/null; then
        if [ "$WORKSPACE" = "/workspace" ]; then
            printf '[whitelist]\nprefix = [ "/workspace" ]\n' > /etc/xdg/direnv/direnv.toml 2>/dev/null || true
        else
            printf '[whitelist]\nprefix = [ "/workspace", "%s" ]\n' "$WORKSPACE" > /etc/xdg/direnv/direnv.toml 2>/dev/null || true
        fi
    fi
    if [ ! -f /etc/xdg/direnv/direnvrc ]; then
        printf 'type -P mise &>/dev/null && eval "$(mise direnv activate 2>/dev/null || true)"\n' > /etc/xdg/direnv/direnvrc 2>/dev/null || true
    fi
fi

if [ $CONFIG_FOUND -eq 1 ]; then
    echo "[mise-entrypoint] Found workspace mise config ($FOUND_PATH). Initializing environment..."
    mise trust --all 2>/dev/null || true
    echo "[mise-entrypoint] Installing tools via mise..."
    mise install || true
else
    echo "[mise-entrypoint] No workspace-specific mise configuration found in $WORKSPACE."
    echo "[mise-entrypoint] Using global mise configurations (/etc/mise/conf.d/*.toml)."
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

echo "[mise-entrypoint] Mise & Direnv environment ready."

# Hand over execution to the base NixOS container entrypoint
exec /bin/entrypoint.sh "$@"
