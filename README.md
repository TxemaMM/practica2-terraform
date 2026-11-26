# Práctica 2 · Terraform + Docker — Ranking de videojuegos

Aplicación web (Flask) para votar videojuegos, desplegada **entera con Terraform** sobre Docker en dos entornos independientes, **dev** y **prod**, que pueden convivir en la misma máquina.

- Balanceador **nginx** (round-robin) delante de varias réplicas de la web.
- **PostgreSQL** para usuarios, juegos y votos.
- **Redis** como caché del Top 5 (solo prod).
- **MinIO** (compatible S3) para las portadas de los juegos, con subida de imágenes desde la web.
- Monitorización con **cAdvisor + Prometheus** (métricas), **Alloy + Loki** (logs) y **Grafana** (dashboard y alertas por **Telegram** en prod).

## Arquitectura

```
                    localhost:8080 (dev) / 8081 (prod)
                               │
                    ┌──────────▼──────────┐   red frontend
                    │   nginx  (…-lb)     │
                    └──────────┬──────────┘   red backend (internal: sin salida ni puertos)
             ┌─────────────────┼─────────────────┐
        …-web-1            …-web-2          (…-web-3 en prod)     Flask + gunicorn
             └──────┬──────────┴───────┬─────────┘
             …-db (PostgreSQL)    …-minio (imágenes)    …-cache (Redis, solo prod)

   red monitoring:  cAdvisor ─► Prometheus ─┐
                    Alloy (logs Docker) ─► Loki ─┼─► Grafana (127.0.0.1:3000/3001) ─► Telegram (prod)
```

- Solo nginx publica puerto para la aplicación. Web, base de datos, MinIO y Redis están en una red `internal` y no son accesibles desde fuera.
- Grafana solo escucha en `127.0.0.1`, así que no es accesible desde la red.
- Todos los recursos llevan el prefijo `ranking-dev-` o `ranking-prod-`.

## Dev frente a prod

| | dev | prod |
|---|---|---|
| Réplicas web | 2 | 3 |
| Web | http://localhost:8080 | http://localhost:8081 |
| Grafana | http://localhost:3000 | http://localhost:3001 |
| Caché Redis | no | sí (TTL 60 s) |
| Alertas Telegram | no | sí |

## Estructura del repositorio

```
app/                      Aplicación Flask (Dockerfile, main.py, plantillas, CSS)
db/init.sql               Tablas y los 10 juegos iniciales
assets/images/            Portadas iniciales que se suben a MinIO
scripts/alerts.sh         Provoca y sigue en directo las alertas de Grafana
tests/smoke.sh            Pruebas de humo de un entorno desplegado
terraform/
  envs/dev, envs/prod     Un entorno por carpeta: llaman a los mismos módulos
  modules/
    database/             PostgreSQL + volumen + init.sql
    cache/                Redis con contraseña y límite de memoria
    storage/              MinIO + contenedor de inicialización (bucket, política, usuario)
    web/                  Build de la imagen y N réplicas (count)
    loadbalancer/         nginx generado desde plantilla
    monitoring/           cAdvisor, Prometheus, Loki, Alloy, Grafana y alertas
Makefile                  Atajos para desplegar, probar y destruir
```

## Requisitos

- Docker (el usuario tiene que poder usarlo sin `sudo`)
- Terraform ≥ 1.5
- `make`, `curl` y `python3` (este último solo para `scripts/alerts.sh`)
- Para `make alert-mem`: unos 1,8 GB de RAM libres

`make check` comprueba lo básico.

## Variables secretas

Las contraseñas **no están en el repositorio**. Antes de desplegar, cada entorno necesita su fichero `secrets.auto.tfvars`:

- `terraform/envs/dev/secrets.auto.tfvars`
- `terraform/envs/prod/secrets.auto.tfvars`

Terraform los carga automáticamente y están en `.gitignore`. El `Makefile` se niega a desplegar si falta el fichero.

**dev:**

```hcl
postgres_password      = "cambia-esto"
secret_key             = "cadena-larga-y-aleatoria"
minio_root_password    = "cambia-esto"   # mínimo 8 caracteres
minio_reader_password  = "cambia-esto"   # mínimo 8 caracteres
grafana_admin_password = "cambia-esto"
```

**prod:** las mismas variables, más estas:

```hcl
redis_password     = "cambia-esto"
telegram_bot_token = "123456:ABC..."     # token del bot (@BotFather)
telegram_chat_id   = "123456789"         # chat al que se envían las alertas
```

Notas:
- Una forma de generar `secret_key`: `python3 -c "import secrets; print(secrets.token_hex(32))"`
- Sin un bot de Telegram, pon valores cualquiera. Las alertas se verán igual en Grafana, solo fallará el envío del mensaje.
- Grafana solo usa `grafana_admin_password` la **primera vez** que arranca. Para cambiarla después hay que destruir el entorno o cambiarla desde Grafana.

Los valores no secretos (puertos, réplicas, usuarios) están en `terraform.tfvars` de cada entorno.

## Despliegue

