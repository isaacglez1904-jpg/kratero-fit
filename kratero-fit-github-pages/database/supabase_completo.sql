-- ============================================================
-- Kratero Fit — Esquema completo + Seguridad (RLS) para Supabase
-- ------------------------------------------------------------
-- Pega este script completo en: Supabase → SQL Editor → New query → Run
-- Es idempotente: lo puedes correr en un proyecto nuevo, o repetirlo
-- sobre uno existente, sin duplicar columnas, políticas ni triggers.
--
-- Este archivo consolida, EN ORDEN, los tres scripts que se fueron
-- aplicando por partes:
--   A) supabase_rls_v3.sql      -> esquema base + RLS (un solo admin)
--   B) supabase_multicoach.sql  -> soporte multi-coach (Frente 1)
--   C) supabase_cardio.sql      -> actividades de cardio estilo Strava
--
-- Requiere que ya existan (creadas por tu SQL original de tablas, antes
-- de v3) las tablas: profiles, rutinas, planes_nutricion, avances,
-- habitos, mensajes, anuncios. Este script solo agrega columnas,
-- funciones, triggers y políticas — no crea esas tablas desde cero.
-- ============================================================


-- ############################################################
-- PARTE A — ESQUEMA BASE Y RLS (antes: supabase_rls_v3.sql)
-- ############################################################

-- ============================================================
-- PARTE 0: columnas y restricciones que faltaban
-- ============================================================

-- anuncios: el formulario admin permite elegir categoría, pero la columna no existía
alter table public.anuncios
  add column if not exists categoria text default 'General';

-- rutinas: columnas que usan TANTO el panel del coach como el panel del alumno.
-- Ambos lados deben leer/escribir exactamente estos nombres.
alter table public.rutinas
  add column if not exists dia_semana   text,
  add column if not exists titulo       text,
  add column if not exists descripcion  text,
  add column if not exists video_url    text,
  add column if not exists series       integer default 4,
  add column if not exists repeticiones text default '10-12';

-- planes_nutricion: el panel del alumno lee titulo/carbos/detalles.
-- Se agregan aquí para que el panel del coach pueda escribir los mismos campos.
alter table public.planes_nutricion
  add column if not exists titulo    text default 'Plan Nutricional',
  add column if not exists calorias  integer default 0,
  add column if not exists proteinas numeric default 0,
  add column if not exists carbos    numeric default 0,
  add column if not exists grasas    numeric default 0,
  add column if not exists detalles  text;

-- Si tu base venía de una versión previa con nombres distintos, estas dos
-- migraciones copian los datos viejos a las columnas correctas (una sola vez).
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='planes_nutricion' and column_name='carbohidratos') then
    update public.planes_nutricion set carbos = carbohidratos where carbos is null or carbos = 0;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='planes_nutricion' and column_name='comidas') then
    update public.planes_nutricion set detalles = comidas where detalles is null;
  end if;
end $$;

-- avances: columnas que escribe el panel del alumno y lee el de monitoreo
alter table public.avances
  add column if not exists peso  numeric,
  add column if not exists grasa numeric,
  add column if not exists notas text;

-- mensajes: el chat usa sender_id/receiver_id en AMBOS paneles
alter table public.mensajes
  add column if not exists sender_id   uuid references public.profiles(id) on delete cascade,
  add column if not exists receiver_id uuid references public.profiles(id) on delete cascade,
  add column if not exists mensaje     text;

create index if not exists mensajes_conversacion_idx
  on public.mensajes (sender_id, receiver_id, created_at);

-- habitos: columnas de los 5 hábitos que marca el alumno cada día
alter table public.habitos
  add column if not exists fecha          date not null default current_date,
  add column if not exists agua           boolean default false,
  add column if not exists pasos          boolean default false,
  add column if not exists sueno          boolean default false,
  add column if not exists entrenamiento  boolean default false,
  add column if not exists dieta          boolean default false;

-- habitos: el dashboard hace upsert con onConflict: 'user_id,fecha' → requiere unicidad
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'habitos_user_fecha_unique') then
    alter table public.habitos add constraint habitos_user_fecha_unique unique (user_id, fecha);
  end if;
