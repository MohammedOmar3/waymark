# waymark init  (sourced by bin/waymark; uses exit)
#   --owner-name <s> --owner-email <s> --root <dir> [--repo-roots <a,b>]
#   [--replace-auto-memory yes|no] [--sign-layer yes|no] [--email-allowlist <a,b>]
#   [--plugin-root <dir>]
# Non-interactive setup engine. Never touches Claude settings.

wm_i_name=""; wm_i_email=""; wm_i_root=""; wm_i_repo_roots=""
wm_i_replace="no"; wm_i_sign=""; wm_i_allow=""; wm_i_plugin=""

wm_i_die() { printf 'waymark init: %s\n' "$1" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --owner-name|--owner-email|--root|--repo-roots|--replace-auto-memory|--sign-layer|--email-allowlist|--plugin-root)
      [ $# -ge 2 ] || wm_i_die "missing value for $1" 64
      case "$1" in
        --owner-name) wm_i_name="$2" ;;
        --owner-email) wm_i_email="$2" ;;
        --root) wm_i_root="$2" ;;
        --repo-roots) wm_i_repo_roots="$2" ;;
        --replace-auto-memory) wm_i_replace="$2" ;;
        --sign-layer) wm_i_sign="$2" ;;
        --email-allowlist) wm_i_allow="$2" ;;
        --plugin-root) wm_i_plugin="$2" ;;
      esac
      shift 2 ;;
    *) wm_i_die "unknown argument: $1" 64 ;;
  esac
done

[ -n "$wm_i_name" ] || wm_i_die "--owner-name is required" 64
[ -n "$wm_i_email" ] || wm_i_die "--owner-email is required" 64
[ -n "$wm_i_root" ] || wm_i_die "--root is required" 64
case "$wm_i_replace" in yes|no) ;; *) wm_i_die "--replace-auto-memory must be yes or no" 64 ;; esac
case "$wm_i_sign" in ''|yes|no) ;; *) wm_i_die "--sign-layer must be yes or no" 64 ;; esac

# ---------------------------------------------------------------- preflight
case "$wm_i_email" in *@*) ;; *) wm_i_die "owner email must contain @: $wm_i_email" ;; esac
command -v git >/dev/null 2>&1 || wm_i_die "git is required but was not found"

wm_i_root="$(wm_path "$wm_i_root")"
[ -n "$wm_i_plugin" ] || wm_i_plugin="$wm_here/.."
wm_i_plugin="$(wm_path "$wm_i_plugin")"
[ -d "$wm_i_plugin/templates/layer" ] || wm_i_die "templates not found under $wm_i_plugin"
[ -f "$wm_i_plugin/bin/waymark" ] || wm_i_die "plugin bin not found under $wm_i_plugin"

if [ -e "$wm_i_root" ]; then
  [ -d "$wm_i_root" ] || wm_i_die "root exists and is not a directory: $wm_i_root"
  if [ -n "$(ls -A "$wm_i_root" 2>/dev/null)" ]; then
    wm_i_die "root exists and is not empty: $wm_i_root"
  fi
fi

