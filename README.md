# pclaude

Run [Claude Code](https://claude.com/claude-code) inside a Podman container, sandboxed to
the directory you launch it from.

Claude runs with `--dangerously-skip-permissions`, so it never stops to ask — but it can
only see the current project, your `~/.claude` config and nothing else of your machine.

```sh
cd ~/dev/some-project
pclaude
```

## Install

**1. Install Podman**

```sh
sudo dnf install podman          # Fedora / RHEL / CentOS
sudo apt install podman          # Debian / Ubuntu
sudo pacman -S podman            # Arch
brew install podman && podman machine init && podman machine start   # macOS
```

**2. Install pclaude**

```sh
git clone https://github.com/brickpop/pclaude.git
cd pclaude
./install.sh          # add --dev to also build the Foundry/Deno/Bun/Go image
```

This copies `pclaude` to `~/.local/bin`, the Dockerfiles to `~/.local/share/pclaude`,
and builds the image (a few minutes).

If `~/.local/bin` is not on your `PATH`:

```sh
fish_add_path ~/.local/bin                                    # fish
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc      # bash/zsh
```

**3. Log in**, once, on the first run: `pclaude` and follow the browser prompt. The
credentials land in `~/.claude` on the host, so they survive image rebuilds.

## Usage

Arguments are passed through to `claude` untouched:

```sh
pclaude                             # interactive session
pclaude -p "explain this repo"      # print mode
pclaude --model opus --resume       # any claude flag
pclaude mcp list                    # any claude subcommand
```

The launcher's own options are namespaced so they can never clash with a Claude flag:

| Option | |
|---|---|
| `--pclaude-build` | Build the base image |
| `--pclaude-build-dev` | Build the dev image (Foundry, Deno, Bun, Go) |
| `--pclaude-dev` | Run using the dev image |
| `--pclaude-update` | Rebuild from scratch, pulling the latest base and Claude Code |
| `--pclaude-shell` | Open a shell in the container instead of Claude |
| `--pclaude-help` | Usage |

### Running something other than Claude

The image sets `claude` as its `CMD` and clears the entrypoint, so Claude is only the
default — any command in the image can replace it, with no `--entrypoint` needed:

```sh
podman run --rm -it -v $PWD:/workspace:z localhost/pclaude:latest        # claude
podman run --rm -it -v $PWD:/workspace:z localhost/pclaude:latest bash   # a shell
podman run --rm -v $PWD:/workspace:z localhost/pclaude:dev forge test    # anything else
```

`pclaude --pclaude-shell` is just the shorthand for the second one, with all the usual
mounts applied.

## What gets mounted

| Host | Container | |
|---|---|---|
| `$PWD` | `/workspace` | read-write — the only project code Claude can reach |
| `~/.claude` | `/home/node/.claude` | credentials, settings, agents, history |
| `~/.claude.json` | `/home/node/.claude.json` | project state |
| `~/.gitconfig` | `/home/node/.gitconfig` | read-only, if present |

`ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, `GH_TOKEN` and friends are forwarded when set.
Nothing else from your machine is visible. Running in `$HOME` itself is refused (it would
defeat the point); set `PCLAUDE_ALLOW_HOME=1` if you really mean it.

Note that the container has **unrestricted network access** — the sandbox is about your
filesystem, not about what Claude can reach online.

### SELinux

On Fedora/RHEL, bind mounts are relabelled with `:z` (shared) so that repeated and
concurrent sessions work. The stricter `:Z` gives each container a private MCS category,
which means a second `pclaude` session would relabel `~/.claude` out from under the first
and break it — use `PCLAUDE_RELABEL=Z` only if you run one session at a time. On
non-SELinux hosts no suffix is added at all.

To undo the relabelling of a directory later: `restorecon -R <dir>`.

## Configuration

| Variable | Default | |
|---|---|---|
| `PCLAUDE_IMAGE` | `localhost/pclaude:latest` | image to run (`:dev` with `--pclaude-dev`) |
| `PCLAUDE_HOME` | `~/.local/share/pclaude` | where the Dockerfiles live |
| `PCLAUDE_ARGS` | — | extra `podman run` args |
| `PCLAUDE_NO_YOLO` | — | `1` restores Claude's permission prompts |
| `PCLAUDE_RELABEL` | `auto` | `z`, `Z` or `off` |
| `PCLAUDE_ALLOW_HOME` | — | `1` allows running in `$HOME` |

Mount something extra:

```sh
PCLAUDE_ARGS="-v $HOME/dev/shared-lib:/shared:z" pclaude
```

Forward your SSH agent, so Claude can push:

```sh
PCLAUDE_ARGS="-v $SSH_AUTH_SOCK:/ssh-agent:z -e SSH_AUTH_SOCK=/ssh-agent" pclaude
```

## Images

Two tags of the same image:

**`localhost/pclaude:latest`** (`Dockerfile`) — `node:22-slim` plus Claude Code, git,
openssh, curl, jq, make, unzip, fzf, vim, less. Node 22 and npm come from the base image.

**`localhost/pclaude:dev`** (`Dockerfile.dev`) — everything above plus Foundry (`forge`,
`cast`, `anvil`), Deno, Bun and Go. It is layered `FROM localhost/pclaude:latest`, so it
reuses the base image you already have and only adds the toolchains on top.

```sh
pclaude --pclaude-build-dev
pclaude --pclaude-dev
```

Pin a Claude Code version, or a Go version, at build time:

```sh
pclaude --pclaude-build --build-arg CLAUDE_CODE_VERSION=2.1.223
pclaude --pclaude-build-dev --build-arg GO_VERSION=1.24.5
```

Claude Code self-updates inside a running container, but the change is lost when it
exits. Run `pclaude --pclaude-update` now and then to bake in the current release.

## Uninstall

```sh
rm ~/.local/bin/pclaude
rm -rf ~/.local/share/pclaude
podman rmi -f $(podman images localhost/pclaude -q)
```
