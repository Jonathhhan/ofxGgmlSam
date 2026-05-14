#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${ADDON_ROOT}/libs/sam.cpp"
DEST_DIR="${OFXGGML_SAM_CPP_DIR:-${PACKAGE_DIR}/source}"

SAM_CPP_REPO="${OFXGGML_SAM_CPP_REPO:-https://github.com/YavorGIvanov/sam.cpp.git}"
SAM_CPP_REF="${OFXGGML_SAM_CPP_REF:-81002818eb0e2cb3b9a523286b067f80f8424431}"

if ! command -v git >/dev/null 2>&1; then
	echo "git is required to install sam.cpp" >&2
	exit 1
fi

mkdir -p "$(dirname "${DEST_DIR}")"

if [ -d "${DEST_DIR}/.git" ]; then
	echo "==> Updating existing sam.cpp checkout in ${DEST_DIR}"
	git -C "${DEST_DIR}" fetch --tags origin
else
	if [ -e "${DEST_DIR}" ] && [ -n "$(find "${DEST_DIR}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
		echo "Refusing to overwrite non-empty directory: ${DEST_DIR}" >&2
		exit 1
	fi
	rm -rf "${DEST_DIR}"
	echo "==> Cloning sam.cpp into ${DEST_DIR}"
	git clone --recursive "${SAM_CPP_REPO}" "${DEST_DIR}"
fi

git -C "${DEST_DIR}" checkout "${SAM_CPP_REF}"
git -C "${DEST_DIR}" submodule update --init --recursive

mkdir -p "${PACKAGE_DIR}/include" "${PACKAGE_DIR}/src"
python - <<'PY' "${DEST_DIR}/sam.cpp"
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("ggml_scale(ctx0, cur, ggml_new_f32(ctx0, float(2.0f*M_PI)))",
                    "ggml_scale(ctx0, cur, float(2.0f*M_PI))")
text = text.replace("ggml_new_f32(ctx0, 1.0f/sqrtf(n_enc_head_dim))",
                    "1.0f/sqrtf(n_enc_head_dim)")
text = text.replace("ggml_new_f32(ctx0, 1.0f/sqrt(float(Q->ne[0])))",
                    "1.0f/sqrt(float(Q->ne[0]))")
path.write_text(text, encoding="utf-8")
PY
cp "${DEST_DIR}/sam.h" "${PACKAGE_DIR}/include/sam.h"
cp "${DEST_DIR}/sam.cpp" "${PACKAGE_DIR}/src/sam.cpp"

cat <<EOF
==> sam.cpp is installed.

Package: ${PACKAGE_DIR}
Source:  ${DEST_DIR}
Ref:     ${SAM_CPP_REF}

The pinned source is patched for the Core ggml scale API. The addon supplies a
packaged source for porting, but the point example does not auto-enable the
in-process adapter because this sam.cpp revision still needs a Core ggml
allocator port.
EOF
