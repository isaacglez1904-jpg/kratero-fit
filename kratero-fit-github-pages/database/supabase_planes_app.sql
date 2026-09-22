-- ============================================================
-- Kratero Fit — Planes de la app (Básico / Avanzado)
-- ------------------------------------------------------------
-- Pega este script en: Supabase → SQL Editor → New query → Run
-- Es idempotente: se puede correr varias veces sin duplicar nada.
-- Requiere que ya exista el esquema base (supabase_completo.sql)
-- y la actualización de pesos (supabase_actualizacion_pesos.sql).
--
-- OJO: esto es un plan NUEVO y distinto de la columna "plan" que
-- ya existe en profiles (esa es el plan de MEMBRESÍA del gym:
-- "Plan Básico" / "Plan Mensual" / "Pase Anual VIP", y la sigue
-- manejando admin-dashboard.html tal cual). Esta columna nueva,
-- "plan_app", controla qué SECCIONES ve el alumno dentro de la
-- app (Básico = solo lo esencial, Avanzado = todo).
-- ============================================================

-- ============================================================
-- PARTE 1: columna plan_app en profiles
-- ============================================================
alter table public.profiles
  add column if not exists plan_app text not null default 'basico';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_plan_app_check'
  ) then
    alter table public.profiles
      add constraint profiles_plan_app_check check (plan_app in ('basico', 'avanzado'));
  end if;
end $$;

-- ============================================================
-- PARTE 2: columna "origen" en rutinas
-- ------------------------------------------------------------
-- 'coach'  -> la creó el entrenador desde admin-rutinas.html (como hasta ahora)
-- 'propio' -> la creó el propio alumno desde su dashboard (plan Básico)
-- ============================================================
alter table public.rutinas
  add column if not exists origen text not null default 'coach';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'rutinas_origen_check'
  ) then
    alter table public.rutinas
      add constraint rutinas_origen_check check (origen in ('coach', 'propio'));
  end if;
end $$;

-- ============================================================
-- PARTE 3: el alumno puede crear/editar/borrar SUS PROPIOS
-- ejercicios (origen = 'propio'). Los que crea el coach
-- (origen = 'coach') siguen protegidos solo para admin/coach,
-- las políticas de la PARTE A del script base no cambian.
-- ============================================================
drop policy if exists "rutinas_propio_insert" on public.rutinas;
create policy "rutinas_propio_insert"
  on public.rutinas for insert
  with check (user_id = auth.uid() and origen = 'propio');

drop policy if exists "rutinas_propio_update" on public.rutinas;
create policy "rutinas_propio_update"
  on public.rutinas for update
  using (user_id = auth.uid() and origen = 'propio');

drop policy if exists "rutinas_propio_delete" on public.rutinas;
create policy "rutinas_propio_delete"
  on public.rutinas for delete
  using (user_id = auth.uid() and origen = 'propio');

-- ============================================================
-- PARTE 4 (NUEVO): gif de referencia del ejercicio
-- ------------------------------------------------------------
-- Guarda el ID del ejercicio de la librería pública de gifs
-- (free-exercise-db, dominio público) para poder mostrar la
-- animación de referencia en la tarjeta del ejercicio.
-- ============================================================
alter table public.rutinas
  add column if not exists demo_ejercicio_id text;

-- ============================================================
-- Fin. Verifica en Supabase → Table Editor:
-- - profiles tiene la columna "plan_app" ('basico' por defecto)
-- - rutinas tiene la columna "origen" ('coach' por defecto)
-- Para subir a alguien a plan Avanzado a mano:
--   update public.profiles set plan_app = 'avanzado' where email = 'correo@ejemplo.com';
-- (o hazlo desde admin-dashboard.html una vez actualizado ese panel)
-- ============================================================
