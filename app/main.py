import socket

import io

import os
from contextlib import contextmanager
from functools import wraps

import urllib3
from minio import Minio
from minio.error import S3Error

import json
import redis
import time
import psycopg2
import psycopg2.errors
from flask import (Flask, flash, jsonify, redirect, render_template, request,
                   session, url_for, Response, abort)
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.secret_key = os.environ["SECRET_KEY"]

MAX_UPLOAD_MB = 5
app.config["MAX_CONTENT_LENGTH"] = MAX_UPLOAD_MB * 1024 * 1024


@app.errorhandler(413)
def upload_too_large(e):
    flash(f"La imagen supera el máximo de {MAX_UPLOAD_MB} MB.")
    return redirect(url_for("index"))

INSTANCE_NAME = os.environ.get("INSTANCE_NAME", socket.gethostname())
APP_ENV = os.environ.get("APP_ENV", "dev")

@app.context_processor
def inject_instance():
    # Hace disponibles estas variables en TODAS las plantillas
    return {"instance_name": INSTANCE_NAME, "app_env": APP_ENV}

@app.after_request
def add_instance_header(response):
    # Cabecera HTTP útil para comprobar el reparto con curl
    response.headers["X-Served-By"] = INSTANCE_NAME
    return response


# --- Almacenamiento de imágenes (MinIO) ---
MINIO_ENDPOINT = os.environ.get("MINIO_ENDPOINT", "")
MINIO_BUCKET = os.environ.get("MINIO_BUCKET", "game-images")

minio_client = None
if MINIO_ENDPOINT:
    minio_client = Minio(
        MINIO_ENDPOINT,
        access_key=os.environ["MINIO_ACCESS_KEY"],
        secret_key=os.environ["MINIO_SECRET_KEY"],
        secure=False,  # red interna aislada: no hace falta TLS
        region="us-east-1",
        http_client=urllib3.PoolManager(     # Timeouts cortos: si MinIO cae, la web no se queda colgada
            timeout=urllib3.Timeout(connect=2, read=5),
            retries=urllib3.Retry(total=1, backoff_factor=0.1),
        ),
    )


def fetch_image(object_name):
    response = minio_client.get_object(MINIO_BUCKET, object_name)
    try:
        return response.read()
    finally:
        response.close()
        response.release_conn()

# Tipos permitidos: extensión -> (firma de los primeros bytes, tipo MIME)
IMAGE_TYPES = {
    "jpg": (b"\xff\xd8\xff", "image/jpeg"),
    "png": (b"\x89PNG\r\n\x1a\n", "image/png"),
}


def detect_image_type(data):
    """Mira los primeros bytes del fichero, no el nombre que manda el navegador."""
    for ext, (magic, mime) in IMAGE_TYPES.items():
        if data.startswith(magic):
            return ext, mime
    return None, None


def store_image(game_id, data, ext, mime):
    """Sube la imagen a MinIO. Devuelve True/False y nunca lanza excepción."""
    if minio_client is None:
        return False
    try:
        minio_client.put_object(
            MINIO_BUCKET,
            f"game-{game_id}.{ext}",      # el nombre lo decidimos nosotros
            io.BytesIO(data),
            length=len(data),
            content_type=mime,
        )
        return True
    except Exception as e:
        app.logger.error("No se pudo subir la imagen del juego %s: %s", game_id, e)
        return False

