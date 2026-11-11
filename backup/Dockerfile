ARG POSTGRES_MAJOR=18
FROM postgres:${POSTGRES_MAJOR}-alpine
# tzdata: agendamento no fuso America/Sao_Paulo; openssl+rclone: cópia externa criptografada (opcional)
RUN apk add --no-cache tzdata openssl rclone \
 && mkdir -p /backups/daily /backups/weekly /backups/monthly \
 && chown -R postgres:postgres /backups
COPY --chmod=0755 backup.sh backup-loop.sh restore-check.sh external-copy.sh /usr/local/bin/
USER postgres
VOLUME /backups
ENTRYPOINT []
CMD ["backup-loop.sh"]
