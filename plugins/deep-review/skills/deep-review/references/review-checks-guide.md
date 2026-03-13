# Deep Review Checks Guide

Reference catalog for all 31 checks across 8 categories with CWE/OWASP/Standard references,
detection patterns, multi-language examples, safe patterns, and remediation strategies.

---

## 1. Security (10 Checks) — OWASP Top 10 / CWE

### CWE-89 — SQL Injection | OWASP A03:2021

**Definition:** User-controlled input is concatenated into a SQL query string without parameterization, allowing attackers to modify query logic.

**Taint flow:** `HTTP request param` → string concat → `SQL execute()`

**Detection patterns:**
| Language | Bad Pattern | Safe Pattern |
|---|---|---|
| Python | `cursor.execute("SELECT * FROM t WHERE id=" + uid)` | `cursor.execute("SELECT * FROM t WHERE id=%s", (uid,))` |
| Java | `stmt.execute("SELECT * FROM t WHERE id=" + id)` | `PreparedStatement ps = conn.prepareStatement("... WHERE id=?"); ps.setInt(1, id)` |
| JS/Node | `` db.query(`SELECT * FROM t WHERE id=${id}`) `` | `db.query("SELECT * FROM t WHERE id=$1", [id])` |
| PHP | `mysqli_query($conn, "SELECT * FROM t WHERE id=" . $_GET['id'])` | `$stmt = $conn->prepare("SELECT * WHERE id=?"); $stmt->bind_param("s", $id)` |

**False positives — skip:** Parameterized queries, ORM .filter() with keyword args, SQLAlchemy .text() with bindparams

---

### CWE-79 — Cross-Site Scripting (XSS) | OWASP A03:2021

**Definition:** User-controlled data is rendered in HTML output without encoding, enabling script injection.

**Taint flow:** `user input` → template/DOM without encoding → `browser renders`

**Detection patterns:**
| Language | Bad Pattern | Safe Pattern |
|---|---|---|
| JS/React | `<div dangerouslySetInnerHTML={{__html: userInput}} />` | `<div>{userInput}</div>` (auto-escaped) |
| JS/DOM | `element.innerHTML = userInput` | `element.textContent = userInput` |
| Jinja2 | `{{ user_input \| safe }}` | `{{ user_input }}` (auto-escaped) |
| Vue | `<div v-html="userInput">` | `<div>{{ userInput }}</div>` |

---

### CWE-78 — OS Command Injection | OWASP A03:2021

**Definition:** User input is passed to a shell command without sanitization.

**Taint flow:** `user input` → shell execution with string concat

**Detection patterns:**
| Language | Bad Pattern | Safe Pattern |
|---|---|---|
| Python | `os.system("ping " + host)` | `subprocess.run(["ping", host], shell=False)` |
| Python | `subprocess.run(f"ls {path}", shell=True)` | `subprocess.run(["ls", path], shell=False)` |
| JS/Node | `exec("ls " + dir)` | `execFile("ls", [dir])` |
| Java | `Runtime.exec("cmd /c dir " + path)` | `new ProcessBuilder("cmd", "/c", "dir", path).start()` |

---

### CWE-22 — Path Traversal | OWASP A01:2021

**Definition:** User-controlled path traverses outside the intended directory via ../ sequences.

**BAD:**
```python
# Python
filename = request.args.get('file')
with open('/var/data/' + filename) as f:  # ../../../etc/passwd works
    return f.read()
```

**GOOD:**
```python
import os
filename = request.args.get('file')
safe_path = os.path.realpath(os.path.join('/var/data/', filename))
if not safe_path.startswith('/var/data/'):
    abort(403)
with open(safe_path) as f:
    return f.read()
```

---

### CWE-502 — Insecure Deserialization | OWASP A08:2021

**BAD (Python):** `data = pickle.loads(user_bytes)` — executes arbitrary code
**BAD (Python):** `config = yaml.load(user_yaml)` — executes !!python/object tags
**GOOD (Python):** `config = yaml.safe_load(user_yaml)` — restricted loader
**BAD (Java):** `ObjectInputStream ois = new ObjectInputStream(request.getInputStream()); ois.readObject()`

---

### CWE-798 — Hard-coded Credentials | OWASP A02:2021