@app.route("/images/<int:game_id>")
def game_image(game_id):
    if minio_client is None:
        abort(404)

    # Orden de búsqueda: imagen JPG del juego, PNG del juego, imagen por defecto
    candidates = (
        (f"game-{game_id}.jpg", "image/jpeg"),
        (f"game-{game_id}.png", "image/png"),
        ("default.jpg", "image/jpeg"),
    )

    data = mimetype = None
    for name, mime in candidates:
        try:
            data = fetch_image(name)
            mimetype = mime
            break
        except S3Error as e:
            if e.code == "NoSuchKey":
                continue
            app.logger.error("MinIO error al pedir %s: %s", name, e)
            abort(502)
        except Exception as e:
            app.logger.error("MinIO no disponible: %s", e)
            abort(503)  # MinIO no responde

    if data is None:
        abort(404)

    response = Response(data, mimetype=mimetype)
    # Caché corta: una imagen recién subida debe verse pronto
    response.headers["Cache-Control"] = "public, max-age=60"
    return response

    
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "db"),
    "dbname": os.environ["POSTGRES_DB"],
    "user": os.environ["POSTGRES_USER"],
    "password": os.environ["POSTGRES_PASSWORD"],
    "connect_timeout": 2,
}

CACHE_ENABLED = os.environ.get("CACHE_ENABLED", "false").lower() == "true"
CACHE_TTL = int(os.environ.get("CACHE_TTL", "30"))
TOP_KEY = "ranking:top5"

cache = None
if CACHE_ENABLED:
    cache = redis.Redis(
        host=os.environ.get("REDIS_HOST", "cache"),
        port=6379,
        password=os.environ.get("REDIS_PASSWORD") or None,
        decode_responses=True,
        socket_connect_timeout=1,
        socket_timeout=1,
    )

@contextmanager
def db():
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        with conn:
            with conn.cursor() as cur:
                yield cur
    finally:
        conn.close()


def check_db():
    try:
        with db() as cur:
            cur.execute("SELECT 1")
        return True
    except psycopg2.Error:
        return False

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if "user_id" not in session:
            flash("Inicia sesión para hacer eso.")
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped

def top5_from_db():
    with db() as cur:
        cur.execute("""
            SELECT g.name, COUNT(v.id) AS votes
            FROM games g
            LEFT JOIN votes v ON v.game_id = g.id
            GROUP BY g.id, g.name
            ORDER BY votes DESC, g.name
            LIMIT 5
        """)
        return [{"name": r[0], "votes": r[1]} for r in cur.fetchall()]


def get_top5():
    """Devuelve (filas, origen, milisegundos). Origen: 'cache' o 'db'."""
    start = time.perf_counter()
    rows, source = None, "db"

    if cache is not None:
        try:
            raw = cache.get(TOP_KEY)
            if raw is not None:
                rows, source = json.loads(raw), "cache"
        except redis.RedisError:
            pass

    if rows is None:
        rows = top5_from_db()
        if cache is not None:
            try:
                cache.setex(TOP_KEY, CACHE_TTL, json.dumps(rows))
            except redis.RedisError:
                pass

    elapsed = round((time.perf_counter() - start) * 1000, 1)
    return rows, source, elapsed


def invalidate_cache():
    if cache is not None:
        try:
            cache.delete(TOP_KEY)
        except redis.RedisError:
            pass


def cache_state():
    if cache is None:
        return "disabled"
    try:
        cache.ping()
        return "up"
    except redis.RedisError:
        return "down"