end $$;

-- planes_nutricion: admin-nutricion.html hace upsert con onConflict: 'user_id' → requiere unicidad
-- (un plan nutricional por usuario)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'planes_nutricion_user_unique') then
    alter table public.planes_nutricion add constraint planes_nutricion_user_unique unique (user_id);
  end if;
end $$;

-- ============================================================
-- PARTE 1: función auxiliar — ¿el usuario logueado es admin?
-- SECURITY DEFINER evita la "recursión infinita" al consultar
-- la tabla profiles desde sus propias políticas.
-- ============================================================
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and rol = 'admin'
  );
$$;

-- ============================================================
-- PARTE 1B (NUEVO): creación automática de perfil al registrarse
-- ------------------------------------------------------------
-- Antes, registro.html insertaba en "profiles" desde el navegador
-- justo después de signUp(). Si tu proyecto tiene activada la
-- confirmación por correo, en ese momento todavía NO hay sesión
-- activa, así que auth.uid() es null y la política RLS rechaza
-- el insert -> el usuario queda creado en Auth pero SIN perfil,
-- y luego ni el login funciona (busca el perfil y no existe).
--
-- Este trigger corre en el servidor con permisos elevados
-- (SECURITY DEFINER) apenas se crea el usuario en auth.users,
-- sin depender de que haya sesión ni de las políticas RLS.
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nombre, email, rol, plan)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', ''),
    new.email,
    'usuario',
    'Plan Básico'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- PARTE 2: PROFILES
-- ============================================================
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (id = auth.uid());

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin());

-- ============================================================
-- PARTE 3: RUTINAS
-- ============================================================
alter table public.rutinas enable row level security;

drop policy if exists "rutinas_select_own_or_admin" on public.rutinas;
create policy "rutinas_select_own_or_admin"
  on public.rutinas for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "rutinas_admin_insert" on public.rutinas;
create policy "rutinas_admin_insert"
  on public.rutinas for insert
  with check (public.is_admin());

drop policy if exists "rutinas_admin_update" on public.rutinas;
create policy "rutinas_admin_update"
  on public.rutinas for update
  using (public.is_admin());

drop policy if exists "rutinas_admin_delete" on public.rutinas;
create policy "rutinas_admin_delete"
  on public.rutinas for delete
  using (public.is_admin());

-- ============================================================
-- PARTE 4: PLANES_NUTRICION
-- ============================================================
alter table public.planes_nutricion enable row level security;

drop policy if exists "nutricion_select_own_or_admin" on public.planes_nutricion;
create policy "nutricion_select_own_or_admin"
  on public.planes_nutricion for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "nutricion_admin_insert" on public.planes_nutricion;
create policy "nutricion_admin_insert"
  on public.planes_nutricion for insert
  with check (public.is_admin());

drop policy if exists "nutricion_admin_update" on public.planes_nutricion;
create policy "nutricion_admin_update"
  on public.planes_nutricion for update
  using (public.is_admin());

drop policy if exists "nutricion_admin_delete" on public.planes_nutricion;
create policy "nutricion_admin_delete"
  on public.planes_nutricion for delete
  using (public.is_admin());

-- ============================================================
-- PARTE 5: AVANCES
-- ============================================================
alter table public.avances enable row level security;

drop policy if exists "avances_select_own_or_admin" on public.avances;
create policy "avances_select_own_or_admin"
  on public.avances for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "avances_insert_own" on public.avances;
create policy "avances_insert_own"
  on public.avances for insert
  with check (user_id = auth.uid());

-- ============================================================
-- PARTE 6: HABITOS
-- ============================================================
alter table public.habitos enable row level security;

drop policy if exists "habitos_select_own_or_admin" on public.habitos;
create policy "habitos_select_own_or_admin"
  on public.habitos for select
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "habitos_insert_own" on public.habitos;
create policy "habitos_insert_own"
  on public.habitos for insert
  with check (user_id = auth.uid());

drop policy if exists "habitos_update_own" on public.habitos;
create policy "habitos_update_own"
  on public.habitos for update
  using (user_id = auth.uid());

-- ============================================================
-- PARTE 7: MENSAJES (chat usuario ↔ coach)
-- ============================================================
alter table public.mensajes enable row level security;

