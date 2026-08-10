#!/usr/bin/env bash
set -euo pipefail

flutter_bin="$(command -v flutter)"
flutter_root="${FLUTTER_ROOT:-}"
if [[ -z "$flutter_root" ]]; then
  flutter_root="$(dirname "$(dirname "$flutter_bin")")"
fi
tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
patch_file="$tool_dir/flutter-semantics-190431.patch"

if git -C "$flutter_root" apply --check "$patch_file"; then
  git -C "$flutter_root" apply "$patch_file"
elif git -C "$flutter_root" apply --reverse --check "$patch_file"; then
  printf 'Flutter semantics fix is already applied.\n'
else
  printf 'Flutter SDK does not match the semantics fix patch.\n' >&2
  exit 1
fi
