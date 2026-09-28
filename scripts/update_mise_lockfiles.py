#!/usr/bin/env python3
"""Regenerate committed mise locks for every mise image lineage."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

try:
    from .discover_images import discover_images
except ImportError:  # Running the file directly from the scripts directory.
    from discover_images import discover_images


PLATFORMS = "linux-x64,linux-arm64"


def _config_name(config_path: Path, images_dir: Path) -> str:
    """Return a stable conf.d filename stem for a repository config."""
    relative = config_path.parent.relative_to(images_dir)
    return "-".join(part for part in relative.parts if part != ".config")


def _lineage_images(repo_root: Path) -> list[dict]:
    images = discover_images(str(repo_root / "images"))
    result = []
    for image in images:
        if isinstance(image["mise_config_lineage"], str):
            image["mise_config_lineage"] = json.loads(image["mise_config_lineage"])
        if (
            image["builder_mode"] == "mise"
            and image["mise_config_lineage"]
            and (repo_root / image["context"] / ".config/mise.toml").is_file()
        ):
            result.append(image)
    return result


def _generate_lock(
    *,
    repo_root: Path,
    image: dict,
    staging_dir: Path,
) -> Path:
    image_name = image["image_name"]
    system_dir = staging_dir / "system" / image_name
    conf_dir = system_dir / "conf.d"
    global_dir = staging_dir / "global"
    global_root = global_dir / image_name
    global_file = global_dir / f"{image_name}.toml"
    conf_dir.mkdir(parents=True)
    global_root.mkdir(parents=True)
    # A syntactically valid empty config avoids nested provider processes
    # treating the explicitly selected global file as missing.
    global_file.write_text("[tools]\n", encoding="utf-8")

    images_dir = repo_root / "images"
    for index, relative_config in enumerate(image["mise_config_lineage"], start=1):
        source = repo_root / relative_config
        if not source.is_file():
            raise FileNotFoundError(f"missing mise config: {relative_config}")
        link_name = f"{index * 10:02d}-{_config_name(source, images_dir)}.toml"
        (conf_dir / link_name).symlink_to(source)

    environment = os.environ.copy()
    environment.update(
        {
            "MISE_SYSTEM_CONFIG_DIR": str(system_dir),
            "MISE_CONFIG_DIR": str(system_dir),
            "MISE_GLOBAL_CONFIG_FILE": str(global_file),
            "MISE_GLOBAL_CONFIG_ROOT": str(global_root),
            "MISE_TRUSTED_CONFIG_PATHS": str(images_dir),
            "MISE_LOCKED": "0",
            "MISE_YES": "1",
        }
    )
    subprocess.run(
        [
            "mise",
            "lock",
            "--global",
            "--bump",
            "--platform",
            PLATFORMS,
        ],
        cwd=repo_root,
        env=environment,
        check=True,
    )
    lockfile = system_dir / "mise.lock"
    if not lockfile.is_file() or lockfile.stat().st_size == 0:
        raise RuntimeError(f"mise did not produce a lockfile for {image_name}")
    return lockfile


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    runner_temp = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir()))
    runner_temp.mkdir(parents=True, exist_ok=True)
    lineage_images = _lineage_images(repo_root)
    if not lineage_images:
        raise RuntimeError("no mise image lineages found")

    with tempfile.TemporaryDirectory(prefix="mise-lock-update-", dir=runner_temp) as temporary:
        staging_dir = Path(temporary)
        generated: list[tuple[Path, Path, Path]] = []
        for image in lineage_images:
            destination_config = repo_root / image["context"] / ".config"
            source = _generate_lock(repo_root=repo_root, image=image, staging_dir=staging_dir)
            generated.append((destination_config / "mise.lock", destination_config / ".mise", source))

        # Publish only after every lineage resolved successfully. A network or
        # provider failure therefore leaves all previously committed locks intact.
        for destination, sidecar_destination, source in generated:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            sidecar_source = source.parent / ".mise"
            if sidecar_destination.exists():
                shutil.rmtree(sidecar_destination)
            if sidecar_source.is_dir():
                shutil.copytree(sidecar_source, sidecar_destination)

    subprocess.run(["git", "diff", "--check"], cwd=repo_root, check=True)


if __name__ == "__main__":
    main()
