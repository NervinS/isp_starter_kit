import { Module, Global } from '@nestjs/common';
import { SmartoltService } from './smartolt.service';
import { SmartoltQueue } from './smartolt.queue';

@Global()
@Module({
  providers: [SmartoltService, SmartoltQueue],
  exports: [SmartoltQueue] // exportamos solo la cola para usarla desde OrdenesController
})
export class SmartoltModule {}
