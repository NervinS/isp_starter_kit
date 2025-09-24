import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, Index } from 'typeorm';

@Entity({ name: 'app_users' })
export class AppUser {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index({ unique: true })
  @Column({ type: 'varchar', length: 80 })
  username: string;

  @Column({ type: 'text', name: 'pass_hash' })
  passHash: string;

  @Column({ type: 'text', array: true, default: '{}' })
  roles: string[];

  @CreateDateColumn({ type: 'timestamptz' })
  created_at: Date;
}
