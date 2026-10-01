# Kratero Fit

App de entrenamiento con seguimiento de hábitos, nutrición, rutinas y cardio con GPS en vivo (estilo Strava), chat directo con el coach, y panel de administración.

## Estructura
- `index.html`, `login.html`, `registro.html` — páginas públicas
- `dashboard.html` — panel del alumno
- `admin-*.html` — panel del coach/admin (rutinas, nutrición, mensajes, monitoreo, transformaciones, anuncios)
- `perfil.html`, `recuperar-password.html`, `nueva-password.html` — cuenta
- `supabase_completo.sql` — esquema de base de datos y políticas RLS (idempotente, se puede correr varias veces)

## Backend
Supabase (Postgres + Auth + Storage). La URL y la anon key están en cada archivo HTML — es seguro tenerlas públicas, el acceso real lo controlan las políticas de Row Level Security definidas en `supabase_completo.sql`.

## Cómo correrlo localmente
No necesita build ni servidor especial: son archivos estáticos. Basta con abrirlos con un servidor local simple, por ejemplo:
```
npx serve .
```