**BAD:**
```python
DATABASE_PASSWORD = "admin123"
API_KEY = "sk-abc123def456"
```

**GOOD:**
```python
DATABASE_PASSWORD = os.environ["DATABASE_PASSWORD"]
API_KEY = os.environ["API_KEY"]
```

**False positives:** "changeme", "<YOUR_API_KEY>", "example", "placeholder", test fixtures

---

### CWE-918 — SSRF | OWASP A10:2021

**BAD:** `requests.get(request.args.get('url'))` — allows internal network access
**GOOD:** Validate URL against allowlist of permitted domains before making request

---

### CWE-862 — Missing Authorization | OWASP A01:2021

**BAD (Python/Flask):**
```python
@app.route('/admin/users')
def admin_users():  # No @login_required or role check
    return User.query.all()
```

**GOOD:** `@login_required @require_role('admin')` decorators applied

---

### CWE-327 — Weak Cryptography | OWASP A02:2021

**BAD:** `hashlib.md5(password.encode()).hexdigest()` — MD5 is cryptographically broken for passwords
**BAD:** `hashlib.sha1(data)` for password hashing
**GOOD:** `bcrypt.hashpw(password, bcrypt.gensalt(rounds=12))` or `argon2-cffi`

---

### CWE-352 — CSRF | OWASP A01:2021

**BAD:** POST endpoint without CSRF token validation in forms or missing SameSite cookie
**GOOD:** Django: `{% csrf_token %}` in forms + CsrfViewMiddleware; Flask-WTF: `form.hidden_tag()`

---

## 2. Performance (6 Checks) — CWE-1073/834/407/401

### N+1 Query (CWE-1073)

**BAD (Django Python):**
```python
orders = Order.objects.all()  # 1 query
for order in orders:
    print(order.customer.name)  # N queries (lazy load)
# Total: N+1 queries
```

**GOOD:**
```python
orders = Order.objects.select_related('customer').all()  # 1 query with JOIN
for order in orders:
    print(order.customer.name)  # no extra query
```

**BAD (Java/JPA):**
```java
List<Order> orders = orderRepo.findAll();
for (Order o : orders) {
    o.getCustomer().getName();  // lazy load per iteration
}
```

**GOOD:** Use `@EntityGraph` or JPQL `JOIN FETCH` to load associations eagerly.

---

### Blocking I/O in Async (CWE-834)

**BAD (Python):**
```python
async def handle_request(request):
    time.sleep(2)  # blocks the event loop
    data = requests.get(url).json()  # sync HTTP in async context
```

**GOOD:**
```python
async def handle_request(request):
    await asyncio.sleep(2)
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            data = await response.json()
```

---

### O(n squared) Nested Loop (CWE-407)

**BAD:**
```python
for item in items:
    for other in items:
        if item.id == other.ref_id:  # O(n^2)
            process(item, other)
```

**GOOD:**
```python
ref_map = {item.id: item for item in items}  # O(n) build
for item in items:
    if item.ref_id in ref_map:  # O(1) lookup
        process(item, ref_map[item.ref_id])
```

---

### String Concatenation in Loop (CWE-407)

**BAD (Java):**
```java
String result = "";
for (String s : items) {
    result = result + s;  // O(n^2) — creates new string each time
}
```

**GOOD:**
```java
StringBuilder sb = new StringBuilder();
for (String s : items) {
    sb.append(s);  // O(n) — amortized
}
String result = sb.toString();
```

---

### Unbounded Cache / Collection (CWE-401)

**BAD:**
```python
_request_cache = {}  # module-level, grows forever

def get_data(key):
    if key not in _request_cache:
        _request_cache[key] = expensive_compute(key)
    return _request_cache[key]
```

**GOOD:**
```python
from functools import lru_cache

@lru_cache(maxsize=1000)  # bounded, LRU eviction
def get_data(key):
    return expensive_compute(key)
```

---

### Event Listener Leak (CWE-401)

**BAD (React):**
```javascript
useEffect(() => {
    window.addEventListener('resize', handleResize);
    // Missing cleanup — listener accumulates on re-render
}, []);
```

**GOOD:**
```javascript
useEffect(() => {
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
}, []);
```

---

## 3. Concurrency (4 Checks) — CWE-367/833/362/366

