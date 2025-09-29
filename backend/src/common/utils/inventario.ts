// src/common/utils/inventario.ts
export type ItemMaterial = { materialIdInt: number; cantidad: number };

export function consolidateMaterials(items: ItemMaterial[]): ItemMaterial[] {
  const map = new Map<number, number>();
  for (const it of items) {
    const prev = map.get(it.materialIdInt) ?? 0;
    map.set(it.materialIdInt, prev + Number(it.cantidad));
  }
  return [...map.entries()].map(([materialIdInt, cantidad]) => ({ materialIdInt, cantidad }));
}
