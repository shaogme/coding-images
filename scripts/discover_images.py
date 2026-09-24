#!/usr/bin/env python3
"""Discover image topology and emit the staged build matrices used by CI."""

import argparse
import json
import os
import sys
from pathlib import Path


# Runtime and builder lineages are deliberately separate. A passthrough image
# has no builder target of its own, but it still points at the nearest real
# builder artifact so descendants can use the same archive.
IMAGE_DEPENDENCY_GRAPH = {
    "common": {"stage": 0, "runtime_parent": None, "builder_parent": "mise-builder", "builder_parent_tag": "mise-builder", "builder_mode": "mise", "builder_artifact_parent": "mise-builder"},
    "podman": {"stage": 1, "runtime_parent": "common", "builder_parent": "common", "builder_parent_tag": "common-builder", "builder_mode": "passthrough", "builder_artifact_parent": "common"},
    "npins-common": {"stage": 1, "runtime_parent": "common", "builder_parent": "common", "builder_parent_tag": "common-builder", "builder_mode": "passthrough", "builder_artifact_parent": "common"},
    "rust-common": {"stage": 2, "runtime_parent": "podman", "builder_parent": "common", "builder_parent_tag": "common-builder", "builder_mode": "mise", "builder_artifact_parent": "common"},
    "qemu-common": {"stage": 2, "runtime_parent": "podman", "builder_parent": "common", "builder_parent_tag": "common-builder", "builder_mode": "passthrough", "builder_artifact_parent": "common"},
    "npins-rust": {"stage": 3, "runtime_parent": "rust-common", "builder_parent": "rust-common", "builder_parent_tag": "rust-common-builder", "builder_mode": "passthrough", "builder_artifact_parent": "rust-common"},
    "rust-wasm": {"stage": 3, "runtime_parent": "rust-common", "builder_parent": "rust-common", "builder_parent_tag": "rust-common-builder", "builder_mode": "mise", "builder_artifact_parent": "rust-common"},
    "rust-cross": {"stage": 3, "runtime_parent": "rust-common", "builder_parent": "rust-common", "builder_parent_tag": "rust-common-builder", "builder_mode": "mise", "builder_artifact_parent": "rust-common"},
    # qemu-common is passthrough, so its builder tag is an alias of the
    # common artifact rather than a second uploaded archive.
    "qemu-rust-common": {"stage": 3, "runtime_parent": "qemu-common", "builder_parent": "qemu-common", "builder_parent_tag": "qemu-common-builder", "builder_mode": "mise", "builder_artifact_parent": "common"},
    "qemu-rust-cross": {"stage": 4, "runtime_parent": "qemu-rust-common", "builder_parent": "qemu-rust-common", "builder_parent_tag": "qemu-rust-common-builder", "builder_mode": "mise", "builder_artifact_parent": "qemu-rust-common"},
}

# Compatibility for callers that used the old graph's ``parent`` field.
for _dependency in IMAGE_DEPENDENCY_GRAPH.values():
    _dependency.setdefault("parent", _dependency.get("runtime_parent"))


def _runtime_chain(image_name: str) -> list[str]:
    """Return runtime ancestors in parent-to-child order, including image."""
    chain: list[str] = []
    current: str | None = image_name
    while current:
        chain.append(current)
        current = IMAGE_DEPENDENCY_GRAPH.get(current, {}).get("runtime_parent")
    chain.reverse()
    return chain


def get_ancestors(image_name: str) -> list[str]:
    """Return the legacy child-to-root runtime ancestor list."""
    chain = _runtime_chain(image_name)
    return list(reversed(chain[:-1])) + ["global"]


def _builder_chain(image_name: str) -> list[str]:
    """Return logical builder parents, ending at the upstream builder."""
    chain: list[str] = []
    current: str | None = image_name
    while current:
        dep = IMAGE_DEPENDENCY_GRAPH.get(current)
        if not dep:
            chain.append("mise-builder")
            break
        parent = dep.get("builder_parent")
        if not parent:
            break
        chain.append(parent)
        if parent not in IMAGE_DEPENDENCY_GRAPH:
            break
        current = parent
    return chain


def _matches_target(image_name: str, rel_path: str, target: str) -> bool:
    return target in ("all", "*", "") or target in (image_name, rel_path.lower())


