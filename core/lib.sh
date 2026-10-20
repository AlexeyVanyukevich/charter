# Sourced by a project's ./run, never executed:
#
#   source node_modules/charter/core/lib.sh
#
# Sourcing is inert. No shell options are set, no directory is changed and nothing runs — the
# caller owns `set -euo pipefail` and its own `cd`, and a library that took either would
# surprise whoever sources it halfway down a script.

# ── output ───────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; OFF=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; OFF=''
fi

step() { printf '%s→ %s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '%s✓ %s%s\n' "$GREEN" "$1" "$OFF"; }
note() { printf '%s  %s%s\n' "$DIM" "$1" "$OFF"; }

# Fail with an instruction, not just a symptom. The second argument is what to do about it.
die() {
  printf '%s✗ %s%s\n' "$RED" "$1" "$OFF" >&2
  [ $# -gt 1 ] && printf '%s  %s%s\n' "$YELLOW" "$2" "$OFF" >&2
  exit 1
}

# ── environment ──────────────────────────────────────────────────────────────

# `.env` is the local counterpart of what compose already substitutes for the Docker stack.
#
# Read line by line rather than sourced, so the conventional precedence holds: command line,
# then the file, then the script's own defaults. `. ./.env` assigns unconditionally and would
# let the file override an explicit `PORT=4100 ./run dev`.
#
# The grammar is plain `KEY=value`, matching what compose itself reads: no quoting, no
# expansion, `#` starts a comment. A value may contain `=`; only the first one splits.
load_env_file() {
  [ -f .env ] || return 0
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | \#*) continue ;; esac
    key=${line%%=*}
    [ -n "${!key:-}" ] && continue
    export "$key=${line#*=}"
  done < .env
}

# ── preflight ────────────────────────────────────────────────────────────────

need_docker() {
  command -v docker >/dev/null 2>&1 ||
    die "Docker is not installed." "Install Docker Desktop, then run this again."
  docker info >/dev/null 2>&1 ||
    die "Docker is installed but not running." "Start Docker Desktop and wait for it to report ready."
}

# The floor is a variable because it is the one thing that differs between projects today, and
# a project that needs a newer Node should say so rather than fork this function.
need_node() {
  local min="${CHARTER_NODE_MIN:-24}"
  local hint="${CHARTER_NODE_HINT:-Install Node ${min} or newer.}"
  command -v node >/dev/null 2>&1 || die "Node is not installed." "$hint"
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -lt "$min" ]; then
    printf '%s! Node %s is older than the required %s.%s\n' "$YELLOW" "$(node -v)" "$min" "$OFF" >&2
    note "nvm use   (or install Node ${min}) — continuing anyway"
  fi
}

# GitHub Packages wants a token even to install. CI provides one as GITHUB_TOKEN; a developer's
# comes from the GitHub CLI's login, which keeps it in the system's credential store. Either way
# it is handed to the one command that needs it and never exported into the caller's session.
with_github_token() {
  local token="${GITHUB_TOKEN:-}"
  if [ -z "$token" ]; then
    command -v gh >/dev/null 2>&1 ||
      die "Installing needs a GitHub token, and the GitHub CLI is not installed." \
        "Install it from https://cli.github.com, then: gh auth login && gh auth refresh -s read:packages"
    token="$(gh auth token 2>/dev/null)" && [ -n "$token" ] ||
      die "Installing needs a GitHub token, and the GitHub CLI is not signed in." \
        "gh auth login && gh auth refresh -s read:packages"
  fi
  GITHUB_TOKEN="$token" "$@"
}

# A project whose .npmrc reads ${GITHUB_TOKEN} installs from GitHub Packages and gets a token.
# One that does not never needs the GitHub CLI.
need_deps() {
  [ -d node_modules ] && return 0
  step "Installing dependencies"
  if grep -qs 'GITHUB_TOKEN' .npmrc; then
    with_github_token npm install
  else
    npm install
  fi
}

# Plugins are turned on in the repository's .claude/settings.json and downloaded per machine, so
# a fresh clone has the first and not the second. This installs, at project scope, each enabled
# plugin this machine lacks for this repository. A machine without Claude Code — CI among them —
# has nothing to install into, and ./run must not fail over that.
need_plugins() {
  [ -f .claude/settings.json ] || return 0
  local wanted
  wanted="$(node -e '
    const settings = JSON.parse(require("fs").readFileSync(".claude/settings.json", "utf8"))
    for (const [id, on] of Object.entries(settings.enabledPlugins ?? {})) if (on === true) console.log(id)
  ' 2>/dev/null)" || die ".claude/settings.json is not valid JSON." "Fix it, then run this again."
  [ -n "$wanted" ] || return 0

  if ! command -v claude >/dev/null 2>&1; then
    note "Claude Code is not installed; skipping its plugins"
    return 0
  fi

  # Installed for this repository means a project-scope entry whose projectPath is this directory.
  # Both sides go through realpath, because a temp or symlinked path is recorded resolved. It is
  # the native one, because on Windows the other keeps an 8.3 short name and the case it was given.
  local missing
  # shellcheck disable=SC2086
  missing="$(claude plugin list --json | node -e '
    const fs = require("fs")
    const real = (p) => { try { return fs.realpathSync.native(p) } catch { return p } }
    const here = real(".")
    const have = new Set(JSON.parse(fs.readFileSync(0, "utf8"))
      .filter((p) => p.scope === "project" && real(p.projectPath) === here)
      .map((p) => p.id))
    for (const id of process.argv.slice(1)) if (!have.has(id)) console.log(id)
  ' $wanted)" || die "Could not list Claude Code's installed plugins." "Run: claude plugin list"
  [ -n "$missing" ] || return 0

  step "Installing Claude Code plugins"
  # A machine where Claude Code never ran interactively has not registered the official marketplace.
  if grep -q '@claude-plugins-official$' <<< "$missing" &&
    ! claude plugin marketplace list --json | node -e '
      const list = JSON.parse(require("fs").readFileSync(0, "utf8"))
      process.exit(list.some((m) => m.name === "claude-plugins-official") ? 0 : 1)
    ' 2>/dev/null; then
    claude plugin marketplace add anthropics/claude-plugins-official >/dev/null ||
      die "Could not add Claude Code's official plugin marketplace." \
        "Run: claude plugin marketplace add anthropics/claude-plugins-official"
  fi
  local id
  while read -r id; do
    # No stdin: the loop's own input is the list of ids still to install.
    claude plugin install "$id" --scope project </dev/null >/dev/null ||
      die "Could not install the Claude Code plugin $id." "Run: claude plugin install $id --scope project"
    ok "$id"
  done <<< "$missing"
}

# The commit rule is enforced by the kit's commit-msg hook, and hooks are not cloned, so each
# clone installs it. The hooks directory gets a wrapper rather than a copy or a symlink: it
# follows the kit through upgrades and needs no executable bit from the tarball. Until the kit
# is installed it lets a commit through and says nothing was checked. A wrapper an older kit
# wrote is rewritten; a project's own commit-msg hook is never replaced.
need_hooks() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local hooks wrapper
  hooks="$(git rev-parse --git-path hooks)"
  # Read with `read`, not `$(cat <<…)`: bash 3.2 misparses the quotes in a heredoc inside a
  # command substitution.
  IFS= read -r -d '' wrapper <<'HOOK' || true
#!/bin/sh
# charter commit-msg
f=node_modules/charter/core/hooks/commit-msg
if [ ! -f "$f" ]; then
  echo "charter: $f is missing, so this message was not checked. Run npm install." >&2
  exit 0
fi
exec bash "$f" "$@"
HOOK
  if [ -e "$hooks/commit-msg" ] || [ -L "$hooks/commit-msg" ]; then
    # dev-kit is the kit's name before 3.0; a wrapper it wrote is ours to rewrite too.
    if ! grep -qxE '# (charter|dev-kit) commit-msg' "$hooks/commit-msg" 2>/dev/null; then
      note "$hooks/commit-msg is this project's own, so charter's is not installed."
      note "To enforce the commit rule, call node_modules/charter/core/hooks/commit-msg \"\$1\" from it."
      return 0
    fi
    # git skips a hook without its executable bit, silently, so the current text alone is not enough.
    [ "$(cat "$hooks/commit-msg")" = "${wrapper%$'\n'}" ] && [ -x "$hooks/commit-msg" ] && return 0
  fi
  mkdir -p "$hooks"
  printf '%s' "$wrapper" > "$hooks/commit-msg"
  chmod +x "$hooks/commit-msg"
  ok "commit-msg hook"
}

# Copies the template and says so. Whatever else the project wants to tell the reader about the
# new file — which port it points at, which secret is still blank — is the caller's to `note`,
# because only the caller knows.
need_env() {
  if [ ! -f .env ]; then
    step "Creating .env from .env.example"
    cp .env.example .env
    return 1
  fi
  return 0
}
