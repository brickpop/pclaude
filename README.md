
```sh
podman build -t localhost/pclaude .
```

```sh
function pclaude
    podman run --rm -it --userns keep-id -v $HOME/.claude.json:/home/node/.claude.json:Z -v $HOME/.claude:/home/node/.claude:Z -v $PWD:/workspace:Z localhost/pclaude claude --dangerously-skip-permissions --model claude-opus-4-8 $argv
end
```
