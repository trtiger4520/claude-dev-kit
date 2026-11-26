# Stack-specific checks

The vulnerability classes in `Generic` define what to look for. The per-stack sections add two things only: regexes that give a grep sweep somewhere to start, and framework traps that are easy to miss. Neither is a complete list — an API that behaves like a class counts whether or not it is named here. A hit is a place to read, not a finding. "Where siblings have it" means compare against neighboring routes, controllers, or handlers.

## Detection

| Signal | Stack | Then check dependencies for |
| --- | --- | --- |
| `package.json`, `tsconfig.json` | JavaScript / TypeScript | express, fastify, koa, @nestjs, next, nuxt, react, vue, @angular, electron |
| `pyproject.toml`, `requirements*.txt`, `Pipfile`, `setup.py` | Python | django, djangorestframework, flask, fastapi |
| `*.csproj`, `*.sln`, `global.json` | .NET | Microsoft.AspNetCore, EntityFrameworkCore, Dapper, Newtonsoft.Json |
| `pom.xml`, `build.gradle`, `build.gradle.kts` | Java / Kotlin | spring-boot, spring-security, mybatis, jackson |
| `go.mod` | Go | gin, echo, chi, fiber, gorm |
| `composer.json`, `wp-config.php` | PHP | laravel/framework, symfony, WordPress |
| `Gemfile` | Ruby | rails, sinatra, pundit, cancancan |
| `Cargo.toml` | Rust | actix-web, axum, rocket, sqlx, diesel |
| `Dockerfile`, `docker-compose*.yml`, `*.tf`, Kubernetes YAML, `.github/workflows/`, `.gitlab-ci.yml`, `nginx.conf` | Infrastructure and CI | — |
| `AndroidManifest.xml`, `Info.plist` | Mobile | — |

## Generic

Classes are defined by what the code does, not by API name:

- **Query construction**: input becomes part of a SQL, NoSQL, LDAP, or search query string instead of a bound parameter. Includes identifiers that cannot be parameterized (column and table names, `ORDER BY`, `LIMIT`) and second-order cases, where a stored value is later concatenated into a query
- **HTML output**: input reaches markup unescaped, or through an API that bypasses the template engine's escaping. Includes stored values rendered later, values placed in attributes, URLs (`javascript:`), and inline scripts, and DOM writes fed by `location`, `postMessage`, or browser storage
- **Command execution**: input reaches a shell or the arguments of a spawned process
- **Code evaluation**: input is evaluated as code, as a template, or as an expression
- **File paths**: input chooses a path that is read, written, served, deleted, or extracted to; uploads with unrestricted name, type, or destination
- **Outbound requests**: input chooses the host or protocol of a request the server makes (SSRF)
- **Deserialization**: untrusted bytes are parsed by a format that can instantiate arbitrary types or resolve external entities
- **Access control**: an entry point is reachable without the identity, role, or ownership check it needs; object references are not scoped to the caller (IDOR); request bodies are bound straight onto persistence models (mass assignment)
- **Configuration**: CORS that reflects any origin with credentials, debug mode in production configuration, default credentials

Secrets (search tracked files only; confirm with `git ls-files`):

- `AKIA[0-9A-Z]{16}` · `-----BEGIN [A-Z ]*PRIVATE KEY-----` · `gh[pousr]_[A-Za-z0-9]{36}` · `github_pat_` · `xox[baprs]-` · `sk_live_` · `AIza[0-9A-Za-z_-]{35}` · `eyJ[A-Za-z0-9_-]{10,}\.eyJ`
- `(password|passwd|secret|api[_-]?key|token|connection ?string)\s*[:=]\s*["'][^"']{8,}`
- Tracked files named `.env*`, `*.pem`, `*.pfx`, `*.p12`, `*.key`, `id_rsa*`, `credentials*.json`, `*.tfstate`, `secrets.*`

Cryptography:

- MD5 or SHA-1 for passwords or signatures; DES, 3DES, RC4; ECB mode; static IV or salt
- Non-cryptographic random generator used for tokens, reset codes, or session IDs
- TLS certificate or hostname verification disabled
- JWT accepted without signature verification, without a fixed algorithm list, or signed with a hard-coded secret

## JavaScript / TypeScript

Sinks:

- Code execution: `eval\(|new Function\(|vm\.runIn|setTimeout\(\s*["'`]`
- Commands: `child_process|execSync?\(|spawn\(.*shell:\s*true`
- SQL: `\.(query|raw|execute)\(\s*[`"'].*(\$\{|\+)` · `\$queryRawUnsafe|\$executeRawUnsafe` · `sequelize\.query`
- NoSQL: `\$where` · request body or query passed whole into `find(`, `findOne(`, `updateOne(` (operator injection)
- DOM and templates: `innerHTML|outerHTML|document\.write|insertAdjacentHTML|dangerouslySetInnerHTML|v-html|bypassSecurityTrust|\[innerHTML\]`
- Files: `fs\.\w+\(|res\.sendFile\(|path\.(join|resolve)\(` fed by request data
- Outbound requests: `fetch\(|axios|got\(|http\.request` with a user-supplied URL
- Deserialization: `node-serialize|unserialize\(|yaml\.load\(`
- Tokens and TLS: `jwt\.decode\(` used for trust decisions · `jwt\.verify\(` without `algorithms` · `Math\.random\(` for secrets · `rejectUnauthorized:\s*false|NODE_TLS_REJECT_UNAUTHORIZED`

Frameworks:

- Express, Koa, Fastify: routers mounted without auth middleware where siblings have it; `cors({ origin: true, credentials: true })`; hard-coded session secret; `res.redirect(req.query...)`
- NestJS: controllers or handlers without guards where siblings have them; `@Public()` on sensitive handlers; no `ValidationPipe({ whitelist: true })` so DTOs accept extra fields
- Next.js: every `app/**/route.ts`, `pages/api/**`, and Server Action is a public endpoint needing its own auth check, not only middleware; secrets in `NEXT_PUBLIC_*`; full database objects passed to client components or `getServerSideProps`
- React, Vue, Angular: XSS only through the raw-output APIs above; `href` or `src` bound to a user URL (`javascript:`); secrets in `VITE_*` or `REACT_APP_*` variables, which ship to the browser
- Electron: `nodeIntegration: true`, `contextIsolation: false`, `webSecurity: false`, `shell.openExternal` with a user URL

Audit: `npm audit` / `pnpm audit` / `yarn npm audit`. Check `preinstall` and `postinstall` scripts.

## Python

Sinks:

- Code execution: `\beval\(|\bexec\(|compile\(|__import__\(`
- Commands: `os\.system|os\.popen|subprocess\.\w+\(.*shell\s*=\s*True`
- Deserialization: `pickle\.loads?|cPickle|dill\.|shelve\.|marshal\.loads|joblib\.load|torch\.load|yaml\.load\(` without `SafeLoader`
- SQL: `execute\(\s*(f["']|["'].*(%|\.format\())` · `\.raw\(|\.extra\(|RawSQL\(|text\(\s*f["']`
- Templates: `render_template_string|Template\(.*request|Markup\(|mark_safe|\|\s*safe|autoescape\s*=\s*False`
- Files: `open\(|send_file\(|send_from_directory\(|os\.path\.join\(` fed by request data (`join` discards the prefix when given an absolute path) · `extractall\(` on uploaded archives
- Outbound requests: `requests\.|httpx\.|urllib` with a user URL · `verify\s*=\s*False`
- XML: `xml\.etree|xml\.dom|xml\.sax|lxml` parsing untrusted input without `defusedxml`
- Other: `random\.` for tokens instead of `secrets` · `hashlib\.(md5|sha1)` for passwords · `tempfile\.mktemp` · `assert` used as an authorization check

Frameworks:

- Django: `DEBUG = True`, `ALLOWED_HOSTS = ['*']`, hard-coded `SECRET_KEY`; `@csrf_exempt`; views without `@login_required` or permission mixins where siblings have them; querysets not filtered by `request.user`; DRF `AllowAny`, missing default permission classes, serializers with `fields = '__all__'`
- Flask: `debug=True`, hard-coded `SECRET_KEY`, routes without the auth decorator siblings use, `render_template_string` with user input, `send_file` with a user path
- FastAPI: routes without the `Depends(...)` auth dependency siblings use; `allow_origins=["*"]` with `allow_credentials=True`; no `response_model`, so ORM fields leak; request models that accept privileged fields such as `is_admin` or `role`

Audit: `pip-audit`, `safety check`, `bandit -r <src>`.

## .NET

Sinks:

- SQL: `FromSqlRaw|ExecuteSqlRaw|SqlCommand\(|CommandText\s*=` with concatenation or interpolation (`FromSqlInterpolated` and `FromSql` are parameterized) · Dapper `Query|Execute` with a built string
- Commands: `Process\.Start|ProcessStartInfo`
- Deserialization: `BinaryFormatter|NetDataContractSerializer|LosFormatter|SoapFormatter|ObjectStateFormatter` · `TypeNameHandling\.(All|Auto|Objects|Arrays)`
- XML: `DtdProcessing\.Parse|XmlResolver\s*=|XmlTextReader`
- Output: `Html\.Raw\(|new HtmlString\(|\(MarkupString\)`
- Files: `Path\.Combine\(` fed by request data (an absolute later segment overrides the base) · `File\.\w+\(|PhysicalFile\(`
- Outbound requests: `HttpClient` with a user URL · `ServerCertificateCustomValidationCallback|DangerousAcceptAnyServerCertificateValidator`
- Other: `new Random\(` for tokens · `MD5|SHA1|DES|TripleDES|CipherMode\.ECB` · `Redirect\(` with a user URL instead of `LocalRedirect` · `Type\.GetType\(|Assembly\.Load` with user input

ASP.NET Core:

- Controllers, actions, or minimal-API endpoints without `[Authorize]` or `.RequireAuthorization()` where siblings have it; `[AllowAnonymous]` on sensitive actions; no fallback authorization policy
- Actions that load by ID without checking ownership or tenant
- Entities bound directly from the request instead of a DTO (overposting)
- `[IgnoreAntiforgeryToken]` or missing antiforgery on cookie-authenticated form posts
- CORS: `AllowAnyOrigin` with credentials, `SetIsOriginAllowed(_ => true)`
- JWT: `ValidateIssuer|ValidateAudience|ValidateLifetime|ValidateIssuerSigningKey\s*=\s*false`, `RequireHttpsMetadata = false`
- `UseDeveloperExceptionPage` outside the development branch; connection strings and keys in tracked `appsettings*.json` or `web.config`; `debug="true"`, `customErrors mode="Off"`

Audit: `dotnet list package --vulnerable --include-transitive`.

## Java / Kotlin

Sinks:

- SQL: `createQuery\(|createNativeQuery\(|\.executeQuery\(|\.executeUpdate\(|jdbcTemplate\.\w+\(` with concatenation · MyBatis `\$\{`
- Commands: `Runtime\.getRuntime\(\)\.exec|ProcessBuilder`
- Deserialization: `ObjectInputStream|readObject\(|XMLDecoder|XStream|new Yaml\(\)|enableDefaultTyping|JsonTypeInfo\.Id\.CLASS`
- XML: `DocumentBuilderFactory|SAXParserFactory|XMLInputFactory|TransformerFactory` without DTD and external entities disabled
- Expression languages: `SpelExpressionParser|parseExpression\(|OgnlUtil|MVEL` with user input
- Files: `new File\(|Paths\.get\(|FileInputStream\(` fed by request data · `ZipEntry` names used unchecked
- Outbound requests: `RestTemplate|WebClient|openConnection\(` with a user URL
- Output: `th:utext`, unescaped `<%= %>` in JSP, user-supplied Freemarker or Velocity templates
- Other: `new Random\(` for tokens · `getInstance\("(MD5|SHA-1|DES|AES)"\)` (bare `AES` means ECB) · `TrustManager` or `HostnameVerifier` that accepts everything

Spring:

- `SecurityFilterChain`: how wide `permitAll()` is, whether `anyRequest()` is authenticated, `csrf().disable()` on a cookie-session application, `web.ignoring()` matchers
- Methods without `@PreAuthorize` or `@Secured` where siblings have it; lookups by ID without an ownership check
- Entities used directly as `@RequestBody` or `@ModelAttribute`
- Actuator: `management.endpoints.web.exposure.include=*` without authentication (`env`, `heapdump`)
- `@CrossOrigin` with any origin and credentials; `"redirect:" +` request input; H2 console enabled; secrets in tracked `application*.properties` or `.yml`

Audit: OWASP Dependency-Check when the build configures it, `osv-scanner`.

## Go

Sinks:

- SQL: `\.(Query|QueryRow|Exec)(Context)?\(.*(\+|fmt\.Sprintf)` · GORM `\.Raw\(|\.Exec\(|\.Where\(fmt\.Sprintf`
- Commands: `exec\.Command(Context)?\(` with `sh -c` or user-controlled arguments
- Output: `template\.(HTML|JS|URL)\(` · `text/template` used to render HTML
- Files: `filepath\.Join\(|os\.Open\(|os\.ReadFile\(|http\.ServeFile\(` fed by request data (`Join` cleans but does not confine) · archive entry names used unchecked
- Outbound requests: `http\.(Get|Post)\(|\.Do\(` with a user URL · `InsecureSkipVerify:\s*true`
- Tokens: `math/rand` for secrets · JWT keyfunc that does not check `token.Method` · `ParseUnverified`
- Other: errors from auth or validation calls discarded with `_` · `net/http/pprof` on a public mux

Frameworks (gin, echo, chi, fiber): route groups without the auth middleware siblings use; `ShouldBind` or `Bind` into a model struct with privileged fields; CORS allowing all origins with credentials.

Audit: `govulncheck ./...`.

## PHP

Sinks:

- Code execution: `\beval\(|\bassert\(|create_function|preg_replace\(.*/[a-z]*e` · `(include|require)(_once)?\s*\(?\s*\$`
- Commands: `system\(|\bexec\(|shell_exec|passthru|popen|proc_open` and backticks
- Deserialization: `unserialize\(` · `phar://`
- SQL: `mysqli_query|->query\(|DB::raw|whereRaw|selectRaw|orderByRaw|havingRaw` with interpolated variables
- Output: `echo .*\$_(GET|POST|REQUEST|COOKIE)` · Blade `\{!!` · Twig `\|\s*raw`
- Files and requests: `file_get_contents|fopen|readfile|curl_exec` with user input · `move_uploaded_file` without an extension allowlist
- Other: `extract\(\$_|\$\$` · `md5\(|sha1\(` for passwords · `==` comparing hashes or tokens instead of `hash_equals` · `rand\(|mt_rand\(|uniqid\(` for tokens · `LIBXML_NOENT` · `header\(["']Location:.*\$_`

Frameworks:

- Laravel: `APP_DEBUG=true` or `APP_KEY` in a tracked file; `$guarded = []` or `$request->all()` passed to `create`/`update`; routes outside the `auth` middleware group; controllers without a policy or `authorize()` call where siblings have one; entries in the CSRF `$except` list
- Symfony: gaps in `security.yaml` `access_control`; profiler or debug enabled in production
- WordPress: handlers without `wp_verify_nonce` or `check_admin_referer` and `current_user_can`; `$wpdb->query` without `prepare`; `wp_ajax_nopriv_` actions; output without `esc_html` or `esc_attr`

Audit: `composer audit`.

## Ruby

Sinks:

- Code execution: `\beval\(|instance_eval|class_eval|\.send\(|public_send\(|constantize` with user input
- Commands: `system\(|\bexec\(|%x|Open3|IO\.popen|Kernel\.open\(|\bopen\(` with user input, and backticks
- Deserialization: `Marshal\.load|YAML\.load\(` instead of `safe_load`
- SQL: `where\(["'].*#\{|find_by_sql|\.order\(params|\.pluck\(params`
- Output: `\.html_safe|\braw\(|<%==` · `render inline:` · `render params`
- Files and redirects: `send_file|File\.(read|open)` with params · `redirect_to params`

Rails: `permit!` or unfiltered params into `create`/`update`; `skip_before_action :verify_authenticity_token` or the authentication callback; controllers without the Pundit or CanCanCan call siblings make; `Model.find(params[:id])` instead of a lookup scoped to the current user; `master.key` or `secret_key_base` in a tracked file.

Audit: `bundle audit`, `brakeman -q`.

## Rust

Memory safety is out of scope except `unsafe` blocks that handle external input. Sinks: `Command::new\(` with a shell or user arguments · `sqlx::query\(&format!|sql_query\(format!` · `danger_accept_invalid_certs` · paths joined from request data · handlers missing the auth extractor or middleware siblings use.

Audit: `cargo audit`.

## Infrastructure and CI

- Dockerfile: secrets in `ENV`, `ARG`, or copied `.env` files; `ADD` from a URL; `curl ... | sh`. Running as root and floating tags are hardening notes
- Compose: `privileged: true`, the Docker socket mounted, database or admin ports published on all interfaces, default passwords
- Kubernetes: `privileged`, `hostNetwork`, `hostPID`, `hostPath`, secrets as literal env values or in ConfigMaps, `cluster-admin` bindings, wildcard RBAC rules
- Terraform and other IaC: ingress from `0.0.0.0/0` to admin or database ports, public buckets, IAM `"*"` actions on `"*"` resources, hard-coded credentials, committed state files
- GitHub Actions: `pull_request_target` that checks out the PR head; `${{ github.event.* }}` or `github.head_ref` interpolated into `run:`; `permissions: write-all`; secrets echoed to logs. Actions pinned by tag instead of commit SHA are a hardening note
- nginx: `alias` under a `location` without a trailing slash (traversal), `autoindex on`, `proxy_pass` to a host taken from the request

## Mobile

- Android: `android:exported="true"` components without a permission, `android:debuggable="true"`, `usesCleartextTraffic`, WebView with JavaScript enabled plus `addJavascriptInterface`, keys in resources or `BuildConfig`
- iOS: `NSAllowsArbitraryLoads`, keys in `Info.plist`, secrets in `UserDefaults` instead of the Keychain