drop policy if exists "mensajes_select_participant" on public.mensajes;
create policy "mensajes_select_participant"
  on public.mensajes for select
  using (sender_id = auth.uid() or receiver_id = auth.uid());

drop policy if exists "mensajes_insert_as_self" on public.mensajes;
create policy "mensajes_insert_as_self"
  on public.mensajes for insert
  with check (sender_id = auth.uid());

-- NUEVO: columna "leido" para el punto rojo de mensajes no leídos en el dashboard.
-- Solo quien RECIBIÓ el mensaje puede marcarlo como leído (no el que lo envió).
alter table public.mensajes
  add column if not exists leido boolean default false;

drop policy if exists "mensajes_update_leido_receptor" on public.mensajes;
create policy "mensajes_update_leido_receptor"
  on public.mensajes for update
  using (receiver_id = auth.uid())
  with check (receiver_id = auth.uid());

-- ============================================================
-- PARTE 8: ANUNCIOS
-- ============================================================
alter table public.anuncios enable row level security;

drop policy if exists "anuncios_select_authenticated" on public.anuncios;
create policy "anuncios_select_authenticated"
  on public.anuncios for select
  using (auth.role() = 'authenticated');

drop policy if exists "anuncios_admin_insert" on public.anuncios;
create policy "anuncios_admin_insert"
  on public.anuncios for insert
  with check (public.is_admin());

drop policy if exists "anuncios_admin_delete" on public.anuncios;
create policy "anuncios_admin_delete"
  on public.anuncios for delete
  using (public.is_admin());

-- ============================================================
-- PARTE 9 (NUEVO): recuperar tu cuenta y dejarla como admin
-- ------------------------------------------------------------
-- Tu usuario ya existe en auth.users (isaacglez1904@gmail.com)
-- pero se quedó sin fila en profiles por el error de RLS.
-- Esto la crea (o la actualiza si el trigger ya la creó) y la
-- marca como admin.
-- ============================================================
insert into public.profiles (id, nombre, email, rol, plan, edad, peso, estatura, nivel_actividad)
select id, 'Isaac González', email, 'admin', 'Plan Básico', 22, 77, 177, 'Moderado'
from auth.users
where email = 'isaacglez1904@gmail.com'
on conflict (id) do update set rol = 'admin';

-- ============================================================
-- Fin. Verifica en Supabase → Authentication → Policies que las
-- 7 tablas muestren "RLS enabled" y las políticas aquí creadas.
-- Verifica también en Database → Functions y Database → Triggers
-- que "handle_new_user" y "on_auth_user_created" aparezcan.
-- ============================================================



-- ############################################################
-- PARTE B — MULTI-COACH (antes: supabase_multicoach.sql)
-- ############################################################

-- ============================================================
-- PARTE 1: columna coach_id en profiles y anuncios
-- ============================================================
alter table public.profiles
  add column if not exists coach_id uuid references public.profiles(id);

alter table public.anuncios
  add column if not exists coach_id uuid references public.profiles(id);
-- coach_id = null  -> anuncio global (solo lo publica el admin dueño)
-- coach_id = <id>  -> solo lo ven los alumnos de ESE coach

-- ============================================================
-- PARTE 2: funciones auxiliares
-- ============================================================

-- ¿Soy coach?
create or replace function public.is_coach()
returns boolean
language sql security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and rol = 'coach');
$$;

-- ¿El perfil "target" es alumno mío (coach logueado)?
create or replace function public.is_my_student(target uuid)
returns boolean
language sql security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = target and coach_id = auth.uid());
$$;

-- Mi coach asignado (si soy alumno)
create or replace function public.get_my_coach_id()
returns uuid
language sql security definer set search_path = public
as $$
  select coach_id from public.profiles where id = auth.uid();
$$;

-- ¿Puedo gestionar (ver/asignar/editar) los datos de este alumno?
-- Admin dueño: todos. Coach: solo los suyos.
create or replace function public.puede_gestionar_alumno(target uuid)
returns boolean
language sql security definer set search_path = public
as $$
  select public.is_admin() or public.is_my_student(target);
$$;