### TOCTOU Race Condition (CWE-367)

**BAD (File system):**
```python
if os.path.exists(lockfile):  # check
    pass
else:
    open(lockfile, 'w').close()  # act — another thread can create between check and act
```

**GOOD (EAFP):**
```python
try:
    fd = os.open(lockfile, os.O_CREAT | os.O_EXCL | os.O_WRONLY)  # atomic
    os.close(fd)
except FileExistsError:
    pass  # another process owns the lock
```

**BAD (Database):**
```sql
SELECT count FROM inventory WHERE id = 1;
-- another transaction can decrement here
UPDATE inventory SET count = count - 1 WHERE id = 1;
```

**GOOD:**
```sql
SELECT count FROM inventory WHERE id = 1 FOR UPDATE;  -- locks row
UPDATE inventory SET count = count - 1 WHERE id = 1;
```

---

### Deadlock Risk (CWE-833)

**BAD:**
```python
# Thread A                    # Thread B
lock_a.acquire()              lock_b.acquire()
lock_b.acquire()              lock_a.acquire()  # DEADLOCK
```

**GOOD:** Always acquire locks in the same global order (alphabetical, by ID, etc.)

---

### Shared Mutable State (CWE-362)

**BAD:**
```python
request_count = 0  # module-level mutable

def handle_request():
    global request_count
    request_count += 1  # not thread-safe
```

**GOOD:**
```python
import threading
_lock = threading.Lock()
request_count = 0

def handle_request():
    global request_count
    with _lock:
        request_count += 1
```

---

### Non-Atomic Increment (CWE-366)

**BAD (Java):** `static int counter = 0; counter++;` in multi-threaded code
**GOOD (Java):** `static AtomicInteger counter = new AtomicInteger(0); counter.incrementAndGet();`
**BAD (Go):** `count++` on shared package-level variable
**GOOD (Go):** `atomic.AddInt64(&count, 1)` or mutex-protected increment

---

## 4. Resilience (5 Checks) — CWE-1069/396/755/772/390

### Empty Catch Block (CWE-1069)

**BAD:**
```python
try:
    result = db.query(sql)
except Exception:
    pass  # silently swallows ALL errors including DB connection failures
```

**GOOD:**
```python
try:
    result = db.query(sql)
except DatabaseError as e:
    logger.error("DB query failed: %s", e)
    raise  # re-raise so caller knows it failed
```

---

### Unhandled Promise (CWE-755)

**BAD (JS):**
```javascript
fetch('/api/data').then(r => r.json());  // no .catch()
// Or:
async function load() {
    const data = await fetch('/api/data').then(r => r.json());  // no try/catch
}
```

**GOOD:**
```javascript
fetch('/api/data')
    .then(r => r.json())
    .catch(err => console.error('Fetch failed:', err));
// Or:
async function load() {
    try {
        const data = await fetch('/api/data').then(r => r.json());
    } catch (err) {
        handleError(err);
    }
}
```

---

### Resource Leak (CWE-772)

**BAD (Python):**
```python
f = open('data.txt')
data = f.read()
# If read() throws, f.close() never called
```

**GOOD:**
```python
with open('data.txt') as f:
    data = f.read()
# Automatically closed even on exception
```

**BAD (Java):**
```java
Connection conn = DriverManager.getConnection(url);
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery(sql);  // if this throws, conn is leaked
```

**GOOD:** Use try-with-resources:
```java
try (Connection conn = DriverManager.getConnection(url);
     Statement stmt = conn.createStatement();
     ResultSet rs = stmt.executeQuery(sql)) {
    // automatically closed
}
```

---

### Swallowed Exception (CWE-390)

**BAD:**
```python
try:
    payment.charge(amount)
except PaymentError as e:
    logger.error("Payment failed: %s", e)
    # EXECUTION CONTINUES — caller assumes payment succeeded!

send_confirmation_email()  # sends even though payment failed
```

**GOOD:**
```python
try:
    payment.charge(amount)
except PaymentError as e:
    logger.error("Payment failed: %s", e)
    raise  # or return {"success": False, "error": str(e)}
```

---

## 5. API Design (4 Checks) — RFC 7231

### REST Verb Misuse

