# Improve statusline-command.sh

## Context
The current statusline shows only the git branch, with no indication of working tree state. The user wants a more professional display that shows git change counts alongside the branch.

## File to edit
`/Users/andrei/.claude/statusline-command.sh`

## Current output
```
~/claudeStatus  main  |  Haiku 4.5  ctx:41%
```

## Target output
```
~/claudeStatus  main +2 ~1 -1 ?3  |  Haiku 4.5  ctx:41% ●●○○○
```

## Plan

### Git status section
Use `git status --porcelain` to count:
- `+N` staged changes (green) — first char in `[AMDRC]`
- `~N` unstaged modified (yellow) — second char is `M`
- `-N` unstaged deleted (red) — second char is `D`
- `?N` untracked files (dim) — line starts with `??`

### Context format
Add a 5-dot mini progress bar after the percentage (●●○○○), same style as statusline.sh.

### Color scheme
- Directory: cyan bold
- Branch: green
- `+` staged: green
- `~` modified: yellow
- `-` deleted: red
- `?` untracked: dim white
- Separator `|`: dim
- Model: dim
- ctx label: dim, percentage bold

### Full rewrite of statusline-command.sh
```sh
#!/bin/sh
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

short_cwd="${cwd/#$HOME/\~}"

# Git info
git_branch=""
git_staged=0; git_modified=0; git_deleted=0; git_untracked=0

if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  st=$(git -C "$cwd" status --porcelain 2>/dev/null)
  if [ -n "$st" ]; then
    git_staged=$(printf '%s\n' "$st" | grep -cE '^[AMDRC].' 2>/dev/null || echo 0)
    git_modified=$(printf '%s\n' "$st" | grep -cE '^.[M]' 2>/dev/null || echo 0)
    git_deleted=$(printf '%s\n' "$st" | grep -cE '^.[D]' 2>/dev/null || echo 0)
    git_untracked=$(printf '%s\n' "$st" | grep -c '^??' 2>/dev/null || echo 0)
  fi
fi

# Context % + mini bar
ctx_str=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used" 2>/dev/null || echo "$used")
  bar=""; i=1
  while [ "$i" -le 5 ]; do
    [ "$used_int" -ge $((i * 20)) ] && bar="${bar}●" || bar="${bar}○"
    i=$((i + 1))
  done
  ctx_str="${used_int}% ${bar}"
fi

# Directory
printf "\033[1;36m%s\033[0m" "$short_cwd"

# Branch + git status counts
if [ -n "$git_branch" ]; then
  printf "  \033[0;32m%s\033[0m" "$git_branch"
  [ "$git_staged"   -gt 0 ] && printf " \033[0;32m+%d\033[0m" "$git_staged"
  [ "$git_modified" -gt 0 ] && printf " \033[0;33m~%d\033[0m" "$git_modified"
  [ "$git_deleted"  -gt 0 ] && printf " \033[0;31m-%d\033[0m" "$git_deleted"
  [ "$git_untracked" -gt 0 ] && printf " \033[2m?%d\033[0m" "$git_untracked"
fi

# Separator
printf "  \033[2m|\033[0m  "

# Model
[ -n "$model" ] && printf "\033[2m%s\033[0m" "$model"

# Context
[ -n "$ctx_str" ] && printf "  \033[2mctx:\033[0m\033[1m%s\033[0m" "$ctx_str"
```

## Verification
Run the script manually to see output:
```bash
echo '{}' | sh /Users/andrei/.claude/statusline-command.sh
```
