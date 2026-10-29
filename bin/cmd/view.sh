# waymark view [--no-open] [--out <file>]  (sourced by bin/waymark; uses exit)
# Builds one self-contained HTML snapshot of every .md file in the layer
# (viewer/template.html + vendor libraries, all base64-embedded) and opens it.
# Default output: <layer>/.view/index.html. bash 3.2 ok; no network.

wm_vw_open=1
wm_vw_out=""
wm_vw_outset=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-open) wm_vw_open=0; shift ;;
    --out) wm_vw_out="${2:-}"; wm_vw_outset=1; [ $# -ge 2 ] || { printf 'waymark view: --out needs a file\n' >&2; exit 64; }; shift 2 ;;
    --out=*) wm_vw_out="${1#--out=}"; wm_vw_outset=1; shift ;;
    *) printf 'waymark view: unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done
wm_vw_layer="$(wm_layer_root)" || { printf 'waymark view: no layer found\n' >&2; exit 2; }
# Plugin dir holding viewer/: next to this bin, else $CLAUDE_PLUGIN_ROOT, else
# plugin_root in layer.conf (the layer's own bin/ copy has no viewer/ beside it).
wm_vw_plugin=""
for wm_vw_p in "${wm_here%/*}" "${CLAUDE_PLUGIN_ROOT:-}" "$(wm_conf_get "$wm_vw_layer/layer.conf" plugin_root 2>/dev/null)"; do
  [ -n "$wm_vw_p" ] || continue
  case "$wm_vw_p" in *'\'*|[A-Za-z]:*) wm_vw_p="$(wm_path "$wm_vw_p")" ;; esac
  if [ -f "$wm_vw_p/viewer/template.html" ]; then wm_vw_plugin="$wm_vw_p"; break; fi
done
[ -n "$wm_vw_plugin" ] || { printf 'waymark view: viewer/template.html not found next to bin/, in $CLAUDE_PLUGIN_ROOT or at plugin_root in layer.conf\n' >&2; exit 2; }
wm_vw_tpl="$wm_vw_plugin/viewer/template.html"
wm_vw_vendor="$wm_vw_plugin/viewer/vendor"
# Stylesheets inlined at <!--WAYMARK:CSS--> in this order (tokens first: it holds the Hallmark stamp).
wm_vw_cssdir="$wm_vw_plugin/viewer"
for wm_vw_c in tokens.css base.css viewer.css; do
  [ -f "$wm_vw_cssdir/$wm_vw_c" ] || { printf 'waymark view: missing stylesheet: %s\n' "$wm_vw_c" >&2; exit 2; }
  if grep -qi '</style' "$wm_vw_cssdir/$wm_vw_c"; then
    printf 'waymark view: stylesheet must not contain </style: %s\n' "$wm_vw_c" >&2; exit 2
  fi
done
for wm_vw_c in marked purify mermaid; do
  [ -r "$wm_vw_vendor/$wm_vw_c.min.js" ] || { printf 'waymark view: missing vendor file: %s.min.js\n' "$wm_vw_c" >&2; exit 2; }
done

if [ "$wm_vw_outset" = 1 ] && [ -z "$wm_vw_out" ]; then
  printf 'waymark view: --out needs a non-empty file name\n' >&2; exit 64
fi
if [ -z "$wm_vw_out" ]; then
  wm_vw_out="$wm_vw_layer/.view/index.html"
else
  case "$wm_vw_out" in *'\'*|[A-Za-z]:*) wm_vw_out="$(wm_path "$wm_vw_out")" ;; esac
  if [ -d "$wm_vw_out" ]; then
    printf 'waymark view: --out is a directory: %s\n' "$wm_vw_out" >&2; exit 64
  fi
fi

# Keep snapshots out of the layer's commits (older layers may lack the entry).
if [ -f "$wm_vw_layer/.gitignore" ] &&
   ! grep -qx '/\{0,1\}\.view/\{0,1\}[[:space:]]*' "$wm_vw_layer/.gitignore" 2>/dev/null; then
  if [ -n "$(tail -c 1 "$wm_vw_layer/.gitignore" 2>/dev/null)" ]; then
    printf '\n.view/\n' >> "$wm_vw_layer/.gitignore"
  else
    printf '.view/\n' >> "$wm_vw_layer/.gitignore"
  fi
