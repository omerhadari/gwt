# gwt

Pure Bash* (Almost), single file (no promises) Git worktree manager. Quickly switch between worktrees with automatic creation and cleanup.

*Except for `select`, completions, maybe a bit more in the future

## Install

Read the [source](https://raw.githubusercontent.com/omerhadari/gwt/main/gwt) and understand if you're ok with running it on your machine.

Download or copy it, and make it executable and add it to your `PATH`.

Then add to your `~/.bashrc` or `~/.zshrc`:
```bash
# gwt shell integration (required)
eval "$(gwt config shell init bash)"  # or zsh

# tab completion (optional)
eval "$(gwt config completion bash)"  # or zsh
```
There is intentionally no installation one-liner a-la `curl -o` here.
This is a simple tool that doesn't do much, but it does run git commands
and makes it easy to add hooks, please make sure you're fine with how it works before using (as the license says - authors bare no responsibility etc...).


## Usage

```bash
gwt switch feature-x          # Switch to worktree (if exists)
gwt switch -c feature-y       # Create worktree and switch
gwt switch -                  # Switch to previous worktree

gwt remove                    # Remove current worktree and branch
gwt remove feature-x          # Remove specific worktree

gwt list                      # List all worktrees
gwt select                    # Interactive picker (requires fzf)
```

## Optional dependencies

- [fzf](https://github.com/junegunn/fzf) - required for `gwt select`

## How it works

Worktrees are created as siblings to your repo:
```
~/code/myproject/           # main branch
~/code/myproject.feature-x/ # feature-x branch
~/code/myproject.feature-y/ # feature-y branch
```

Shell integration is required for `switch`, `remove`, and `select` to change your working directory.

## Hooks

Run a script after creating a new worktree:

```bash
gwt config hooks install                              # Install git hook (per repo)
gwt config hooks install --global                     # Install git hook (global, uses core.hooksPath)
gwt config hooks set-post-create /path/to/script.sh   # Set script (per repo)
gwt config hooks set-post-create --global /path/to/script.sh  # Set script (global)
```

The script receives `$1` (branch name) and `$2` (worktree path).

This is a thin wrapper around git's [post-checkout hook](https://git-scm.com/docs/githooks#_post_checkout). `hooks install` will fail if you already have one.

## Acknowledgements

Inspired by [worktrunk](https://github.com/max-sixty/worktrunk). If you want more features (better previews, more sophisticated hooks, CI integration and more), use that instead.

## License

MIT
