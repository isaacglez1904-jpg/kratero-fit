-- ============================================================
-- Kratero Fit — Registro de pesos por ejercicio
-- ------------------------------------------------------------
-- Pega este script en: Supabase → SQL Editor → New query → Run
-- Es idempotente: se puede correr varias veces sin duplicar nada.
-- Requiere que ya exista el esquema base (supabase_completo.sql).
-- ============================================================

-- 1) Nueva columna en "rutinas": permite marcar qué ejercicios sí
--    necesitan que el alumno registre peso (unos son con pesas,
--    otros son de peso corporal, cardio, movilidad, etc.)
alter table public.rutinas
  add column if not exists requiere_peso boolean not null default true;

-- 2) Nueva tabla: historial de pesos que el alumno va registrando
--    cada vez que entrena un ejercicio de su rutina.
create table if not exists public.registro_pesos (
  id                      uuid primary key default gen_random_uuid(),
  rutina_id               uuid not null references public.rutinas(id) on delete cascade,
  user_id                 uuid not null references public.profiles(id) on delete cascade,
  peso_kg                 numeric not null,
  series_completadas      integer,
  repeticiones_completadas text,
  notas                   text,
  created_at              timestamptz not null default now()
);

create index if not exists registro_pesos_rutina_idx on public.registro_pesos (rutina_id, created_at desc);
create index if not exists registro_pesos_user_idx   on public.registro_pesos (user_id, created_at desc);

alter table public.registro_pesos enable row level security;

-- El alumno ve y guarda su propio historial.
drop policy if exists "registro_pesos_propio_select" on public.registro_pesos;
create policy "registro_pesos_propio_select"
  on public.registro_pesos for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

drop policy if exists "registro_pesos_propio_insert" on public.registro_pesos;
create policy "registro_pesos_propio_insert"
  on public.registro_pesos for insert
  with check (user_id = auth.uid());

drop policy if exists "registro_pesos_propio_delete" on public.registro_pesos;
create policy "registro_pesos_propio_delete"
  on public.registro_pesos for delete
  using (user_id = auth.uid());

-- Fin. Verifica en Supabase → Table Editor que exista "registro_pesos"
-- y que "rutinas" ya tenga la columna "requiere_peso".
