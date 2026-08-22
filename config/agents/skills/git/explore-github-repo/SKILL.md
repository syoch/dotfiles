---
name: explore-github-repo
description: Use when exploring a GitHub repository's source code structure and file contents without cloning it. Trigger keywords: explore github repo, browse repo source, read github file, github api directory listing, view source without clone, inspect repository structure.
args: <owner/repo>
---

# Explore a GitHub Repository Without Cloning

Use this skill to explore the structure and contents of a GitHub repository by leveraging the GitHub REST API and raw file URLs — no `git clone` needed.

## When to use
- You want to understand a library's source layout before deciding to use or clone it.
- You need to read a specific file (or a few files) from a public GitHub repo.
- You want to check type definitions, exports, or implementation details of an external dependency.

## Procedure

### 1. List the root directory
```
webfetch https://api.github.com/repos/{owner}/{repo}/contents/
```
Returns a JSON array of entries. Each entry has:
- `name` — file/dir name
- `type` — `"file"` or `"dir"`
- `path` — relative path
- `url` — API URL to drill into directories
- `download_url` — raw URL for files (only present for files)

### 2. Drill into subdirectories
Use the `url` field from a `"dir"` entry to list its contents:
```
webfetch {entry.url}
```

### 3. Read file contents
Use `download_url` for files, or construct the raw URL directly:
```
webfetch https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}
```
Example:
```
webfetch https://raw.githubusercontent.com/JuanCouste/overpass-ql-ts/master/src/model/enum.ts
```

## Gotchas & Pitfalls

- **Rate limiting**: Unauthenticated GitHub API calls are limited to 60/hour. Rate limit info is in response headers (`x-ratelimit-remaining`). If blocked, wait or add `?ref=main` to stale requests.
- **Branch default**: Default branch is often `main` or `master`. Check the repo's homepage first, or use the API's `contents/` endpoint which follows the default branch.
- **Large repos**: The API may truncate directory listings in large repos. Use deeper paths for targeted navigation.
- **Binary files**: Raw URLs work for text; binaries return garbled content. Check `size` and `type` fields before fetching.
- **Monorepos**: Entry point and exports are typically in root `index.ts`, `index.js`, or `package.json`'s `main`/`exports` field.

## Verification
- Confirm the response is a JSON array (directory) or an object (single file).
- For files, confirm the content starts as expected (e.g., `import` statements for TypeScript).

## See also
- GitHub REST API docs: https://docs.github.com/en/rest/repos/contents
