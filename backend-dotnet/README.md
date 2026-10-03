# Backend (C# / ASP.NET Core / SQL Server)

The C# rewrite of `backend/` (Python / FastAPI). Same HTTP contract, so the Flutter apps do not
change. The gaze estimator stays in Python (`backend/eyetracking/gaze`, a separate process); this
API only forwards `/gaze/*` to it. During the move both backends live side by side and the Python
HTTP tests are the acceptance tests for both.

```
dotnet build backend-dotnet
dotnet test backend-dotnet                       # C# tests (unit + in-process HTTP)
cd backend && EYETRACKING_PARITY=dotnet python -m pytest -q    # Python contract tests against the C# API
```

The contract run builds `EyeTracking.Web`, starts it on a throwaway SQL Server database
(`EyeTracking_Test_*`, dropped afterwards) next to a synthetic Python gaze service, and empties the
database before every test (`POST /__test/reset`, test mode only). `EYETRACKING_PARITY_KEEP_LOGS=1`
keeps the server log; `EYETRACKING_TEST_SQLSERVER` picks another server (default `localhost`,
Windows authentication).

Settings are the Python ones (`EYETRACKING_*` variables or `.env` in the working directory), plus
`EYETRACKING_DB_CONNECTION` (SQL Server connection string, default database `EyeTracking_Dev`) and
`EYETRACKING_GAZE_SERVICE_URL` (default `http://127.0.0.1:8100`).

## Layout (mirrors the Python layers)

| Python | C# |
|---|---|
| `domain/*.py` | `src/EyeTracking.Domain` — entities (`Models.cs` step 1, `Entities.cs` steps 2-7, all `partial`), rules, `Errors.cs` |
| `application/ports.py`, `authz.py`, `*_use_cases.py` | `src/EyeTracking.Application` — `Ports*.cs`, `Authz.cs`, `*UseCases.cs` (static classes, one per Python module) |
| `infrastructure/` | `src/EyeTracking.Infrastructure` — `Db/EyeTrackingDb.cs` (all 35 tables), `Db/EfUnitOfWork.cs`, `Db/*Repositories.cs`, `Security.cs`, adapters |
| `web/` | `src/EyeTracking.Web` — `Endpoints/<Step>/*` (one `IEndpointModule` per router), `Http/*`, `Settings.cs`, `Program.cs` |
| `tests/` | `tests/EyeTracking.Tests` — C# versions of the tests that need Python internals |

## Porting rules

- **Port, don't redesign.** Keep names, order of checks, error messages and status codes. The
  Python file is the specification; the Python tests are the acceptance test.
- **One step, its own files.** Add rules to the step's partial entities in a new
  `Domain/<Step>.cs`; repositories as `Application/Ports.<Step>.cs` (interfaces plus
  `public partial interface IUnitOfWork { IXRepo X { get; } }`) and
  `Infrastructure/Db/<Step>Repositories.cs` (implementations plus
  `public sealed partial class EfUnitOfWork { public IXRepo X => field ??= new XRepo(this); }`);
  use cases as `Application/<Step>UseCases.cs`; endpoints in `Web/Endpoints/<Step>/`. Endpoint
  modules and their services (`IEndpointModule.AddServices`) are found automatically — no
  central list to edit. If your code calls into a step that is not ported yet, add the target
  method as a minimal stub in that step's file with `// stub: completed in step N`.
- **Unit of work.** `uow.X.Add(e)` saves at once inside the request transaction so the id
  exists (SQLAlchemy flush); `uow.Commit()` makes it permanent; anything not committed is rolled
  back. `EfUnitOfWork.Add/Save/Flush` and `Db` are there for repository implementations.
- **Free-form JSON** (Python dicts/lists in layouts, payloads, answers) is `JsonObject`/`JsonArray`.
  Read it with `Domain.Json` (`Str`, `Num`, `Int`, `Truthy`, `IsBlank` follow Python semantics).
  Edits in place are saved (the comparer compares JSON text).
- **Wire format.** `Reply.Ok/Created/Json` write snake_case names, snake_case enum values,
  naive UTC timestamps (`JsonFormat.Timestamp`) and Python-style floats. Output DTOs are records
  (PascalCase, becomes snake_case). Enums: `e.Value()` / `Wire.Parse<T>()`.
- **Requests.** Resolve `ctx.Principal()` first (401 comes before 422, as in FastAPI), then
  `await ctx.Body<T>()` (422 in FastAPI's list format; pydantic constraints via `IValidatedBody`
  and `Check.Literal/MinLength/MaxLength/Range`). Router-level `HTTPException` is
  `throw new HttpError(status, detail)`; domain errors (`NotFound`, `Forbidden`, `Conflict`,
  `Invalid`, `AuthenticationFailed`) map to 404/403/409/422/401 with the message as `detail`.
  Route parameters: `/studies/{studyId:int}/...`.
- **Python semantics to keep:** `round()` is `PyMath.Round` (Python rounds the exact binary
  value: `round(0.025, 2)` is 0.03 but `Math.Round` gives 0.02); `statistics.median` and numpy
  percentiles are in `PyMath` too; `//` floors; `statistics.median`; `sorted` is stable (`OrderBy` is);
  dict order is insertion order (`JsonObject` keeps it); `x or y` truthiness; `int()` truncates.
  Python float division of ints is `/` on doubles in C#. `sum()` of floats (compensated since 3.12)
  and `math.hypot` are `PyMath.Sum`/`PyMath.Hypot`; `csv.reader` is `PyCsv` (Domain/Pilot.cs).
- **SQL Server differs from SQLite:** string lengths are enforced (check or trim user text as the
  domain intends; never let a too-long value turn into a 500 where Python returned 200),
  foreign keys are enforced and never cascade (delete children first), text comparison is
  case-insensitive except for columns created with `exact: true`, and `datetime2(6)` keeps
  microseconds. Only ever create or drop databases named `EyeTracking_Test_*`.
- **External providers.** Claude is called through the official `Anthropic` NuGet SDK (see
  `Infrastructure/Ai/AnthropicText.cs`), other vendors with plain `HttpClient`. Adapters take an
  injectable client or `HttpMessageHandler`, keys come from settings only, and failures carry the
  Python exception name in the job's error (`GenerationError.Kind`). Tests never call a real vendor.
- **Tests.** Make the step's Python HTTP tests pass with `EYETRACKING_PARITY=dotnet` without
  changing them. A test that needs Python internals (`c.app`, `app.state`, fakes, `SqlUnitOfWork`,
  pure Python unit tests) gets `@pytest.mark.python_only` and a C# version in
  `tests/EyeTracking.Tests/<Step>Tests.cs` (`ApiFactory` gives an in-process API on its own
  database; `Override` swaps services). Re-run the earlier steps' contract tests before finishing.
- Do not change the Python backend's behaviour; only add `python_only` markers to its tests.