-- ============================================================
-- PARTE 3: PROFILES — quién puede ver a quién
-- ============================================================
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_select_policy" on public.profiles;
create policy "profiles_select_policy"
  on public.profiles for select
  using (
    id = auth.uid()                 -- yo mismo
    or public.is_admin()            -- el admin dueño ve todo
    or rol in ('admin', 'coach')    -- cualquiera puede ver el directorio de coaches (para el selector de registro y el chat)
    or public.is_my_student(id)     -- un coach ve a sus propios alumnos
  );

-- El update de rol/plan/coach_id sigue reservado a: uno mismo (sus propios
-- datos físicos) o el admin dueño (gestión de cuentas). Los coaches NO
-- deben poder cambiar roles ni reasignarse alumnos por su cuenta.
drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin());

-- ============================================================
-- PARTE 4: RUTINAS — admin o coach dueño del alumno
-- ============================================================
drop policy if exists "rutinas_select_own_or_admin" on public.rutinas;
create policy "rutinas_select_own_or_admin"
  on public.rutinas for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

drop policy if exists "rutinas_admin_insert" on public.rutinas;
create policy "rutinas_admin_insert"
  on public.rutinas for insert
  with check (public.puede_gestionar_alumno(user_id));

drop policy if exists "rutinas_admin_update" on public.rutinas;
create policy "rutinas_admin_update"
  on public.rutinas for update
  using (public.puede_gestionar_alumno(user_id));

drop policy if exists "rutinas_admin_delete" on public.rutinas;
create policy "rutinas_admin_delete"
  on public.rutinas for delete
  using (public.puede_gestionar_alumno(user_id));

-- ============================================================
-- PARTE 5: PLANES_NUTRICION — mismo criterio
-- ============================================================
drop policy if exists "nutricion_select_own_or_admin" on public.planes_nutricion;
create policy "nutricion_select_own_or_admin"
  on public.planes_nutricion for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

drop policy if exists "nutricion_admin_insert" on public.planes_nutricion;
create policy "nutricion_admin_insert"
  on public.planes_nutricion for insert
  with check (public.puede_gestionar_alumno(user_id));

drop policy if exists "nutricion_admin_update" on public.planes_nutricion;
create policy "nutricion_admin_update"
  on public.planes_nutricion for update
  using (public.puede_gestionar_alumno(user_id));

drop policy if exists "nutricion_admin_delete" on public.planes_nutricion;
create policy "nutricion_admin_delete"
  on public.planes_nutricion for delete
  using (public.puede_gestionar_alumno(user_id));

-- ============================================================
-- PARTE 6: AVANCES y HABITOS — el coach dueño ahora puede
-- consultarlos (monitoreo), pero solo el alumno los crea/edita.
-- ============================================================
drop policy if exists "avances_select_own_or_admin" on public.avances;
create policy "avances_select_own_or_admin"
  on public.avances for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

drop policy if exists "habitos_select_own_or_admin" on public.habitos;
create policy "habitos_select_own_or_admin"
  on public.habitos for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

-- ============================================================
-- PARTE 7: MENSAJES — separación estricta entre coaches
-- ------------------------------------------------------------
-- Un alumno solo puede escribirle a SU coach asignado.
-- Un coach solo puede escribirle a SUS alumnos.
-- El admin dueño puede ver todo (supervisor) pero esto no da pie
-- a que un coach vea los mensajes de otro coach.
-- ============================================================
drop policy if exists "mensajes_select_participant" on public.mensajes;
create policy "mensajes_select_participant"
  on public.mensajes for select
  using (sender_id = auth.uid() or receiver_id = auth.uid() or public.is_admin());

drop policy if exists "mensajes_insert_as_self" on public.mensajes;
create policy "mensajes_insert_as_self"
  on public.mensajes for insert
  with check (
    sender_id = auth.uid()
    and (
      receiver_id = public.get_my_coach_id()   -- alumno -> su coach
      or public.is_my_student(receiver_id)     -- coach -> su alumno
      or public.is_admin()                     -- admin dueño, sin restricción
    )
  );

