# Kratero Fit — listo para GitHub Pages

Esta carpeta ya está organizada tal como GitHub Pages la necesita:
todos los `.html`, iconos, `manifest.json` y `sw.js` están en la raíz
(no dentro de una subcarpeta `www/`), y se agregó el archivo `.nojekyll`
para que GitHub no intente procesar el sitio con Jekyll.

La carpeta `database/` trae tus 3 scripts SQL de Supabase, solo como
respaldo dentro del repositorio — GitHub Pages no los va a "servir"
como página, ahí solo quedan guardados.

## Cómo publicarlo (usando la web de GitHub, sin usar la terminal)

1. Entra a https://github.com/new y crea un repositorio nuevo.
   - Nombre sugerido: `kratero-fit`
   - Puede ser público o privado (Pages funciona en ambos si tienes
     cuenta Pro; con cuenta gratis el repo debe ser **público** para
     poder activar Pages).
   - NO marques "Add a README" (para evitar conflictos, ya traemos uno).

2. En la página del repo recién creado, busca el enlace
   "uploading an existing file" (o ve a Add file → Upload files).

3. Arrastra **todo el contenido de esta carpeta** (los archivos, no
   la carpeta en sí) a esa pantalla de subida. Espera a que termine
   de cargar y dale "Commit changes".

4. Ve a Settings → Pages (menú de la izquierda).
   - En "Source" elige la rama `main` y la carpeta `/ (root)`.
   - Dale "Save".

5. Espera 1-2 minutos y GitHub te va a mostrar la URL pública, algo así:
   `https://tu-usuario.github.io/kratero-fit/`

Esa es tu nueva URL. La app funciona igual que en Netlify: sigue
conectada a la misma base de datos de Supabase (las credenciales de
Supabase están dentro de los archivos HTML, no cambian con el hosting).

## Actualizar el sitio más adelante

Cada vez que yo te entregue una nueva versión de algún archivo,
solo tienes que volver a "Add file → Upload files" en el repo y subir
el archivo actualizado (GitHub te va a preguntar si quieres
reemplazar el existente — dile que sí).

## Nota sobre el dominio

Si más adelante quieres un dominio propio (ej. `kraterofit.com`) en
vez de `tu-usuario.github.io/kratero-fit`, se puede configurar desde
la misma pantalla de Settings → Pages → Custom domain. Avísame cuando
llegues a ese punto y te ayudo con esa parte.