fi
wm_vw_odir="$(dirname "$wm_vw_out")"
mkdir -p "$wm_vw_odir" 2>/dev/null || { printf 'waymark view: cannot create %s\n' "$wm_vw_odir" >&2; exit 2; }
wm_vw_odir="$(cd "$wm_vw_odir" && pwd)" || exit 2
wm_vw_out="$wm_vw_odir/$(basename "$wm_vw_out")"
wm_vw_tmp="$wm_vw_out.tmp.$$"
trap 'rm -f "$wm_vw_tmp"' EXIT

# wm_vw_b64 <file>: one-line base64 of a file's bytes (GNU wraps, BSD does not)
# Fails (and sets wm_vw_err) when the file cannot be read or encoded.
wm_vw_b64() {
  local st
  base64 < "$1" | tr -d '\n'
  st="${PIPESTATUS[0]}${PIPESTATUS[1]}"
  [ "$st" = 00 ] || { wm_vw_err=1; return 1; }
}

# wm_vw_attr <string>: escape for a double-quoted HTML attribute
wm_vw_attr() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//\"/&quot;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

wm_vw_stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
wm_vw_list="$(cd "$wm_vw_layer" && LC_ALL=C find . \
  \( -name .git -o -name .view -o -path ./inbox -o -path ./active \) -prune -o \
  -type f -name '*.md' -print | LC_ALL=C sed 's|^\./||' | LC_ALL=C sort)"

# Any failure inside the build (unreadable file, base64, cat) sets wm_vw_err;
# then the temp file is discarded and the previous snapshot stays.
wm_vw_err=0
: > "$wm_vw_tmp" || exit 2
{
  while IFS= read -r wm_vw_line || [ -n "$wm_vw_line" ]; do
    case "$wm_vw_line" in
      '<!--WAYMARK:DATA-->')
        if [ -n "$wm_vw_list" ]; then
          while IFS= read -r wm_vw_rel; do
            wm_vw_mt="$(wm__mtime "$wm_vw_layer/$wm_vw_rel")"
            printf '<script type="application/x-waymark" data-path="%s" data-mtime="%s">' \
              "$(wm_vw_attr "$wm_vw_rel")" "${wm_vw_mt:-0}"
            wm_vw_b64 "$wm_vw_layer/$wm_vw_rel"
            printf '</script>\n'
          done < <(printf '%s\n' "$wm_vw_list")
        fi
        ;;
      '<!--WAYMARK:CSS-->')
        printf '<style>\n'
        cat "$wm_vw_cssdir/tokens.css" "$wm_vw_cssdir/base.css" "$wm_vw_cssdir/viewer.css" || wm_vw_err=1
        printf '</style>\n'
        ;;
      '<!--WAYMARK:VENDOR-->')
        printf '<script type="text/plain" id="wm-marked">'; wm_vw_b64 "$wm_vw_vendor/marked.min.js"; printf '</script>\n'
        printf '<script type="text/plain" id="wm-purify">'; wm_vw_b64 "$wm_vw_vendor/purify.min.js"; printf '</script>\n'
        printf '<script type="text/plain" id="wm-mermaid">'; wm_vw_b64 "$wm_vw_vendor/mermaid.min.js"; printf '</script>\n'
        ;;
      *'<!--WAYMARK:BUILT-->'*)
        printf '%s\n' "${wm_vw_line/'<!--WAYMARK:BUILT-->'/$wm_vw_stamp}"
        ;;
      *) printf '%s\n' "$wm_vw_line" ;;
    esac
  done < "$wm_vw_tpl"
} >> "$wm_vw_tmp" || wm_vw_err=1
[ "$wm_vw_err" = 0 ] || { printf 'waymark view: build failed; previous snapshot kept\n' >&2; exit 2; }

mv -f "$wm_vw_tmp" "$wm_vw_out" || { printf 'waymark view: cannot write %s\n' "$wm_vw_out" >&2; exit 2; }
printf '%s\n' "$wm_vw_out"

if [ "$wm_vw_open" = 1 ]; then
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
      MSYS2_ARG_CONV_EXCL='*' cmd.exe /c start "" "$(cygpath -w "$wm_vw_out")" >/dev/null 2>&1 || : ;;
    Darwin) open "$wm_vw_out" >/dev/null 2>&1 || : ;;
    *) command -v xdg-open >/dev/null 2>&1 && { xdg-open "$wm_vw_out" >/dev/null 2>&1 || :; } ;;
  esac
fi
exit 0
