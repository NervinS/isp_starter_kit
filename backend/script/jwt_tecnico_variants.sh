#!/usr/bin/env bash
set -euo pipefail

TEC_ID="${1:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"

gen() {
  local mode="$1"      # sub | tecnicoId | both
  local enriched="$2"  # 0 | 1

  docker compose exec -T api node -e "
    const jwt=require('jsonwebtoken');
    const secret=process.env.JWT_SECRET||'dev';
    const p={};
    if ('$mode'==='sub') p.sub='$TEC_ID';
    if ('$mode'==='tecnicoId') p.tecnicoId='$TEC_ID';
    if ('$mode'==='both') { p.sub='$TEC_ID'; p.tecnicoId='$TEC_ID'; }
    // claims comunes en guards caseros:
    if ($enriched) {
      p.role='tecnico';
      p.rol='tecnico';
      p.scope=['tecnico'];
      p.permisos=['tecnico'];
      p.typ='tech';
    }
    const token=jwt.sign(p, secret, { expiresIn:'2h' });
    console.log(token);
  " | tr -d '\r'
}

echo "SUB=$(gen sub 0)"
echo "TECID=$(gen tecnicoId 0)"
echo "BOTH=$(gen both 0)"
echo "SUB_PLUS=$(gen sub 1)"
echo "TECID_PLUS=$(gen tecnicoId 1)"
echo "BOTH_PLUS=$(gen both 1)"