| Violation | Correct |
|---|---|
| GET /createUser | POST /users |
| GET /deleteUser?id=5 | DELETE /users/5 |
| POST /getUsers | GET /users |
| PUT /users/5 for partial update | PATCH /users/5 |

---

### Wrong HTTP Status Codes

| Situation | Wrong | Correct |
|---|---|---|
| Resource created | 200 | 201 Created |
| Successful delete | 200 | 204 No Content |
| Validation error | 500 | 400 Bad Request |
| Not logged in | 403 | 401 Unauthorized |
| Lacks permission | 401 | 403 Forbidden |
| Not found | 200 with error body | 404 Not Found |

---

### Missing Pagination

**BAD:**
```python
@app.get('/users')
def list_users():
    return jsonify(User.query.all())  # could return millions of records
```

**GOOD:**
```python
@app.get('/users')
def list_users():
    page = request.args.get('page', 1, type=int)
    per_page = min(request.args.get('per_page', 20, type=int), 100)
    pagination = User.query.paginate(page=page, per_page=per_page)
    return jsonify({
        'data': [u.to_dict() for u in pagination.items],
        'total': pagination.total,
        'page': page,
        'per_page': per_page
    })
```

---

## 6. Testing Quality (4 Checks) — xUnit Test Patterns

### Test Without Assertion

**BAD:**
```python
def test_user_creation():
    user = User.create(name="Alice")
    # No assert — test always passes
```

**GOOD:**
```python
def test_user_creation():
    user = User.create(name="Alice")
    assert user.id is not None
    assert user.name == "Alice"
    assert user.created_at is not None
```

---

### Sleepy Test

**BAD:**
```python
def test_async_task():
    task.start()
    time.sleep(5)  # arbitrary wait — flaky on slow machines
    assert task.is_complete()
```

**GOOD:**
```python
def test_async_task():
    task.start()
    # Poll with timeout
    for _ in range(50):
        if task.is_complete():
            break
        time.sleep(0.1)
    assert task.is_complete()
```

---

### Mystery Guest

**BAD (unit test accessing real file):**
```python
def test_parse_config():
    config = parse_config('/etc/myapp/config.yaml')  # external dependency
    assert config['debug'] == False
```

**GOOD:**
```python
def test_parse_config(tmp_path):
    config_file = tmp_path / 'config.yaml'
    config_file.write_text('debug: false')
    config = parse_config(str(config_file))
    assert config['debug'] == False
```

---

## 7. Maintainability (4 Checks) — CWE-1086/1121

### God Class (CWE-1086) — Threshold: >500 LOC or >10 public methods spanning multiple domains

**Bad:** `class UserManager` with 800 lines handling DB, email, payments, HTML rendering
**Good:** Split into `UserRepository`, `UserEmailService`, `PaymentService`, `UserProfileRenderer`

---

### Cyclomatic Complexity > 15 (CWE-1121)

**How to count:** Start at 1. Add 1 for each: `if`, `elif`, `else if`, `while`, `for`, `case`, `&&`, `||`, `?:`, `except`/`catch` block.

**Threshold:** CC > 15 requires refactoring. CC > 20 is CRITICAL.

**Refactoring strategies:**
- Extract sub-functions for each logical branch
- Replace complex conditionals with strategy pattern or lookup tables
- Use guard clauses / early return to reduce nesting

---

### Dead Code — Unreachable code, unused imports, unused variables

**BAD:**
```python
def calculate(x):
    return x * 2
    print("done")  # unreachable after return
```

**BAD:** `import os` at top of file when `os` is never used

---

### Magic Numbers — Unexplained literals in business logic

**BAD:**
```python
if retry_count > 3:           # why 3?
    wait(86400)                # why 86400?
price = amount * 1.08         # tax rate?
```

**GOOD:**
```python
MAX_RETRIES = 3
SECONDS_PER_DAY = 86400
TAX_RATE = 0.08

if retry_count > MAX_RETRIES:
    wait(SECONDS_PER_DAY)
price = amount * (1 + TAX_RATE)
```

---

## 8. Architecture (4 Checks) — CWE-1047/1048 / NASA P10 R1

### Circular Dependency (CWE-1047)

**BAD:**
```
# user.py
from services.auth import verify_token   # A imports B

# services/auth.py
from models.user import User             # B imports A — CYCLE
```