-- ============================================================
-- PARTE 8: ANUNCIOS — globales (admin) o por coach
-- ============================================================
drop policy if exists "anuncios_select_authenticated" on public.anuncios;
create policy "anuncios_select_authenticated"
  on public.anuncios for select
  using (
    auth.role() = 'authenticated'
    and (
      coach_id is null                       -- anuncio global, todos lo ven
      or coach_id = auth.uid()                -- el propio coach ve lo que publicó
      or coach_id = public.get_my_coach_id()  -- el alumno ve lo de su coach
      or public.is_admin()
    )
  );

drop policy if exists "anuncios_admin_insert" on public.anuncios;
create policy "anuncios_admin_insert"
  on public.anuncios for insert
  with check (
    (coach_id is null and public.is_admin())
    or (coach_id = auth.uid() and public.is_coach())
  );

drop policy if exists "anuncios_admin_delete" on public.anuncios;
create policy "anuncios_admin_delete"
  on public.anuncios for delete
  using (public.is_admin() or (coach_id = auth.uid() and public.is_coach()));

-- ============================================================
-- PARTE 9: el trigger de registro ahora también guarda coach_id
-- (viene del metadata que manda registro.html en el signUp)
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, nombre, email, rol, plan, coach_id)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', ''),
    new.email,
    'usuario',
    'Plan Básico',
    nullif(new.raw_user_meta_data->>'coach_id', '')::uuid
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
-- (el trigger on_auth_user_created ya apunta a esta función, no hay que recrearlo)

-- ============================================================
-- Fin Frente 1. Verifica en Supabase → Table Editor → profiles
-- que exista la columna coach_id, y en Authentication → Policies
-- que las políticas de arriba se hayan actualizado.
-- ============================================================



-- ############################################################
-- PARTE C — CARDIO ESTILO STRAVA (antes: supabase_cardio.sql)
-- ############################################################

create extension if not exists pgcrypto;

-- ============================================================
-- PARTE 1: tabla de actividades de cardio
-- ============================================================
create table if not exists public.actividades_cardio (
  id                     uuid primary key default gen_random_uuid(),
  user_id                uuid not null references public.profiles(id) on delete cascade,
  tipo                   text not null check (tipo in ('running', 'caminata')),
  distancia_km           numeric not null default 0,
  duracion_segundos      integer not null default 0,
  ritmo_promedio_seg_km  numeric,              -- segundos por km (null si la distancia fue insuficiente)
  calorias_estimadas     integer,              -- estimación por fórmula MET, no es un dato clínico
  ruta                   jsonb,                -- arreglo de puntos GPS: [{ "lat": .., "lng": .. }, ...]
  created_at             timestamptz not null default now()
);

create index if not exists actividades_cardio_user_id_idx
  on public.actividades_cardio (user_id, created_at desc);

alter table public.actividades_cardio enable row level security;

-- ============================================================
-- PARTE 2: RLS — mismo criterio que avances/habitos:
-- el propio alumno gestiona sus actividades; su coach (o el admin
-- dueño) puede consultarlas para monitoreo, pero no crearlas/editarlas.
-- ============================================================
drop policy if exists "cardio_select_own_or_admin" on public.actividades_cardio;
create policy "cardio_select_own_or_admin"
  on public.actividades_cardio for select
  using (user_id = auth.uid() or public.puede_gestionar_alumno(user_id));

drop policy if exists "cardio_insert_own" on public.actividades_cardio;
create policy "cardio_insert_own"
  on public.actividades_cardio for insert
  with check (user_id = auth.uid());

drop policy if exists "cardio_delete_own" on public.actividades_cardio;
create policy "cardio_delete_own"
  on public.actividades_cardio for delete
  using (user_id = auth.uid());

-- No se habilita UPDATE a propósito: una actividad ya guardada se borra
-- y se vuelve a registrar si hace falta corregirla, en vez de editarse.

-- ============================================================
-- Fin. Verifica en Supabase → Table Editor que exista
-- actividades_cardio y que las políticas RLS se hayan creado.
-- ============================================================


