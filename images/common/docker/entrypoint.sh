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

# Determine user home directory:
# respect CONTAINER_HOME override or resolve according to TARGET_UID
if [ -n "$CONTAINER_HOME" ]; then
    USER_HOME="$CONTAINER_HOME"
elif [ "$TARGET_UID" -ne 0 ]; then
    USER_HOME="/home/dev"
else
    USER_HOME="${HOME:-/root}"
fi

# Ensure user-specific Cargo, Nix profile, and PNPM paths are dynamically configured
# for the active user
USER_PATHS="$USER_HOME/.cargo/bin:$USER_HOME/.nix-profile/bin"
if [ -n "$PNPM_HOME" ]; then
    USER_PATHS="$PNPM_HOME/bin:$PNPM_HOME:$USER_PATHS"
fi
export PATH="$USER_PATHS:$PATH"

# ==========================================
# Unified AI Credentials & Tool Config Setup
# ==========================================
CODING_CONFIG_DIR="${CODING_CONFIG_DIR:-/data/coding-config}"
DEVBOX_DATA_DIR="${DEVBOX_DATA_DIR:-/data/devbox}"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/data/.cargo/target}"
mkdir -p "$CODING_CONFIG_DIR/claude" \
         "$CODING_CONFIG_DIR/codex" \
         "$CODING_CONFIG_DIR/gemini" \
         "$CODING_CONFIG_DIR/opencode" \
         "$DEVBOX_DATA_DIR"

if [ "$TARGET_UID" -ne 0 ]; then
    chown -R "$TARGET_UID:$TARGET_GID" \
        "$CODING_CONFIG_DIR" "$DEVBOX_DATA_DIR" /etc/mise /data/.cargo 2>/dev/null || true
fi