```bash
make check        # requisitos
make up-dev       # despliega dev   (o make up para dev y prod)
make up-prod      # despliega prod
make urls         # muestra las URLs de la web y de Grafana
make status       # lista los contenedores
```

La primera vez tarda unos minutos, porque descarga las imágenes y construye la de la web. Terraform espera a que cada servicio esté sano (healthchecks) antes de crear el siguiente:

**redes → BD / MinIO (+ inicialización) / Redis → réplicas web → nginx**

Otros comandos: `make plan-dev`, `make plan-prod`, `make validate`, `make fmt` y `make help` para ver todos.

## Pruebas

```bash
make test-dev     # pruebas de humo de dev
make test-prod    # pruebas de humo de prod
make test-ha      # alta disponibilidad: para una réplica de prod, comprueba que la web sigue respondiendo y la recupera
```

`tests/smoke.sh` comprueba que:
- están todas las réplicas y ninguna está *unhealthy*;
- el balanceador responde;
- `/status` informa de la BD y de la caché esperada;
- el reparto llega a todas las réplicas (cabecera `X-Served-By`);
- las imágenes se sirven desde MinIO;
- Grafana responde.

## Alertas (prod)

Hay tres reglas, definidas como código en `terraform/modules/monitoring/templates/alert-rules.yml.tftpl`:

| Regla | Condición | Tiempo |
|---|---|---|
| Réplicas web caídas | menos réplicas web vivas de las esperadas | 30 s |
| CPU alta en contenedor | > 80 % de un núcleo | 1 min |
| Memoria alta en contenedor | > 1 GiB | 2 min |

Se pueden provocar de verdad y seguir su estado (Normal → Pending → Firing → Normal) desde la terminal:

```bash
make alerts           # estado actual de las reglas
make alert-cpu        # contenedor de estrés que gasta 1 núcleo
make alert-mem        # contenedor de estrés que reserva ~1,3 GB
make alert-replicas   # para ranking-prod-web-1 y luego la recupera
```

- Piden la contraseña del admin de Grafana, o la leen de la variable de entorno `GRAFANA_PASSWORD`.
- Cada prueba tarda unos 3-5 minutos, y envía a Telegram un aviso 🔴 ALERTA y después ✅ RESUELTA.
- El contenedor de estrés (`ranking-prod-stress`) no tiene red y se elimina al terminar, también si se interrumpe con Ctrl+C.

En Grafana: **Alerting → Alert rules → Alertas (prod)**.

## Monitorización

Grafana (usuario y contraseña de los tfvars/secretos) tiene el dashboard **Contenedores (dev/prod)** ya provisionado, con:
- contenedores activos y réplicas web activas;
- CPU y memoria por contenedor (Prometheus);
- líneas de log por minuto y los logs del entorno con buscador (Loki).

`make querys` muestra 5 consultas PromQL (Prometheus) y 5 LogQL (Loki) de ejemplo, ya preparadas para dev (`make querys ENTORNO=prod` para prod), con lo que hay que mirar en cada una. Se pegan en Grafana → **Explore**.

Cada entorno tiene su propia pila de monitorización:
- Prometheus guarda solo las métricas de su entorno, filtrando por prefijo (retención 3 días).
- Alloy envía a Loki solo los logs de los contenedores de su entorno (retención 72 h).

## Imágenes de los juegos

- Las portadas iniciales están en `assets/images/` con el nombre `game-<id>.jpg` (o `.png`), donde `<id>` es el id del juego en `db/init.sql`: 1 = Zelda BotW … 10 = Red Dead Redemption 2.
- `default.jpg` se usa cuando un juego no tiene portada.
- Al desplegar, un contenedor de inicialización las sube al bucket privado `game-images` de MinIO. Si cambian, se vuelven a subir en el siguiente `make up-*`.
- La web las sirve en `/images/<id>`, pidiéndolas a MinIO con un usuario que puede leer y subir, pero no borrar.
- Las que suben los usuarios al añadir un juego se guardan en el volumen de MinIO.

`make images` lista lo que hay en el bucket.

## Demostraciones útiles

- **Balanceo**: `curl -sI http://localhost:8080/ | grep X-Served-By` varias veces. También el texto «Servido por …» de la página indica qué réplica respondió.
- **Caché (prod)**: el Top 5 indica si se sirvió desde la caché o desde la BD, y cuánto tardó. Al votar se invalida.
- **Caída de una dependencia**:
  - `docker stop ranking-prod-cache`: la web sigue funcionando y `/status` dice `degraded`.
  - `docker stop ranking-dev-minio`: la web sigue y solo desaparecen las portadas (recarga con Ctrl+Shift+R; el navegador guarda las imágenes 60 s).
  - Vuelve a arrancarlos con `docker start`.
- **Logs centralizados**: en el dashboard, escribe `MinIO no disponible` en "Buscar en logs" después de parar MinIO.

## Destruir

```bash
make down-dev     # pide confirmación
make down-prod
make down         # los dos
```

`destroy` **borra también los volúmenes**: usuarios, votos, imágenes subidas, métricas y logs. Las imágenes Docker descargadas se conservan (`keep_locally`), así que el siguiente despliegue es más rápido.

