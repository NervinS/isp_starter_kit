import { consolidateMaterials } from './inventario';

describe('consolidateMaterials', () => {
  it('suma cantidades por material', () => {
    const out = consolidateMaterials([
      { materialIdInt: 3, cantidad: 1 },
      { materialIdInt: 3, cantidad: 2 },
      { materialIdInt: 7, cantidad: 5 },
    ]);
    expect(out).toEqual([
      { materialIdInt: 3, cantidad: 3 },
      { materialIdInt: 7, cantidad: 5 },
    ]);
  });
});
