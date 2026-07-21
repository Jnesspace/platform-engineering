# examples — pick a scenario × a path

Common requests, each shown three ways. The module never changes; only who authors the call.

| I want... | A. Root config (dev) | B. Shopping list (GitOps) | C. Blueprint (form) |
|---|---|---|---|
| just an S3 bucket | [just-s3/](just-s3) | `object_storage` in `platform.yaml` | [`blueprints/object-storage.yaml`](../blueprints/object-storage.yaml) |
| just a Postgres DB | [just-database/](just-database) | `database` in `platform.yaml` | [`blueprints/database.yaml`](../blueprints/database.yaml) |
| a bucket + DB + secret | [s3-and-db/](s3-and-db) | [`jimmy-app/platform.yaml`](jimmy-app/platform.yaml) | [`blueprints/app.yaml`](../blueprints/app.yaml) |
| a full app repo | [jimmy-app/](jimmy-app) | `platform.yaml` + Dockerfile | [`blueprints/app.yaml`](../blueprints/app.yaml) |

**The through-line:** code doesn't disappear — *authorship moves*. Path A, every developer writes the module call (same as GitHub today). Path C, the platform team writes it once (the Blueprint/engine) and consumers only supply variables. The `modules/` are the one thing present in every path.