@app.get("/")
def index():
    games, voted, db_error = [], set(), False
    top, source, elapsed = [], None, None       
    try:
        top, source, elapsed = get_top5()     
        with db() as cur:
            cur.execute("""
                SELECT g.id, g.name, COUNT(v.id) AS votes
                FROM games g
                LEFT JOIN votes v ON v.game_id = g.id
                GROUP BY g.id, g.name
                ORDER BY votes DESC, g.name
            """)
            games = cur.fetchall()
            if "user_id" in session:
                cur.execute(
                    "SELECT game_id FROM votes WHERE user_id = %s",
                    (session["user_id"],),
                )
                voted = {r[0] for r in cur.fetchall()}
    except psycopg2.Error:
        db_error = True
    return render_template("index.html", games=games, voted=voted, db_error=db_error,
                           top=top, source=source, elapsed=elapsed)


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        if not 3 <= len(username) <= 30 or len(password) < 6:
            flash("El usuario debe tener de 3 a 30 caracteres y la contraseña al menos 6.")
            return render_template("register.html")

        try:
            with db() as cur:
                cur.execute(
                    "INSERT INTO users (username, password_hash) VALUES (%s, %s)",
                    (username, generate_password_hash(password)),
                )
        except psycopg2.errors.UniqueViolation:
            flash("Ese nombre de usuario ya existe.")
            return render_template("register.html")
        except psycopg2.Error:
            flash("La base de datos no está disponible.")
            return render_template("register.html")

        flash("Cuenta creada. Ya puedes iniciar sesión.")
        return redirect(url_for("login"))

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        try:
            with db() as cur:
                cur.execute(
                    "SELECT id, password_hash FROM users WHERE username = %s",
                    (username,),
                )
                row = cur.fetchone()
        except psycopg2.Error:
            flash("La base de datos no está disponible.")
            return render_template("login.html")

        if row is None or not check_password_hash(row[1], password):
            flash("Usuario o contraseña incorrectos.")
            return render_template("login.html")

        session.clear()
        session["user_id"] = row[0]
        session["username"] = username
        flash(f"Bienvenido, {username}.")
        return redirect(url_for("index"))

    return render_template("login.html")


@app.post("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada.")
    return redirect(url_for("index"))


@app.post("/games")
@login_required
def add_game():
    name = request.form.get("name", "").strip()
    if not 1 <= len(name) <= 60:
        flash("El nombre debe tener entre 1 y 60 caracteres.")
        return redirect(url_for("index"))

    # Imagen opcional: se valida ANTES de tocar la base de datos
    image = request.files.get("image")
    image_data = ext = mime = None
    if image and image.filename:
        image_data = image.read()
        ext, mime = detect_image_type(image_data)
        if ext is None:
            flash("La imagen debe ser un JPG o PNG válido.")
            return redirect(url_for("index"))

    try:
        with db() as cur:
            # RETURNING id nos da el id del juego recién creado (nada si ya existía)
            cur.execute(
                "INSERT INTO games (name) VALUES (%s) "
                "ON CONFLICT (name) DO NOTHING RETURNING id",
                (name,),
            )
            row = cur.fetchone()
    except psycopg2.Error:
        flash("La base de datos no está disponible.")
        return redirect(url_for("index"))

    if row is None:
        flash("Ese videojuego ya estaba en la lista.")
        return redirect(url_for("index"))

    invalidate_cache()
    if image_data is None:
        flash("Videojuego añadido.")
    elif store_image(row[0], image_data, ext, mime):
        flash("Videojuego añadido con su imagen.")
    else:
        flash("Videojuego añadido, pero no se pudo guardar la imagen.")
    return redirect(url_for("index"))


@app.post("/games/<int:game_id>/vote")
@login_required
def vote(game_id):
    try:
        with db() as cur:
            cur.execute(
                "INSERT INTO votes (user_id, game_id) VALUES (%s, %s) "
                "ON CONFLICT (user_id, game_id) DO NOTHING",
                (session["user_id"], game_id),
            )
            counted = cur.rowcount == 1
    except psycopg2.errors.ForeignKeyViolation:
        flash("Ese videojuego no existe.")
        return redirect(url_for("index"))
    except psycopg2.Error:
        flash("La base de datos no está disponible.")
        return redirect(url_for("index"))
    if counted:
        invalidate_cache()
    flash("Voto registrado." if counted else "Ya habías votado ese videojuego.")
    return redirect(url_for("index"))


@app.get("/status")
def status():
    db_ok = check_db()
    cache_s = cache_state()

    if not db_ok:
        overall, code = "down", 503
    elif cache_s == "down":
        overall, code = "degraded", 200
    else:
        overall, code = "ok", 200

    return jsonify(status=overall, database="up" if db_ok else "down", cache=cache_s), code