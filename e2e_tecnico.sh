# 1) Crear venta y pagar (genera orden)
VCOD=$(curl -sS -X POST http://127.0.0.1:3000/v1/ventas \
  -H 'Content-Type: application/json' \
  -d '{"cliente_nombre":"Test","cliente_apellido":"Tecnico","documento":"CC-DEMO","plan":"FTTH 200M Hogar","total":30}' \
  | jq -r '.venta.codigo')

curl -sS -X POST "http://127.0.0.1:3000/v1/ventas/$VCOD/pagar" | tee /tmp/pago.json
ORD=$(jq -r '.orden.codigo' /tmp/pago.json)

# 2) Preparar evidencias base64 (usa tus archivos locales)
FOTO=$(base64 -w0 /home/yarumo/isp_starter_kit/tmp/foto1.jpg)
FIRMA=$(base64 -w0 /home/yarumo/isp_starter_kit/tmp/firma.png)

cat > /tmp/cerrar.json <<JSON
{"lat":4.711,"lng":-74.072,"onu_serial":"ZTEG12345678","vlan":"110","precinto":"P-0001","tecnico":"TEC-001",
 "fotos":["data:image/jpeg;base64,$FOTO"],"firma":"data:image/png;base64,$FIRMA"}
JSON

# 3) Cerrar orden (vía proxy del frontend o directo al backend)
curl -sS -X POST "http://127.0.0.1:3001/api/ordenes/$ORD/cerrar-completo" \
  -H 'Content-Type: application/json' --data-binary @/tmp/cerrar.json | tee /tmp/cerrar_resp.json

# 4) Ver estado y logs
curl -sS "http://127.0.0.1:3000/v1/ordenes?estado=cerrada" | jq .
echo "Revisa consola del backend para ver la cola SmartOLT."
