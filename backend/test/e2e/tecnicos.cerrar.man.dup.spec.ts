it('cierra MAN consolidando [1,2] y descuenta 3 del técnico', async () => {
  const COD = `MAN-${Date.now()}-DUP`;
  const TEC_ID = 'c1f2dd81-8f1c-477c-b7cd-580dd13916d3';
  const MAT = 3;

  // crear, asignar, iniciar (usa tus helpers e2e)
  await crearOrden(COD, 'MAN');
  await asignarOrden(COD, TEC_ID);
  await iniciarOrden(COD, TEC_ID);

  const prev = await getStockTecnico(MAT);

  // cerrar con duplicados
  await cerrarOrden(COD, TEC_ID, {
    materiales: [{ materialIdInt: MAT, cantidad: 1 }, { materialIdInt: MAT, cantidad: 2 }],
  });

  const post = await getStockTecnico(MAT);
  expect(prev - post).toBe(3);

  // espejo y OM
  await expectDesviacionCero(TEC_ID, MAT);
  const om = await getOrdenMateriales(COD);
  expect(om).toEqual([{ material_id: MAT, cantidad: '3.000000', descontado: true }]);

  // idempotencia: reintentar cierre mismo payload no cambia stock
  await cerrarOrden(COD, TEC_ID, {
    materiales: [{ materialIdInt: MAT, cantidad: 1 }, { materialIdInt: MAT, cantidad: 2 }],
  });
  const post2 = await getStockTecnico(MAT);
  expect(post2).toBe(post);
});
