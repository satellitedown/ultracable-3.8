#!/usr/bin/env bash
#
# Ultracable 3.8 installer.
#
#   curl -fsSL https://raw.githubusercontent.com/satellitedown/ultracable-3.8/main/install.sh | bash
#
# Options:
#   --ref REF      branch or tag to install (default: main)
#   --prefix DIR   where the ultracable command goes (default: ~/.local)
#   --home DIR     where the project goes (default: ~/.ultracable)
#   --add-path     append PREFIX/bin to your shell rc if it is not on PATH
#   -h, --help     show this
#
# FLASH AT YOUR OWN RISK. The author accepts no liability. See README.
#
set -euo pipefail

REPO_SLUG="${ULTRACABLE_REPO:-satellitedown/ultracable-3.8}"
REF="${ULTRACABLE_REF:-main}"
PREFIX="${ULTRACABLE_PREFIX:-$HOME/.local}"
UC_HOME="${ULTRACABLE_HOME:-$HOME/.ultracable}"
SRC="$UC_HOME/src"
ADD_PATH=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; Z=$'\033[0m'
else
	G=""; Y=""; R=""; Z=""
fi

say() { printf '%s==>%s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%swarn:%s %s\n' "$Y" "$Z" "$*" >&2; }
die() { printf '%serror:%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
		--ref) REF="${2:?--ref needs a value}"; shift 2 ;;
		--prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
		--home) UC_HOME="${2:?--home needs a value}"; SRC="$UC_HOME/src"; shift 2 ;;
		--add-path) ADD_PATH=1; shift ;;
		-h | --help)
			sed -n '2,16p' "${BASH_SOURCE[0]:-/dev/null}" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*) die "unknown option: $1 (try --help)" ;;
	esac
done

command -v tar >/dev/null 2>&1 || die "tar is required"
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || die "curl or wget is required"

# From a checkout, install what is on disk. Piped from curl, fetch the tarball.
LOCAL_SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/bin/ultracable" ]; then
	LOCAL_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	say "Installing from checkout: $LOCAL_SRC"
else
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	say "Downloading $REPO_SLUG@$REF"
	URL="https://github.com/$REPO_SLUG/archive/refs/heads/$REF.tar.gz"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$URL" | tar -xz -C "$TMP"
	else
		wget -qO- "$URL" | tar -xz -C "$TMP"
	fi
	LOCAL_SRC="$TMP/$(basename "$REPO_SLUG")-$(printf '%s' "$REF" | tr '/' '-')"
fi
[ -d "$LOCAL_SRC" ] || die "download or unpack failed"

say "Installing project to $SRC"
mkdir -p "$UC_HOME" "$PREFIX/bin"
rm -rf "$SRC.new"
mkdir -p "$SRC.new"
(
	cd "$LOCAL_SRC" &&
		tar --exclude='./.git' -cf - .
) | (cd "$SRC.new" && tar -xf -)
rm -rf "$SRC"
mv "$SRC.new" "$SRC"

say "Installing $PREFIX/bin/ultracable"
cat >"$PREFIX/bin/ultracable" <<SHIM
#!/usr/bin/env bash
# Ultracable launcher (installed by install.sh).
export ULTRACABLE_HOME="\${ULTRACABLE_HOME:-$UC_HOME}"
exec "\$ULTRACABLE_HOME/src/bin/ultracable" "\$@"
SHIM
chmod 0755 "$PREFIX/bin/ultracable"

case ":$PATH:" in
	*":$PREFIX/bin:"*) ;;
	*)
		warn "$PREFIX/bin is not on your PATH"
		if [ "$ADD_PATH" = 1 ]; then
			SHELL_NAME="$(basename "${SHELL:-bash}")"
			case "$SHELL_NAME" in
				fish)
					RC="$HOME/.config/fish/config.fish"
					LINE="fish_add_path $PREFIX/bin"
					;;
				*)
					RC="$HOME/.${SHELL_NAME}rc"
					LINE="export PATH=\"$PREFIX/bin:\$PATH\""
					;;
			esac
			mkdir -p "$(dirname "$RC")"
			if grep -q ultracable "$RC" 2>/dev/null; then
				say "PATH already handled in $RC"
			else
				printf '\n# ultracable\n%s\n' "$LINE" >>"$RC"
				say "Added $PREFIX/bin to $RC — restart your shell"
			fi
		else
			printf '    export PATH="%s/bin:$PATH"   # add to your shell rc, or rerun with --add-path\n' "$PREFIX"
		fi
		;;
esac

say "ultracable $("$PREFIX/bin/ultracable" version) installed"

cat <<'EOF'

  Next:
    ultracable doctor             check your machine and the stock firmware
    ultracable hash               verify sha256 of a2363_upd_img.bin
    ultracable flash --simulate   ...flash your cable

  FLASH AT YOUR OWN RISK. The author accepts no liability. See README.

EOF
