#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "${root}/research/sm8550-suspend-lab/sm8550_suspend_lab.py" host self-test
printf 'sm8550 suspend lab test passed\n'