-- ============================================================
-- Fin del script consolidado. Verifica en Supabase:
--   Database → Tables       -> profiles tiene coach_id;
--                               existe actividades_cardio
--   Database → Functions    -> is_admin, is_coach, is_my_student,
--                               get_my_coach_id, puede_gestionar_alumno,
--                               handle_new_user
--   Database → Triggers     -> on_auth_user_created
--   Authentication→Policies -> las 8 tablas (profiles, rutinas,
--                               planes_nutricion, avances, habitos,
--                               mensajes, anuncios, actividades_cardio)
--                               muestran "RLS enabled" con sus políticas
-- ============================================================


-- ############################################################
-- PARTE D — TRANSFORMACIONES (fotos antes/después en la portada)
-- ############################################################
-- Alimenta la sección "Cambios de nuestros atletas" de index.html.
-- IMPORTANTE: index.html es una página pública (sin login), por eso esta
-- tabla es la ÚNICA con lectura anónima, y solo de las filas publicadas.
-- ============================================================

create table if not exists public.transformaciones (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references public.profiles(id) on delete set null,
  nombre        text not null,                 -- nombre o alias que se muestra en la portada
  foto_antes    text,                          -- URL pública de la foto "antes"
  foto_despues  text,                          -- URL pública de la foto "después"
  peso_inicial  numeric,
  peso_final    numeric,
  meses         integer,                       -- duración del proceso
  testimonio    text,
  orden         integer not null default 0,    -- para controlar el orden en la portada
  publicado     boolean not null default false,-- nada se muestra hasta que lo apruebes
  created_at    timestamptz not null default now()
);

create index if not exists transformaciones_publicado_idx
  on public.transformaciones (publicado, orden);

alter table public.transformaciones enable row level security;

-- Lectura pública SOLO de las transformaciones ya publicadas (para la portada)
drop policy if exists "transformaciones_select_publicas" on public.transformaciones;
create policy "transformaciones_select_publicas"
  on public.transformaciones for select
  using (publicado = true or public.is_admin());

-- Solo el admin dueño crea, edita y borra transformaciones
drop policy if exists "transformaciones_admin_insert" on public.transformaciones;
create policy "transformaciones_admin_insert"
  on public.transformaciones for insert
  with check (public.is_admin());

drop policy if exists "transformaciones_admin_update" on public.transformaciones;
create policy "transformaciones_admin_update"
  on public.transformaciones for update
  using (public.is_admin());

drop policy if exists "transformaciones_admin_delete" on public.transformaciones;
create policy "transformaciones_admin_delete"
  on public.transformaciones for delete
  using (public.is_admin());

-- ============================================================
-- Storage: bucket público para las fotos de transformaciones.
-- Crea el bucket "transformaciones" en Supabase → Storage y márcalo
-- como público; luego pega aquí las URLs en foto_antes / foto_despues.
-- ============================================================
insert into storage.buckets (id, name, public)
values ('transformaciones', 'transformaciones', true)
on conflict (id) do nothing;

drop policy if exists "transformaciones_storage_lectura_publica" on storage.objects;
create policy "transformaciones_storage_lectura_publica"
  on storage.objects for select
  using (bucket_id = 'transformaciones');

drop policy if exists "transformaciones_storage_admin_escribe" on storage.objects;
create policy "transformaciones_storage_admin_escribe"
  on storage.objects for insert
  with check (bucket_id = 'transformaciones' and public.is_admin());

drop policy if exists "transformaciones_storage_admin_borra" on storage.objects;
create policy "transformaciones_storage_admin_borra"
  on storage.objects for delete
  using (bucket_id = 'transformaciones' and public.is_admin());

-- ############################################################
-- PARTE D — REGISTRO DE PESOS POR EJERCICIO (antes: supabase_actualizacion_pesos.sql)
-- ############################################################

-- Columna en "rutinas": permite marcar qué ejercicios sí necesitan que el
-- alumno registre peso (unos son con pesas, otros son de peso corporal,
-- cardio, movilidad, etc.)
alter table public.rutinas
  add column if not exists requiere_peso boolean not null default true;

-- Historial de pesos que el alumno va registrando cada vez que entrena
-- un ejercicio de su rutina.
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

-- Fin Parte D. Verifica en Supabase → Table Editor que exista "registro_pesos"
-- y que "rutinas" ya tenga la columna "requiere_peso".
