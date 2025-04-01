from typing import Self
import dataclasses
import dagger
from dagger import dag, function, object_type, Container, ReturnType


_PG_SHIM = "while ! pg_isready -h postgres -U postgres; do sleep 1; done"


@dataclasses.dataclass
class ExecResult:
    exit_code: int
    stdout: str
    stderr: str

    @classmethod
    async def from_dagger(cls, ctr: dagger.Container) -> Self:
        return cls(
            exit_code=await ctr.exit_code(),
            stdout=await ctr.stdout(),
            stderr=await ctr.stderr(),
        )


@object_type
class Workspace:
    postgres: dagger.Service
    postgrest: dagger.Service
    ctr: Container
    db_anon_role: str
    db_schema: str

    @classmethod
    async def create(
        cls,
        db_anon_role: str = "web_anon",
        db_schema: str = "api",
    ) -> Self:
        postgres = (
            dag.container()
            .from_("postgres:17.0-alpine")
            .with_env_variable("POSTGRES_USER", "postgres")
            .with_env_variable("POSTGRES_PASSWORD", "postgres")
            .with_env_variable("POSTGRES_DB", "postgres")
            .with_env_variable("DB_ANON_ROLE", db_anon_role)
            .with_env_variable("DB_SCHEMA", db_schema)
            .with_exposed_port(5432)
            .as_service(use_entrypoint=True)
        )
        postgrest = (
            dag.container()
            .from_("postgrest/postgrest:latest")
            .with_service_binding("postgres", postgres)
            .with_env_variable("PGRST_DB_URI", "postgres://postgres:postgres@postgres:5432/postgres")
            .with_env_variable("PGRST_DB_ANON_ROLE", db_anon_role)
            .with_env_variable("PGRST_DB_SCHEMA", db_schema)
            .with_exposed_port(3000)
            .as_service(use_entrypoint=True)
        )
        ctr = (
            dag.container()
            .from_("alpine:3.21.3")
            .with_exec(["apk", "--update", "add", "postgresql-client", "curl"])
            .with_env_variable("PGPASSWORD", "postgres")
            .with_service_binding("postgres", postgres)
            .with_service_binding("postgrest", postgrest)
            .with_workdir("/app")
        )
        return cls(
            postgres=postgres,
            postgrest=postgrest,
            ctr=ctr,
            db_anon_role=db_anon_role,
            db_schema=db_schema,
        )

    @function
    async def exec_any(self, command: list[str]) -> ExecResult:
        return await ExecResult.from_dagger(
            self.ctr
            .with_exec(["sh", "-c", _PG_SHIM])
            .with_exec(command, expect=ReturnType.ANY)
        )
    
    @function
    async def exec_sql(self, contents: str) -> ExecResult:
        return await ExecResult.from_dagger(
            self.ctr
            .with_service_binding("postgres", self.postgres)
            .with_env_variable("PGPASSWORD", "postgres")
            .with_new_file("script.sql", contents)
            .with_exec(["sh", "-c", _PG_SHIM])
            .with_exec(["psql", "-h", "postgres", "-U", "postgres", "-d", "postgres", "-f", "script.sql"])
        )
    
    @function
    async def exec_all(self, sql_files: list[str], command: list[str]) -> ExecResult:
        container = self.ctr.with_exec(["sh", "-c", _PG_SHIM])
        for sql_file in sql_files:
            container = container.with_new_file("script.sql", sql_file)
            container = container.with_exec(["psql", "-h", "postgres", "-U", "postgres", "-d", "postgres", "-f", "script.sql"])
        return await ExecResult.from_dagger(
            container.with_exec(command, expect=ReturnType.ANY)
        )

    @function
    def container(self) -> Container:
        return self.ctr
