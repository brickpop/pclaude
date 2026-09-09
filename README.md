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
./install.sh
```

This copies `pclaude` to `~/.local/bin`, the Dockerfile to `~/.local/share/pclaude`,
and builds the image (a few minutes).

If `~/.local/bin` is not on your `PATH`:

```sh
fish_add_path ~/.local/bin                                    # fish
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc      # bash/zsh
```

**3. Log in** once, on the host, with plain `claude /login`. That single login covers
`pclaude` too, and survives image rebuilds.

Claude Code reads `~/.claude/.credentials.json` on Linux, but on macOS it keeps the token
in the login Keychain, which the Linux container cannot reach. So on macOS `pclaude`
mirrors your Keychain login into that file (mode `0600`) on every run. The host stays the
only place you ever run `/login`; don't log in from inside the container, or the next run
will overwrite it with the host's copy anyway.

If you authenticate with `ANTHROPIC_API_KEY`, Bedrock or Vertex instead, no login is
needed at all — those are forwarded from the environment.

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
| `--pclaude-build` | Build the image |
| `--pclaude-update` | Rebuild it from scratch, pulling the latest base and Claude Code |
| `--pclaude-shell` | Open a shell in the container instead of Claude |
| `--pclaude-help` | Usage |

### Running something other than Claude

The image sets `claude` as its `CMD` and clears the entrypoint, so Claude is only the
default — any command in the image can replace it, with no `--entrypoint` needed:

```sh
podman run --rm -it -v $PWD:$PWD:z -w $PWD localhost/pclaude        # claude
podman run --rm -it -v $PWD:$PWD:z -w $PWD localhost/pclaude bash   # a shell
podman run --rm -v $PWD:$PWD:z -w $PWD localhost/pclaude forge test # anything else
```

`pclaude --pclaude-shell` is just the shorthand for the second one, with all the usual
mounts applied.

## What gets mounted

| Host | Container | |
|---|---|---|
| `$PWD` | `$PWD` (same path) | read-write — the only project code Claude can reach |
| `~/.claude` | `/home/node/.claude` | credentials, settings, agents, history |
| `~/.claude.json` | `/home/node/.claude.json` | project state |
| `~/.gitconfig` | `/home/node/.gitconfig` | read-only, if present |

`ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, `GH_TOKEN` and friends are forwarded when set.
Nothing else from your machine is visible. Running in `$HOME` itself is refused (it would
defeat the point); set `PCLAUDE_ALLOW_HOME=1` if you really mean it.

The project keeps its host path inside the container, and `HOME` stays `/home/node`.
Claude keys per-project session history off the working directory, so each repo gets its
own history and `pclaude --continue` picks up where `claude --continue` left off in that
same repo.

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
| `PCLAUDE_IMAGE` | `localhost/pclaude` | image to run |
| `PCLAUDE_HOME` | `~/.local/share/pclaude` | where the Dockerfile lives |
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

## What's in the image

One image, `localhost/pclaude`, built from `node:22-slim`. Everything is on `PATH`, so
Claude can reach for any of it:

| | |
|---|---|
| **Node** | node, npm — from the base image |
| **Bun** | bun |
| **Deno** | deno |
| **Foundry** | forge, cast, anvil, chisel |
| **Go** | go, with `GOPATH=/home/node/go` |
| **Claude Code** | claude |
| **Shell tools** | git, openssh, curl, jq, make, unzip, fzf, vim, less, ps |

That comes to about 1.3 GB, of which Claude Code's own binary is 277 MB and Node is
119 MB. The first build takes a few minutes; after that it is cached.

Pin a version at build time:

```sh
pclaude --pclaude-build --build-arg CLAUDE_CODE_VERSION=2.1.223
pclaude --pclaude-build --build-arg GO_VERSION=1.24.5
```

Claude Code self-updates inside a running container, but the change is lost when it
exits. Run `pclaude --pclaude-update` now and then to bake in the current release.
Claude Code installs last in the `Dockerfile`, so bumping it reuses the toolchain layers.

## Uninstall

```sh
rm ~/.local/bin/pclaude
rm -rf ~/.local/share/pclaude
podman rmi -f $(podman images localhost/pclaude -q)
```