# Helper function to create symlinks from home directories to unified storage
setup_ai_symlinks() {
    local home_dir="$1"
    local uid="$2"
    local gid="$3"

    [ -z "$home_dir" ] && return 0
    mkdir -p "$home_dir" "$home_dir/.config" "$home_dir/.local" \
             "$home_dir/.cache" "$home_dir/.cargo"
    if [ "$uid" -ne 0 ]; then
        chown "$uid:$gid" "$home_dir" "$home_dir/.config" 2>/dev/null || true
        chown -R "$uid:$gid" \
            "$home_dir/.local" "$home_dir/.cache" "$home_dir/.cargo" 2>/dev/null || true
    fi

    link_ai_path() {
        local target="$1"
        local link="$2"

        # Strictly reject legacy volume mounts (no backward compatibility)
        if mountpoint -q "$link" 2>/dev/null || grep -qs " $link " /proc/mounts; then
            echo "[mise-entrypoint] FATAL: Volume mount detected at '$link'!" >&2
            echo "[mise-entrypoint] Independent AI mounts" \
                 "(codex-config, gemini-config, opencode-config, claude-config)" \
                 "are strictly unsupported." >&2
            echo "[mise-entrypoint] Please use unified volume:" \
                 "coding-config:/data/coding-config" >&2
            exit 1
        fi

        # Remove non-symlink path and strictly enforce symlink to unified storage
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
elif [ -d ".config/mise/conf.d" ] && \
     compgen -G ".config/mise/conf.d/*.toml" > /dev/null 2>&1; then
    FOUND_PATH=".config/mise/conf.d/*.toml"
fi

if [ -n "$FOUND_PATH" ]; then
    CONFIG_FOUND=1
fi

if [ $CONFIG_FOUND -eq 1 ]; then
    echo "[mise-entrypoint] Found workspace mise config ($FOUND_PATH)." \
         "Initializing environment..."
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

# ==========================================
# Devbox Workspace Auto-Init & Auto-Loading
# ==========================================
if command -v devbox >/dev/null 2>&1 || mise which devbox >/dev/null 2>&1; then
    # Load global devbox environment if global configuration exists
    if [ -f "$DEVBOX_DATA_DIR/global/default/devbox.json" ]; then
        # Ensure hook script exists so devbox shellenv --init-hook does not fail on missing file
        mkdir -p "$DEVBOX_DATA_DIR/global/default/.devbox/gen/scripts" 2>/dev/null || true
        [ -f "$DEVBOX_DATA_DIR/global/default/.devbox/gen/scripts/.hooks.sh" ] || \
            touch "$DEVBOX_DATA_DIR/global/default/.devbox/gen/scripts/.hooks.sh" 2>/dev/null || true
        if [ "$TARGET_UID" -ne 0 ]; then
            chown -R "$TARGET_UID:$TARGET_GID" "$DEVBOX_DATA_DIR/global/default/.devbox" 2>/dev/null || true
        fi
        DEVBOX_GLOBAL_ENV="$(devbox global shellenv --init-hook 2>/dev/null || devbox global shellenv 2>/dev/null || true)"
        if [ -n "$DEVBOX_GLOBAL_ENV" ]; then
            eval "$DEVBOX_GLOBAL_ENV" 2>/dev/null || true
        fi
    fi

    DEVBOX_CONFIG_FOUND=0
    if [ -f "devbox.json" ]; then
        DEVBOX_CONFIG_FOUND=1
    elif [ "${DEVBOX_AUTO_INIT:-0}" = "1" ] || [ "${DEVBOX_AUTO_INIT,,}" = "true" ]; then
        echo "[mise-entrypoint] DEVBOX_AUTO_INIT is enabled. Initializing devbox project in $WORKSPACE..."
        devbox init || true
        if [ -f "devbox.json" ]; then
            DEVBOX_CONFIG_FOUND=1
            if [ "$TARGET_UID" -ne 0 ] && [ "${CHOWN_WORKSPACE:-0}" = "1" ]; then
                chown "$TARGET_UID:$TARGET_GID" devbox.json 2>/dev/null || true
            fi
        fi
    fi

    if [ $DEVBOX_CONFIG_FOUND -eq 1 ]; then
        echo "[mise-entrypoint] Found workspace devbox configuration (devbox.json)." \
             "Initializing devbox environment..."
        echo "[mise-entrypoint] Installing tools via devbox..."
        devbox install || true
        mkdir -p .devbox/gen/scripts 2>/dev/null || true
        [ -f .devbox/gen/scripts/.hooks.sh ] || touch .devbox/gen/scripts/.hooks.sh 2>/dev/null || true
        DEVBOX_WORKSPACE_ENV="$(devbox shellenv --init-hook 2>/dev/null || devbox shellenv 2>/dev/null || true)"
        if [ -n "$DEVBOX_WORKSPACE_ENV" ]; then
            eval "$DEVBOX_WORKSPACE_ENV" 2>/dev/null || true
        fi
        if [ "$TARGET_UID" -ne 0 ] && [ -d ".devbox" ] && [ "${CHOWN_WORKSPACE:-0}" = "1" ]; then
            chown -R "$TARGET_UID:$TARGET_GID" .devbox 2>/dev/null || true
        fi
        echo "[mise-entrypoint] Devbox environment loaded."
    fi
fi

# ==========================================
# Sccache (Compiler Cache) Setup
# ==========================================
# Allow disabling sccache explicitly via environment variables:
# e.g., SCCACHE_DISABLE=1/true, ENABLE_SCCACHE=0/false, USE_SCCACHE=0/false,
# NO_SCCACHE=1, DISABLE_SCCACHE=1, or RUSTC_WRAPPER=""/none/off/0
SCCACHE_IS_DISABLED=0

if [ "${SCCACHE_DISABLE:-}" = "1" ] || [ "${SCCACHE_DISABLE,,}" = "true" ]; then
    SCCACHE_IS_DISABLED=1
elif [ -n "${ENABLE_SCCACHE+x}" ] && \
     { [ "$ENABLE_SCCACHE" = "0" ] || [ "${ENABLE_SCCACHE,,}" = "false" ] || \
       [ "${ENABLE_SCCACHE,,}" = "no" ] || [ "${ENABLE_SCCACHE,,}" = "off" ]; }; then
    SCCACHE_IS_DISABLED=1
elif [ -n "${USE_SCCACHE+x}" ] && \
     { [ "$USE_SCCACHE" = "0" ] || [ "${USE_SCCACHE,,}" = "false" ] || \
       [ "${USE_SCCACHE,,}" = "no" ] || [ "${USE_SCCACHE,,}" = "off" ]; }; then
    SCCACHE_IS_DISABLED=1
elif [ "${NO_SCCACHE:-}" = "1" ] || [ "${NO_SCCACHE,,}" = "true" ] || \
     [ "${DISABLE_SCCACHE:-}" = "1" ] || [ "${DISABLE_SCCACHE,,}" = "true" ]; then
    SCCACHE_IS_DISABLED=1
elif [ -n "${RUSTC_WRAPPER+x}" ] && \
     { [ -z "$RUSTC_WRAPPER" ] || [ "$RUSTC_WRAPPER" = "none" ] || \
       [ "$RUSTC_WRAPPER" = "off" ] || [ "$RUSTC_WRAPPER" = "0" ]; }; then
    SCCACHE_IS_DISABLED=1
fi

if [ "$SCCACHE_IS_DISABLED" -eq 1 ]; then
    echo "[mise-entrypoint] Sccache is explicitly disabled via environment variable."
    unset RUSTC_WRAPPER
    export SCCACHE_DISABLE=1
    # Fallback to incremental compilation when sccache is disabled
    if [ "${CARGO_INCREMENTAL:-}" = "0" ]; then
        export CARGO_INCREMENTAL=1
    fi
else
    # Enable sccache by default when sccache or rust environment is detected
    if command -v sccache >/dev/null 2>&1 || \
       mise which sccache >/dev/null 2>&1 || \
       [ -f "/etc/mise/conf.d/20-rust.toml" ] || \
       [ "${RUSTC_WRAPPER:-}" = "sccache" ]; then
        export RUSTC_WRAPPER="${RUSTC_WRAPPER:-sccache}"
        export SCCACHE_DIR="${SCCACHE_DIR:-/data/sccache}"
        export SCCACHE_IGNORE_SERVER_IO_ERROR="${SCCACHE_IGNORE_SERVER_IO_ERROR:-1}"
        # Incremental compilation must be disabled for sccache caching to work effectively
        if [ -z "${CARGO_INCREMENTAL:-}" ] || [ "$CARGO_INCREMENTAL" = "1" ]; then
            export CARGO_INCREMENTAL=0
        fi

        # Ensure sccache storage directory exists with proper permissions
        mkdir -p "$SCCACHE_DIR" 2>/dev/null || true
        if [ "$TARGET_UID" -ne 0 ]; then
            CURRENT_OWNER=$(stat -c '%u' "$SCCACHE_DIR" 2>/dev/null || echo "")
            if [ "$CURRENT_OWNER" != "$TARGET_UID" ]; then
                chown -R "$TARGET_UID:$TARGET_GID" "$SCCACHE_DIR" 2>/dev/null || true
            fi
        fi
        echo "[mise-entrypoint] Sccache compiler cache enabled" \
             "(SCCACHE_DIR=$SCCACHE_DIR, RUSTC_WRAPPER=$RUSTC_WRAPPER)."
    fi
fi

echo "[mise-entrypoint] Mise & Devbox environment ready."

# Hand over execution to the base NixOS container entrypoint
exec /bin/entrypoint.sh "$@"