**Fix:** Extract shared interface to `models/base.py`. Both modules import from base.

---

### Excessive Coupling CBO > 20 (CWE-1048)

**Detection:** Count distinct external types a class imports and uses.
A class with 25 imports spanning many unrelated modules has CBO ~25 — exceeds threshold.

**Fix:** Apply Single Responsibility Principle. If a class depends on >20 things, it is doing too much.

---

### Layer Violation

**BAD:** Controller directly importing SQLAlchemy models:
```python
# controllers/user_controller.py
from sqlalchemy import create_engine  # database concern in controller layer
```

**GOOD:** Controller calls service, service calls repository:
```
Controller → Service Layer → Repository/DAO → Database
```

---

### Unbounded Recursion (NASA P10 R1)

**BAD:**
```python
def traverse_tree(node):
    process(node)
    for child in node.children:
        traverse_tree(child)  # no depth limit — stack overflow on deep trees
```

**GOOD:**
```python
def traverse_tree(node, depth=0, max_depth=1000):
    if depth > max_depth:
        raise RecursionLimitError(f"Tree too deep: {depth}")
    process(node)
    for child in node.children:
        traverse_tree(child, depth + 1, max_depth)
```

---

## Quick Reference: CWE / Standard Cross-Reference

| Check | CWE | OWASP | NASA P10 | CERT | Severity |
|---|---|---|---|---|---|
| SQL Injection | CWE-89 | A03 | — | IDS00-J | CRITICAL |
| XSS | CWE-79 | A03 | — | — | HIGH |
| Command Injection | CWE-78 | A03 | — | ENV33-C | CRITICAL |
| Path Traversal | CWE-22 | A01 | — | FIO02-J | HIGH |
| Insecure Deserialization | CWE-502 | A08 | — | SER12-J | HIGH |
| Hard-coded Credentials | CWE-798 | A02 | — | MSC41-C | HIGH |
| SSRF | CWE-918 | A10 | — | — | HIGH |
| Missing Authorization | CWE-862 | A01 | — | — | HIGH |
| Weak Crypto | CWE-327 | A02 | — | MSC61-J | MEDIUM |
| CSRF | CWE-352 | A01 | — | — | MEDIUM |
| N+1 Query | CWE-1073 | — | — | — | HIGH |
| Blocking I/O | CWE-834 | — | — | — | HIGH |
| O(n^2) Loop | CWE-407 | — | — | — | HIGH |
| String Concat in Loop | CWE-407 | — | — | — | MEDIUM |
| Unbounded Cache | CWE-401 | — | — | — | MEDIUM |
| Event Listener Leak | CWE-401 | — | — | — | MEDIUM |
| TOCTOU | CWE-367 | — | — | FIO45-C | HIGH |
| Deadlock | CWE-833 | — | — | CON35-C | MEDIUM |
| Shared Mutable State | CWE-362 | — | — | CON02-J | HIGH |
| Non-Atomic Increment | CWE-366 | — | — | — | HIGH |
| Empty Catch | CWE-1069 | — | — | ERR00-J | HIGH |
| Generic Catch-All | CWE-396 | — | — | ERR08-J | MEDIUM |
| Unhandled Promise | CWE-755 | — | — | — | HIGH |
| Resource Leak | CWE-772 | — | — | FIO04-J | HIGH |
| Swallowed Exception | CWE-390 | — | — | ERR00-J | HIGH |
| REST Verb Misuse | — | — | — | — | HIGH |
| Breaking Changes | — | — | — | — | HIGH |
| Missing Pagination | — | — | — | — | MEDIUM |
| Wrong Status Codes | — | — | — | — | MEDIUM |
| God Class | CWE-1086 | — | R4 | — | HIGH |
| Cyclomatic Complexity | CWE-1121 | — | R4 | — | HIGH |
| Dead Code | — | — | — | MSC12-C | LOW |
| Magic Numbers | — | — | — | — | LOW |
| Circular Dependency | CWE-1047 | — | — | — | HIGH |
| Excessive Coupling | CWE-1048 | — | — | — | HIGH |
| Layer Violation | — | — | — | — | MEDIUM |
| Unbounded Recursion | — | — | R1 | — | MEDIUM |