# nearest existing ancestor must not be inside a git work tree
wm_i_anc="$wm_i_root"
while [ ! -d "$wm_i_anc" ]; do
  case "$wm_i_anc" in */*) wm_i_anc="${wm_i_anc%/*}" ;; *) wm_i_anc="." ;; esac
  [ -n "$wm_i_anc" ] || wm_i_anc="/"
done
if [ "$(git -C "$wm_i_anc" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
  wm_i_die "root is inside a git work tree: $wm_i_root"
fi

wm_i_gpg_global="$(git config --global --get commit.gpgsign 2>/dev/null)"
[ -n "$wm_i_sign" ] || wm_i_sign="no"

# ----------------------------------------------------------------- create
mkdir -p "$wm_i_root" || wm_i_die "cannot create $wm_i_root"
wm_i_root="$(cd "$wm_i_root" && pwd)"
cp -R "$wm_i_plugin/templates/layer/." "$wm_i_root/" || wm_i_die "copy failed"
rm -rf "$wm_i_root/bin"
cp -R "$wm_i_plugin/bin" "$wm_i_root/bin" || wm_i_die "copy of bin failed"

# substitute tokens (parameter expansion: values may contain any character)
wm_i_created="$(wm_today)"
wm_i_o="{"; wm_i_o="$wm_i_o$wm_i_o"
for wm_i_f in $(cd "$wm_i_root" && grep -rl "$wm_i_o" . --exclude-dir=.git --exclude-dir=bin 2>/dev/null); do
  wm_i_c="$(cat "$wm_i_root/$wm_i_f"; printf x)"; wm_i_c="${wm_i_c%x}"
  wm_i_c="${wm_i_c//"${wm_i_o}OWNER_NAME}}"/$wm_i_name}"
  wm_i_c="${wm_i_c//"${wm_i_o}OWNER_EMAIL}}"/$wm_i_email}"
  wm_i_c="${wm_i_c//"${wm_i_o}CREATED}}"/$wm_i_created}"
  printf '%s' "$wm_i_c" > "$wm_i_root/$wm_i_f"
done

wm_i_ver="0.1.0"
if [ -f "$wm_i_plugin/.claude-plugin/plugin.json" ]; then
  wm_i_v="$(wm_json_str "$(cat "$wm_i_plugin/.claude-plugin/plugin.json")" version 2>/dev/null)"
  [ -z "$wm_i_v" ] || wm_i_ver="$wm_i_v"
fi
wm_conf_set "$wm_i_root/layer.conf" email_allowlist "$wm_i_allow"
wm_conf_set "$wm_i_root/layer.conf" repo_roots "$wm_i_repo_roots"
wm_conf_set "$wm_i_root/layer.conf" plugin_version "$wm_i_ver"
wm_conf_set "$wm_i_root/layer.conf" replace_auto_memory "$wm_i_replace"

# -------------------------------------------------------------------- git
git -C "$wm_i_root" init -q || wm_i_die "git init failed" 3
git -C "$wm_i_root" symbolic-ref HEAD refs/heads/main
git -C "$wm_i_root" config user.name "$wm_i_name"
git -C "$wm_i_root" config user.email "$wm_i_email"
mkdir -p "$wm_i_root/.git/hooks"
cp "$wm_i_plugin/templates/pre-commit" "$wm_i_root/.git/hooks/pre-commit"
chmod +x "$wm_i_root/.git/hooks/pre-commit"
wm_i_notice=""
if [ "$wm_i_gpg_global" = "true" ] && [ "$wm_i_sign" != "yes" ]; then
  git -C "$wm_i_root" config commit.gpgsign false
  wm_i_notice="commit signing is on globally; set commit.gpgsign=false for this layer only (use --sign-layer yes to sign)"
  printf 'waymark init: notice: %s\n' "$wm_i_notice"
fi

# ------------------------------------------------------------ index+commit
export WAYMARK_ROOT="$wm_i_root"
if [ -f "$wm_i_root/bin/cmd/index.sh" ]; then
  bash "$wm_i_root/bin/waymark" index >/dev/null 2>&1 || true
fi
wm_commit "chore: initialise waymark layer"
wm_i_crc=$?
if [ "$wm_i_crc" != 0 ]; then
  [ ! -f "$wm_i_root/active/.scan-failed.log" ] || cat "$wm_i_root/active/.scan-failed.log" >&2
  wm_i_die "initial commit failed (code $wm_i_crc); layer left at $wm_i_root" 3
fi

# ------------------------------------------------------------ pointer file
mkdir -p "$(wm_config_home)"
wm_conf_set "$(wm_config_home)/waymark.conf" root "$wm_i_root"

# ------------------------------------------------------------------ table
wm_i_fail=0
wm_i_row() { # name ok-flag detail
  if [ "$2" = 0 ]; then printf 'PASS  %s\n' "$1"; else printf 'FAIL  %s  (%s)\n' "$1" "${3:-}"; wm_i_fail=1; fi
}
printf 'waymark init: layer at %s\n' "$wm_i_root"
[ -f "$wm_i_root/layer.conf" ]; wm_i_row "layer.conf present" $?
[ -f "$wm_i_root/PROTOCOL.md" ] && [ -f "$wm_i_root/DOCS-PROTOCOL.md" ] && [ -f "$wm_i_root/INDEX.md" ]; wm_i_row "protocol and index files" $?
[ -x "$wm_i_root/.git/hooks/pre-commit" ]; wm_i_row "pre-commit hook installed" $?
[ "$(git -C "$wm_i_root" symbolic-ref --short HEAD 2>/dev/null)" = main ]; wm_i_row "branch is main" $?
[ -z "$(git -C "$wm_i_root" status --porcelain 2>/dev/null)" ]; wm_i_row "working tree clean" $?
[ "$(git -C "$wm_i_root" log -1 --format=%s 2>/dev/null)" = "chore: initialise waymark layer" ]; wm_i_row "initial commit" $?
bash "$wm_i_root/bin/waymark" scan --root "$wm_i_root" >/dev/null 2>&1; wm_i_row "secrets scan clean" $?
[ "$(wm_conf_get "$(wm_config_home)/waymark.conf" root)" = "$wm_i_root" ]; wm_i_row "pointer file written" $?
[ "$wm_i_fail" = 0 ] || exit 1
exit 0
