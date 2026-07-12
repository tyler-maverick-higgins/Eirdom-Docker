# Stateful storage and permissions

The database failures observed in the source archive were permission failures, not application failures:

- PostgreSQL could not read `global/pg_filenode.map`.
- Valkey could not create temporary RDB files in `/data`.
- Paperless followed its login redirect, touched PostgreSQL, returned HTTP 500, and its health check failed.

## Safe repair workflow

1. Stop the affected stack.
2. Record the bind mount sources with `docker inspect <container> --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'`.
3. Back up the directories before changing ownership.
4. Determine the image UID/GID rather than guessing:

```bash
docker run --rm --entrypoint id postgres:16-alpine postgres
docker run --rm --entrypoint id valkey/valkey:8-alpine valkey
```

5. Apply ownership only to the relevant database directory.
6. Start PostgreSQL/Valkey first and verify `pg_isready` / `valkey-cli ping`.
7. Start the application.

Do not initialize a new database over an existing directory and do not delete `global/pg_filenode.map`.
