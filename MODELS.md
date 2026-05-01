# Central LLM model registry

`models.json` (sibling file) is the single source of truth for which concrete
model each of my projects uses for each role. When a vendor deprecates a
model, **edit `models.json` once** and every consumer picks up the change on
its next config fetch.

## Why this exists

I have N projects across multiple repos that hard-code strings like
`"claude-sonnet-4-6"`. Vendors deprecate models every few months. Without a
central registry, every deprecation means grep-replace across N repos.

## Schema

```json
{
  "schema_version": 1,
  "aliases": {
    "<role>": { "id": "<vendor-model-id>", "vendor": "<anthropic|openai|xai|...>", "notes": "..." }
  },
  "projects": {
    "<project-name>": { "<role-key>": "<alias-name>" }
  }
}
```

- **Aliases** are role-shaped names (e.g. `extractor`, `judge_cheap`).
  They resolve to a concrete `{id, vendor}` pair.
- **Projects** map their internal role keys to aliases. So `streikcheck.de`
  uses `enrich.primary → extractor → claude-sonnet-4-6`. When Anthropic
  ships Sonnet 5, I update the alias and `streikcheck.de` automatically
  switches.
- **Adding a project**: append under `projects.<project-name>`. Define new
  aliases only if existing ones don't fit your role shape.

## Fetching from a consumer project

Public read URL:
```
https://raw.githubusercontent.com/ferreirafabio/dotfiles/main/models.json
```

### Python (no deps, with cache)

```python
import json, time, urllib.request

_RAW = "https://raw.githubusercontent.com/ferreirafabio/dotfiles/main/models.json"
_CACHE: dict = {"cfg": None, "ts": 0}

def get_model(project: str, role: str, *, ttl_s: int = 3600) -> str:
    """Resolve project+role to a concrete vendor model id."""
    if _CACHE["cfg"] is None or time.time() - _CACHE["ts"] > ttl_s:
        with urllib.request.urlopen(_RAW, timeout=5) as r:
            _CACHE["cfg"] = json.load(r)
            _CACHE["ts"] = time.time()
    cfg = _CACHE["cfg"]
    alias = cfg["projects"][project][role]
    return cfg["aliases"][alias]["id"]

# Example:
# get_model("streikcheck.de", "enrich.primary") → "claude-sonnet-4-6"
```

### Bash (one-liner)

```sh
curl -s https://raw.githubusercontent.com/ferreirafabio/dotfiles/main/models.json \
  | jq -r --arg p streikcheck.de --arg r enrich.primary \
    '.aliases[.projects[$p][$r]].id'
```

### Node / TypeScript

```ts
const RAW = "https://raw.githubusercontent.com/ferreirafabio/dotfiles/main/models.json";
let cache: { cfg: any; ts: number } = { cfg: null, ts: 0 };

export async function getModel(project: string, role: string, ttlSeconds = 3600): Promise<string> {
  if (!cache.cfg || Date.now() / 1000 - cache.ts > ttlSeconds) {
    cache.cfg = await fetch(RAW, { cache: "no-store" }).then(r => r.json());
    cache.ts = Date.now() / 1000;
  }
  const alias = cache.cfg.projects[project][role];
  return cache.cfg.aliases[alias].id;
}
```

## Operational notes

- **Cache aggressively**: a 1-hour TTL is fine. A vendor deprecation gets
  picked up within an hour of the registry update; instant propagation isn't
  needed.
- **Fallback to a hard-coded default** in client code if the fetch fails —
  GitHub raw can have brief outages. Don't make the LLM call depend on the
  registry being reachable.
- **Don't call `get_model()` per request**. Resolve once at process start
  (or per worker) and reuse.
- **Don't store API keys here.** Only model identifiers — those aren't
  secrets. Keys live in `.env` per project.

## Adding a new project

1. Pick role keys that match your project's call sites (`primary`, `retry`,
   `cheap_classifier`, etc. — descriptive names, dotted for nesting).
2. Reuse existing aliases (`extractor`, `extractor_retry`, `judge_cheap`,
   `agent_websearch`) when they fit.
3. Define a new alias only if your role has fundamentally different
   requirements (e.g. you want a vendor-different model: GPT-4 for one
   specific behaviour Anthropic can't replicate).
4. PR or push to `main`. Consumers pick up on next refresh.

## Updating a model (deprecation handling)

```diff
   "extractor": {
-    "id": "claude-sonnet-4-6",
+    "id": "claude-sonnet-4-7",
     "vendor": "anthropic",
     "notes": "..."
   }
```

That's the whole change. Bump `updated_at`. Done.
