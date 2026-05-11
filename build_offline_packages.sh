#!/bin/bash
set -euo pipefail

APT_CACHE_DIR="/var/cache/apt/archives"
OUT_DIR="local_packages"
TARBALL="local_packages.tar.gz"

RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RESET=$'\033[0m'

usage() {
    echo "Usage: $0 -f <packages.txt>" >&2
    echo "  packages.txt lines: <sha256>  <filename.deb>" >&2
    exit 2
}

big_error() {
    local msg="$1"
    echo
    echo "${RED}################################################################${RESET}" >&2
    echo "${RED}!!!                  SHA256 VERIFICATION FAILED              !!!${RESET}" >&2
    echo "${RED}################################################################${RESET}" >&2
    echo "${RED}${msg}${RESET}" >&2
    echo "${RED}################################################################${RESET}" >&2
    echo
    exit 1
}

PACKAGES_FILE=""
while getopts ":f:h" opt; do
    case "$opt" in
        f) PACKAGES_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$PACKAGES_FILE" ]]; then
    usage
fi

if [[ ! -r "$PACKAGES_FILE" ]]; then
    echo "${RED}error:${RESET} cannot read packages file: $PACKAGES_FILE" >&2
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "${RED}error:${RESET} must run as root (apt cache + /etc/apt access)" >&2
    exit 1
fi

declare -a EXPECTED_SHAS=()
declare -a EXPECTED_FILES=()
declare -a PKG_NAMES=()

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// /}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    sha="$(awk '{print $1}' <<<"$line")"
    fname="$(awk '{print $2}' <<<"$line")"

    if [[ -z "$sha" || -z "$fname" ]]; then
        echo "${RED}error:${RESET} malformed line in $PACKAGES_FILE: $line" >&2
        exit 1
    fi

    pkg="${fname%%_*}"

    EXPECTED_SHAS+=("$sha")
    EXPECTED_FILES+=("$fname")
    PKG_NAMES+=("$pkg")
done <"$PACKAGES_FILE"

if [[ "${#PKG_NAMES[@]}" -eq 0 ]]; then
    echo "${RED}error:${RESET} no packages parsed from $PACKAGES_FILE" >&2
    exit 1
fi

echo "${GREEN}==>${RESET} ${#PKG_NAMES[@]} package(s) to fetch:"
printf '    - %s\n' "${PKG_NAMES[@]}"

echo "${GREEN}==>${RESET} apt-get clean"
apt-get clean

echo "${GREEN}==>${RESET} apt-get update"
apt-get update

echo "${GREEN}==>${RESET} apt-get install --download-only --reinstall"
apt-get install --download-only --reinstall -y "${PKG_NAMES[@]}"

echo "${GREEN}==>${RESET} verifying sha256 sums against $APT_CACHE_DIR"
declare -a FAILURES=()
for i in "${!EXPECTED_FILES[@]}"; do
    fname="${EXPECTED_FILES[$i]}"
    expected="${EXPECTED_SHAS[$i]}"
    path="$APT_CACHE_DIR/$fname"

    if [[ ! -f "$path" ]]; then
        FAILURES+=("MISSING  $fname  (not found in $APT_CACHE_DIR)")
        continue
    fi

    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        FAILURES+=("MISMATCH $fname  expected=$expected  actual=$actual")
    else
        echo "    ${GREEN}ok${RESET}  $fname"
    fi
done

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
    msg=""
    for f in "${FAILURES[@]}"; do
        msg+="  $f"$'\n'
    done
    big_error "$msg"
fi

echo "${GREEN}==>${RESET} resetting ./$OUT_DIR"
rm -rf "./$OUT_DIR"
mkdir "./$OUT_DIR"

echo "${GREEN}==>${RESET} copying verified .debs into ./$OUT_DIR"
for fname in "${EXPECTED_FILES[@]}"; do
    cp "$APT_CACHE_DIR/$fname" "./$OUT_DIR/$fname"
done

cp "$PACKAGES_FILE" "./$OUT_DIR/packages.txt"

cat >"./$OUT_DIR/install.sh" <<'INSTALL_EOF'
#!/bin/bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

echo "==> Verifying sha256 sums..."
sha256sum -c packages.txt

echo "==> Installing packages (offline, dpkg -i)..."
sudo dpkg -i *.deb

echo "==> Done."
INSTALL_EOF
chmod 0755 "./$OUT_DIR/install.sh"

echo "${GREEN}==>${RESET} creating $TARBALL"
rm -f "./$TARBALL"
tar czf "./$TARBALL" "$OUT_DIR"

echo
echo "${GREEN}done.${RESET} ${YELLOW}$TARBALL${RESET} ready ($(du -h "./$TARBALL" | awk '{print $1}'))"
