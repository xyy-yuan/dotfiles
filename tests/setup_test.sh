#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test_help_mentions_new_modes() {
    local output
    output="$(bash "$ROOT_DIR/setup.sh" --help)"

    [[ "$output" == *"--dry-run"* ]]
    [[ "$output" == *"--yes"* ]]
}

test_dry_run_does_not_write_home_files() {
    local tmp_home
    tmp_home="$(mktemp -d)"
    trap 'rm -rf "$tmp_home"' RETURN

    HOME="$tmp_home" bash "$ROOT_DIR/setup.sh" --dry-run --yes >"$tmp_home/setup-dry-run.out"

    [[ ! -e "$tmp_home/.zshrc" ]]
    [[ ! -e "$tmp_home/.zshrc.local" ]]
    [[ ! -d "$tmp_home/.local" ]]
    [[ ! -d "$tmp_home/.config" ]]
    grep -q "MesloLGS Nerd Font Mono" "$tmp_home/setup-dry-run.out"
    grep -q "Clear Dark" "$tmp_home/setup-dry-run.out"
    grep -q "terminal.integrated.fontFamily" "$tmp_home/setup-dry-run.out"
    grep -q "===> \\[基础配置全部完成\\]" "$tmp_home/setup-dry-run.out"
}

test_help_mentions_new_modes
test_dry_run_does_not_write_home_files

echo "setup_test.sh: ok"
