#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
doctor_ps1="$script_dir/doctor-sam.ps1"

if command -v pwsh >/dev/null 2>&1; then
	exec pwsh -NoProfile -File "$doctor_ps1" "$@"
fi

if command -v powershell >/dev/null 2>&1; then
	exec powershell -NoProfile -File "$doctor_ps1" "$@"
fi

echo "PowerShell 7+ is required to run doctor-sam.sh" >&2
exit 1
