-- Vista con joins útiles para la API
CREATE OR REPLACE VIEW v_kardex_det AS
SELECT
  vk.id,
  vk.fecha,
  vk.tipo,
  vk.material_id,
  mat.codigo  AS material_codigo,
  mat.nombre  AS material_nombre,
  vk.cantidad,
  vk.delta,
  vk.almacen_id,
  alm.codigo  AS almacen_codigo,
  alm.nombre  AS almacen_nombre,
  vk.from_almacen_id,
  fa.codigo   AS from_almacen_codigo,
  vk.to_almacen_id,
  ta.codigo   AS to_almacen_codigo,
  vk.tecnico_id,
  vk.nota
FROM v_kardex vk
LEFT JOIN materiales mat   ON mat.id = vk.material_id
LEFT JOIN almacenes  alm   ON alm.id = vk.almacen_id
LEFT JOIN almacenes  fa    ON fa.id  = vk.from_almacen_id
LEFT JOIN almacenes  ta    ON ta.id  = vk.to_almacen_id;
