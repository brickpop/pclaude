#!/usr/bin/env bash
# Installs the pclaude launcher into ~/.local/bin and builds the image.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="${HOME}/.local/bin"
share="${PCLAUDE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pclaude}"

command -v podman >/dev/null || { echo "podman is not installed — see the README" >&2; exit 1; }

mkdir -p "$bin" "$share"
install -m 0644 "$src/Dockerfile" "$share/Dockerfile"
install -m 0755 "$src/pclaude" "$bin/pclaude"
echo "installed: $bin/pclaude"
echo "installed: $share/Dockerfile"

"$bin/pclaude" --pclaude-build "$@"

case ":$PATH:" in
  *":$bin:"*) ;;
  *)
    echo
    echo "NOTE: $bin is not on your PATH. Add it:"
    echo "  bash/zsh:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "  fish:      fish_add_path ~/.local/bin"
    ;;
esac

echo
echo "Done. Run 'pclaude' inside any project directory."
