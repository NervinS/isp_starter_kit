#!/usr/bin/env bash
set -euo pipefail

API="${API_BASE:-http://127.0.0.1:3000}"
TEC_ID="${TEC_ID:-a5fa2f0d-4911-4f05-bbfa-ad3e9f38c4ec}"

# Firma un token con el SECRET real en el contenedor (role=tecnico, sub=TEC_ID)
JWT=$(docker compose exec -T api node -e "const jwt=require('jsonwebtoken'); const secret=process.env.JWT_SECRET||'devsecret'; const payload={ sub:'$TEC_ID', role:'tecnico' }; const token=jwt.sign(payload, secret, { expiresIn:'2h' }); console.log(token);" | tr -d '\r')

echo "Bearer $JWT"
