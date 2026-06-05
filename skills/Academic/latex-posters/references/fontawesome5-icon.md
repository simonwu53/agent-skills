# Using `fontawesome5` icons in LaTeX posters

`\usepackage{fontawesome5}` gives ~1,500 vector icons (Font Awesome 5.15.4). Works with pdflatex/xelatex/lualatex.

## Two ways to place an icon

- **Macro:** `\faBus`, `\faRoute`, `\faMapMarker` — camelCase of the icon name.
- **Name-based:** `\faIcon{bus}`, `\faIcon{map-marker-alt}` — the hyphenated icon name.

Prefer `\faIcon{...}` when unsure: it works for every icon, including `*-alt` variants that have **no** macro (e.g. `\faMapMarkerAlt` and `\faFireAlt` do not exist — use `\faIcon{map-marker-alt}` / `\faIcon{fire-alt}`).

## When you hit "Undefined control sequence \faXxx"

It usually means the macro name is wrong, not that the package is broken or outdated. Check the mapping file (the hyphenated name **always** exists):

```bash
grep -i "<icon-name>" /usr/local/texlive/<year>/texmf-dist/tex/latex/fontawesome5/fontawesome5-mapping.def
```

Read the matched line `\__fontawesome_def_icon:nnnnn{<macro>}{<name>}...`:
- `{\faBus}` → macro exists, use `\faBus`.
- `{}` (empty) → no macro; use `\faIcon{<name>}`.

Do **not** "fix" this by reinstalling/updating — 5.15.4 is the latest `fontawesome5` release, and missing macros for `*-alt` icons are intentional.