def discover_images(images_dir: str, target_filter: str = "all") -> list[dict]:
    images_path = Path(images_dir).resolve()
    if not images_path.is_dir():
        print(f"Error: Images directory '{images_dir}' not found.", file=sys.stderr)
        sys.exit(1)

    target = (target_filter or "all").strip().lower()
    dockerfiles = sorted(images_path.rglob("Dockerfile"))
    discovered: dict[str, dict] = {}
    repo_root = Path(__file__).resolve().parent.parent

    for dockerfile in dockerfiles:
        docker_dir = dockerfile.parent
        context_dir = docker_dir.parent if docker_dir.name == "docker" else docker_dir
        rel_path = context_dir.relative_to(images_path).as_posix()
        if rel_path == ".":
            continue
        image_name = rel_path.replace("/", "-").lower()
        if image_name in discovered:
            continue
        try:
            rel_context = context_dir.relative_to(repo_root).as_posix()
            rel_dockerfile = dockerfile.relative_to(repo_root).as_posix()
        except ValueError:
            rel_context = context_dir.as_posix()
            rel_dockerfile = dockerfile.as_posix()

        dep = IMAGE_DEPENDENCY_GRAPH.get(
            image_name,
            {
                "stage": 0,
                "runtime_parent": None,
                "builder_parent": "mise-builder",
                "builder_parent_tag": "mise-builder",
                "builder_mode": "passthrough",
                "builder_artifact_parent": "mise-builder",
            },
        )
        runtime_chain = _runtime_chain(image_name)
        builder_chain = _builder_chain(image_name)
        discovered[image_name] = {
            "image_name": image_name,
            "context": rel_context,
            "dockerfile": rel_dockerfile,
            "rel_path": rel_path,
            "stage": dep["stage"],
            # Keep parent for consumers of the old matrix protocol.
            "parent": dep.get("runtime_parent"),
            "runtime_parent": dep.get("runtime_parent") or "mise",
            "builder_parent": dep.get("builder_parent") or "mise-builder",
            "builder_parent_tag": dep.get("builder_parent_tag") or (
                "mise-builder"
                if (dep.get("builder_parent") or "mise-builder") == "mise-builder"
                else f"{dep.get('builder_parent') or 'mise-builder'}-builder"
            ),
            "builder_mode": dep.get("builder_mode", "passthrough"),
            "builder_artifact_parent": dep.get("builder_artifact_parent", "mise-builder"),
            "runtime_ancestors": json.dumps(runtime_chain[:-1] + ["global"]),
            "builder_ancestors": json.dumps(builder_chain),
            "build_closure": json.dumps({"runtime": runtime_chain, "builder": builder_chain}, separators=(",", ":")),
            # Kept for callers that still use the old cache input name.
            "ancestors": json.dumps(runtime_chain[:-1] + ["global"]),
        }

    requested = [
        name for name, image in discovered.items()
        if _matches_target(name, image["rel_path"], target)
    ]
    if not requested:
        return []

    # A single target must bring every runtime ancestor into the staged build.
    closure: set[str] = set()
    for target_name in requested:
        closure.update(_runtime_chain(target_name))
        for builder_name in _builder_chain(target_name):
            if builder_name in discovered:
                closure.update(_runtime_chain(builder_name))

    return sorted(
        (discovered[name] for name in closure),
        key=lambda image: (image["stage"], image["image_name"]),
    )


def get_staged_matrices(images: list[dict], is_single_target: bool = False) -> dict[int, list[dict]]:
    """Group images by their declared topology stage."""
    del is_single_target  # Kept in the API for scripts importing this helper.
    stages: dict[int, list[dict]] = {stage: [] for stage in range(5)}
    for image in images:
        stages.setdefault(image.get("stage", 0), []).append(image)
    return stages


def main() -> None:
    parser = argparse.ArgumentParser(description="Discover Docker images and emit dependency-aware CI matrices.")
    parser.add_argument("-d", "--images-dir", default=os.environ.get("IMAGES_DIR", "images"))
    parser.add_argument("-t", "--target", default=os.environ.get("TARGET_IMAGE", "all"))
    parser.add_argument("-f", "--format", choices=["matrix", "json", "names", "stages"], default="matrix")
    parser.add_argument("--github-output", nargs="?", const=os.environ.get("GITHUB_OUTPUT", ""), help="Append matrices to the specified GitHub Actions output file.")
    args = parser.parse_args()

    images = discover_images(args.images_dir, args.target)
    if not images:
        print(f"Error: No images found matching target '{args.target}'.", file=sys.stderr)
        sys.exit(1)

    staged = get_staged_matrices(images, args.target not in ("all", "*", ""))
    print(f"Discovered {len(images)} image(s): {[image['image_name'] for image in images]}", file=sys.stderr)
    for stage, stage_images in sorted(staged.items()):
        print(f"  - Stage {stage}: {[image['image_name'] for image in stage_images]}", file=sys.stderr)

    matrix_json = json.dumps({"include": images}, separators=(",", ":"))
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as output:
            output.write(f"matrix={matrix_json}\n")
            output.write(f"count={len(images)}\n")
            for stage in range(5):
                stage_json = json.dumps({"include": staged.get(stage, [])}, separators=(",", ":"))
                output.write(f"stage_{stage}={stage_json}\n")
                output.write(f"has_stage_{stage}={'true' if staged.get(stage) else 'false'}\n")
                output.write(f"count_stage_{stage}={len(staged.get(stage, []))}\n")

    if args.format == "matrix":
        print(matrix_json)
    elif args.format == "stages":
        print(json.dumps({stage: {"include": entries} for stage, entries in staged.items()}, indent=2))
    elif args.format == "json":
        print(json.dumps(images, indent=2))
    else:
        print("\n".join(image["image_name"] for image in images))


if __name__ == "__main__":
    main()
