#!/usr/bin/env python3
"""
Script: scripts/discover_images.py
Description: Scans the images/ directory for Docker images and outputs matrix configurations for CI/CD workflows.
"""

import argparse
import json
import os
import sys
from pathlib import Path


def discover_images(images_dir: str, target_filter: str = "all") -> list:
    images_path = Path(images_dir).resolve()
    if not images_path.exists() or not images_path.is_dir():
        print(f"Error: Images directory '{images_dir}' not found.", file=sys.stderr)
        sys.exit(1)

    target_filter = (target_filter or "all").strip().lower()

    # Find all Dockerfiles under images directory
    dockerfiles = sorted(list(images_path.rglob("Dockerfile")))

    images = []
    seen_contexts = set()

    for df in dockerfiles:
        df_dir = df.parent
        # If Dockerfile is inside a 'docker' subdirectory, use the parent folder as context
        if df_dir.name == "docker":
            context_dir = df_dir.parent
        else:
            context_dir = df_dir

        if context_dir in seen_contexts:
            continue
        seen_contexts.add(context_dir)

        # Calculate relative path from images_dir (e.g. rust/common)
        rel_path = context_dir.relative_to(images_path).as_posix()
        if rel_path == ".":
            continue

        # Image name normalized to lower-kebab-case (e.g. rust-common)
        image_name = rel_path.replace("/", "-").lower()

        # Check target filter matching
        if target_filter in ("all", "*", "") or target_filter == image_name or target_filter == rel_path.lower():
            # Get repository-relative paths with forward slashes
            try:
                repo_root = Path(__file__).resolve().parent.parent
                rel_context = context_dir.relative_to(repo_root).as_posix()
                rel_dockerfile = df.relative_to(repo_root).as_posix()
            except ValueError:
                rel_context = context_dir.as_posix()
                rel_dockerfile = df.as_posix()

            images.append({
                "image_name": image_name,
                "context": rel_context,
                "dockerfile": rel_dockerfile,
                "rel_path": rel_path
            })

    # Sort deterministically by image name
    images.sort(key=lambda x: x["image_name"])
    return images


def main():
    parser = argparse.ArgumentParser(
        description="Discover Docker images under images/ directory for CI/CD workflows."
    )
    parser.add_argument(
        "-d", "--images-dir",
        default=os.environ.get("IMAGES_DIR", "images"),
        help="Path to the images root directory (default: 'images')."
    )
    parser.add_argument(
        "-t", "--target",
        default=os.environ.get("TARGET_IMAGE", "all"),
        help="Filter target image name or relative path (default: 'all')."
    )
    parser.add_argument(
        "-f", "--format",
        choices=["matrix", "json", "names"],
        default="matrix",
        help="Output format: 'matrix' (GitHub Actions matrix json), 'json' (raw list), or 'names' (default: matrix)."
    )
    parser.add_argument(
        "--github-output",
        nargs="?",
        const=os.environ.get("GITHUB_OUTPUT", ""),
        help="Write matrix JSON to the specified GitHub output file or $GITHUB_OUTPUT."
    )

    args = parser.parse_args()

    images = discover_images(args.images_dir, args.target)

    if not images:
        print(f"Error: No images found matching target '{args.target}'.", file=sys.stderr)
        sys.exit(1)

    print(f"Discovered {len(images)} image(s): {[img['image_name'] for img in images]}", file=sys.stderr)

    # Format matrix structure for GitHub Actions
    matrix_data = {"include": images}
    matrix_json = json.dumps(matrix_data)

    # Write to GitHub Output if requested
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as f:
            f.write(f"matrix={matrix_json}\n")
            f.write(f"count={len(images)}\n")
        print(f"Written matrix to GitHub Output: {args.github_output}", file=sys.stderr)

    # Output to stdout
    if args.format == "matrix":
        print(matrix_json)
    elif args.format == "json":
        print(json.dumps(images, indent=2))
    elif args.format == "names":
        for img in images:
            print(img["image_name"])


if __name__ == "__main__":
    main()
