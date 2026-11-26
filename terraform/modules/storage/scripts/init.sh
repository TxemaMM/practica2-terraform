echo "Esperando a MinIO..."
until mc ready local >/dev/null 2>&1; do sleep 1; done

# 1. Bucket privado (sin acceso anónimo)
mc mb --ignore-existing "local/${BUCKET}"
mc anonymous set none "local/${BUCKET}"

# 2. Política de la aplicación: leer, subir y listar. NO borrar.
cat > /tmp/app-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::${BUCKET}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${BUCKET}"]
    }
  ]
}
EOF
mc admin policy create local "${BUCKET}-app" /tmp/app-policy.json

# 3. Usuario de la aplicación con la política nueva
mc admin user add local "${READER_USER}" "${READER_PASSWORD}"
mc admin policy attach local "${BUCKET}-app" --user "${READER_USER}" || echo "(la política ya estaba asignada)"

# 4. Subir las imágenes iniciales
mc mirror --overwrite /images "local/${BUCKET}"

echo "MinIO inicializado"