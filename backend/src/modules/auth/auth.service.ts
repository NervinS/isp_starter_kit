import { Injectable, UnauthorizedException } from '@nestjs/common';
import { Repository } from 'typeorm';
import { InjectRepository } from '@nestjs/typeorm';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { AppUser } from './app_user.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(AppUser) private readonly usersRepo: Repository<AppUser>,
    private readonly jwt: JwtService,
  ) {}

  private async validate(username: string, password: string): Promise<AppUser> {
    const user = await this.usersRepo.findOne({ where: { username } });
    if (!user) throw new UnauthorizedException('Credenciales inválidas');
    const ok = await argon2.verify(user.passHash, password);
    if (!ok) throw new UnauthorizedException('Credenciales inválidas');
    return user;
  }

  async login(username: string, password: string) {
    const user = await this.validate(username, password);
    const payload = { sub: user.id, username: user.username, roles: user.roles || [] };
    return {
      access_token: await this.jwt.signAsync(payload),
      user: { username: user.username, roles: user.roles || [] },
    };
  }
}
